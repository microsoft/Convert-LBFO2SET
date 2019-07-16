Function Convert-LBFO2Set {
<#
    .SYNOPSIS
        This is the synopsis

    .DESCRIPTION
        This is the description

    .PARAMETER param1
        Description of Param1

    .PARAMETER param2
        Description of Param1

    .EXAMPLE
        Convert-LBFO2Set -Param1 xyz

    .EXAMPLE
        Convert-LBFO2Set -Param1 xyz -Param2

    .NOTES
        Author: Microsoft Core Networking team and the Networking Blackbelts

        Please file issues on GitHub @ GitHub.com/Microsoft/Convert-LBFO2SET

    .LINK
        More projects               : https://github.com/topics/msftnet
        Windows Networking Blog     : https://blogs.technet.microsoft.com/networking/
#>

    $here = Split-Path -Parent $PSScriptRoot

    $ValidationResults = Invoke-Pester -Script "$here\tests\unit\unit.tests.ps1" -PassThru
    $ValidationResults | Select-Object -Property TagFilter, Time, TotalCount, PassedCount, FailedCount, SkippedCount, PendingCount | Format-Table -AutoSize

    If ($ValidationResults.FailedCount -ne 0) { Write-Host 'Prerequisite checks have failed.' ; Break }


}

# Main conversion script.
<#
#requires -Version 5.1
#requires -RunAsAdministrator
#requires -Modules NetLbfo
#>
<#
To-do

 - Everything...

 Steps:

 1.   Get current LBFO config. - DONE
 2.   Validate that the current config can be 1:1 converted. - DONE
 2.5. Install Hyper-V if it's missing. - DONE
 3.   Generates prompts for validation errors that will allow the script to continue or stop. - DONE
       a. Invalid SET algorithm: AddressHash - DONE
       b. LACP/Static - DONE
 4.   Backup the current LBFO setup. - DONE
 5.   Convert LBFO to SET.
 6.   Validate config.
 7.   Revert if there was a failure.

#>

######################
###   PARAMETERS   ###
######################

param (
    [string]$Path = "$PSScriptRoot",

    # Overrides whatever the current Load Balance algorithm is and uses Hyper-V Port in the SET team. Needed for automation purposes to bypass the prompt.
    [switch]$useHyperVPort,

    # TODO: [DC] Let's discuss this; it's probably wiser just to warn/prompt since this requires a reboot etc.
    # Forces a Hyper-V installation, if not already installed. This will reboot the server automatically after 60 seconds.
    [switch]$forceHyperVInstall
)


######################
###   VARIABLES    ###
######################
#region

# log, config, etc. files get saved here
$script:dataPath = $Path

# name of the execution log file
$script:logName = "Convert-Lbfo2Set_log.log"

# list of unsupported load balacing algorithms
[array]$badLbAlg = "IPAddresses", "MacAddresses", "TransportPorts"

# list of unsupported teaming modes
[array]$badTM = "Static", "LACP"

# collect the current LBFO state
[array]$LBFO = Get-NetLbfoTeam

#endregion


######################
###   FUNCTIONS    ###
######################
#region

# FUNCTION: Get-TimeStamp
# PURPOSE:  Returns a timestamp string

function Get-TimeStamp
{
    return "$(Get-Date -format "yyyyMMdd_HHmmss_ffff")"
} # end Get-TimeStamp


# FUNCTION: Write-Log
# PURPOSE:  Writes script information to a log file and to the screen when -Verbose or -tee is set.

function Write-Log {
    param ([string]$text, [switch]$tee = $false, [string]$foreColor = $null)

    $foreColors = "Black","Blue","Cyan","DarkBlue","DarkCyan","DarkGray","DarkGreen","DarkMagenta","DarkRed","DarkYellow","Gray","Green","Magenta","Red","White","Yellow"

    # check the log file, create if missing
    $isPath = Test-Path "$script:dataPath\$script:logName"
    if (!$isPath) {
        "$(Get-TimeStamp): Log started" | Out-File "$script:dataPath\$script:logName" -Force
        "$(Get-TimeStamp): Local log file path: $("$script:dataPath\$script:logName")" | Out-File "$script:dataPath\$script:logName" -Force
        Write-Verbose "Local log file path: $("$script:dataPath\$script:logName")"
    }

    # write to log
    "$(Get-TimeStamp): $text" | Out-File "$script:dataPath\$script:logName" -Append

    # write text verbosely
    Write-Verbose $text

    if ($tee)
    {
        # make sure the foreground color is valid
        if ($foreColors -contains $foreColor -and $foreColor)
        {
            Write-Host -ForegroundColor $foreColor $text
        } else {
            Write-Host $text
        }
    }
} # end Write-Log


# FUNCTION: New-TextMenu
# PURPOSE:  Creates a text-based console menu.
#
# $options are an array of hashtables contaning a label and a helpMessage.
# Example: (@{Label="First Option";  helpMessage="Something helpful."}, @{Label="Second Option";  helpMessage="More help."})
#
# Output is the

