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

# List of apps to install
$apps = @(
    "Microsoft.PowerShell",
    "7zip.7zip",
    "Git.Git",
    "SublimeHQ.SublimeText.4",
    "Microsoft.DotNet.SDK.10",
    "Microsoft.DotNet.SDK.9",
    "Microsoft.DotNet.SDK.8",
    "Microsoft.VisualStudioCode",
    "Microsoft.VisualStudio.2022.Enterprise",
    "Microsoft.SQLServerManagementStudio.22"
)

# Install each app silently
foreach ($app in $apps) {
    winget install --id $app --silent --accept-package-agreements --accept-source-agreements
}

Write-Host "`nScript completed successfully!" -ForegroundColor Green
pause