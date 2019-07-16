Describe 'Convert-LBFO2SET' {
    Context PreValidation {
        $NodeOS = Get-CimInstance -ClassName 'Win32_OperatingSystem'

        ### Verify the Host is sufficient version
        It "${env:ComputerName} must be Windows Server 2016, or Server 2019" {
            $NodeOS.Caption | Should be ($NodeOS.Caption -like '*Windows Server 2016*' -or $NodeOS.Caption -like '*Windows Server 2019*')
        }

        $HyperVInstallation = (Get-WindowsFeature -Name Hyper-V -ComputerName $system).InstallState
        $VMSwitch = Get-VMSwitch -Name $VirtualSwitch -CimSession $system -ErrorAction SilentlyContinue

        It "${env:ComputerName} must have Hyper-V installed" {
            $HyperVInstallation | Should be 'Installed'
        }

        It "The virtual switch [$VirtualSwitch] should exist on the Hyper-V Host [$system]" {
            $VMSwitch | Should not BeNullOrEmpty
        }

        It "The virtual switch [$VirtualSwitch] should have SR-IOV enabled" {
            $VMSwitch.IovEnabled | Should be $true
        }

        It "The virtual switch [$VirtualSwitch] SR-IOV Support Reasons property should be empty" {
            (Get-VMSwitch).IovSupportReasons | Should be $null
        }
    }
}