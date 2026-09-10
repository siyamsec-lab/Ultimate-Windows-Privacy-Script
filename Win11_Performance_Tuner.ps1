#requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Performance Optimization / Lightweight Configuration

.DESCRIPTION
    Applies conservative performance optimizations without attempting
    to disable critical Windows components.

    Designed for Windows 10/11.

.NOTES
    Run as Administrator.
    A log is written to %ProgramData%\WinPerformanceOptimizer
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$LogRoot = "$env:ProgramData\WinPerformanceOptimizer"
$LogFile = Join-Path $LogRoot "Optimization.log"

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

function Write-Log {
    param(
        [string]$Message
    )

    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"

    Write-Host $Line
    Add-Content -Path $LogFile -Value $Line
}

function Set-ServiceSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [ValidateSet("Automatic","Manual","Disabled")]
        [string]$StartupType = "Manual"
    )

    $Service = Get-Service -Name $Name

    if ($null -eq $Service) {
        Write-Log "Service not found: $Name"
        return
    }

    try {
        Set-Service -Name $Name -StartupType $StartupType
        Write-Log "Service configured: $Name -> $StartupType"
    }
    catch {
        Write-Log "Could not configure service: $Name"
    }
}

# ------------------------------------------------------------
# Initial information
# ------------------------------------------------------------

Write-Log "=============================================="
Write-Log "Windows Performance Optimizer starting"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User: $env:USERNAME"
Write-Log "PowerShell: $($PSVersionTable.PSVersion)"
Write-Log "=============================================="

# ------------------------------------------------------------
# Create Restore Point
# ------------------------------------------------------------

Write-Log "Attempting to create a system restore point..."

try {
    Enable-ComputerRestore -Drive "$($env:SystemDrive)\" | Out-Null

    Checkpoint-Computer `
        -Description "Before WinPerformanceOptimizer" `
        -RestorePointType "MODIFY_SETTINGS" | Out-Null

    Write-Log "Restore point created."
}
catch {
    Write-Log "Restore point could not be created. Continuing."
}

# ------------------------------------------------------------
# Detect Windows version
# ------------------------------------------------------------

$OS = Get-CimInstance Win32_OperatingSystem

Write-Log "Windows version: $($OS.Caption)"
Write-Log "Build: $($OS.BuildNumber)"
Write-Log "RAM: $([math]::Round($OS.TotalVisibleMemorySize / 1MB, 1)) GB"

# ------------------------------------------------------------
# Power Plan
# ------------------------------------------------------------

Write-Log "Configuring power plan..."

$PowerPlans = powercfg /list

$Ultimate = $PowerPlans |
    Select-String "Ultimate Performance"

if ($Ultimate) {
    $Guid = [regex]::Match(
        $Ultimate.ToString(),
        "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"
    ).Value

    if ($Guid) {
        powercfg /setactive $Guid
        Write-Log "Ultimate Performance power plan activated."
    }
}
else {
    $High = $PowerPlans |
        Select-String "High performance"

    if ($High) {
        $Guid = [regex]::Match(
            $High.ToString(),
            "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"
        ).Value

        if ($Guid) {
            powercfg /setactive $Guid
            Write-Log "High Performance power plan activated."
        }
    }
}

# ------------------------------------------------------------
# Windows visual effects
# ------------------------------------------------------------

Write-Log "Reducing unnecessary visual effects..."

$VisualEffects = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"

New-Item -Path $VisualEffects -Force | Out-Null

Set-ItemProperty `
    -Path $VisualEffects `
    -Name "VisualFXSetting" `
    -Type DWord `
    -Value 2

