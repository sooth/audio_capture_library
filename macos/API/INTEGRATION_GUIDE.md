# AudioCaptureKit Integration Guide

This guide explains how to integrate AudioCaptureKit into your Swift application.

## Integration Methods

### 1. Swift Package Manager (Recommended)

#### Xcode Integration
1. Open your project in Xcode
2. Go to **File → Add Package Dependencies**
3. Click **Add Local...**
4. Navigate to `/path/to/audio_capture_library/macos/API`
5. Click **Add Package**
6. Select your target and click **Add Package**

#### Package.swift Integration
Add to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(path: "/path/to/audio_capture_library/macos/API")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["AudioCaptureKit"]
    )
]
```

### 2. Framework Integration

Build the framework:
```bash
cd /path/to/audio_capture_library/macos/API
swift build -c release
```

The framework will be at `.build/release/AudioCaptureKit.framework`

### 3. Direct Source Integration

Copy the `Sources/AudioCaptureKit` directory to your project.

## Project Setup

### 1. Info.plist Permissions

Add these keys to your app's Info.plist:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record audio.</string>

<key>NSScreenCaptureUsageDescription</key>
<string>This app needs screen recording permission to capture system audio.</string>
```

### 2. Entitlements

For sandboxed apps, add to your `.entitlements` file:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
```

### 3. Build Settings

Ensure these frameworks are linked:
- AVFoundation
- CoreAudio
- AudioToolbox
- ScreenCaptureKit (macOS 13.0+)

## Basic Usage

```swift
import AudioCaptureKit

class AudioManager {
    func recordAudio() async throws {
        // Simple recording
        let url = try await AudioCaptureKit.shared.recordToFile(
            duration: 10.0,
            outputURL: URL(fileURLWithPath: "recording.wav")
        )
        print("Saved to: \(url)")
    }
    
    func streamAudio() async throws {
        // Real-time streaming
        let stream = try await AudioCaptureKit.shared.streamAudio()
        
        for await buffer in stream {
            // Process buffer
            processAudioBuffer(buffer)
        }
    }
}
```

## SwiftUI Integration

```swift
import SwiftUI
import AudioCaptureKit

struct ContentView: View {
    @State private var isRecording = false
    @State private var devices: [AudioDevice] = []
    @State private var selectedDevice: AudioDevice?
    
    var body: some View {
        VStack {
            Picker("Audio Device", selection: $selectedDevice) {
                ForEach(devices, id: \.id) { device in
                    Text(device.name).tag(device as AudioDevice?)
                }
            }
            
            Button(isRecording ? "Stop Recording" : "Start Recording") {
                Task {
                    if isRecording {
                        try? await AudioCaptureKit.shared.stopRecording()
                    } else {
                        try? await startRecording()
                    }
                    isRecording.toggle()
                }
            }
        }
        .task {
            devices = await AudioCaptureKit.shared.listAudioDevices()
            selectedDevice = devices.first
        }
    }
    
    func startRecording() async throws {
        guard let device = selectedDevice else { return }
        
        let url = URL(fileURLWithPath: "recording.wav")
        try await AudioCaptureKit.shared.recordToFile(
            from: device,
            outputURL: url
        )
    }
}
```

## Advanced Usage

### Custom Audio Processing

```swift
// Create a session with custom processing
let session = AudioCaptureSession()

// Add a callback output for real-time processing
let processor = CallbackOutput { buffer in
    // Your custom processing
    let rms = calculateRMS(buffer)
    updateLevelMeter(rms)
}

try await session.addOutput(processor)
try await session.startCapture()
```

### Network Streaming

```swift
// Set up network output
let networkOutput = NetworkOutput(port: 9876)
try await session.addOutput(networkOutput)

// Python client can connect and receive audio
```

## Troubleshooting

### Common Issues

1. **No audio devices found**
   - Check microphone permissions
   - Ensure app is not sandboxed without proper entitlements

2. **System audio not captured**
   - Requires screen recording permission
   - User must grant permission in System Settings

3. **Build errors**
   - Ensure minimum macOS 13.0 deployment target
   - Link required frameworks

## Example Projects

See `Examples/ExampleApp` for a complete working example.

## Support

For issues, please check:
1. Console.app for permission errors
2. Xcode console for runtime errors
3. AudioCaptureError descriptions for specific issues