function New-TextMenu
{
    param(
        [string]$caption,
        [string]$message,
        [array]$options
    )

    $count = 0
    $opts = '$options = [System.Management.Automation.Host.ChoiceDescription[]]('

    foreach ($option in $options) {

        Invoke-Expression "`$o$count = New-Object System.Management.Automation.Host.ChoiceDescription `"`&$($option.Label)`n`"`, `"$($option.helpMessage)`""

        $opts += "`$o$count`,"

        $count++
    }

    $oQuit = New-Object System.Management.Automation.Host.ChoiceDescription "&Quit", "Quit menu. Will abort if no NIC selected."
    $opts += '$oQuit)'

    Invoke-Expression "`$options = $opts"

    $result = $host.ui.PromptForChoice($caption, $message, $options, 0)

    return $result

} # end New-TextMenu



#endregion


######################
###   VALIDATION   ###
######################
#region

# check whether an unsupported teaming mode or LB algorithm is in use
foreach ($team in $LBFO)
{
    # compare against list of unsupport teaming modes
    if ($team.TeamingMode -in $badTM)
    {
        throw ("$($team.TeamingMode) is an unsupported Teaming Mode in SET. The the switch configuration must be disabled and LBFO changed to Switch Independent for the conversion to work.")
    }

    # now check the algorithm.
    # Ignored when -useHyperVPort set.
    if (!$useHyperVPort -and $team.LoadBalancingAlgorithm -in $badLbAlg)
    {
        $Local:message = @"
A pre-requisite check has failed: The $($team.LoadBalancingAlgorithm) algorithm is not supported in SET.
The Microsoft recommendation is to switch to the Hyper-V Port algorithm.
Please quit if testing is needed before converting to Hyper-V Port.

S - Switch to Hyper-V Port
Q - Quit

"@

        $Local:options = @{Label="S - Switch to Hyper-V Port";  helpMessage="Continue converting LBFO to SET and switch to the Hyper-V Port algorithm."}

        $Local:result = New-TextMenu -caption "Unsupport load balance algorithm detected!" -message $Local:message -options $options

        switch ($Local:result)
        {
            # switch to Hyper-V Port
            0 {
                # set $useHyperVPort to $true
                $useHyperVPort = $true
            }

            1 {
                throw ("Execution ended by user prompt. Exit reason: Unsupported LB algorithm `($($team.LoadBalancingAlgorithm)`).")
            }
        }
    }
}

# test dataPath
$isDPFnd = Get-Item $script:dataPath -EA SilentlyContinue

if (!$isDPFnd)
{
    # try to create it
    try
    {
        New-Item -Path $script:dataPath -ItemType Directory -Force -EA Stop | Write-Log
    }
    catch
    {
        throw ("Could not create the data path. This is needed for backing up the current configuration and logging. Error: $($error[0].ToString())")
    }
}

# need to make sure the New-VMSwitch command is available
$isNvmsFnd =  Get-Command New-VMSwitch -EA SilentlyContinue

if (!$forceHyperVInstall -and !$isNvmsFnd)
{
    # need to install Hyper-V role. Prompt first.
    $Local:message = @"
A pre-requisite check has failed: The Hyper-V role is not installed.
The Hyper-V role is needed to configure SET. You do not need to use Hyper-V,
but it must be installed.

Installing Hyper-V requires a reboot, and the same user must logon post-reboot
for the installation to complete. The process is handled by the script with a
60 seconds delay before the reboot.

Please rerun the script after the reboot.

I - Install Hyper-V (reboot required)
Q - Quit

"@

        $Local:options = @{Label="I - Install Hyper-V (reboot required)";  helpMessage="Install the Hyper-V role and reboot."}

        $Local:result = New-TextMenu -caption "Required feature or role is missing!" -message $Local:message -options $options

        switch ($Local:result)
        {
            # install Hyper-V and reboot
            0 {
                try
                {
                    Install-WindowsFeature Hyper-V -IncludeAllSubFeature -IncludeManagementTools -Confirm:$false -ErrorAction Stop
                }
                catch
                {
                    throw ("The Hyper-V installation failed. Error: $($Error[0].ToString())")
                }

                # using legacy shutdown to notify all users on the system
                shutdown --% /r /t 60 /c "Installing Hyper-V. Reboot in 60 seconds." /d p:2:3
            }

            1 {
                throw ("Execution ended by user prompt. Exit reason: Hyper-V is not installed.")
            }
        }
} elseif ($forceHyperVInstall -and !$isNvmsFnd)
{
    try
    {
        Install-WindowsFeature Hyper-V -IncludeAllSubFeature -IncludeManagementTools -Confirm:$false -ErrorAction Stop
    }
    catch
    {
        throw ("The Hyper-V installation failed. Error: $($Error[0].ToString())")
    }

    # using legacy shutdown to notify all users on the system
    shutdown --% /r /t 60 /c "Installing Hyper-V. Reboot in 60 seconds." /d p:2:3
}

#endregion


######################
###      MAIN      ###
######################

# backup the LBFO details to file
try
{
    $LBFO | Format-List * | Out-String | Out-File -FilePath "$script:dataPath\LBFO_settings.txt" -Force -EA Stop
}
catch
{
    throw ("Could not backup the LBFO settings. Error: $($error[0].ToString())")
}


## Convert LBFO to SET ##
# backup the IP details. Filter out IPv6 link-local address (FE80:)
$tIP = Get-NetIPAddress -InterfaceAlias $LBFO.Name | Where-Object { $_.IPAddress -notmatch "^fe80:.*$" }



Write-Verbose "Work complete!"
