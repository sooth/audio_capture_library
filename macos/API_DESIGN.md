# Audio Capture Library - API Design Document

## Overview

This document describes the standardized API interface layer for the macOS Audio Capture Library. The API provides a clean, type-safe, and intuitive interface for audio capture, playback, recording, and streaming operations.

## Architecture

### Core Design Principles

1. **Protocol-Oriented Design**: Extensible interfaces using Swift protocols
2. **Actor-Based Concurrency**: Thread-safe operations using Swift actors
3. **Async/Await**: Modern asynchronous programming patterns
4. **Type Safety**: Comprehensive error handling with typed errors
5. **Session-Based**: Clear lifecycle management for audio operations

### Component Hierarchy

```
AudioCaptureKit (Main Entry Point)
├── AudioDeviceManager (Device Enumeration & Selection)
├── AudioCaptureSession (Recording/Capture)
│   ├── StreamingAudioRecorder (Internal)
│   └── AudioStreamMultiplexer (Output Distribution)
├── AudioPlaybackSession (Playback)
│   └── StreamingAudioPlayer (Internal)
└── AudioOutput Implementations
    ├── FileOutput (WAV Recording)
    ├── StreamOutput (Async Stream)
    ├── CallbackOutput (Closure-based)
    ├── PlaybackOutput (Speaker Output)
    └── RingBufferOutput (Lock-free Buffer)
```

## API Reference

### AudioCaptureKit

The main entry point for all audio operations.

```swift
// Singleton access
let kit = AudioCaptureKit.shared

// Or create instance
let kit = AudioCaptureKit()
```

#### Device Management

```swift
// Get available devices
let playbackDevices = try await kit.getPlaybackDevices()
let recordingDevices = try await kit.getRecordingDevices()

// Set devices
try await kit.setPlaybackDevice(usbSpdifDevice)
try await kit.setRecordingDevice(systemAudioDevice)

// Get current devices
let currentPlayback = try await kit.getCurrentPlaybackDevice()
let currentRecording = try await kit.getCurrentRecordingDevice()
```

#### Capture Operations

```swift
// Start capture with default configuration
let session = try await kit.startCapture()

// Start with custom configuration
var config = CaptureConfiguration()
config.format = AudioFormat.standardWAV
config.bufferQueueSize = 16
let session = try await kit.startCapture(configuration: config)

// Stop capture
try await kit.stopCapture(session: session)
```

#### Playback Operations

```swift
// Start playback
var config = PlaybackConfiguration()
config.delay = 2.0  // 2 second delay
config.volume = 0.5
let playbackSession = try await kit.startPlayback(configuration: config)

// Connect input source
try await playbackSession.setInput(captureSession)

// Control playback
await playbackSession.setVolume(0.7)

// Stop playback
try await kit.stopPlayback(session: playbackSession)
```

#### Quick Operations

```swift
// Record to file
try await kit.recordToFile(url: fileURL, duration: 10.0)

// Stream with callback
let session = try await kit.streamAudio { buffer in
    // Process buffer
}

// Play system audio
let session = try await kit.playSystemAudio(device: speakerDevice)
```

### AudioDevice

Represents an audio input or output device.

```swift
struct AudioDevice {
    let id: String                    // Unique identifier
    let name: String                  // Human-readable name
    let manufacturer: String?         // Device manufacturer
    let type: DeviceType             // .input, .output, .system
    let audioDeviceID: AudioDeviceID // Core Audio ID
    let supportedFormats: [AudioFormat]
    let isDefault: Bool
    let status: DeviceStatus         // .connected, .disconnected
    let capabilities: DeviceCapabilities
}
```

### AudioFormat

Describes audio format parameters.

```swift
struct AudioFormat {
    let sampleRate: Double      // Hz (e.g., 48000.0)
    let channelCount: UInt32    // Number of channels
    let bitDepth: UInt32        // Bits per sample (16, 24, 32)
    let isInterleaved: Bool     // Data layout
    let isFloat: Bool           // Float vs Integer samples
    
    // Common formats
    static let defaultFormat    // 48kHz, 2ch, 32-bit float
    static let cdQuality       // 44.1kHz, 2ch, 16-bit int
    static let standardWAV     // 48kHz, 2ch, 16-bit int
}
```

