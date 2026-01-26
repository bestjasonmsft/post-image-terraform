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

The traditional approach using a PowerShell script.

**Usage:**
```powershell
.\Post-Image-Winget-App-Installer.ps1
```

**Note:** This script will automatically handle execution policy settings and may require administrator privileges.
