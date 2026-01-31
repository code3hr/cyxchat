@echo off
set SDK_CMAKE=C:\Users\chick\AppData\Local\Android\Sdk\cmake\3.22.1\bin
set NDK=C:\Users\chick\AppData\Local\Android\Sdk\ndk\27.0.12077973
set TOOLCHAIN=%NDK%\build\cmake\android.toolchain.cmake
set SRC=D:\Dev\conspiracy\cyxchat\android_build

echo === Building arm64-v8a ===
rmdir /s /q "%SRC%\build-arm64" 2>nul
"%SDK_CMAKE%\cmake.exe" -S "%SRC%" -B "%SRC%\build-arm64" -G Ninja ^
  -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN%" ^
  -DANDROID_ABI=arm64-v8a ^
  -DANDROID_PLATFORM=android-23 ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_MAKE_PROGRAM="%SDK_CMAKE%\ninja.exe"
if errorlevel 1 (
    echo CONFIGURE FAILED for arm64
    exit /b 1
)
"%SDK_CMAKE%\cmake.exe" --build "%SRC%\build-arm64"
if errorlevel 1 (
    echo BUILD FAILED for arm64
    exit /b 1
)

echo === Building armeabi-v7a ===
rmdir /s /q "%SRC%\build-arm32" 2>nul
"%SDK_CMAKE%\cmake.exe" -S "%SRC%" -B "%SRC%\build-arm32" -G Ninja ^
  -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN%" ^
  -DANDROID_ABI=armeabi-v7a ^
  -DANDROID_PLATFORM=android-23 ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_MAKE_PROGRAM="%SDK_CMAKE%\ninja.exe"
if errorlevel 1 (
    echo CONFIGURE FAILED for arm32
    exit /b 1
)
"%SDK_CMAKE%\cmake.exe" --build "%SRC%\build-arm32"
if errorlevel 1 (
    echo BUILD FAILED for arm32
    exit /b 1
)

echo === Done ===
echo arm64: %SRC%\build-arm64\libcyxchat.so
echo arm32: %SRC%\build-arm32\libcyxchat.so
