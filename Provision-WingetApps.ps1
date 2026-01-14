# TODO:
# - Download surface selfhost center
# - Support Edge extensions
# - Open ABS tool

<#
.SYNOPSIS
    Automates installation of Windows applications using winget with configuration management.

.DESCRIPTION
    Provision-WingetApps.ps1 provides a streamlined way to install and manage Windows applications 
    using the Windows Package Manager (winget). It supports interactive mode, configuration tracking 
    via JSON files, dry-run previews, and comprehensive logging.

    Key features:
    - Install apps from a JSON configuration file
    - Interactive mode for selective installation
    - Install and automatically track new apps to JSON
    - WhatIf mode for dry-run previews
    - Full transcript logging support

.PARAMETER Interactive
    Prompts for confirmation before installing each application from the list.
    Allows selective installation with Y (Yes), N (No), or A (All remaining) options.

.PARAMETER WhatIf
    Shows what would be installed without making any actual changes.
    Useful for previewing installation plans or testing configurations.

.PARAMETER InstallAndTrack
    Installs specified applications and automatically adds them to the apps.json tracking file.
    Accepts one or more winget package IDs (e.g., "Git.Git", "Microsoft.PowerShell").
    Avoids adding duplicates to the tracking file.

.PARAMETER AppsFile
    Specifies a custom JSON file containing the list of applications to install.
    If not provided, uses apps.json in the script's directory.
    Supports both absolute and relative paths.

.PARAMETER LogFile
    Enables transcript logging to the specified file path.
    Captures all console output including winget installation progress.
    Supports both absolute and relative paths.
    Automatically creates the log directory if it doesn't exist.

.EXAMPLE
    .\Provision-WingetApps.ps1
    
    Installs all applications listed in apps.json (in the script directory) silently.

.EXAMPLE
    .\Provision-WingetApps.ps1 -Interactive
    
    Prompts for confirmation before installing each app from apps.json.

.EXAMPLE
    .\Provision-WingetApps.ps1 -WhatIf
    
    Shows what applications would be installed without actually installing them.

.EXAMPLE
    .\Provision-WingetApps.ps1 -InstallAndTrack "Git.Git","Microsoft.PowerShell"
    
    Installs Git and PowerShell, then adds them to apps.json for tracking.

.EXAMPLE
    .\Provision-WingetApps.ps1 -AppsFile "C:\Config\my-apps.json"
    
    Installs apps from a custom JSON file instead of the default apps.json.

.EXAMPLE
    .\Provision-WingetApps.ps1 -LogFile "install.log"
    
    Installs apps and logs all output to install.log in the current directory.

.EXAMPLE
    .\Provision-WingetApps.ps1 -Interactive -WhatIf -LogFile "preview.log"
    
    Interactive preview mode with logging - see what would be installed and log the session.

.NOTES
    File Name      : Provision-WingetApps.ps1
    Prerequisite   : Windows Package Manager (winget) must be installed
    Requires       : PowerShell 5.1 or later
    
    The script runs without elevation by default. Individual app installers will request 
    UAC elevation when needed. Some installers (like Spotify) require non-elevated context.

.LINK
    https://github.com/microsoft/winget-cli
#>
param(
    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [string[]]$InstallAndTrack,

    [Parameter(Mandatory = $false)]
    [string]$AppsFile,

    [Parameter(Mandatory = $false)]
    [string]$LogFile
)



function Get-AppsFromJson {
    <#
    .SYNOPSIS
    Loads the list of apps from the JSON configuration file.
    .PARAMETER JsonPath
    Path to the JSON file containing the app list.
    .OUTPUTS
    Array of app IDs to install.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) {
        Write-Host "Error: JSON file not found at: $JsonPath" -ForegroundColor Red
        Write-Host " " 
        Write-Host "Would you like to create a new apps.json file with example apps? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        
        if ($response -ieq 'Y') {
            $exampleConfig = @{
                apps = @(
                    "Microsoft.PowerShell",
                    "Git.Git",
                    "Microsoft.VisualStudioCode"
                )
            }
            
            $exampleConfig | ConvertTo-Json -Depth 10 | Set-Content $JsonPath -Encoding UTF8
            Write-Host "Created example apps.json at: $JsonPath" -ForegroundColor Green
            Write-Host "Please edit this file to add your desired applications, then run the script again." -ForegroundColor Cyan
            exit 0
        } else {
            throw "Configuration file not found"
        }
    }

    $appsConfig = Get-Content $JsonPath -Raw | ConvertFrom-Json
    $apps = @($appsConfig.apps | ForEach-Object { $_.ToString() })

    Write-Host "Loaded $($apps.Count) apps from $JsonPath" -ForegroundColor Cyan
    
    return $apps
}

