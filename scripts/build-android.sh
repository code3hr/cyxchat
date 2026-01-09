#!/bin/bash
# Build CyxChat C library for Android
# Requires: Android NDK installed via Android Studio

set -e

# Find NDK path
if [ -z "$ANDROID_NDK_HOME" ]; then
    # Try common locations
    if [ -d "$HOME/AppData/Local/Android/Sdk/ndk" ]; then
        NDK_DIR=$(ls -d "$HOME/AppData/Local/Android/Sdk/ndk"/*/ 2>/dev/null | head -1)
    elif [ -d "$ANDROID_HOME/ndk" ]; then
        NDK_DIR=$(ls -d "$ANDROID_HOME/ndk"/*/ 2>/dev/null | head -1)
    fi
    ANDROID_NDK_HOME="$NDK_DIR"
fi

if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "Error: Android NDK not found!"
    echo "Install NDK via Android Studio: Tools > SDK Manager > SDK Tools > NDK"
    echo "Or set ANDROID_NDK_HOME environment variable"
    exit 1
fi

echo "Using NDK: $ANDROID_NDK_HOME"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_DIR/lib"
CYXWIZ_DIR="$(dirname "$PROJECT_DIR")"  # Parent conspiracy directory

# Output directory for Android libs
ANDROID_LIBS="$PROJECT_DIR/app/android/app/src/main/jniLibs"
mkdir -p "$ANDROID_LIBS"

# Architectures to build
ARCHS="arm64-v8a armeabi-v7a x86_64"

for ARCH in $ARCHS; do
    echo ""
    echo "========================================="
    echo "Building for $ARCH"
    echo "========================================="

    BUILD_DIR="$LIB_DIR/build-android-$ARCH"
    mkdir -p "$BUILD_DIR"

    # Set CMake variables based on architecture
    case $ARCH in
        arm64-v8a)
            ABI="arm64-v8a"
            ;;
        armeabi-v7a)
            ABI="armeabi-v7a"
            ;;
        x86_64)
            ABI="x86_64"
            ;;
    esac

    # Configure with Android toolchain
    cmake -B "$BUILD_DIR" -S "$LIB_DIR" \
        -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM=android-21 \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DCYXWIZ_DIR="$CYXWIZ_DIR"

    # Build
    cmake --build "$BUILD_DIR" --config Release

    # Copy to jniLibs
    mkdir -p "$ANDROID_LIBS/$ARCH"
    cp "$BUILD_DIR/libcyxchat.so" "$ANDROID_LIBS/$ARCH/"

    echo "Built: $ANDROID_LIBS/$ARCH/libcyxchat.so"
done

echo ""
echo "========================================="
echo "Android build complete!"
echo "Libraries in: $ANDROID_LIBS"
echo "========================================="
ls -la "$ANDROID_LIBS"/*/