### AudioOutput Protocol

Interface for audio output destinations.

```swift
protocol AudioOutput {
    var id: UUID { get }
    func configure(format: AudioFormat) async throws
    func process(_ buffer: AudioBuffer) async throws
    func handleError(_ error: Error) async
    func finish() async
}
```

#### Built-in Outputs

1. **FileOutput**: Records to WAV file
   ```swift
   let output = FileOutput(url: URL(fileURLWithPath: "recording.wav"))
   ```

2. **StreamOutput**: Provides AsyncStream of buffers
   ```swift
   let output = StreamOutput(queueSize: 64)
   for await buffer in output.bufferStream {
       // Process buffer
   }
   ```

3. **CallbackOutput**: Delivers buffers via closure
   ```swift
   let output = CallbackOutput { buffer in
       print("Got buffer: \(buffer.duration)s")
   }
   ```

4. **PlaybackOutput**: Plays through speakers
   ```swift
   let output = PlaybackOutput(device: speakerDevice, delay: 1.0)
   ```

5. **RingBufferOutput**: Lock-free ring buffer
   ```swift
   let output = RingBufferOutput(bufferDuration: 2.0)
   let bytesRead = output.read(into: buffer, maxBytes: 1024)
   ```

### Session Management

#### AudioCaptureSession

```swift
// Add outputs
try await session.addOutput(fileOutput)
try await session.addOutput(streamOutput)

// Remove output
try await session.removeOutput(fileOutput)

// Control
try await session.pause()
try await session.resume()

// Monitor state
await session.addStateObserver { state in
    print("State changed to: \(state)")
}

// Get statistics
let stats = await session.getStatistics()
```

#### AudioPlaybackSession

```swift
// Set input source
try await playbackSession.setInput(captureSession)

// Volume control
await playbackSession.setVolume(0.8)
let volume = await playbackSession.getVolume()

// Direct buffer scheduling
playbackSession.scheduleBuffer(customBuffer)
```

### Error Handling

Comprehensive error types with recovery suggestions:

```swift
enum AudioCaptureError: LocalizedError {
    // Device errors
    case deviceNotFound(String)
    case deviceDisconnected(String)
    
    // Permission errors
    case screenRecordingPermissionRequired
    case microphonePermissionRequired
    
    // Session errors
    case invalidState(String)
    case sessionNotActive
    
    // Format errors
    case unsupportedFormat(String)
    case formatMismatch(String)
    
    // ... and more
}
```

### Buffer Management

#### AudioBuffer

Wrapper for PCM buffers with metadata:

```swift
struct AudioBuffer {
    let pcmBuffer: AVAudioPCMBuffer
    let format: AudioFormat
    let timestamp: Date
    var duration: TimeInterval { get }
}
```

#### AudioBufferQueue

Thread-safe queue with async stream support:

```swift
let queue = AudioBufferQueue(maxSize: 32)

// Enqueue
await queue.enqueue(buffer)

// Stream interface
for await buffer in queue.stream {
    // Process buffer
}

// Statistics
let stats = await queue.getStatistics()
print("Drop rate: \(stats.dropRate)")
```

## Usage Patterns

### Simple Recording

```swift
// Record 10 seconds to file
let kit = AudioCaptureKit.shared
try await kit.recordToFile(
    url: URL(fileURLWithPath: "recording.wav"),
    duration: 10.0
)
```

### Live Monitoring

```swift
let session = try await kit.startCapture()

let monitor = CallbackOutput { buffer in
    let level = calculateAudioLevel(buffer)
    updateUI(level: level)
}

try await session.addOutput(monitor)
```

### Multi-Output Streaming

