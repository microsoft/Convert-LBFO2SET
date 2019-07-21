Function Convert-LBFO2Set {
<#
    .SYNOPSIS
        This is the synopsis

    .DESCRIPTION
        This script will allow you to migrate a LBFO Team into a SET team.  It will also migrate a vSwitch (if added to the LBFO Team)
        To a new vSwitch on SET including the vNICs.  This enables you to migrate a host with active virtual machines.

        More info about the virtue of SET and why LBFO is dying

    .PARAMETER LBFOTeam
        The name of the LBFO Team to be migrated

    .PARAMETER SETTeam
        The name of the SET team to be created (the team does not need to already exist)

    .PARAMETER AllowOutage
        Use this to allow a migration of a team and vSwitch with only one pNIC.  In this case, the migration will incur an outage
        for any virtual NICs connected to the team because the underlying pNIC can only be connected to one team at a time

    .PARAMETER EnableBestPractices
        Use this to set Microsoft recommended best practices for the team and/or Virtual Switch.  If this switch is omitted, the
        existing settings from the LBFO team will be configured on SET

    .EXAMPLE
        Convert-LBFO2Set TODO

    .EXAMPLE
        Convert-LBFO2Set TODO

    .NOTES
        Author: Microsoft Core Networking team and the Networking Blackbelts

        Please file issues on GitHub @ GitHub.com/Microsoft/Convert-LBFO2SET

    .LINK
        More projects               : https://github.com/topics/msftnet
        Windows Networking Blog     : https://blogs.technet.microsoft.com/networking/
#>
    param (
        [parameter(Mandatory = $true)]
        [String] $LBFOTeam ,

        [parameter(Mandatory = $true)]
        [String] $SETTeam ,

        [parameter(Mandatory = $False)]
        [Switch] $AllowOutage ,

        [parameter(Mandatory = $False)]
        [Switch] $EnableBestPractices
    )

$here = Split-Path -Parent (Get-Module -Name Convert-LBFO2SET).Path

#region Data Collection
    $configData = @{ NetLBFOTeam = Get-NetLbfoTeam -Name $LBFOTeam -ErrorAction SilentlyContinue }

    $ValidationResults = Invoke-Pester -Script "$here\tests\unit\unit.tests.ps1" -Tag PreValidation -PassThru
    $ValidationResults | Select-Object -Property TagFilter, Time, TotalCount, PassedCount, FailedCount, SkippedCount, PendingCount | Format-Table -AutoSize

    If ($ValidationResults.FailedCount -ne 0) { Write-Host 'Prerequisite checks have failed.' ; Break }

    $configData += @{
        NetAdapter        = Get-NetAdapter -Name $configData.NetLBFOTeam.TeamNics -ErrorAction SilentlyContinue
        NetAdapterBinding = Get-NetAdapterBinding -Name $configData.NetLBFOTeam.TeamNics -ErrorAction SilentlyContinue
    }

    $configData += @{
        VMSwitch = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object NetAdapterInterfaceGuid -eq $configData.NetAdapter.InterfaceGuid
    }

    if ($ConfigData.VMSwitch) {
        $configData += @{
            VMNetworkAdapter = Get-VMNetworkAdapter -All | Where-Object SwitchName -EQ $configData.VMSwitch.Name -ErrorAction SilentlyContinue
        }
    }
#endregion

    # If Legacy QoS is enabled on any vNIC we can't enable IOV on the new SET Team as this makes the vSwitch bandwidth mode = 'None'
    # If no legacy QoS is in use, enable the EnableIOV = $true
    Switch ($ConfigData.VMSwitch.BandwidthReservationMode) {
        {'Absolute' -or 'Weight'} {
            If ($configData.VMNetworkAdapter.BandwidthSetting) { $IovEnabled = $false }
            Else { $IovEnabled = $true }
        }

        'None' { $IovEnabled = $true }
    }

#region Create new SET team
    if ($configData.NetLBFOTeam.Members.Count -eq 1) {
        $NetAdapterNames = $configData.NetLBFOTeam.Members
        $AdapterMigrationNeeded = $false

        # Only one pnIC - Destroy the LBFOTeam
        # AllowOutage must be $true to get this far with a single pNIC; tested in PreValidation
        Remove-NetLbfoTeam -Name $configData.NetLBFOTeam.Name -Confirm:$false
    }
    else {
        $NetAdapterNames = $configData.NetLBFOTeam.Members[0]
        $AdapterMigrationNeeded = $true

        Remove-NetLbfoTeamMember -Name $configData.NetLBFOTeam.Members[0] -Team $configData.NetLBFOTeam.Name -Confirm:$False
    }

    $SETTeamParams = @{
        Name = $SETTeam
        NetAdapterName = $NetAdapterNames
        EnableIov      = $IovEnabled
        EnablePacketDirect    = $false
        EnableEmbeddedTeaming = $true
    }

    New-VMSwitch @SETTeamParams
    # Restore team configuration items

#endregion

    $vNICMigrationNeeded = If ($configData.VMNetworkAdapter) { $true } Else { $false }

    # Will migrate vmNICs but not host vNICs - Need to figure this out
    if ($vNICMigrationNeeded) {
        Connect-VMNetworkAdapter -VMNetworkAdapter ($configData.VMNetworkAdapter | Where VMName -ne $Null) -SwitchName $SETTeam
    }

#region Fire and Brimstone
    $remainingAdapters = $configData.NetLBFOTeam.Members

    If ($configData.VMSwitch) { Remove-VMSwitch -Name $configData.VMSwitch.Name -Force }
    Remove-NetLbfoTeam -Name $configData.NetLBFOTeam.Name -Confirm:$false

    Add-VMSwitchTeamMember -NetAdapterName $remainingAdapters -VMSwitchName $SETTeam
#endregion

    if ($EnableBestPractices) {
        $SETInterfaces = (Get-VMSwitchTeam -Name $SETTeam).NetAdapterInterfaceDescriptions

        Foreach ($interface in $SETInterfaces) {
            Reset-NetAdapterAdvancedProperty -Name $interface -DisplayName 'NVGRE Encapsulated Task Offload', 'VXLAN Encapsulated Task Offload', 'IPV4 Checksum Offload',
                'NetworkDirect Technology', 'Recv Segment Coalescing (IPv4)', 'Recv Segment Coalescing (IPv6)',
                'Maximum number of RSS Processors', 'Maximum Number of RSS Queues', 'RSS Base Processor Number',
                'Virtual Machine Queues', 'RSS Load Balancing Profile', 'SR-IOV', 'TCP/UDP Checksum Offload (IPv4)', 'TCP/UDP Checksum Offload (IPv6)'

            Set-NetAdapterAdvancedProperty -Name $interface -DisplayName 'Packet Direct' -RegistryValue 0
            Set-NetAdapterAdvancedProperty -Name $interface -RegistryValue 1 -DisplayName 'Receive Side Scaling', 'Virtual Switch RSS', 'NetworkDirect Functionality'
        }
    }
}

#TODO: Check for pinned vNICs
#TODO: Migrate host vNICs (do we need to backup and restore settings?)