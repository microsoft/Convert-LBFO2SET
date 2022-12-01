BeforeAll {
    $NodeOS = Get-CimInstance -ClassName 'Win32_OperatingSystem'
        
    # detect the version of Windows
    $osBldVer = [System.Environment]::OSVersion.Version.Build

    $HyperVInstallation = (Get-WindowsFeature -Name Hyper-V -ComputerName $env:ComputerName -ErrorAction SilentlyContinue).InstallState

    # [DONE]TODO: LBFO team should be attached to a vSwitch
    $vSwitch = Get-VMSwitch -ErrorAction SilentlyContinue
    $netAdapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -in $vSwitch.NetAdapterInterfaceDescriptions -and $_.Name -eq $LBFOTeam }

    $vSwitchExists = $vSwitch | Where-Object Name -eq $SETTeam

    $VmsBinary = Get-Item "$here\helpers\$nicReconnBin" -ErrorAction SilentlyContinue
}

Describe 'OSValidation' -Tag PreValidation {
    Context HostOS {

        ### Verify the Host is sufficient version
        It "${env:ComputerName}`: Must be Windows Server 2016, or Server 2019" {
            $NodeOS.Caption | Should -Be ($NodeOS.Caption -like '*Windows Server 2016*' -or $NodeOS.Caption -like '*Windows Server 2019*')
        }

        It "${env:ComputerName}`: Must NOT be a SAC release" {
            # 14393 defines Server 2016 (RS1)
            # 17763 defines Server 2019 (RS5)
            # 20348 defines Server 2022 (Fe) 
            # ... Attaching LBFO to a vmSwitch in WS2022 is not supported. In this case there is nothing to convert.
            # ... In-place upgrades with a virtual network might be possible. This needs to be tested.
            $osBldVer | Should -BeIn @(14393, 17763)
        }

        It "${env:ComputerName}`: Must have Hyper-V installed" {
            $HyperVInstallation | Should -Be 'Installed'
        }

        It "${env:ComputerName}`: LBFO Team [$LBFOTeam] must already exist" {
            $configData.NetLBFOTeam | Should -Not -BeNullOrEmpty
        }

        It "${env:ComputerName}`: Teaming mode for LBFO team [$LBFOTeam] must not be LACP" {
            $configData.NetLBFOTeam.TeamingMode | Should -Not -Be 'LACP'
        }

        If ($AllowOutage -eq $false) {
            It "${env:ComputerName} $LBFOTeam`: Must have at least two adapters when -AllowOutage is not set" {
                $configData.NetLBFOTeam.Members.Count | Should -BeGreaterThan 1
            }
        }

        
        It "${env:ComputerName}`: LBFO Team [$LBFOTeam] must be attached to a vSwitch" {
            $netAdapter.Name | Should -Be $LBFOTeam
        }

        #TODO: Add to Test condition
        If ($vSwitchExists) {
            It "${env:ComputerName}`: The existing SET Team [$SETTeam] must have teaming enabled" {
                $vSwitchExists.EmbeddedTeamingEnabled | Should -Be $true
            }
        }

        It "${env:ComputerName}`: Must have $nicReconnBin in $here\helpers." {
            $VmsBinary.Name | Should -Be $nicReconnBin
        }
    }
}


Describe 'SETTeam' {
    Context SETTeam {

        It "The virtual switch [$VirtualSwitch] should have SR-IOV enabled" {
            $VMSwitch.IovEnabled | Should -Be $true
        }

        It "The virtual switch [$VirtualSwitch] SR-IOV Support Reasons property should be empty" {
            (Get-VMSwitch).IovSupportReasons | Should -Be $null
        }
    }
}
