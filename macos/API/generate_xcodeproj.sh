#!/bin/bash

# Generate Xcode project for AudioCaptureKit

echo "Generating Xcode project..."
swift package generate-xcodeproj

if [ $? -eq 0 ]; then
    echo "✅ Xcode project generated successfully!"
    echo "   Open AudioCaptureKit.xcodeproj to develop in Xcode"
else
    echo "❌ Failed to generate Xcode project"
fi