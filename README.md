# Provision-WingetApps

A comprehensive PowerShell script to quickly provision a configured set of apps via winget following a Windows clean install.

## Synopsis

`Provision-WingetApps.ps1` is a PowerShell script that automates the installation of Windows applications using the Windows Package Manager (winget). It reads a list of applications from a JSON configuration file and installs them silently with extensive logging and error handling.

## Description

This script provides a streamlined way to install multiple applications after a fresh Windows installation. It supports interactive app selection, includes a WhatIf mode for testing, allows adding new apps to the tracking file, supports custom configuration files, and provides comprehensive logging capabilities.

### Features

- **Automatic Installation**: Silently installs all apps from the configuration file
- **Interactive Mode**: Prompt for confirmation before installing each app (Y/N/A responses)
- **WhatIf Mode**: Preview what would be installed without making changes
- **Install and Track**: Install new apps and automatically add them to your tracking file
- **Custom Configuration Files**: Specify alternative JSON files for different app sets
- **Comprehensive Logging**: Log all operations to a file with timestamps
- **JSON Configuration**: Easy-to-edit list of applications
- **Robust Error Handling**: Try-catch blocks with proper exit codes (0 = success, 1 = failure)
- **First-Run Experience**: Interactive JSON file creation with example apps if file doesn't exist

## Requirements

- Windows 10/11
- PowerShell 5.1 or later
- Windows Package Manager (winget) installed

## Parameters

### -Interactive

Enables interactive mode where you are prompted to confirm installation for each application.

- **Type**: Switch
- **Required**: No
- **Default**: False

When enabled, you can respond with:
- `Y` - Install the current application
- `N` - Skip the current application
- `A` - Install the current application and all remaining apps without further prompts

```powershell
.\Provision-WingetApps.ps1 -Interactive
```

### -WhatIf

Runs the script in preview mode, showing what would be installed without actually installing anything or modifying files.

- **Type**: Switch
- **Required**: No
- **Default**: False

```powershell
.\Provision-WingetApps.ps1 -WhatIf
```

### -InstallAndTrack

Install one or more new applications and automatically add them to your apps.json tracking file.

- **Type**: String array
- **Required**: No
- **Default**: None

```powershell
.\Provision-WingetApps.ps1 -InstallAndTrack "Microsoft.PowerToys","Google.Chrome"
```

### -AppsFile

Specify a custom JSON configuration file instead of the default apps.json. Supports both relative and absolute paths.

- **Type**: String
- **Required**: No
- **Default**: apps.json (in script directory)

```powershell
.\Provision-WingetApps.ps1 -AppsFile "C:\MyApps\custom-apps.json"
```

### -LogFile

Enable logging to a file with timestamps. All console output will also be written to the specified log file.

- **Type**: String
- **Required**: No
- **Default**: None (console only)

```powershell
.\Provision-WingetApps.ps1 -LogFile "install-log.txt"
```

## Usage Examples

### Example 1: Install all apps silently

```powershell
.\Provision-WingetApps.ps1
```

Installs all applications listed in `apps.json` without prompting.

### Example 2: Interactive installation

```powershell
.\Provision-WingetApps.ps1 -Interactive
```

Prompts for confirmation before installing each application. Use Y/N/A to control which apps are installed.

### Example 3: Preview with WhatIf

```powershell
.\Provision-WingetApps.ps1 -WhatIf
```

Shows what applications would be installed without making any changes.

### Example 4: Interactive preview

```powershell
.\Provision-WingetApps.ps1 -Interactive -WhatIf
```

Prompts for confirmation for each app, then shows what would be installed without actually installing.

### Example 5: Install and track new apps

```powershell
.\Provision-WingetApps.ps1 -InstallAndTrack "Microsoft.PowerToys","Mozilla.Firefox"
```

Installs the specified apps and automatically adds them to apps.json for future tracking.

### Example 6: Use a custom apps file

```powershell
.\Provision-WingetApps.ps1 -AppsFile "work-apps.json"
```

Uses a different JSON file for the application list.

### Example 7: Enable logging

```powershell
.\Provision-WingetApps.ps1 -LogFile "install-log.txt"
```

Logs all output to a file with timestamps while still displaying to console.

### Example 8: Combined parameters

```powershell
.\Provision-WingetApps.ps1 -Interactive -WhatIf -AppsFile "test-apps.json" -LogFile "test.log"
```

Combines multiple parameters: interactive selection, preview mode, custom apps file, and logging.

### Example 9: Install new app to custom tracking file

```powershell
.\Provision-WingetApps.ps1 -InstallAndTrack "Notepad++.Notepad++" -AppsFile "dev-tools.json"
```

Installs a new app and adds it to a specific tracking file.

### Example 10: Run with ExecutionPolicy bypass

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\Provision-WingetApps.ps1
```

Temporarily bypasses execution policy for the current PowerShell session.

## Configuration

### apps.json

The script reads application IDs from a JSON file located in the same directory as the script.

**File location**: `apps.json` (same directory as the script, or specify custom path with `-AppsFile`)

**Format**:
```json
{
  "apps": [
    "Microsoft.PowerShell",
    "7zip.7zip",
    "Git.Git",
    "Microsoft.VisualStudioCode",
    "Microsoft.DotNet.SDK.8",
    "Microsoft.VisualStudio.2022.Enterprise"
  ]
}
```

Each string in the `apps` array should be a valid winget package ID. To find package IDs, use:

```powershell
winget search <app-name>
```

### First Run

If `apps.json` doesn't exist when the script runs, it will offer to create one for you with example applications including:
- Microsoft PowerShell
- Git
- Visual Studio Code



## Output

The script provides colored console output:
- **Green**: Success messages and confirmations
- **Yellow**: Warnings and informational headers
- **Cyan**: Informational messages and progress updates
- **Magenta**: WhatIf mode messages
- **Red**: Errors and failures
- **White**: General information and list items

### Logging

When using the `-LogFile` parameter, all output is written to both the console and the specified log file with timestamps in the format `[YYYY-MM-DD HH:mm:ss]`. The log file includes:
- Script start/end timestamps
- All installation operations
- Errors and warnings
- Final status

## Notes

- The script runs without elevation by default; individual app installers will request UAC when needed
- Applications are installed with `--silent` flag to minimize user interaction
- Package agreements and source agreements are automatically accepted
- Relative paths for `-AppsFile` and `-LogFile` are resolved to absolute paths at script start
- The script uses proper exit codes: 0 for success, 1 for errors
- All file modifications are wrapped in try-catch blocks for robust error handling

## Troubleshooting

**Script won't run due to execution policy**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Or set for current process only:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

**App not found error**: Verify the package ID using `winget search <app-name>` and update your JSON file with the correct ID.

**JSON file not found**: If apps.json is missing on first run, the script will offer to create it for you. Choose 'Y' to create it with example apps, or 'N' to exit and create your own manually.

**Installation fails**: Individual installers may require administrator privileges and will prompt for UAC elevation when needed.

## Architecture

The script is organized into modular functions:

- `Get-AppsFromJson`: Load apps from JSON with first-run creation support
- `Add-AppsToJson`: Add new apps to JSON, avoiding duplicates
- `Install-AndTrackApps`: Install apps and track them in JSON
- `Get-UserConfirmation`: Interactive app selection with Y/N/A prompts
- `Install-WingetApps`: Install apps from list with progress reporting
- `Start-AppInstallation`: Main orchestration function

## License

This project is provided as-is for personal and commercial use.
