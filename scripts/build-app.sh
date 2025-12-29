#!/bin/bash
# Build CyxChat Flutter app
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/app"

# Parse arguments
PLATFORM=""
RELEASE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --android)
            PLATFORM="android"
            shift
            ;;
        --ios)
            PLATFORM="ios"
            shift
            ;;
        --linux)
            PLATFORM="linux"
            shift
            ;;
        --macos)
            PLATFORM="macos"
            shift
            ;;
        --windows)
            PLATFORM="windows"
            shift
            ;;
        --release)
            RELEASE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--android|--ios|--linux|--macos|--windows] [--release]"
            exit 1
            ;;
    esac
done

cd "$APP_DIR"

echo "=== Building CyxChat Flutter App ==="

# Get dependencies
echo "Getting dependencies..."
flutter pub get

# Build for platform
if [ -n "$PLATFORM" ]; then
    BUILD_CMD="flutter build $PLATFORM"
    if [ $RELEASE -eq 1 ]; then
        BUILD_CMD="$BUILD_CMD --release"
    else
        BUILD_CMD="$BUILD_CMD --debug"
    fi

    echo "Building for $PLATFORM..."
    $BUILD_CMD
else
    # Just run
    echo "Running in debug mode..."
    flutter run
fi

echo ""
echo "=== Build complete ==="
