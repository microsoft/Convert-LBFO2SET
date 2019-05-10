# Main conversion script.

#requires -Version 5.1
#requires -RunAsAdministrator
#requires -Modules NetLbfo, NetSwitchTeam, "Hyper-V"

<#
HELP SECTION

#>

<#
To-do

 - Everything...

#>

######################
###   PARAMETERS   ###
######################

param (


    [string]$Path = "$PSScriptRoot"
)


######################
###   VARIABLES    ###
######################
#region

# log, config, etc. files get saved here
$script:dataPath = $Path

# name of the execution log file
$script:logName = "Convert-Lbfo2Set_log.log"


#endregion


######################
###   FUNCTIONS    ###
######################
#region

# FUNCTION: Get-TimeStamp
# PURPOSE: Returns a timestamp string

function Get-TimeStamp 
{
    return "$(Get-Date -format "yyyyMMdd_HHmmss_ffff")"
} # end Get-TimeStamp


# FUNCTION: Write-Log
# PURPOSE: Writes script information to a log file and to the screen when -Verbose or -tee is set.

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

#endregion


######################
###   VALIDATION   ###
######################
#region

#endregion


######################
###      MAIN      ###
######################





Write-Verbose "Work complete!"
