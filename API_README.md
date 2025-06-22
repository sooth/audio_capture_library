# Audio Capture API - Quick Start Guide

This is a production-ready API for controlling audio capture on macOS from Python applications.

## Components

1. **AudioCaptureServer** (`macos/AudioCaptureServer.swift`) - Swift TCP server
2. **Python Client** (`python/audio_capture_client.py`) - Python client library
3. **Test Suite** (`python/test_audio_capture_api.py`) - Comprehensive tests

## Quick Setup

### 1. Build the Server

```bash
cd macos
./compile_audio_server.sh
```

### 2. Run the Server

```bash
./build/AudioCaptureServer
```

The server listens on port 9876 and supports multiple concurrent clients.

### 3. Use from Python

```python
from audio_capture_client import AudioCaptureClient, record_audio

# Quick recording
output = record_audio(duration=5.0, capture_system_audio=True)
print(f"Saved to: {output}")

# Advanced usage
with AudioCaptureClient() as client:
    devices = client.list_devices()
    client.start_recording(device_id=0, capture_system_audio=True)
    # ... do work ...
    output = client.stop_recording()
```

## Run Tests

```bash
# Quick integration test
./test_api_integration.sh

# Full test suite
cd python
python test_audio_capture_api.py
```

## Features

- ✅ List available microphones
- ✅ Start/stop recording with device selection
- ✅ Capture system audio (requires Screen Recording permission)
- ✅ Real-time status monitoring
- ✅ File download support
- ✅ Thread-safe operation
- ✅ Comprehensive error handling
- ✅ Production-ready with proper resource cleanup

## Example Applications

See `python/example_usage.py` for complete examples including:
- Device selection
- Status monitoring
- Error handling
- Async-style recording

## Documentation

See `API_DOCUMENTATION.md` for complete API reference and protocol details.