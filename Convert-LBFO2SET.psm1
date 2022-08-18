Function Convert-LBFO2Set
{
    <#
        .SYNOPSIS
            Virtual Switches attached to an LBFO team has been deprecated by Microsoft. Use this tool, to 
            migrate your team to the alternative teaming solution, Switch Embedded Teaming (SET).
    
        .DESCRIPTION
            This script will allow you to migrate a LBFO Team into a SET team.  It will also migrate a vSwitch (if added to the LBFO Team)
            To a new vSwitch on SET including the vNICs. This enables you to migrate a host with active virtual machines.
    
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
            Convert-LBFO2Set -LBFOTeam NameofLBFOTeam -SETTeam NewSETTeamName
    
        .EXAMPLE
            Convert-LBFO2Set TODO
    
        .NOTES
            Author: Microsoft Edge OS Networking Team and Microsoft CSS
    
            Please file issues on GitHub @ GitHub.com/Microsoft/Convert-LBFO2SET
    
        .LINK
            More projects               : https://github.com/topics/msftnet
            Windows Networking Blog     : https://blogs.technet.microsoft.com/networking/
    #>
	[CmdletBinding()]
	param (
		[parameter(Mandatory = $true)]
		[String]$LBFOTeam,
		[parameter(Mandatory = $true)]
		[String]$SETTeam,
		[parameter(Mandatory = $False)]
		[Switch]$AllowOutage = $false,
		[parameter(Mandatory = $False)]
		[Switch]$EnableBestPractices = $false
	)
	Write-Verbose "Collecting data and validating configuration."
	# check whether $LBFOTeam is the vSwitch or the LBFO team name bound to a vSwitch
	# if there is an LBFO team with the name we simply use that
	$isLBFOTeam = Get-NetLbfoTeam -Name $LBFOTeam -ErrorAction SilentlyContinue
	if (-NOT $isLBFOTeam)
	{
		# check to see whether this is a vSwitch
		$isvSwitch = Get-VMSwitch $LBFOTeam -ErrorAction SilentlyContinue
		if ($isvSwitch)
		{
			Write-Verbose "LBFOTeam is a vSwitch. Verifying that an LBFO team is attached."
			## a vSwitch was found. Now make sure there is an LBFO team attached.
			# get the vSwitch adapter(s) based on the InterfaceDescription contained in the vSwitch object
			$tmpAdapter = Get-NetAdapter | Where-Object InterfaceDescription -in $isvSwitch.NetAdapterInterfaceDescriptions
			# compare to list of LBFO team adapters
			$tmpTeam = Get-NetLbfoTeam | Where-Object { $_.Name -in $tmpAdapter.Name -or $_.Name -eq $tmpAdapter.Name }
			if ($tmpTeam)
			{
				# we found the LBFO team attached to the vSwitch! Set that to $LBFOTeam. We'll rediscover the vSwitch later.
				$LBFOTeam = $tmpTeam.Name
			}
			else
			{
				Throw "An LBFO team associated with $LBFOTeam could not be detected."
			}
		}
		else
		{
			Throw "Failed to find an LBFO team or vSwitch named $LBFOTeam`."
		}
		Remove-Variable isLBFOTeam, isvSwitch, tmpAdapter, tmpTeam -ErrorAction SilentlyContinue
	}
	else
	{
		Remove-Variable isLBFOTeam -ErrorAction SilentlyContinue
	}
	# get the path to where the module is stored
	$here = Split-Path -Parent (Get-Module -Name Convert-LBFO2SET).Path
	if (-NOT $here)
	{
		throw "Could not find the module path."
	}
	# detect the version of Windows
	$osMajVer = [System.Environment]::OSVersion.Version.Major
	$osBldVer = [System.Environment]::OSVersion.Version.Build
	switch ($osMajVer)
	{
		10
		{
			switch ($osBldVer)
			{
				14393 {
					$nicReconnBin = "nicReconnect1.exe"
				}
				17763 {
					$nicReconnBin = "nicReconnect5.exe"
				}
				default
				{
					throw "This version of Windows is not yet certified for Convert-LBFO2SET."
				}
			}
		}
		default
		{
			throw "A supported version of Windows was not detected."
		}
	}
	#region Data Collection
	$configData = @{ NetLBFOTeam = Get-NetLbfoTeam -Name $LBFOTeam -ErrorAction SilentlyContinue }
	$ValidationResults = Invoke-Pester -Script "$here\tests\unit\unit.tests.ps1" -Tag PreValidation -PassThru
	$ValidationResults | Select-Object -Property TagFilter, Time, TotalCount, PassedCount, FailedCount, SkippedCount, PendingCount | Format-Table -AutoSize
	If ($ValidationResults.FailedCount -ne 0)
	{
		Write-Warning 'Prerequisite checks have failed.'
		Write-Warning "`n`nPlease note: if the failure was due to LACP: `n`t - We will intentionally NOT convert this type of team as the new team will not be functional until the port-channel on the physical switch has been modified"
		Write-Warning "To continue with an LACP conversion, please break the port-channel on the physical switch and modify the LBFO team to Switch Independent (Set-NetLbfoTeam -TeamingMode SwitchIndependent)"
		throw
	}
	$configData += @{
		NetAdapter = Get-NetAdapter -Name $configData.NetLBFOTeam.TeamNics -ErrorAction SilentlyContinue
		NetAdapterBinding = Get-NetAdapterBinding -Name $configData.NetLBFOTeam.TeamNics -ErrorAction SilentlyContinue
	}
	$configData += @{
		LBFOVMSwitch = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object NetAdapterInterfaceGuid -eq $configData.NetAdapter.InterfaceGuid
	}
	if ($ConfigData.LBFOVMSwitch)
	{
		$configData += @{
			VMNetworkAdapter = Get-VMNetworkAdapter -All | Where-Object SwitchName -EQ $configData.LBFOVMSwitch.Name -ErrorAction SilentlyContinue
		}
		# Grabbing host vNICs (ManagementOS) attached to the LBFO vSwitch
		$configData += @{ HostvNICs = @(Get-VMNetworkAdapter -ManagementOS -SwitchName $configData.LBFOVMSwitch.Name) }
	}
	#endregion
	# EnableIOV should be $true as a best practice unless Hyper-V QoS is in use. Enabling IOV turns the vSwitch Bandwidth mode to 'None' so no legacy QoS
	Write-Verbose "Bandwidth Reservation Mode: $($ConfigData.LBFOVMSwitch.BandwidthReservationMode)"
	Switch ($ConfigData.LBFOVMSwitch.BandwidthReservationMode)
	{
		{ 'Absolute' -or 'Weight' } {
			If ($ConfigData.VMNetworkAdapter.BandwidthSetting)
			{
				$IovEnabled = $true
			}
			Else
			{
				$IovEnabled = $false
			}
		}
		'None' { $IovEnabled = $true }
		default { $IovEnabled = $false }
	}
	#region Create new SET team
	#TODO: test this logic thuroughly...
	if ($AllowOutage -eq $true -and $configData.NetLBFOTeam.Members.Count -eq 1)
	{
		$NetAdapterNames = $configData.NetLBFOTeam.Members
		# Only one pnIC - Destroy the LBFOTeam
		Remove-NetLbfoTeam -Name $configData.NetLBFOTeam.Name -Confirm:$false
	}
	else
	{
		$NetAdapterNames = $configData.NetLBFOTeam.Members[0]
		Remove-NetLbfoTeamMember -Name $configData.NetLBFOTeam.Members[0] -Team $configData.NetLBFOTeam.Name -Confirm:$False
	}
	Write-Verbose "IOV Enabled: $IovEnabled"
	$SETTeamParams = @{
		Name				  = $SETTeam
		NetAdapterName	      = $NetAdapterNames
		EnablePacketDirect    = $false
		EnableEmbeddedTeaming = $true
		AllowManagementOS	  = $false
		MinimumBandwidthMode  = $($ConfigData.LBFOVMSwitch.BandwidthReservationMode)
		EnableIov			  = $IovEnabled
	}
	Write-verbose "SETTeam Parameters: $($SETTeamParams | Out-String)"
	$vSwitchExists = Get-VMSwitch -Name $SETTeam -ErrorAction SilentlyContinue
	if (-NOT $vSwitchExists)
	{
		New-VMSwitch @SETTeamParams
	}
	else
	{
		$VerbosePreference = 'Continue'
		Write-Verbose "Team named [$SETTeam] exists and will be used"
		$VerbosePreference = 'SilentlyContinue'
	}
	Remove-Variable SETTeamParams -ErrorAction SilentlyContinue
	#endregion
	$vmNICs = ($configData.VMNetworkAdapter | Where-Object VMName -ne $Null)
	$vNICMigrationNeeded = If ($vmNICs) { $true }
	Else { $false }
	# TODO: Add vmNIC and Host vNIC to test cases.
	if ($vNICMigrationNeeded) { Connect-VMNetworkAdapter -VMNetworkAdapter $vmNICs -SwitchName $SETTeam -ErrorAction SilentlyContinue }
	# migrate host vNIC(s)
	Foreach ($HostvNIC in $configData.HostvNics)
	{
		& "$($here)\helpers\$($nicReconnBin)" -r "$($HostvNIC.Name)" "$SETTeam" | Out-Null
	}
	# validation to make sure there are no more vmNICs attached
	$vmMigGood = Get-VMNetworkAdapter -All | Where-Object SwitchName -EQ $configData.LBFOVMSwitch.Name -ErrorAction SilentlyContinue
	if ($vmMigGood)
	{
		throw "Critical vmNIC migration failure. The following virtual NICs were not migrated to the new SET switch:`n$($vmMigGood | ForEach-Object {
				"`n`t$($_.Name) [$(if ($_.VMName) { "$($_.VMName)" }
					else { "host" })] "
			})"
	}
	#region Fire and Brimstone
	$remainingAdapters = $configData.NetLBFOTeam.Members
	if ($configData.LBFOVMSwitch)
	{
		Remove-VMSwitch -Name $configData.LBFOVMSwitch.Name -Force -ErrorAction SilentlyContinue | Out-Null
	}
	Remove-NetLbfoTeam -Name $configData.NetLBFOTeam.Name -Confirm:$false -ErrorAction SilentlyContinue
	#TODO: May need to check that the switch and / or team actually were removed before moving on
	Add-VMSwitchTeamMember -NetAdapterName $remainingAdapters -VMSwitchName $SETTeam
	Remove-Variable HostvNIC -ErrorAction SilentlyContinue
        <# Temporarily removing till we work through host vNIC migration plan
        foreach ($HostvNIC in ($configData.HostvNICs)) {
            $NewNetAdapterName = $configData.HostvNICs.$($HostvNIC.Keys).HostvNICNetAdapter.Name
    
            Rename-NetAdapter -Name "$NewNetAdapterName-446f776e2057697468204c42464f" -NewName $NewNetAdapterName
        }
        #>
	#endregion
	Write-Verbose "Enable Best Practices Parameter Present: $EnableBestPractices"
	if ($EnableBestPractices)
	{
		$SETInterfaces = (Get-VMSwitchTeam -Name $SETTeam).NetAdapterInterfaceDescription
		$SETAdapters = (Get-NetAdapter | Where-Object InterfaceDescription -in $SETInterfaces).Name
		Foreach ($interface in $SETAdapters)
		{
			Reset-NetAdapterAdvancedProperty -Name $interface -ErrorAction SilentlyContinue `
											 -DisplayName 'NVGRE Encapsulated Task Offload', 'VXLAN Encapsulated Task Offload', 'IPV4 Checksum Offload',
											 'NetworkDirect Technology', 'Recv Segment Coalescing (IPv4)', 'Recv Segment Coalescing (IPv6)',
											 'Maximum number of RSS Processors', 'Maximum Number of RSS Queues', 'RSS Base Processor Number',
											 'RSS Load Balancing Profile', 'SR-IOV', 'TCP/UDP Checksum Offload (IPv4)', 'TCP/UDP Checksum Offload (IPv6)'
			Set-NetAdapterAdvancedProperty -Name $interface -DisplayName 'Packet Direct' -RegistryValue 0 -ErrorAction SilentlyContinue
			Set-NetAdapterAdvancedProperty -Name $interface -RegistryValue 1 -DisplayName 'Receive Side Scaling', 'Virtual Switch RSS', 'Virtual Machine Queues', 'NetworkDirect Functionality' -ErrorAction SilentlyContinue
		}
		$NodeOSCaption = (Get-CimInstance -ClassName 'Win32_OperatingSystem').Caption
		Switch -Wildcard ($NodeOSCaption)
		{
			'*Windows Server 2016*' {
				$SETSwitchUpdates = @{ DefaultQueueVrssQueueSchedulingMode = 'StaticVRSS' }
				$vmNICUpdates = @{ VrssQueueSchedulingMode = 'StaticVRSS' }
				$HostvNICUpdates = @{ VrssQueueSchedulingMode = 'StaticVRSS' }
			}
			'*Windows Server 2019*' {
				$SETSwitchUpdates = @{
					EnableSoftwareRsc				    = $true
					DefaultQueueVrssQueueSchedulingMode = 'Dynamic'
				}
				$vmNICUpdates = @{ VrssQueueSchedulingMode = 'Dynamic' }
				$HostvNICUpdates = @{ VrssQueueSchedulingMode = 'Dynamic' }
			}
		}
		$SETSwitchUpdates += @{
			Name						  = $SETTeam
			DefaultQueueVrssEnabled	      = $true
			DefaultQueueVmmqEnabled	      = $true
			DefaultQueueVrssMinQueuePairs = 8
			DefaultQueueVrssMaxQueuePairs = 16
		}
		$vmNICUpdates += @{
			VMName		      = '*'
			VrssEnabled	      = $true
			VmmqEnabled	      = $true
			VrssMinQueuePairs = 8
			VrssMaxQueuePairs = 16
		}
		$HostvNICUpdates += @{
			ManagementOS	  = $true
			VrssEnabled	      = $true
			VmmqEnabled	      = $true
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
