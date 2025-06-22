#!/bin/bash

# Build script for AudioCaptureKit Swift Package

echo "Building AudioCaptureKit Swift Package..."
echo "========================================"

# Navigate to package directory
cd "$(dirname "$0")"

# Clean previous builds
echo "Cleaning previous builds..."
swift package clean

# Build the package
echo -e "\nBuilding package..."
swift build

if [ $? -eq 0 ]; then
    echo -e "\n✅ Package built successfully!"
    
    # Run tests
    echo -e "\nRunning tests..."
    swift test
    
    if [ $? -eq 0 ]; then
        echo -e "\n✅ All tests passed!"
    else
        echo -e "\n❌ Some tests failed"
        exit 1
    fi
    
    # Build documentation (if you have DocC set up)
    # echo -e "\nBuilding documentation..."
    # swift package generate-documentation
    
    echo -e "\n✅ AudioCaptureKit is ready to use!"
    echo ""
    echo "To use in your project:"
    echo "1. In Xcode: File → Add Package Dependencies → Add Local → Select this directory"
    echo "2. Or add to Package.swift:"
    echo "   dependencies: ["
    echo "       .package(path: \"$(pwd)\")"
    echo "   ]"
    echo ""
    echo "Example app available in Examples/ExampleApp/"
    
else
    echo -e "\n❌ Build failed!"
    exit 1
fi