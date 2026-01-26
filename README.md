# post-image-terraform

Scripts and configuration files to quickly reinstall a configured set of apps via winget following a Windows clean install.

## Applications Installed

This repository installs the following applications:
- PowerShell
- 7-Zip
- Git
- Sublime Text 4
- .NET SDK 10, 9, and 8
- Visual Studio Code
- Visual Studio 2022 Enterprise
- SQL Server Management Studio 22

## Installation Methods

There are two ways to install the applications:

### Method 1: WinGet Configuration File (Recommended)

The modern, declarative approach using Windows DSC framework. This method is idempotent (safe to run multiple times) and requires no execution policy changes.

**Local usage:**
```powershell
winget configure -f winget-config.dsc.yaml
```

**Remote usage (from GitHub):**
```powershell
winget configure -f https://raw.githubusercontent.com/bestjasonmsft/post-image-terraform/main/winget-config.dsc.yaml
```

**Benefits:**
- ✅ Declarative approach - describes desired state rather than imperative steps
- ✅ Idempotent - safe to run multiple times
- ✅ No execution policy issues - runs in WinGet's context
- ✅ Better error handling - built-in retry and validation
- ✅ Modern - uses Windows DSC framework

### Method 2: PowerShell Script

The traditional approach using a PowerShell script with configurable application list.

**Usage:**

Using the default configuration file:
```powershell
.\Post-Image-Winget-App-Installer.ps1
```

Using a custom configuration file:
```powershell
.\Post-Image-Winget-App-Installer.ps1 -ConfigFile "my-apps.json"
```

**Note:** This script will automatically handle execution policy settings and may require administrator privileges.

## Customizing the Application List

The PowerShell script uses a JSON configuration file (`apps-config.json` by default) to determine which applications to install. This makes it easy to customize your installation without modifying the script itself.

### Configuration File Format

The configuration file uses the following JSON structure:

```json
{
  "applications": [
    {
      "id": "Microsoft.PowerShell",
      "name": "PowerShell",
      "enabled": true
    },
    {
      "id": "7zip.7zip",
      "name": "7-Zip",
      "enabled": true
    }
  ]
}
```

Each application entry has three properties:
- **id**: The WinGet package identifier (required for installation)
- **name**: A friendly name for the application (displayed during installation)
- **enabled**: Whether to install this application (`true` or `false`)

### Enabling/Disabling Applications

To disable an application without removing it from the list, simply change its `enabled` property to `false`:

```json
{
  "id": "Microsoft.VisualStudio.2022.Enterprise",
  "name": "Visual Studio 2022 Enterprise",
  "enabled": false
}
```

### Adding New Applications

To add a new application to the list:

1. Find the WinGet package ID using:
   ```powershell
   winget search "application name"
   ```

2. Add a new entry to the `applications` array in your configuration file:
   ```json
   {
     "id": "PackageId.FromWinGet",
     "name": "Friendly Application Name",
     "enabled": true
   }
   ```

### Multiple Configuration Files

You can maintain multiple configuration files for different scenarios:

- `apps-work.json` - Applications for work environments
- `apps-home.json` - Applications for personal use
- `apps-minimal.json` - Essential applications only

To use a specific configuration:
```powershell
.\Post-Image-Winget-App-Installer.ps1 -ConfigFile "apps-work.json"
```

### Benefits of External Configuration

- **Flexibility**: Customize your application list without modifying the script
- **Maintainability**: Separation of configuration from logic
- **Reusability**: Maintain multiple config files for different scenarios
- **User-friendly**: Simple enable/disable toggle for each application
- **Version control**: Config changes are easier to track and review
