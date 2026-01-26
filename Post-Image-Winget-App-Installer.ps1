param(
    [string]$ConfigFile = "apps-config.json"
)

# Check the effective execution policy
$effectivePolicy = Get-ExecutionPolicy

if ($effectivePolicy -ne 'Unrestricted' -and $effectivePolicy -ne 'Bypass') {
    Write-Host "Current effective execution policy is: $effectivePolicy" -ForegroundColor Yellow
    Write-Host "Attempting to elevate and set to Unrestricted..." -ForegroundColor Yellow
    
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        # Not admin - relaunch as administrator
        $scriptPath = $MyInvocation.MyCommand.Path
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        exit
    }
    
    # Running as admin - set execution policy at the highest available scope
    try {
        # Try LocalMachine scope first (requires admin)
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Stop
        Write-Host "Execution policy set to Unrestricted at LocalMachine scope!" -ForegroundColor Green
    }
    catch {
        # If LocalMachine fails, try Process scope as fallback
        try {
            Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force -ErrorAction Stop
            Write-Host "Execution policy set to Unrestricted for current process" -ForegroundColor Yellow
            Write-Host "Note: This setting will only last for this PowerShell session" -ForegroundColor Yellow
        }
        catch {
            Write-Host "Could not set execution policy: $_" -ForegroundColor Yellow
            Write-Host "Continuing with current policy (script launched with Bypass)..." -ForegroundColor Cyan
        }
    }
    
    # Verify the effective policy
    $newPolicy = Get-ExecutionPolicy
    Write-Host "Current effective policy is now: $newPolicy" -ForegroundColor Cyan
}
else {
    Write-Host "Execution policy is already permissive ($effectivePolicy)" -ForegroundColor Green
}

Write-Host "`nExecuting main script..." -ForegroundColor Cyan

Write-Host "Current execution policy: $(Get-ExecutionPolicy -Scope CurrentUser)"

# Read and parse the configuration file
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path -Path $scriptDir -ChildPath $ConfigFile

Write-Host "`nLoading configuration from: $configPath" -ForegroundColor Cyan

# Check if config file exists
if (-not (Test-Path -Path $configPath)) {
    Write-Host "ERROR: Configuration file not found: $configPath" -ForegroundColor Red
    Write-Host "Please ensure the configuration file exists or specify a different file using the -ConfigFile parameter." -ForegroundColor Yellow
    pause
    exit 1
}

# Read and parse JSON
try {
    $configContent = Get-Content -Path $configPath -Raw -ErrorAction Stop
    $config = $configContent | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Failed to parse configuration file: $_" -ForegroundColor Red
    Write-Host "Please ensure the configuration file is valid JSON format." -ForegroundColor Yellow
    pause
    exit 1
}

# Validate configuration structure
if (-not $config.applications) {
    Write-Host "ERROR: Configuration file does not contain 'applications' property." -ForegroundColor Red
    pause
    exit 1
}

# Filter enabled applications
$enabledApps = $config.applications | Where-Object { $_.enabled -eq $true }

if ($enabledApps.Count -eq 0) {
    Write-Host "WARNING: No enabled applications found in configuration file." -ForegroundColor Yellow
    Write-Host "Please enable at least one application in the configuration file." -ForegroundColor Yellow
    pause
    exit 0
}

# Display installation summary
Write-Host "`n=====================================" -ForegroundColor Green
Write-Host "Applications to Install: $($enabledApps.Count)" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green

foreach ($app in $enabledApps) {
    Write-Host "  - $($app.name) ($($app.id))" -ForegroundColor Cyan
}

Write-Host "`nPress any key to start installation..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Install each enabled app silently
Write-Host "`nStarting installation..." -ForegroundColor Green
foreach ($app in $enabledApps) {
    Write-Host "`nInstalling: $($app.name)..." -ForegroundColor Cyan
    winget install --id $app.id --silent --accept-package-agreements --accept-source-agreements
}

Write-Host "`nScript completed successfully!" -ForegroundColor Green
pause