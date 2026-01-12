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

# Script-level variable for logging
$script:LogFilePath = $null

function Test-IsAdministrator {
    <#
    .SYNOPSIS
    Checks if the current PowerShell session is running as Administrator.
    #>
    $currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ScriptDirectory {
    <#
    .SYNOPSIS
    Gets the directory where the script is located, with fallbacks for different execution contexts.
    .OUTPUTS
    String path to the script directory.
    #>
    if ($PSScriptRoot) {
        return $PSScriptRoot
    } elseif ($MyInvocation.MyCommand.Path) {
        return Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        return $PWD.Path
    }
}

function Write-Log {
    <#
    .SYNOPSIS
    Writes a message to both console and log file (if logging is enabled).
    .PARAMETER Message
    The message to write.
    .PARAMETER Color
    Optional foreground color for console output.
    .PARAMETER NoNewline
    If set, doesn't add a newline after the message.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Color,

        [Parameter(Mandatory = $false)]
        [switch]$NoNewline
    )

    # Write to console
    if ($Color) {
        if ($NoNewline) {
            Write-Host $Message -ForegroundColor $Color -NoNewline
        } else {
            Write-Host $Message -ForegroundColor $Color
        }
    } else {
        if ($NoNewline) {
            Write-Host $Message -NoNewline
        } else {
            Write-Host $Message
        }
    }

    # Write to log file if enabled
    if ($script:LogFilePath) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$timestamp] $Message" | Out-File -FilePath $script:LogFilePath -Append -Encoding UTF8
    }
}

