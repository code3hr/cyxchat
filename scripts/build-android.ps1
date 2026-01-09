# Build CyxChat for Android (Windows PowerShell script)
# Requires: Android Studio with SDK & NDK installed

param(
    [string]$NdkPath = "",
    [string]$Arch = "all"  # all, arm64-v8a, armeabi-v7a, x86_64
)

$ErrorActionPreference = "Stop"

# Find Android NDK
if (-not $NdkPath) {
    $SdkPath = "$env:LOCALAPPDATA\Android\Sdk"
    if (Test-Path "$SdkPath\ndk") {
        $NdkPath = (Get-ChildItem "$SdkPath\ndk" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
    }
}

if (-not $NdkPath -or -not (Test-Path $NdkPath)) {
    Write-Error @"
Android NDK not found!

To install:
1. Open Android Studio
2. Go to: Tools > SDK Manager > SDK Tools
3. Check "NDK (Side by side)" and "CMake"
4. Click Apply

Or specify path: .\build-android.ps1 -NdkPath "C:\path\to\ndk"
"@
    exit 1
}

Write-Host "Using NDK: $NdkPath" -ForegroundColor Green

# Paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$CyxWizDir = Split-Path -Parent $ProjectDir
$LibDir = Join-Path $ProjectDir "lib"
$AndroidLibs = Join-Path $ProjectDir "app\android\app\src\main\jniLibs"

# Architectures
$Architectures = @("arm64-v8a", "armeabi-v7a", "x86_64")
if ($Arch -ne "all") {
    $Architectures = @($Arch)
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Building CyxChat for Android" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Project: $ProjectDir"
Write-Host "CyxWiz:  $CyxWizDir"
Write-Host "Archs:   $($Architectures -join ', ')"
Write-Host ""

# Toolchain file
$Toolchain = Join-Path $NdkPath "build\cmake\android.toolchain.cmake"

foreach ($ABI in $Architectures) {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host "Building for $ABI" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Yellow

    # Step 1: Build libcyxwiz for this architecture
    $CyxWizBuild = Join-Path $CyxWizDir "build-android-$ABI"
    Write-Host "Building libcyxwiz..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Force -Path $CyxWizBuild | Out-Null

    cmake -B $CyxWizBuild -S $CyxWizDir `
        -DCMAKE_TOOLCHAIN_FILE="$Toolchain" `
        -DANDROID_ABI="$ABI" `
        -DANDROID_PLATFORM=android-21 `
        -DCMAKE_BUILD_TYPE=Release `
        -DCYXWIZ_BUILD_TESTS=OFF `
        -DCYXWIZ_HAS_CRYPTO=OFF  # Disable crypto for now (requires libsodium for Android)

    cmake --build $CyxWizBuild --config Release

    # Step 2: Build libcyxchat for this architecture
    $CyxChatBuild = Join-Path $LibDir "build-android-$ABI"
    Write-Host "Building libcyxchat..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Force -Path $CyxChatBuild | Out-Null

    cmake -B $CyxChatBuild -S $LibDir `
        -DCMAKE_TOOLCHAIN_FILE="$Toolchain" `
        -DANDROID_ABI="$ABI" `
        -DANDROID_PLATFORM=android-21 `
        -DCMAKE_BUILD_TYPE=Release `
        -DCYXWIZ_ROOT="$CyxWizDir" `
        -DCYXWIZ_BUILD_DIR="$CyxWizBuild" `
        -DCYXCHAT_BUILD_TESTS=OFF `
        -DCYXCHAT_BUILD_STATIC=OFF

    cmake --build $CyxChatBuild --config Release

    # Step 3: Copy to jniLibs
    $OutputDir = Join-Path $AndroidLibs $ABI
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    Copy-Item (Join-Path $CyxChatBuild "libcyxchat.so") $OutputDir -Force

    # Also copy libcyxwiz if it was built as shared
    $CyxWizSo = Join-Path $CyxWizBuild "libcyxwiz.so"
    if (Test-Path $CyxWizSo) {
        Copy-Item $CyxWizSo $OutputDir -Force
    }

    Write-Host "Built: $OutputDir\libcyxchat.so" -ForegroundColor Green
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Android build complete!" -ForegroundColor Green
Write-Host "Libraries in: $AndroidLibs" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  cd $ProjectDir\app"
Write-Host "  flutter build apk --release"
Write-Host ""
