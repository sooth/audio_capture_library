# macOS Audio Capture Library

A comprehensive audio capture and streaming library for macOS with Python integration.

## Features

- 🎤 **System Audio Capture** - Capture all system audio using ScreenCaptureKit
- 🔊 **Real-time Playback** - Stream audio to any output device with configurable delay  
- 💾 **File Recording** - Save audio to standard WAV files
- 🌐 **Network Streaming** - Stream audio to Python or other applications via TCP/IP
- 🎛️ **Device Management** - Enumerate and control audio devices
- 🚀 **Modern API** - Built with Swift async/await and type safety
- 🐍 **Python Integration** - Capture and process audio in Python

## Quick Start

### Prerequisites

- macOS 13.0+ (Ventura or later)
- Xcode Command Line Tools
- Python 3.6+ (for network streaming)
- Screen Recording permission

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd audio_capture_library
   ```

2. Compile the Swift library:
   ```bash
   cd macos
   ./compile_api.sh
   cd ..
   ```

3. Install Python dependencies (optional):
   ```bash
   pip install -r python/requirements.txt
   ```

### Basic Usage

#### Record System Audio to File

```bash
# Record 30 seconds to recording.wav
./macos/build/audio_capture_api record 30 recording
```

#### Stream Audio with Real-time Playback

```bash
# Stream for 30 seconds with 2 second delay
./macos/build/audio_capture_api stream 30
```

#### Network Streaming to Python

Terminal 1 (Swift):
```bash
./macos/build/audio_capture_api network 30 9876
```

Terminal 2 (Python):
```bash
python python/audio_capture_client.py --port 9876 --output captured.wav
```

## Architecture

The library consists of three main layers:

### 1. Core Audio Layer (`macos/`)
- `StreamingAudioRecorder.swift` - System audio capture using ScreenCaptureKit
- `StreamingAudioPlayer.swift` - Real-time playback with AVAudioEngine
- `WavFileWriter.swift` - WAV file recording with format conversion

### 2. API Layer (`macos/API/`)
- `AudioCaptureKit.swift` - Main entry point
- `AudioDevice.swift` - Device enumeration and management
- `AudioSession.swift` - Session-based lifecycle management
- `AudioOutput.swift` - Extensible output protocol
- `NetworkOutput.swift` - TCP/IP streaming server

### 3. Python Integration (`python/`)
- `audio_capture_client.py` - Network client for receiving audio
- Real-time processing capabilities
- WAV file output

## Documentation

- [API Design](macos/API_DESIGN.md) - Comprehensive API documentation
- [Architecture](macos/ARCHITECTURE.md) - Technical architecture details
- [Network Streaming](NETWORK_STREAMING.md) - Network protocol and usage
- [Python Client](python/README.md) - Python integration guide

## Examples

### Swift API Usage

```swift
// Simple recording
let kit = AudioCaptureKit.shared
try await kit.recordToFile(url: fileURL, duration: 10.0)

// Multi-output streaming
let session = try await kit.startCapture()
try await session.addOutput(FileOutput(url: fileURL))
try await session.addOutput(NetworkOutput(port: 9876))
try await session.addOutput(PlaybackOutput(device: speakerDevice))
```

### Python Client Usage

```python
from audio_capture_client import AudioCaptureClient

client = AudioCaptureClient(host='localhost', port=9876)
if client.connect():
    client.record_for_duration(10.0, 'output.wav')
    client.disconnect()
```

## Command Line Interface

The compiled binary provides these commands:

```
devices              List all audio devices
record <duration> <filename>
                    Record audio to WAV file
stream <duration>   Stream audio with playback
monitor <duration>  Monitor audio levels
multi <duration>    Multi-output demonstration
network <duration> [port]
                    Stream audio over network
examples            Run all API examples
```

## Testing

Run the complete network streaming test:
```bash
./test_network_streaming.sh
```

This will:
1. Check all dependencies
2. Compile if needed
3. Start Swift audio streaming
4. Connect Python client
5. Save audio to WAV file

## Requirements

### System Requirements
- macOS 13.0+ (Ventura or later)
- Apple Silicon or Intel Mac
- Screen Recording permission

### Development Requirements
- Xcode Command Line Tools
- Swift 5.5+
- Python 3.6+ (for network features)

### Python Dependencies
```
numpy>=1.19.0
scipy>=1.5.0
```

## Permissions

The library requires Screen Recording permission:

1. Open System Settings
2. Go to Privacy & Security → Screen Recording
3. Enable permission for Terminal or your IDE

## Troubleshooting

### No Audio Captured
- Ensure system audio is playing
- Check Screen Recording permission
- Verify audio device selection

### Connection Issues (Network)
- Check firewall settings
- Verify port availability: `lsof -i :9876`
- Ensure both Swift and Python are running

### Performance Issues
- Use release builds: `./compile_api.sh release`
- Close unnecessary applications
- Check CPU and memory usage

## Project Structure

```
audio_capture_library/
├── macos/                    # Swift implementation
│   ├── API/                  # API layer
│   ├── *.swift              # Core components
│   ├── compile_api.sh       # Build script
│   └── README.md            # macOS documentation
├── python/                   # Python client
│   ├── audio_capture_client.py
│   ├── requirements.txt
│   └── README.md
├── test_network_streaming.sh # Integration test
├── NETWORK_STREAMING.md     # Network protocol docs
└── README.md               # This file
```

## Contributing

Contributions are welcome! Please read the API design document for architecture guidelines.

## License

This project is for educational and personal use.

## Acknowledgments

- Built with Swift, ScreenCaptureKit, and AVFoundation
- Python integration using numpy and scipy
- Inspired by modern audio streaming architectures