function Set-ExecutionPolicyIfNeeded {
    <#
    .SYNOPSIS
    Checks and sets the execution policy if it's not permissive enough.
    #>
    $effectivePolicy = Get-ExecutionPolicy

    if ($effectivePolicy -ne 'Unrestricted' -and $effectivePolicy -ne 'Bypass') {
        Write-Log "Current effective execution policy is: $effectivePolicy" -Color Yellow
        Write-Log "Attempting to elevate and set to Unrestricted..." -Color Yellow
        
        $isAdmin = Test-IsAdministrator
        
        if (-not $isAdmin) {
            # Not admin - relaunch as administrator
            $scriptPath = $MyInvocation.MyCommand.Path
            
            # Build parameter string
            $paramString = ""
            if ($Interactive) { $paramString += "-Interactive " }
            if ($WhatIf) { $paramString += "-WhatIf " }
            if ($InstallAndTrack) { 
                $paramString += "-InstallAndTrack "
                foreach ($app in $InstallAndTrack) {
                    $paramString += "`"$app`","
                }
                $paramString = $paramString.TrimEnd(',') + " "
            }
            if ($AppsFile) { $paramString += "-AppsFile `"$AppsFile`" " }
            if ($LogFile) { $paramString += "-LogFile `"$LogFile`" " }
            
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $paramString"
            exit 0
        }
        
        # Running as admin - set execution policy at the highest available scope
        try {
            # Try LocalMachine scope first (requires admin)
            Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Stop
            Write-Log "Execution policy set to Unrestricted at LocalMachine scope!" -Color Green
        }
        catch {
            # If LocalMachine fails, try Process scope as fallback
            try {
                Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force -ErrorAction Stop
                Write-Log "Execution policy set to Unrestricted for current process" -Color Yellow
                Write-Log "Note: This setting will only last for this PowerShell session" -Color Yellow
            }
            catch {
                Write-Log "Could not set execution policy: $_" -Color Yellow
                Write-Log "Continuing with current policy (script launched with Bypass)..." -Color Cyan
            }
        }
        
        # Verify the effective policy
        $newPolicy = Get-ExecutionPolicy
        Write-Log "Current effective policy is now: $newPolicy" -Color Cyan
    }
    else {
        Write-Log "Execution policy is already permissive ($effectivePolicy)" -Color Green
    }
}

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
        Write-Log "Error: JSON file not found at: $JsonPath" -Color Red
        Write-Log " " 
        Write-Log "Would you like to create a new apps.json file with example apps? (Y/N)" -Color Yellow
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
            Write-Log "Created example apps.json at: $JsonPath" -Color Green
            Write-Log "Please edit this file to add your desired applications, then run the script again." -Color Cyan
            exit 0
        } else {
            throw "Configuration file not found"
        }
    }

    $appsConfig = Get-Content $JsonPath -Raw | ConvertFrom-Json
    $apps = @($appsConfig.apps | ForEach-Object { $_.ToString() })

    Write-Log "Loaded $($apps.Count) apps from $JsonPath" -Color Cyan
    
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

    # Create backup if file exists
    if (Test-Path $JsonPath) {
        $backupPath = "$JsonPath.backup"
        Copy-Item -Path $JsonPath -Destination $backupPath -Force
        Write-Log "Created backup at: $backupPath" -Color DarkGray
        
        $appsConfig = Get-Content $JsonPath -Raw | ConvertFrom-Json
        $existingApps = @($appsConfig.apps)
    } else {
        $existingApps = @()
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
    $updatedConfig = @{
        apps = $existingApps
    }
    
    $updatedConfig | ConvertTo-Json -Depth 10 | Set-Content $JsonPath -Encoding UTF8

    # Report results
    if ($added.Count -gt 0) {
        Write-Log ("`nAdded $($added.Count) app(s) to " + $JsonPath + ":") -Color Green
        foreach ($app in $added) {
            Write-Log "  + $app" -Color Green
        }
    }
    
    if ($skipped.Count -gt 0) {
        Write-Log "`nSkipped $($skipped.Count) app(s) (already in list):" -Color Yellow
        foreach ($app in $skipped) {
            Write-Log "  - $app" -Color Yellow
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

    Write-Log "`n=== Install and Track Apps ===" -Color Yellow
    Write-Log ("Apps to install and add to tracking: $($Apps.Count)`n") -Color Cyan

    if ($WhatIf) {
        Write-Log "WhatIf: Would install the following apps:" -Color Magenta
        foreach ($app in $Apps) {
            Write-Log "  WhatIf: Would install $app" -Color Magenta
        }
        Write-Log "`nWhatIf: Would add these apps to apps.json" -Color Magenta
    } else {
        # Install each app
        $successful = @()
        $failed = @()

        foreach ($app in $Apps) {
            Write-Log "Installing $app..." -Color Cyan
            winget install --id $app --silent --accept-package-agreements --accept-source-agreements | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                $successful += $app
                Write-Log "  ✓ Successfully installed $app" -Color Green
            } else {
                $failed += $app
                Write-Log "  ✗ Failed to install $app" -Color Red
            }
        }

        # Add successful installations to JSON
        if ($successful.Count -gt 0) {
            Add-AppsToJson -JsonPath $JsonPath -NewApps $successful
        }

        # Report results
        Write-Log "`n=== Installation Summary ===" -Color Yellow
        Write-Log "Successful: $($successful.Count)" -Color Green
        if ($failed.Count -gt 0) {
            Write-Log "Failed: $($failed.Count)" -Color Red
            Write-Log "Failed apps were not added to tracking file." -Color Yellow
        }
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

    Write-Log "`n=== Interactive App Selection ===" -Color Yellow
    Write-Log "Please confirm which apps you want to install." -Color Cyan
    Write-Log "Press 'Y' for Yes, 'N' for No, or 'A' to install All remaining apps.`n" -Color Cyan

    $confirmedApps = @()
    $installAll = $false

    for ($i = 0; $i -lt $Apps.Count; $i++) {
        $app = $Apps[$i]
        
        if ($installAll) {
            $confirmedApps += $app
            Write-Log "[$($i + 1)/$($Apps.Count)] $app - Auto-confirmed (All)" -Color Green
            continue
        }

        do {
            $prompt = "[$($i + 1)/$($Apps.Count)] Install $app ? (Y/N/A)"
            $response = Read-Host $prompt
            $response = $response.Trim()
            
            if ($response -ieq 'Y') {
                $confirmedApps += $app
                Write-Log "  Confirmed" -Color Green
                $validInput = $true
            }
            elseif ($response -ieq 'N') {
                Write-Log "  Skipped" -Color Yellow
                $validInput = $true
            }
            elseif ($response -ieq 'A') {
                $confirmedApps += $app
                $installAll = $true
                Write-Log "  Installing this and all remaining apps" -Color Green
                $validInput = $true
            }
            else {
                Write-Log "  Invalid input. Please enter Y, N, or A." -Color Red
                $validInput = $false
            }
        } while (-not $validInput)
    }

    Write-Log "`n=== Confirmation Complete ===" -Color Yellow
    Write-Log "Apps to install: $($confirmedApps.Count) of $($Apps.Count)" -Color Cyan
    
    if ($confirmedApps.Count -gt 0) {
        Write-Log "Selected apps:" -Color Cyan
        foreach ($app in $confirmedApps) {
            Write-Log "  - $app" -Color White
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
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Apps,

        [Parameter(Mandatory = $false)]
        [switch]$WhatIf
    )

    if ($Apps.Count -eq 0) {
        Write-Log "No apps to install." -Color Yellow
        return
    }

    if ($WhatIf) {
        Write-Log "=== WhatIf Mode: Showing what would be installed ===" -Color Magenta
        foreach ($app in $Apps) {
            Write-Log "WhatIf: Would install $app" -Color Magenta
        }
        Write-Log "`nTotal apps that would be installed: $($Apps.Count)" -Color Magenta
    } else {
        Write-Log "=== Starting Installation ===" -Color Yellow
        foreach ($app in $Apps) {
            Write-Log "Installing $app..." -Color Cyan
            winget install --id $app --silent --accept-package-agreements --accept-source-agreements
        }
    }
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

    Write-Log "`nExecuting main script..." -Color Cyan
    Write-Log "Current execution policy: $(Get-ExecutionPolicy -Scope CurrentUser)"
    
    # Display mode
    $mode = @()
    if ($WhatIf) { $mode += "WhatIf" }
    if ($Interactive) { $mode += "Interactive" }
    if ($mode.Count -eq 0) { $mode += "Silent" }
    
    Write-Log "Mode: $($mode -join ', ')" -Color Cyan

    try {
        # Load apps from JSON
        $apps = Get-AppsFromJson -JsonPath $JsonPath

        # Get user confirmation if in interactive mode
        if ($Interactive) {
            $apps = Get-UserConfirmation -Apps $apps
        }

        # Install apps
        Install-WingetApps -Apps $apps -WhatIf:$WhatIf

        if ($WhatIf) {
            Write-Log "`nWhatIf: Script completed (no actual changes made)!" -Color Magenta
        } else {
            Write-Log "`nScript completed successfully!" -Color Green
        }
    }
    catch {
        Write-Log "`nScript failed: $_" -Color Red
        throw
    }
}

# Main execution
try {
    Set-ExecutionPolicyIfNeeded

    # Setup logging if LogFile parameter is provided
    if ($LogFile) {
        # Resolve to absolute path
        if (-not [System.IO.Path]::IsPathRooted($LogFile)) {
            $LogFile = Join-Path $PWD $LogFile
        }
        $script:LogFilePath = $LogFile
        
        # Create log file directory if it doesn't exist
        $logDir = Split-Path -Parent $LogFile
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        $startTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Log "=== Script execution started at $startTime ===" -Color Cyan
        Write-Log "Log file: $LogFile" -Color Cyan
    }

    # Resolve JSON file path to absolute path
    if ($AppsFile) {
        # Convert relative path to absolute
        if (-not [System.IO.Path]::IsPathRooted($AppsFile)) {
            $AppsFile = Join-Path $PWD $AppsFile
        }
        $jsonPath = $AppsFile
    } else {
        $scriptPath = Get-ScriptDirectory
        $jsonPath = Join-Path $scriptPath "apps.json"
    }

    if ($InstallAndTrack) {
        # Install and track new apps
        Install-AndTrackApps -Apps $InstallAndTrack -JsonPath $jsonPath -WhatIf:$WhatIf
    } else {
        # Run normal installation from JSON
        Start-AppInstallation -Interactive:$Interactive -JsonPath $jsonPath -WhatIf:$WhatIf
    }

    if ($script:LogFilePath) {
        $endTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Log "=== Script execution completed successfully at $($endTime) ===" -Color Cyan
    }
    
    pause
    exit 0
}
catch {
    Write-Log "`n=== FATAL ERROR ===" -Color Red
    Write-Log "Error: $_" -Color Red
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Color Red
    
    if ($script:LogFilePath) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Log "=== Script execution failed at $($timestamp) ===" -Color Red
    }
    
    pause
    exit 1
}