# Build libcyxchat C library (Windows)
param(
    [switch]$Debug,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$LibDir = Join-Path $ProjectDir "lib"
$BuildDir = Join-Path $LibDir "build"

$BuildType = if ($Debug) { "Debug" } else { "Release" }

Write-Host "=== Building libcyxchat ===" -ForegroundColor Cyan
Write-Host "Build type: $BuildType"

# Clean if requested
if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host "Cleaning build directory..."
    Remove-Item -Recurse -Force $BuildDir
}

# Create build directory
if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

Push-Location $BuildDir

try {
    # Configure
    Write-Host "Configuring..."
    cmake .. -DCMAKE_BUILD_TYPE="$BuildType"

    # Build
    Write-Host "Building..."
    cmake --build . --config $BuildType

    # Run tests
    Write-Host "Running tests..."
    ctest -C $BuildType --output-on-failure

    Write-Host ""
    Write-Host "=== Build complete ===" -ForegroundColor Green
    Write-Host "Library: $BuildDir\$BuildType\cyxchat.dll"
}
finally {
    Pop-Location
}