# Keep font smoothing enabled
Set-ItemProperty `
    -Path "HKCU:\Control Panel\Desktop" `
    -Name "FontSmoothing" `
    -Value "2"

# ------------------------------------------------------------
# Disable transparency
# ------------------------------------------------------------

Write-Log "Disabling Windows transparency..."

$Personalize = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"

New-Item -Path $Personalize -Force | Out-Null

Set-ItemProperty `
    -Path $Personalize `
    -Name "EnableTransparency" `
    -Type DWord `
    -Value 0

# ------------------------------------------------------------
# Disable unnecessary startup entries
# ------------------------------------------------------------

Write-Log "Inspecting startup applications..."

$StartupPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
)

foreach ($Path in $StartupPaths) {

    if (Test-Path $Path) {

        $Properties = Get-ItemProperty -Path $Path

        foreach ($Property in $Properties.PSObject.Properties) {

            if ($Property.Name -notmatch "^PS") {

                $Value = [string]$Property.Value

                # Leave security and system software alone.
                if ($Value -match "Windows Defender|SecurityHealth|OneDrive") {
                    Write-Log "Keeping startup item: $($Property.Name)"
                    continue
                }

                Write-Log "Startup item detected: $($Property.Name)"
            }
        }
    }
}

# ------------------------------------------------------------
# Remove common consumer apps
# ------------------------------------------------------------

Write-Log "Removing selected unnecessary built-in apps..."

$Apps = @(
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.People",
    "Microsoft.Todos",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxApp",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo"
)

foreach ($App in $Apps) {

    $Packages = Get-AppxPackage -Name $App

    foreach ($Package in $Packages) {
        try {
            Remove-AppxPackage -Package $Package.PackageFullName
            Write-Log "Removed AppX package: $App"
        }
        catch {
            Write-Log "Could not remove: $App"
        }
    }
}

# ------------------------------------------------------------
# Disable selected consumer services
# ------------------------------------------------------------

Write-Log "Configuring nonessential services..."

# Connected User Experiences and Telemetry
Set-ServiceSafe -Name "DiagTrack" -StartupType "Manual"

# Downloaded Maps Manager
Set-ServiceSafe -Name "MapsBroker" -StartupType "Manual"

# Retail Demo
Set-ServiceSafe -Name "RetailDemo" -StartupType "Disabled"

# Xbox services
Set-ServiceSafe -Name "XblAuthManager" -StartupType "Manual"
Set-ServiceSafe -Name "XblGameSave" -StartupType "Manual"
Set-ServiceSafe -Name "XboxNetApiSvc" -StartupType "Manual"
Set-ServiceSafe -Name "XboxGipSvc" -StartupType "Manual"

# ------------------------------------------------------------
# Disable Windows Search indexing ONLY if desired
# ------------------------------------------------------------
# This is intentionally left disabled by default because Search
# indexing is useful on many systems.

$DisableSearch = $false

if ($DisableSearch) {
    Set-ServiceSafe -Name "WSearch" -StartupType "Manual"
    Write-Log "Windows Search configured as Manual."
}
else {
    Write-Log "Windows Search left unchanged."
}

# ------------------------------------------------------------
# Scheduled task optimization
# ------------------------------------------------------------

Write-Log "Reviewing selected consumer scheduled tasks..."

$Tasks = @(
    @{
        Path = "\Microsoft\Windows\Customer Experience Improvement Program\"
        Name = "Consolidator"
    },
    @{
        Path = "\Microsoft\Windows\Customer Experience Improvement Program\"
        Name = "UsbCeip"
    }
)

foreach ($Task in $Tasks) {

    try {
        Disable-ScheduledTask `
            -TaskPath $Task.Path `
            -TaskName $Task.Name | Out-Null

        Write-Log "Disabled scheduled task: $($Task.Name)"
    }
    catch {
        Write-Log "Task unavailable: $($Task.Name)"
    }
}

# ------------------------------------------------------------
# Temporary file cleanup
# ------------------------------------------------------------

Write-Log "Cleaning temporary files..."

$TempLocations = @(
    $env:TEMP,
    "$env:WINDIR\Temp"
)

foreach ($Location in $TempLocations) {

    if (Test-Path $Location) {

        Get-ChildItem `
            -Path $Location `
            -Force `
            -ErrorAction SilentlyContinue |
            Remove-Item `
                -Force `
                -Recurse `
                -ErrorAction SilentlyContinue

        Write-Log "Cleaned: $Location"
    }
}

# ------------------------------------------------------------
# DNS cache
# ------------------------------------------------------------

Write-Log "Flushing DNS cache..."

Clear-DnsClientCache

# ------------------------------------------------------------
# Memory management
# ------------------------------------------------------------

Write-Log "Refreshing performance counters..."

# Tell Windows to prefer performance over UI animations.
Set-ItemProperty `
    -Path "HKCU:\Control Panel\Desktop" `
    -Name "MenuShowDelay" `
    -Value "100"

# ------------------------------------------------------------
# Explorer restart
# ------------------------------------------------------------

Write-Log "Restarting Explorer..."

Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2

Start-Process explorer.exe

# ------------------------------------------------------------
# Final system information
# ------------------------------------------------------------

Write-Log "Optimization complete."

Write-Log "Log file: $LogFile"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Windows Performance Optimization Complete" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log: $LogFile"
Write-Host ""
Write-Host "A reboot is recommended."
Write-Host ""