function Add-AppsToJson {
    <#
    .SYNOPSIS
    Adds new apps to the JSON configuration file, avoiding duplicates.
    .PARAMETER JsonPath
    Path to the JSON file.
    .PARAMETER NewApps
    Array of app IDs to add.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonPath,

        [Parameter(Mandatory = $true)]
        [array]$NewApps
    )

    # Load existing apps or start with empty array
    $existingApps = if (Test-Path $JsonPath) { 
        @((Get-Content $JsonPath -Raw | ConvertFrom-Json).apps)
    } else { 
        @() 
    }

    # Add new apps, avoiding duplicates
    $added = @()
    $skipped = @()
    
    foreach ($app in $NewApps) {
        if ($existingApps -contains $app) {
            $skipped += $app
        } else {
            $existingApps += $app
            $added += $app
        }
    }

    # Save updated JSON
    @{ apps = $existingApps } | ConvertTo-Json -Depth 10 | Set-Content $JsonPath -Encoding UTF8

    # Report results
    if ($added.Count -gt 0) {
        Write-Host "`nAdded $($added.Count) app(s) to $JsonPath`:" -ForegroundColor Green
        foreach ($app in $added) {
            Write-Host "  + $app" -ForegroundColor Green
        }
    }
    
    if ($skipped.Count -gt 0) {
        Write-Host "`nSkipped $($skipped.Count) app(s) (already in list):" -ForegroundColor Yellow
        foreach ($app in $skipped) {
            Write-Host "  - $app" -ForegroundColor Yellow
        }
    }
}

function Install-AndTrackApps {
    <#
    .SYNOPSIS
    Installs apps via winget and adds them to the apps.json tracking file.
    .PARAMETER Apps
    Array of app IDs to install and track.
    .PARAMETER JsonPath
    Path to the JSON file for tracking installed apps.
    .PARAMETER WhatIf
    If set, shows what would be done without making changes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Apps,

        [Parameter(Mandatory = $true)]
        [string]$JsonPath,

        [Parameter(Mandatory = $false)]
        [switch]$WhatIf
    )

    Write-Host "`n=== Install and Track Apps ===" -ForegroundColor Yellow
    Write-Host "Apps to install and add to tracking: $($Apps.Count)`n" -ForegroundColor Cyan

    # Add apps to JSON first, before attempting installation
    if ($Apps.Count -gt 0) {
        if (-not $WhatIf) {
            Add-AppsToJson -JsonPath $JsonPath -NewApps $Apps
        } else {
            Write-Host "WhatIf: Would add $($Apps.Count) app(s) to $JsonPath`n" -ForegroundColor Magenta
        }
    }

    # Install apps using the shared installation function
    $result = Install-WingetApps -Apps $Apps -WhatIf:$WhatIf

    # Report results
    Write-Host "`n=== Installation Summary ===" -ForegroundColor Yellow
    Write-Host "Successful: $($result.Successful.Count)" -ForegroundColor Green
    if ($result.Failed.Count -gt 0) {
        Write-Host "Failed: $($result.Failed.Count)" -ForegroundColor Red
    }
}

function Get-UserConfirmation {
    <#
    .SYNOPSIS
    Prompts the user to confirm installation for each app.
    .PARAMETER Apps
    Array of app IDs to potentially install.
    .OUTPUTS
    Array of app IDs that the user confirmed for installation.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Apps
    )

    Write-Host "`n=== Interactive App Selection ===" -ForegroundColor Yellow
    Write-Host "Please confirm which apps you want to install." -ForegroundColor Cyan
    Write-Host "Press 'Y' for Yes, 'N' for No, or 'A' to install All remaining apps.`n" -ForegroundColor Cyan

    $confirmedApps = @()
    $installAll = $false

    for ($i = 0; $i -lt $Apps.Count; $i++) {
        $app = $Apps[$i]
        
        if ($installAll) {
            $confirmedApps += $app
            Write-Host "[$($i + 1)/$($Apps.Count)] $app - Auto-confirmed (All)" -ForegroundColor Green
            continue
        }

        do {
            $prompt = "[$($i + 1)/$($Apps.Count)] Install $app ? (Y/N/A)"
            $response = Read-Host $prompt
            $response = $response.Trim()
            
            if ($response -ieq 'Y') {
                $confirmedApps += $app
                Write-Host "  Confirmed" -ForegroundColor Green
                $validInput = $true
            }
            elseif ($response -ieq 'N') {
                Write-Host "  Skipped" -ForegroundColor Yellow
                $validInput = $true
            }
            elseif ($response -ieq 'A') {
                $confirmedApps += $app
                $installAll = $true
                Write-Host "  Installing this and all remaining apps" -ForegroundColor Green
                $validInput = $true
            }
            else {
                Write-Host "  Invalid input. Please enter Y, N, or A." -ForegroundColor Red
                $validInput = $false
            }
        } while (-not $validInput)
    }

    Write-Host "`n=== Confirmation Complete ===" -ForegroundColor Yellow
    Write-Host "Apps to install: $($confirmedApps.Count) of $($Apps.Count)" -ForegroundColor Cyan
    
    if ($confirmedApps.Count -gt 0) {
        Write-Host "Selected apps:" -ForegroundColor Cyan
        foreach ($app in $confirmedApps) {
            Write-Host "  - $app" -ForegroundColor White
        }
    }

    return $confirmedApps
}

