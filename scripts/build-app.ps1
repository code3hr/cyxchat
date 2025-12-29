# Build CyxChat Flutter app (Windows)
param(
    [ValidateSet("android", "ios", "windows", "linux", "macos", "web")]
    [string]$Platform,
    [switch]$Release
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$AppDir = Join-Path $ProjectDir "app"

Push-Location $AppDir

try {
    Write-Host "=== Building CyxChat Flutter App ===" -ForegroundColor Cyan

    # Get dependencies
    Write-Host "Getting dependencies..."
    flutter pub get

    # Build for platform
    if ($Platform) {
        $BuildType = if ($Release) { "--release" } else { "--debug" }

        Write-Host "Building for $Platform..."
        flutter build $Platform $BuildType
    }
    else {
        # Default to Windows if no platform specified
        Write-Host "Running in debug mode..."
        flutter run -d windows
    }

    Write-Host ""
    Write-Host "=== Build complete ===" -ForegroundColor Green
}
finally {
    Pop-Location
}
