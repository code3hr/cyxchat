#!/bin/bash
# Development helper script
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_DIR/lib"
APP_DIR="$PROJECT_DIR/app"

show_help() {
    echo "CyxChat Development Helper"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  lib           Build C library (debug)"
    echo "  lib-release   Build C library (release)"
    echo "  app           Run Flutter app"
    echo "  test          Run all tests"
    echo "  clean         Clean all build artifacts"
    echo "  setup         Initial project setup"
    echo ""
}

build_lib() {
    echo "Building C library..."
    "$SCRIPT_DIR/build-lib.sh" "$@"
}

run_app() {
    echo "Running Flutter app..."
    cd "$APP_DIR"
    flutter run
}

run_tests() {
    echo "Running C library tests..."
    cd "$LIB_DIR/build"
    ctest --output-on-failure

    echo ""
    echo "Running Flutter tests..."
    cd "$APP_DIR"
    flutter test
}

clean_all() {
    echo "Cleaning build artifacts..."

    if [ -d "$LIB_DIR/build" ]; then
        rm -rf "$LIB_DIR/build"
        echo "  Removed lib/build"
    fi

    cd "$APP_DIR"
    flutter clean
    echo "  Cleaned Flutter app"
}

setup_project() {
    echo "Setting up project..."

    # Build library
    "$SCRIPT_DIR/build-lib.sh" --debug

    # Get Flutter dependencies
    cd "$APP_DIR"
    flutter pub get

    echo ""
    echo "Setup complete!"
    echo ""
    echo "To run the app:"
    echo "  $0 app"
}

# Main
case "${1:-help}" in
    lib)
        build_lib --debug
        ;;
    lib-release)
        build_lib
        ;;
    app)
        run_app
        ;;
    test)
        run_tests
        ;;
    clean)
        clean_all
        ;;
    setup)
        setup_project
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
