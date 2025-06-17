# Audio Capture Library API

A modern, type-safe API for audio capture, playback, and streaming on macOS.

## Features

- 🎤 **System Audio Capture** - Record system-wide audio using ScreenCaptureKit
- 🔊 **Real-time Playback** - Stream audio to any output device with configurable delay
- 📁 **File Recording** - Save audio to standard WAV files
- 🔄 **Multi-Output Support** - Send audio to multiple destinations simultaneously
- 🎛️ **Device Management** - Enumerate and select audio devices
- 🚀 **Modern Swift** - Built with async/await, actors, and type safety
- 🛡️ **Comprehensive Error Handling** - Detailed errors with recovery suggestions

## Requirements

- macOS 13.0+ (Ventura or later)
- Screen Recording permission
- Swift 5.5+

## Installation

1. Clone the repository
2. Compile the API:
   ```bash
   ./compile_api.sh
   ```

## Quick Start

### Simple Recording

```swift
import AudioCaptureKit

// Record 10 seconds to file
let kit = AudioCaptureKit.shared
try await kit.recordToFile(
    url: URL(fileURLWithPath: "recording.wav"),
    duration: 10.0
)
```

### Live Streaming

```swift
// Stream audio with callback
let session = try await kit.streamAudio { buffer in
    // Process each audio buffer
    let level = calculateAudioLevel(buffer)
    print("Audio level: \(level) dB")
}

// Stop when done
try await kit.stopCapture(session: session)
```

### Multi-Output

```swift
// Start capture session
let session = try await kit.startCapture()

// Add multiple outputs
let fileOutput = FileOutput(url: fileURL)
let streamOutput = StreamOutput()
let playbackOutput = PlaybackOutput(delay: 2.0)

try await session.addOutput(fileOutput)
try await session.addOutput(streamOutput)
try await session.addOutput(playbackOutput)

// Process stream
for await buffer in streamOutput.bufferStream {
    // Process buffer
}
```

## Command Line Usage

The compiled API includes a comprehensive command-line interface:

```bash
# List audio devices
./build/audio_capture_api devices

# Record to file
./build/audio_capture_api record 10 meeting

# Stream with playback
./build/audio_capture_api stream 30

# Monitor audio levels
./build/audio_capture_api monitor 5

# Multi-output demo
./build/audio_capture_api multi 10

# Run all examples
./build/audio_capture_api examples
```

## API Overview

### Core Components

#### AudioCaptureKit
Main entry point for all audio operations.

```swift
let kit = AudioCaptureKit.shared
```

#### AudioDevice
Represents an audio input or output device.

```swift
struct AudioDevice {
    let id: String
    let name: String
    let type: DeviceType  // .input, .output, .system
    let capabilities: DeviceCapabilities
}
```

#### AudioFormat
Describes audio format parameters.

```swift
struct AudioFormat {
    let sampleRate: Double      // Hz
    let channelCount: UInt32    // Channels
    let bitDepth: UInt32        // Bits per sample
    let isInterleaved: Bool     // Data layout
    let isFloat: Bool           // Sample type
}
```

#### AudioOutput Protocol
Interface for audio output destinations.

```swift
protocol AudioOutput {
    func configure(format: AudioFormat) async throws
    func process(_ buffer: AudioBuffer) async throws
    func finish() async
}
```

### Built-in Outputs

1. **FileOutput** - Records to WAV file
2. **StreamOutput** - Provides AsyncStream of buffers
3. **CallbackOutput** - Delivers buffers via closure
4. **PlaybackOutput** - Plays through speakers
5. **RingBufferOutput** - Lock-free ring buffer

### Session Management

Sessions provide lifecycle management for audio operations:

```swift
// Capture session
let captureSession = try await kit.startCapture()
try await captureSession.addOutput(output)
try await captureSession.pause()
try await captureSession.resume()
try await kit.stopCapture(session: captureSession)

// Playback session
let playbackSession = try await kit.startPlayback()
try await playbackSession.setInput(captureSession)
await playbackSession.setVolume(0.8)
```

## Error Handling

The API provides comprehensive error types with recovery suggestions:

```swift
do {
    let session = try await kit.startCapture()
} catch AudioCaptureError.screenRecordingPermissionRequired {
    print("Please grant Screen Recording permission")
    print("System Settings > Privacy & Security > Screen Recording")
} catch AudioCaptureError.deviceDisconnected(let deviceName) {
    print("Device \(deviceName) was disconnected")
    // Try with default device
    let session = try await kit.startCapture()
}
```

## Advanced Usage

### Device Selection

```swift
// Get available devices
let devices = try await kit.getPlaybackDevices()

// Find USB SPDIF adapter
if let usbSpdif = devices.first(where: { $0.name.contains("USB SPDIF") }) {
    try await kit.setPlaybackDevice(usbSpdif)
}
```

### Format Configuration

```swift
var config = CaptureConfiguration()
config.format = AudioFormat(
    sampleRate: 48000.0,
    channelCount: 2,
    bitDepth: 16,
    isInterleaved: true,
    isFloat: false
)

let session = try await kit.startCapture(configuration: config)
```

### Performance Monitoring

```swift
// Enable monitoring
var config = AudioCaptureConfiguration()
config.enableMonitoring = true
config.processingPriority = .realtime
await kit.setConfiguration(config)

// Get statistics
let stats = await kit.getStatistics()
print("Active sessions: \(stats.captureSessionCount)")
```

### SwiftUI Integration

```swift
@MainActor
class AudioViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = -60.0
    
    func startRecording() async {
        let kit = AudioCaptureKit.shared
        let session = try await kit.startCapture()
        
        let monitor = CallbackOutput { [weak self] buffer in
            let level = calculateLevel(buffer)
            Task { @MainActor in
                self?.audioLevel = level
            }
        }
        
        try await session.addOutput(monitor)
        isRecording = true
    }
}
```

## Architecture

The API uses a layered architecture:

1. **API Layer** - High-level, user-friendly interface
2. **Session Layer** - Lifecycle and state management
3. **Core Layer** - Low-level audio capture and playback
4. **Output Layer** - Extensible output destinations

### Threading Model

- **Capture Thread**: High-priority audio capture
- **Processing Queue**: Buffer conversion and distribution
- **Delegate Queue**: Output notification dispatch
- **File I/O Queue**: Background file operations
- **Main Thread**: UI updates only

### Memory Management

- Automatic buffer management
- Configurable queue sizes
- Memory pressure handling
- RAII pattern for resources

## Examples

See `API/Examples.swift` for comprehensive examples including:

- Basic recording
- Multi-output streaming
- Device management
- Error handling
- Performance monitoring
- SwiftUI integration

## Troubleshooting

### Permission Issues
- Grant Screen Recording permission in System Settings
- For microphone input, grant Microphone permission

### No Audio Captured
- Ensure system audio is playing
- Check device selection
- Verify format compatibility

### Performance Issues
- Use release build for production
- Adjust buffer sizes
- Monitor statistics API

## License

This project is for educational and personal use.

## Contributing

Contributions are welcome! Please read the API design document for architecture details.