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

    #TODO: LBFOTeam param should accept either a LBFO bound vSwitch or actual LBFO Team
    $here = Split-Path -Parent (Get-Module -Name Convert-LBFO2SET).Path

    #region Data Collection
    $configData = @{ NetLBFOTeam = Get-NetLbfoTeam -Name $LBFOTeam -ErrorAction SilentlyContinue }

    $ValidationResults = Invoke-Pester -Script "$here\tests\unit\unit.tests.ps1" -Tag PreValidation -PassThru
    $ValidationResults | Select-Object -Property TagFilter, Time, TotalCount, PassedCount, FailedCount, SkippedCount, PendingCount | Format-Table -AutoSize

    If ($ValidationResults.FailedCount -ne 0) { 
        Write-Warning 'Prerequisite checks have failed.'

        Write-Warning "`n`nPlease note: if the failure was due to LACP: `n`t - We will intentionally NOT convert this type of team as the new team will not be functional until the port-channel on the physical switch has been modified"
        Write-Warning "To continue with an LACP conversion, please break the port-channel on the physical switch and modify the LBFO team to Switch Independent (Set-NetLbfoTeam -TeamingMode SwitchIndependent)"

        Break
    }

    $configData += @{
        NetAdapter        = Get-NetAdapter -Name $configData.NetLBFOTeam.TeamNics -ErrorAction SilentlyContinue
        NetAdapterBinding = Get-NetAdapterBinding -Name $configData.NetLBFOTeam.TeamNics -ErrorAction SilentlyContinue
    }

    $configData += @{
        LBFOVMSwitch = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object NetAdapterInterfaceGuid -eq $configData.NetAdapter.InterfaceGuid
    }

    if ($ConfigData.LBFOVMSwitch) {
        $configData += @{
            VMNetworkAdapter  = Get-VMNetworkAdapter -All | Where-Object SwitchName -EQ $configData.LBFOVMSwitch.Name -ErrorAction SilentlyContinue
        }

        # Grabbing additional info for Host vNICs because their migration is a little more complicated.
        foreach ($HostvNIC in $configData.VMNetworkAdapter | Where-Object VMName -eq $Null) {
            $HostvNICNetAdapter = Get-NetAdapter | Where-Object DeviceID -eq $HostvNIC.DeviceId

            $HostvNICs += @(
                @{ $($HostvNIC.Name) = @{ HostvNICNetAdapter = $HostvNICNetAdapter }}
            )
        }

        $configData += @{ HostvNICs = $HostvNICs }

        Remove-Variable HostvNIC -ErrorAction SilentlyContinue
    }
    #endregion

    # EnableIOV should be $true as a best practice unless Hyper-V QoS is in use. Enabling IOV turns the vSwitch Bandwidth mode to 'None' so no legacy QoS
    Switch ($ConfigData.LBFOVMSwitch.BandwidthReservationMode) {
        {'Absolute' -or 'Weight'} {
            If ($configData.VMNetworkAdapter.BandwidthSetting) { $IovEnabled = $false }
            Else { $IovEnabled = $true }
        }

        'None' { $IovEnabled = $true }
    }

    #region Create new SET team
    if ($AllowOutage -eq $true -and $configData.NetLBFOTeam.Members.Count -eq 1) {
        $NetAdapterNames = $configData.NetLBFOTeam.Members
        $AdapterMigrationNeeded = $false

        # Only one pnIC - Destroy the LBFOTeam
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
        AllowManagementOS     = $false
    }

    $vSwitchExists = Get-VMSwitch -Name $SETTeam -ErrorAction SilentlyContinue

    if (-not($vSwitchExists)) { New-VMSwitch @SETTeamParams }
    Else {
        $VerbosePreference = 'Continue'

        Write-Verbose "Team named [$SETTeam] exists and will be used"
        
        $VerbosePreference = 'SilentlyContinue'
    }

    Remove-Variable SETTeamParams -ErrorAction SilentlyContinue
    #endregion
    $vmNICs = ($configData.VMNetworkAdapter | Where VMName -ne $Null)
    $vNICMigrationNeeded = If ($vmNICs) { $true } Else { $false }

    # TODO: Add vmNIC and Host vNIC to test cases.
    if ($vNICMigrationNeeded) { Connect-VMNetworkAdapter -VMNetworkAdapter $vmNICs -SwitchName $SETTeam -ErrorAction SilentlyContinue }

    Foreach ($HostvNIC in ($configData.VMNetworkAdapter | Where VMName -eq $Null)) {
        Write-Output "Original Name: $($HostvNIC.Name)"
        Write-Output "New Name: $($HostvNIC.Name)-446f776e2057697468204c42464f"

        Add-VMNetworkAdapter -SwitchName $SETTeam -Name "$($HostvNIC.Name)-446f776e2057697468204c42464f" -ManagementOS

        Remove-Variable HostvNICSettings -ErrorAction SilentlyContinue

        # Setting host vNIC properties...Going for exact match; Best practices will be enabled later if switch is specified

        # These settings could be null in which case they would fail the Set-VMNetworkAdapter command we're about to do; set only if needed
        if ($HostvNIC.DeviceNaming  -ne $Null)      { $HostvNICSettings += @{ DeviceNaming       = $HostvNIC.DeviceNaming }}
        if ($HostvNIC.PortMirroring -ne $Null)      { $HostvNICSettings += @{ PortMirroring      = $HostvNIC.PortMirroring }}
        if ($HostvNIC.NumaAwarePlacement -ne $Null) { $HostvNICSettings += @{ NumaAwarePlacement = $HostvNIC.NumaAwarePlacement }}
        
        if ($HostvNIC.IovWeight -ne $Null) { $HostvNICSettings += @{ IovWeight = $HostvNIC.IovWeight }}
        if ($HostvNIC.IovQueuePairsRequested -ne $Null) { $HostvNICSettings += @{ IovQueuePairsRequested = $HostvNIC.IovQueuePairsRequested }}
        if ($HostvNIC.IovInterruptModeration -ne $Null) { $HostvNICSettings += @{ IovInterruptModeration = $HostvNIC.IovInterruptModeration }}

        if ($HostvNIC.NotMonitoredInCluster -ne $Null) { $HostvNICSettings += @{ NotMonitoredInCluster = $HostvNIC.NotMonitoredInCluster }}
        if ($HostvNIC.TestReplicaPoolName   -ne $Null) { $HostvNICSettings += @{ TestReplicaPoolName   = $HostvNIC.TestReplicaPoolName }}
        if ($HostvNIC.TestReplicaSwitchName -ne $Null) { $HostvNICSettings += @{ TestReplicaSwitchName = $HostvNIC.TestReplicaSwitchName }}

        # These were added in 1709 so 2016 systems may not have this
        if ($HostvNIC.VrssMinQueuePairs -ne $Null) { $HostvNICSettings += @{ VrssMinQueuePairs = $HostvNIC.VrssMinQueuePairs }}
        if ($HostvNIC.VrssMaxQueuePairs -ne $Null) { $HostvNICSettings += @{ VrssMaxQueuePairs = $HostvNIC.VrssMaxQueuePairs }}

        if ($HostvNIC.VrssQueueSchedulingMode      -ne $Null) { $HostvNICSettings += @{ VrssQueueSchedulingMode      = $HostvNIC.VrssQueueSchedulingMode }}
        if ($HostvNIC.VrssExcludePrimaryProcessor  -ne $Null) { $HostvNICSettings += @{ VrssExcludePrimaryProcessor  = $HostvNIC.VrssExcludePrimaryProcessor }}
        if ($HostvNIC.VrssIndependentHostSpreading -ne $Null) { $HostvNICSettings += @{ VrssIndependentHostSpreading = $HostvNIC.VrssIndependentHostSpreading }}

        # This one could be 'None' in which case restoring that setting won't work due to how the cmdlet works.
        if ($HostvNIC.VrssVmbusChannelAffinityPolicy -ne 'None') { $HostvNICSettings += @{ VrssVmbusChannelAffinityPolicy = $HostvNIC.VrssVmbusChannelAffinityPolicy }}

        $HostvNICSettings += @{
            # Create vNIC with custom name to prevent conflicts with existing host vNIC
            #TODO: This should only be migrated if AllowOutage is $true
            Name         = "$($HostvNIC.Name)-446f776e2057697468204c42464f"
            ManagementOS = $true
            
            DHCPGuard    = $HostvNIC.DHCPGuard
            StormLimit   = $HostvNIC.StormLimit
            RouterGuard  = $HostvNIC.RouterGuard
            AllowTeaming = $HostvNIC.AllowTeaming

            VmqWeight   = $HostvNIC.VmqWeight
            VrssEnabled = $HostvNIC.VrssEnabled
            VmmqEnabled = $HostvNIC.VmmqEnabled

            VirtualSubnetId = $HostvNIC.VirtualSubnetId
            IeeePriorityTag = $HostvNIC.IeeePriorityTag
            MacAddressSpoofing = $HostvNIC.MacAddressSpoofing
        }
        
        Set-VMNetworkAdapter @HostvNICSettings

        #TODO: If static IP Addresses, remove old IP and add to new host vNIC; (only if allowoutage)
        #TODO: Make sure to warn if host vNICs exist so that we can customer knows they're not done and don't destroy the team/switch
        #TODO: Just create a test if they have host vNICs attached and fail if allowoutage is not true

        If ($HostvNIC.IsolationSetting.IsolationMode -eq 'Vlan') {
            Set-VMNetworkAdapterIsolation -ManagementOS -VMNetworkAdapterName "$($HostvNIC.Name)-446f776e2057697468204c42464f" `
                -IsolationMode Vlan -DefaultIsolationID $HostvNIC.IsolationSetting.DefaultIsolationID
        }

        Switch ($HostvNIC.VlanSetting.OperationMode) {
            'Trunk' {
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "$($HostvNIC.Name)-446f776e2057697468204c42464f" `
                    -Trunk -NativeVlanId $HostvNIC.NativeVlanId -AllowedVlanIdList $HostvNIC.AllowedVlanId
            }

            'Access' {
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "$($HostvNIC.Name)-446f776e2057697468204c42464f" `
                    -Access -VlanId $HostvNIC.VlanSetting.AccessVlanId
            }
        }

        if (-not($HostvNIC.VlanSetting.OperationMode -eq 'Untagged')) {

        }
    }

    #TODO: Add post test validation to make sure there are no more vmNICs attached
    #TODO: Add post test validation to make sure there are no more host vNICs attached

#region Fire and Brimstone
    $remainingAdapters = $configData.NetLBFOTeam.Members

    If ($configData.LBFOVMSwitch) { Remove-VMSwitch -Name $configData.LBFOVMSwitch.Name -Force -ErrorAction SilentlyContinue }
    Remove-NetLbfoTeam -Name $configData.NetLBFOTeam.Name -Confirm:$false -ErrorAction SilentlyContinue

    #TODO: May need to check that the switch and / or team actually were removed before moving on

    Add-VMSwitchTeamMember -NetAdapterName $remainingAdapters -VMSwitchName $SETTeam

    Remove-Variable HostvNIC
    foreach ($HostvNIC in ($configData.HostvNICs)) {
        $NewNetAdapterName = $configData.HostvNICs.$($HostvNIC.Keys).HostvNICNetAdapter.Name

        Rename-NetAdapter -Name "$NewNetAdapterName-446f776e2057697468204c42464f" -NewName $NewNetAdapterName
    }
#endregion

    if ($EnableBestPractices) {
        $SETInterfaces = (Get-VMSwitchTeam -Name $SETTeam).NetAdapterInterfaceDescription

        Foreach ($interface in $SETInterfaces) {
            Reset-NetAdapterAdvancedProperty -Name $interface -ErrorAction SilentlyContinue `
                -DisplayName 'NVGRE Encapsulated Task Offload', 'VXLAN Encapsulated Task Offload', 'IPV4 Checksum Offload',
                             'NetworkDirect Technology', 'Recv Segment Coalescing (IPv4)', 'Recv Segment Coalescing (IPv6)',
                             'Maximum number of RSS Processors', 'Maximum Number of RSS Queues', 'RSS Base Processor Number',
                             'RSS Load Balancing Profile', 'SR-IOV', 'TCP/UDP Checksum Offload (IPv4)', 'TCP/UDP Checksum Offload (IPv6)' 

            Set-NetAdapterAdvancedProperty -Name $interface -DisplayName 'Packet Direct' -RegistryValue 0
            Set-NetAdapterAdvancedProperty -Name $interface -RegistryValue 1 -DisplayName 'Receive Side Scaling', 'Virtual Switch RSS', 'Virtual Machine Queues', 'NetworkDirect Functionality'
        }

        $NodeOSCaption = (Get-CimInstance -ClassName 'Win32_OperatingSystem').Caption

        Switch -Wildcard ($NodeOSCaption) {
            '*Windows Server 2016*' {
                $SETSwitchUpdates = @{ DefaultQueueVrssQueueSchedulingMode = 'StaticVRSS' }
                $vmNICUpdates     = @{ VrssQueueSchedulingMode = 'StaticVRSS' }
                $HostvNICUpdates  = @{ VrssQueueSchedulingMode = 'StaticVRSS' }
            }

            '*Windows Server 2019*' {
                $SETSwitchUpdates = @{
                    EnableSoftwareRsc = $true
                    DefaultQueueVrssQueueSchedulingMode = 'Dynamic'
                }

                $vmNICUpdates    = @{ VrssQueueSchedulingMode = 'Dynamic' }
                $HostvNICUpdates = @{ VrssQueueSchedulingMode = 'Dynamic' }
            }
        }

        $SETSwitchUpdates += @{
            Name = $configData
            DefaultQueueVrssEnabled = $true
            DefaultQueueVmmqEnabled = $true
            DefaultQueueVrssMinQueuePairs = 8
            DefaultQueueVrssMaxQueuePairs = 16
        }

        $vmNICUpdates += @{
            VMName      = '*'
            VrssEnabled = $true
            VmmqEnabled = $true
            VrssMinQueuePairs = 8
            VrssMaxQueuePairs = 16
        }

        $HostvNICUpdates += @{
            ManagementOS = $true
            VrssEnabled  = $true
            VmmqEnabled  = $true
            VrssMinQueuePairs = 8
            VrssMaxQueuePairs = 16
        }

        Set-VMSwitch @SETSwitchUpdates
        Set-VMSwitchTeam -Name $SETTeam -LoadBalancingAlgorithm HyperVPort

        Set-VMNetworkAdapter @HostvNICUpdates
        Set-VMNetworkAdapter @vmNICUpdates

        Remove-Variable SETSwitchUpdates, vmNICUpdates, HostvNICUpdates, NodeOSCaption -ErrorAction SilentlyContinue
    }
}


$CPUInfo = Get-CimInstance -ClassName Win32_Processor -Property 'NumberOfCores', 'NumberOfLogicalProcessors'


function GetNumCpusPerNUMA()
{
    $CPUInfo = @()
    $cpuInfo += Get-WmiObject -Class win32_processor -Property "numberOfCores"
    $numcores = $cpuInfo[0].NumberOfCores
    return $numcores
}

function GetNumaCount()
{
    $cpuInfo = Get-WmiObject -Class win32_processor -Property "numberOfCores"
    $numaCount = $cpuInfo.Count
    return $numaCount
}