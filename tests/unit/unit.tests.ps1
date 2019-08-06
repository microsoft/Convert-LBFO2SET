Describe 'OSValidation' -Tag PreValidation {
    Context HostOS {
        $NodeOS = Get-CimInstance -ClassName 'Win32_OperatingSystem'

        ### Verify the Host is sufficient version
        It "${env:ComputerName} must be Windows Server 2016, or Server 2019" {
            $NodeOS.Caption | Should be ($NodeOS.Caption -like '*Windows Server 2016*' -or $NodeOS.Caption -like '*Windows Server 2019*')
        }

        $HyperVInstallation = (Get-WindowsFeature -Name Hyper-V -ComputerName $env:ComputerName -ErrorAction SilentlyContinue).InstallState

        It "${env:ComputerName} must have Hyper-V installed" {
            $HyperVInstallation | Should be 'Installed'
        }

        It "${env:ComputerName} LBFO Team [$LBFOTeam] should already exist" {
            $configData.NetLBFOTeam | Should Not BeNullOrEmpty
        }

        It "${env:ComputerName} Teaming mode for LBFO team [$LBFOTeam] should not be LACP" {
            $configData.NetLBFOTeam.TeamingMode | Should Not Be 'LACP'
        }

        If ($AllowOutage -eq $false) {
            It "$LBFOTeam should have at least two adapters" {
                $configData.NetLBFOTeam.Members.Count | Should BeGreaterThan 1
            }
        }

        $vSwitchExists = Get-VMSwitch -Name $SETTeam -ErrorAction SilentlyContinue

        #TODO: Add to Test condition
        If ($vSwitchExists) {
            It "${env:ComputerName} The existing SET Team [$SETTeam] must have teaming enabled" {
                $vSwitchExists.EmbeddedTeamingEnabled | Should be $true
            }
        }
    }
}


Describe 'SETTeam' {
    Context SETTeam {

        It "The virtual switch [$VirtualSwitch] should have SR-IOV enabled" {
            $VMSwitch.IovEnabled | Should be $true
        }

        It "The virtual switch [$VirtualSwitch] SR-IOV Support Reasons property should be empty" {
            (Get-VMSwitch).IovSupportReasons | Should be $null
        }
    }
}