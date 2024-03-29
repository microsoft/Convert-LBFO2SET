Describe "$($env:repoName)-Manifest" {
    BeforeAll {
      $DataFile   = Import-PowerShellDataFile .\$($env:repoName).psd1 -ErrorAction Stop
      $TestModule = Test-ModuleManifest .\$($env:repoName).psd1 -ErrorAction Stop
      
      Import-Module .\$($env:repoName).psd1 -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
      $command = Get-Command $($env:repoName) -ErrorAction SilentlyContinue
	  
	  $module = Find-Module -Name 'Pester' -ErrorAction SilentlyContinue
	  
	  $testCommand = Get-Command Convert-LBFO2SET
    }
    Context Manifest-Validation {
        It "[Import-PowerShellDataFile] - $($env:repoName).psd1 is a valid PowerShell Data File" {
            $DataFile | Should -Not -BeNullOrEmpty
        }

        It "[Test-ModuleManifest] - $($env:repoName).psd1 should not be empty" {
            $TestModule | Should -Not -BeNullOrEmpty
        }

        It "Should have the $($env:repoName) function available" {
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context "Required Modules" {
            It "Should contain the Pester Module" {
                'Pester' -in ($TestModule).RequiredModules.Name | Should -Be $true
            }

            It "The Pester module should be available in the PowerShell gallery" {
                $module | Should -Not -BeNullOrEmpty
            }
    }

    Context ExportedContent {
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
