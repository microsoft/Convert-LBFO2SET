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

        If ($AllowOutage -eq $false) {
            It "$LBFOTeam should have at least two adapters" {
                $configData.NetLBFOTeam.Members.Count | Should BeGreaterThan 1
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