```swift
let session = try await kit.startCapture()

// Record to file
let fileOutput = FileOutput(url: recordingURL)
try await session.addOutput(fileOutput)

// Stream for processing
let streamOutput = StreamOutput()
try await session.addOutput(streamOutput)

// Play through speakers
let playbackOutput = PlaybackOutput(delay: 2.0)
try await session.addOutput(playbackOutput)

// Process stream
Task {
    for await buffer in streamOutput.bufferStream {
        await processAudio(buffer)
    }
}
```

### Device Selection

```swift
// Find USB SPDIF adapter
let devices = try await kit.getPlaybackDevices()
if let usbSpdif = devices.first(where: { $0.name.contains("USB SPDIF") }) {
    try await kit.setPlaybackDevice(usbSpdif)
}
```

### Error Recovery

```swift
do {
    let session = try await kit.startCapture()
} catch AudioCaptureError.screenRecordingPermissionRequired {
    // Guide user to grant permission
    showPermissionAlert()
} catch AudioCaptureError.deviceDisconnected(let name) {
    // Try fallback device
    print("Device \(name) disconnected, using default")
    let session = try await kit.startCapture()
}
```

## Performance Considerations

### Threading Model

- **Capture Thread**: High-priority audio capture (ScreenCaptureKit)
- **Processing Queue**: Buffer conversion and distribution
- **Delegate Queue**: Output notification dispatch
- **File I/O Queue**: Background file operations
- **Main Thread**: UI updates only

### Memory Management

- Buffer pooling for capture (currently disabled due to format issues)
- Automatic memory pressure handling
- Configurable queue sizes for backpressure
- RAII pattern for resource cleanup

### Optimization Strategies

1. **Zero-Copy Buffers**: Direct PCM buffer passing
2. **Lock-Free Queues**: For real-time paths
3. **Batch Processing**: Group operations when possible
4. **Format Negotiation**: Minimize conversions

## Integration Examples

### SwiftUI Integration

```swift
@MainActor
class AudioCaptureViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = -60.0
    
    private var session: AudioCaptureSession?
    
    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }
    
    private func startRecording() async {
        do {
            let kit = AudioCaptureKit.shared
            session = try await kit.startCapture()
            
            let monitor = CallbackOutput { [weak self] buffer in
                let level = self?.calculateLevel(buffer) ?? -60.0
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }
            
            try await session?.addOutput(monitor)
            isRecording = true
        } catch {
            print("Error: \(error)")
        }
    }
}
```

### Command-Line Tool

See `main_api.swift` for a complete command-line interface implementation.

## Migration Guide

### From Old API to New API

#### Old: Direct recorder usage
```swift
let recorder = StreamingAudioRecorder()
try await recorder.startStreaming()
```

#### New: Session-based API
```swift
let kit = AudioCaptureKit.shared
let session = try await kit.startCapture()
```

#### Old: Manual player setup
```swift
let player = StreamingAudioPlayer(delay: 2.0)
try player.startPlayback()
recorder.addStreamDelegate(player)
```

#### New: Integrated playback
```swift
let playbackSession = try await kit.startPlayback(
    configuration: PlaybackConfiguration(delay: 2.0)
)
try await playbackSession.setInput(captureSession)
```

## Future Enhancements

1. **Network Streaming**
   - RTMP/HLS output support
   - WebRTC integration
   - Remote device support

2. **Advanced Processing**
   - Built-in effects (EQ, compression)
   - Real-time audio analysis
   - Machine learning integration

3. **Enhanced Device Support**
   - Bluetooth device management
   - Virtual device creation
   - Aggregate device support

4. **Extended Format Support**
   - Compressed formats (AAC, MP3)
   - Multi-channel (5.1, 7.1)
   - High-resolution audio

## Best Practices

1. **Always handle errors** - Audio operations can fail for many reasons
2. **Check permissions** - Screen Recording permission is required
3. **Monitor performance** - Use statistics API for production apps
4. **Clean up resources** - Always stop sessions when done
5. **Test device changes** - Handle disconnection gracefully
6. **Use appropriate outputs** - Choose the right output for your use case
7. **Consider latency** - Different outputs have different latency characteristics