function Install-WingetApps {
    <#
    .SYNOPSIS
    Installs applications using winget.
    .PARAMETER Apps
    Array of app IDs to install.
    .PARAMETER WhatIf
    If set, shows what would be installed without actually installing.
    .OUTPUTS
    Hashtable with 'Successful' and 'Failed' arrays of app IDs.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Apps,

        [Parameter(Mandatory = $false)]
        [switch]$WhatIf
    )

    $successful = @()
    $failed = @()

    if ($Apps.Count -eq 0) {
        Write-Host "No apps to install." -ForegroundColor Yellow
        return @{ Successful = $successful; Failed = $failed }
    }

    if ($WhatIf) {
        Write-Host "`n=== WhatIf Mode: Showing what would be installed ===" -ForegroundColor Magenta
        foreach ($app in $Apps) {
            Write-Host "WhatIf: Would install $app" -ForegroundColor Magenta
            $successful += $app
        }
        Write-Host "`nTotal apps that would be installed: $($Apps.Count)" -ForegroundColor Magenta
    } else {
        Write-Host "`n=== Starting Installation ===" -ForegroundColor Yellow
        foreach ($app in $Apps) {
            Write-Host "`nInstalling $app..." -ForegroundColor Cyan
            winget install --id $app --silent --accept-package-agreements --accept-source-agreements | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                $successful += $app
                Write-Host "  ✓ Successfully installed $app" -ForegroundColor Green
            } else {
                $failed += $app
                Write-Host "  ✗ Failed to install $app" -ForegroundColor Red
            }
        }
    }

    return @{ Successful = $successful; Failed = $failed }
}

function Start-AppInstallation {
    <#
    .SYNOPSIS
    Main function that orchestrates the app installation process.
    .PARAMETER Interactive
    If set, prompts for confirmation for each app before installation.
    .PARAMETER JsonPath
    Path to the JSON file containing the app list.
    .PARAMETER WhatIf
    If set, shows what would be installed without actually installing.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Interactive,

        [Parameter(Mandatory = $true)]
        [string]$JsonPath,

        [Parameter(Mandatory = $false)]
        [switch]$WhatIf
    )

    Write-Host "`nExecuting main script..." -ForegroundColor Cyan
    
    # Display mode
    $mode = @()
    if ($WhatIf) { $mode += "WhatIf" }
    if ($Interactive) { $mode += "Interactive" }
    if ($mode.Count -eq 0) { $mode += "Silent" }
    
    Write-Host "Mode: $($mode -join ', ')" -ForegroundColor Cyan

    try {
        # Load apps from JSON
        $apps = Get-AppsFromJson -JsonPath $JsonPath

        # Get user confirmation if in interactive mode
        if ($Interactive) {
            $apps = Get-UserConfirmation -Apps $apps
        }

        # Install apps
        $result = Install-WingetApps -Apps $apps -WhatIf:$WhatIf

        if ($WhatIf) {
            Write-Host "`nWhatIf: Script completed (no actual changes made)!" -ForegroundColor Magenta
        } else {
            Write-Host "`nScript completed successfully!" -ForegroundColor Green
            if ($result.Failed.Count -gt 0) {
                Write-Host "Note: $($result.Failed.Count) app(s) failed to install." -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "`nScript failed: $_" -ForegroundColor Red
        throw
    }
}

# Main execution
try {
    # Setup transcript logging if LogFile parameter is provided
    if ($LogFile) {
        if (-not [System.IO.Path]::IsPathRooted($LogFile)) {
            $LogFile = Join-Path $PWD $LogFile
        }
        
        $logDir = Split-Path -Parent $LogFile
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        Start-Transcript -Path $LogFile -Append
        Write-Host "`n=== Script execution started ===" -ForegroundColor Cyan
    }

    # Resolve JSON file path
    $jsonPath = if ($AppsFile) { 
        if ([System.IO.Path]::IsPathRooted($AppsFile)) { $AppsFile } else { Join-Path $PWD $AppsFile }
    } else { 
        Join-Path $PSScriptRoot "apps.json" 
    }

    if ($InstallAndTrack) {
        # Install and track new apps
        Install-AndTrackApps -Apps $InstallAndTrack -JsonPath $jsonPath -WhatIf:$WhatIf
    } else {
        # Run normal installation from JSON
        Start-AppInstallation -Interactive:$Interactive -JsonPath $jsonPath -WhatIf:$WhatIf
    }

    if ($LogFile) {
        Write-Host "`n=== Script execution completed successfully ===" -ForegroundColor Cyan
        Stop-Transcript
    }
    
    exit 0
}
catch {
    Write-Host "`n=== FATAL ERROR ===" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    
    if ($LogFile) {
        Write-Host "`n=== Script execution failed ===" -ForegroundColor Red
        Stop-Transcript
    }
    
    exit 1
}