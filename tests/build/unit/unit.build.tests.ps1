Describe "$($env:repoName)-Manifest" {
    $DataFile   = Import-PowerShellDataFile .\$($env:repoName).psd1 -ErrorAction SilentlyContinue
    $TestModule = Test-ModuleManifest       .\$($env:repoName).psd1 -ErrorAction SilentlyContinue

    Context Manifest-Validation {
        It "[Import-PowerShellDataFile] - $($env:repoName).psd1 is a valid PowerShell Data File" {
            $DataFile | Should Not BeNullOrEmpty
        }

        It "[Test-ModuleManifest] - $($env:repoName).psd1 should not be empty" {
            $TestModule | Should Not BeNullOrEmpty
        }

        Import-Module .\$($env:repoName).psd1 -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $command = Get-Command $($env:repoName) -ErrorAction SilentlyContinue

        It "Should have the $($env:repoName) function available" {
            $command | Should not BeNullOrEmpty
        }
    }

    Context "Required Modules" {
        'Pester' | ForEach-Object {
            $module = Find-Module -Name $_ -ErrorAction SilentlyContinue

            It "Should contain the $_ Module" {
                $_ -in ($TestModule).RequiredModules.Name | Should be $true
            }

            It "The $_ module should be available in the PowerShell gallery" {
                $module | Should not BeNullOrEmpty
            }
        }
    }

    Context ExportedContent {
        $testCommand = Get-Command Convert-LBFO2SET

        It 'Should default the LBFOTeam mandatory param' {
            Get-Command Convert-LBFO2SET | Should -HaveParameter LBFOTeam -Mandatory
        }

        It 'Should default the SETTeam param to $false' {
            Get-Command Convert-LBFO2SET | Should -HaveParameter SETTeam -Mandatory
        }

        It 'Should default the AllowOutage param to $false' {
            Get-Command Convert-LBFO2SET | Should -HaveParameter AllowOutage -DefaultValue $false
        }

        It 'Should default the EnableBestPractices param to $false' {
            Get-Command Convert-LBFO2SET | Should -HaveParameter EnableBestPractices -DefaultValue $false
        }
    }
}
