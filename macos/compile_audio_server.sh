#!/bin/bash

# Compile script for Audio Capture API Server

echo "Compiling Audio Capture API Server..."

# Source files
SERVER_FILE="AudioCaptureServer.swift"
STREAMING_RECORDER="StreamingAudioRecorder.swift"

# Output binary
OUTPUT="audio_capture_server"

# Compile with necessary files
swiftc -O \
    $SERVER_FILE \
    $STREAMING_RECORDER \
    -o $OUTPUT \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework Foundation \
    -framework ScreenCaptureKit \
    -framework AudioToolbox

if [ $? -eq 0 ]; then
    echo "Successfully compiled to: $OUTPUT"
    
    # Create entitlements file for permissions
    cat > audio_server_entitlements.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
</dict>
</plist>
EOF
    
    # Sign the binary with entitlements
    codesign --force --sign - --entitlements audio_server_entitlements.plist $OUTPUT
    
    # Clean up temp file
    rm -f audio_server_entitlements.plist
    
    echo ""
    echo "Usage: ./$OUTPUT"
    echo ""
    echo "The server will:"
    echo "  - Listen on port 9876 for TCP connections"
    echo "  - Accept JSON commands from Python clients"
    echo "  - Manage audio recording with full control"
    echo "  - Support multiple concurrent clients"
    echo ""
    echo "Available commands:"
    echo "  LIST_DEVICES - Get all available microphones"
    echo "  START_RECORDING - Start recording with device selection"
    echo "  STOP_RECORDING - Stop current recording"
    echo "  GET_STATUS - Get recording status"
    echo "  GET_FILE - Download recorded file"
    echo "  SHUTDOWN - Gracefully shutdown server"
else
    echo "Compilation failed!"
    exit 1
fi