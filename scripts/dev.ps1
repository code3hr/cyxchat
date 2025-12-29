# Development helper script (Windows)
param(
    [Parameter(Position=0)]
    [ValidateSet("lib", "lib-release", "app", "test", "clean", "setup", "help")]
    [string]$Command = "help"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$LibDir = Join-Path $ProjectDir "lib"
$AppDir = Join-Path $ProjectDir "app"

function Show-Help {
    Write-Host "CyxChat Development Helper" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\dev.ps1 <command>"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  lib           Build C library (debug)"
    Write-Host "  lib-release   Build C library (release)"
    Write-Host "  app           Run Flutter app"
    Write-Host "  test          Run all tests"
    Write-Host "  clean         Clean all build artifacts"
    Write-Host "  setup         Initial project setup"
    Write-Host ""
}

function Build-Lib {
    param([switch]$Release)

    Write-Host "Building C library..." -ForegroundColor Yellow
    if ($Release) {
        & "$ScriptDir\build-lib.ps1"
    } else {
        & "$ScriptDir\build-lib.ps1" -Debug
    }
}

function Run-App {
    Write-Host "Running Flutter app..." -ForegroundColor Yellow
    Push-Location $AppDir
    try {
        flutter run -d windows
    } finally {
        Pop-Location
    }
}

function Run-Tests {
    Write-Host "Running C library tests..." -ForegroundColor Yellow
    Push-Location (Join-Path $LibDir "build")
    try {
        ctest -C Debug --output-on-failure
    } finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "Running Flutter tests..." -ForegroundColor Yellow
    Push-Location $AppDir
    try {
        flutter test
    } finally {
        Pop-Location
    }
}

function Clean-All {
    Write-Host "Cleaning build artifacts..." -ForegroundColor Yellow

    $BuildDir = Join-Path $LibDir "build"
    if (Test-Path $BuildDir) {
        Remove-Item -Recurse -Force $BuildDir
        Write-Host "  Removed lib/build"
    }

    Push-Location $AppDir
    try {
        flutter clean
        Write-Host "  Cleaned Flutter app"
    } finally {
        Pop-Location
    }
}

function Setup-Project {
    Write-Host "Setting up project..." -ForegroundColor Yellow

    # Build library
    & "$ScriptDir\build-lib.ps1" -Debug

    # Get Flutter dependencies
    Push-Location $AppDir
    try {
        flutter pub get
    } finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "Setup complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "To run the app:"
    Write-Host "  .\dev.ps1 app"
}

# Main
switch ($Command) {
    "lib" { Build-Lib }
    "lib-release" { Build-Lib -Release }
    "app" { Run-App }
    "test" { Run-Tests }
    "clean" { Clean-All }
    "setup" { Setup-Project }
    "help" { Show-Help }
    default { Show-Help }
}
