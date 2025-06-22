# Audio Capture API Documentation

## Overview

The Audio Capture API provides a comprehensive solution for controlling audio recording on macOS from Python applications. It consists of:

1. **AudioCaptureServer** - A Swift-based TCP server that handles audio capture
2. **audio_capture_client.py** - A Python client library for controlling the server
3. **TCP/JSON Protocol** - A clean, extensible protocol for IPC communication

## Features

- List available audio input devices
- Start/stop audio recording with device selection
- Capture system audio alongside microphone input
- Monitor recording status in real-time
- Download recorded audio files
- Thread-safe operation with support for multiple clients
- Comprehensive error handling and recovery

## Architecture

```
┌─────────────────┐        TCP/JSON         ┌──────────────────┐
│  Python Client  │◄─────────────────────────►│  Swift Server   │
│                 │                          │                  │
│ - Control API   │      Port 9876          │ - Audio Capture  │
│ - File Transfer │      (default)          │ - Device Mgmt    │
│ - Status Query  │                          │ - File I/O       │
└─────────────────┘                          └──────────────────┘
```

## Building and Installation

### Prerequisites

- macOS 13.0 or later
- Xcode Command Line Tools
- Python 3.7 or later
- Screen Recording permission (for system audio capture)

### Building the Server

```bash
cd macos
./compile_audio_server.sh
```

This creates `build/AudioCaptureServer`

### Installing Python Client

```bash
cd python
pip install -r requirements.txt
```

## Quick Start

### 1. Start the Server

```bash
./build/AudioCaptureServer
```

The server will start listening on port 9876.

### 2. Use Python Client

```python
from audio_capture_client import AudioCaptureClient, record_audio

# List available devices
with AudioCaptureClient() as client:
    devices = client.list_devices()
    for device in devices:
        print(f"{device.id}: {device.name}")

# Record audio for 5 seconds
output_file = record_audio(
    duration=5.0,
    device_id=0,
    capture_system_audio=True
)
print(f"Recording saved to: {output_file}")
```

## API Reference

### Python Client API

#### AudioCaptureClient

Main client class for interacting with the audio capture server.

```python
class AudioCaptureClient:
    def __init__(self, host: str = "localhost", port: int = 9876, timeout: float = 30.0)
    def connect(self) -> None
    def disconnect(self) -> None
    def list_devices(self) -> List[AudioDevice]
    def start_recording(self, device_id: int = 0, capture_system_audio: bool = False, 
                       output_path: Optional[str] = None) -> None
    def stop_recording(self) -> str
    def get_status(self) -> RecordingStatus
    def get_file(self, remote_path: str, local_path: Optional[str] = None) -> str
    def shutdown_server(self) -> None
```

#### Data Classes

```python
@dataclass
class AudioDevice:
    id: int
    name: str
    is_input: bool
    is_output: bool

@dataclass
class RecordingStatus:
    state: RecordingState  # IDLE, RECORDING, or STOPPING
    duration: Optional[float]
    device_name: Optional[str]
    captures_system_audio: bool
    output_file: Optional[str]
```

#### Convenience Functions

```python
def list_audio_devices(host: str = "localhost", port: int = 9876) -> List[AudioDevice]

def record_audio(duration: float, device_id: int = 0, 
                capture_system_audio: bool = False,
                output_path: Optional[str] = None,
                host: str = "localhost", port: int = 9876) -> str
```

### TCP/JSON Protocol

The protocol uses newline-delimited JSON messages.

#### Request Format

```json
{
    "id": "unique-request-id",
    "command": "COMMAND_NAME",
    "params": {
        "param1": "value1",
        "param2": "value2"
    }
}
```

#### Response Format

```json
{
    "id": "matching-request-id",
    "success": true,
    "data": {
        "key": "value"
    },
    "error": null
}
```

#### Commands

| Command | Parameters | Description |
|---------|------------|-------------|
| LIST_DEVICES | None | List all available audio input devices |
| START_RECORDING | deviceId, captureSystemAudio, outputPath | Start audio recording |
| STOP_RECORDING | None | Stop current recording and save file |
| GET_STATUS | None | Get current recording status |
| GET_FILE | path | Download a recorded file |
| SHUTDOWN | None | Shutdown the server |

## Examples

### Basic Recording

```python
from audio_capture_client import AudioCaptureClient

with AudioCaptureClient() as client:
    # Start recording with default microphone
    client.start_recording()
    
    # Wait 10 seconds
    time.sleep(10)
    
    # Stop and get file
    output_file = client.stop_recording()
    print(f"Recorded to: {output_file}")
```

### Recording with System Audio

```python
from audio_capture_client import AudioCaptureClient

with AudioCaptureClient() as client:
    # List devices and select one
    devices = client.list_devices()
    
    # Start recording with system audio
    client.start_recording(
        device_id=0,  # First device
        capture_system_audio=True,
        output_path="my_recording.wav"
    )
    
    # Monitor status
    for i in range(5):
        time.sleep(1)
        status = client.get_status()
        print(f"Recording: {status.duration:.1f}s")
    
    # Stop recording
    output_file = client.stop_recording()
    
    # Download file
    local_file = client.get_file(output_file)
```

### Async-style Recording

```python
from audio_capture_client import AudioCaptureClient, AsyncAudioRecorder

with AudioCaptureClient() as client:
    with AsyncAudioRecorder(client) as recorder:
        # Start recording
        recorder.start(device_id=1, capture_system_audio=True)
        
        # Do other work...
        time.sleep(5)
        
        # Recording stops automatically when exiting context
        output_file = recorder.stop()
```

### Error Handling

```python
from audio_capture_client import AudioCaptureClient, CaptureError

try:
    with AudioCaptureClient() as client:
        client.start_recording()
        # ... recording logic ...
        
except CaptureError as e:
    print(f"Capture error: {e}")
except Exception as e:
    print(f"Unexpected error: {e}")
```

## Testing

Run the comprehensive test suite:

```bash
cd python
python test_audio_capture_api.py
```

The test suite includes:
- Unit tests for client functionality
- Protocol validation tests
- Edge case and error handling tests
- Concurrent access tests
- Integration tests (when server is running)

## Troubleshooting

### Server Won't Start

1. Check if another process is using port 9876
2. Ensure you have built the server with `compile_audio_server.sh`
3. Check console for any permission errors

### No Audio Devices Found

1. Ensure microphone permission is granted in System Settings
2. Check that audio devices are properly connected
3. Try running the server with elevated permissions

### System Audio Not Captured

1. Grant Screen Recording permission in System Settings > Privacy & Security
2. Restart the server after granting permission
3. Ensure you set `capture_system_audio=True`

### Connection Errors

1. Verify the server is running
2. Check firewall settings if connecting remotely
3. Ensure correct host and port settings

## Security Considerations

1. The server listens on all interfaces by default - restrict to localhost for security
2. No authentication is implemented - use only on trusted networks
3. File paths are not sanitized - validate paths in production use
4. Consider implementing TLS for network communication

## Performance Notes

- Audio is captured at 48kHz stereo by default
- System audio capture adds minimal overhead
- File transfers are streamed to handle large files efficiently
- Multiple concurrent recordings are not supported (by design)

## License

This API is part of the macOS Audio Capture Library. See main project license for details.