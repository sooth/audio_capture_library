# AudioCaptureKit for Windows

A comprehensive Python audio capture and playback library for Windows, providing functionality equivalent to the macOS AudioCaptureKit.

## Features

- **System Audio Capture**: Record system audio using WASAPI loopback
- **Microphone Recording**: Capture from any input device
- **Real-time Playback**: Low-latency audio playback with configurable delay
- **Multiple Output Destinations**: File, network stream, callback, or playback
- **Device Management**: Enumerate and control audio devices
- **Format Support**: Automatic format conversion and negotiation
- **Network Streaming**: TCP/IP audio streaming for inter-process communication
- **Session-based Architecture**: Manage multiple concurrent audio operations

## Requirements

- Windows 10 version 1803 or later (for loopback recording)
- Python 3.7 or later
- Required packages:
  ```
  numpy
  scipy
  sounddevice
  PyAudioWPatch
  pycaw
  ```

## Installation

```bash
pip install numpy scipy sounddevice PyAudioWPatch pycaw
```

## Quick Start

```python
import asyncio
from windows.API import AudioCaptureKit, quick_record, quick_play_loopback

# Quick record to file
async def record_example():
    await quick_record("output.wav", duration=5.0)

# Quick playback of system audio
async def playback_example():
    await quick_play_loopback(duration=10.0)

# Run examples
asyncio.run(record_example())
```

## Basic Usage

### Recording Audio

```python
import asyncio
from windows.API import AudioCaptureKit, FileOutput

async def record_audio():
    kit = AudioCaptureKit()
    
    # Start recording session
    session = await kit.start_capture()
    
    # Add file output
    file_output = FileOutput("recording.wav")
    await session.add_output(file_output)
    
    # Record for 10 seconds
    await asyncio.sleep(10)
    
    # Stop recording
    await kit.stop_capture(session)

asyncio.run(record_audio())
```

### System Audio Loopback

```python
import asyncio
from windows.API import AudioCaptureKit, DeviceType

async def record_system_audio():
    kit = AudioCaptureKit()
    
    # Find loopback device
    devices = kit.get_recording_devices()
    loopback_device = next((d for d in devices if d.type == DeviceType.LOOPBACK), None)
    
    if loopback_device:
        # Record system audio to file
        session = await kit.record_to_file(
            "system_audio.wav",
            duration=30.0,
            device=loopback_device
        )

asyncio.run(record_system_audio())
```

### Real-time Audio Streaming

```python
import asyncio
from windows.API import AudioCaptureKit, StreamOutput

async def stream_audio():
    kit = AudioCaptureKit()
    
    # Start capture with streaming output
    session = await kit.start_capture()
    stream_output = StreamOutput()
    await session.add_output(stream_output)
    
    # Process audio buffers
    async for buffer in stream_output.buffer_stream:
        print(f"Received buffer: {buffer.data.shape}")
        # Process audio data here
        
        if should_stop():  # Your condition
            break
    
    await kit.stop_capture(session)

asyncio.run(stream_audio())
```

### Network Audio Streaming

```python
import asyncio
from windows.API import AudioCaptureKit

async def start_audio_server():
    kit = AudioCaptureKit()
    
    # Start network streaming server
    session = await kit.start_network_stream(
        host="0.0.0.0",
        port=9876
    )
    
    print("Audio server running on port 9876")
    # Server runs until stopped
    
asyncio.run(start_audio_server())
```

### Audio Playback

```python
import asyncio
from windows.API import AudioCaptureKit, AudioPlaybackSession

async def play_audio():
    kit = AudioCaptureKit()
    
    # Start playback session
    session = await kit.start_playback()
    
    # Schedule audio buffers
    for buffer in audio_buffers:
        await session.schedule_buffer(buffer)
    
    # Wait for playback to complete
    await asyncio.sleep(duration)
    
    await kit.stop_playback(session)

asyncio.run(play_audio())
```

## Advanced Features

### Device Management

```python
from windows.API import AudioCaptureKit

kit = AudioCaptureKit()

# List all devices
playback_devices = kit.get_playback_devices()
recording_devices = kit.get_recording_devices()

for device in playback_devices:
    print(f"Playback: {device.name} ({device.host_api.value})")

for device in recording_devices:
    print(f"Recording: {device.name} ({device.type.value})")

# Set default devices
kit.set_playback_device(playback_devices[0])
kit.set_recording_device(recording_devices[0])
```

### Format Configuration

```python
from windows.API import AudioFormat, CaptureConfiguration

# Create custom format
format = AudioFormat(
    sample_rate=96000.0,
    channel_count=2,
    bit_depth=24,
    is_interleaved=True,
    is_float=False
)

# Use in capture configuration
config = CaptureConfiguration()
config.format = format

session = await kit.start_capture(config)
```

### Multiple Outputs

```python
import asyncio
from windows.API import (
    AudioCaptureKit, FileOutput, 
    NetworkOutput, CallbackOutput
)

async def multi_output_example():
    kit = AudioCaptureKit()
    session = await kit.start_capture()
    
    # Add multiple outputs
    await session.add_output(FileOutput("recording.wav"))
    await session.add_output(NetworkOutput(port=9876))
    await session.add_output(CallbackOutput(process_audio))
    
    # All outputs receive the same audio data
    await asyncio.sleep(30)
    await kit.stop_capture(session)

def process_audio(audio_data):
    # Process audio in callback
    print(f"Audio shape: {audio_data.shape}")

asyncio.run(multi_output_example())
```

### Error Handling

```python
import asyncio
from windows.API import (
    AudioCaptureKit, 
    AudioLoopbackPermissionError,
    DeviceNotFoundError
)

async def safe_recording():
    kit = AudioCaptureKit()
    
    try:
        session = await kit.start_capture()
        # ... recording logic ...
        
    except AudioLoopbackPermissionError:
        print("Windows loopback recording not available")
        print("Requires Windows 10 version 1803 or later")
        
    except DeviceNotFoundError as e:
        print(f"Device error: {e}")
        
    except Exception as e:
        print(f"Unexpected error: {e}")

asyncio.run(safe_recording())
```

## API Differences from macOS

While this Windows implementation maintains API compatibility with the macOS version, there are some platform-specific differences:

1. **Loopback Recording**: Windows uses WASAPI loopback instead of ScreenCaptureKit
2. **Permissions**: No screen recording permission needed, but requires Windows 10 1803+
3. **Device Management**: Setting default devices requires elevated permissions on Windows
4. **Audio APIs**: Uses WASAPI, DirectSound, MME instead of CoreAudio
5. **Latency**: May have slightly higher latency than macOS depending on the audio API used

## Performance Tips

1. **Use WASAPI** for lowest latency when possible
2. **Adjust buffer sizes** based on your latency requirements
3. **Use callbacks** for real-time processing instead of polling
4. **Enable exclusive mode** for dedicated audio hardware access
5. **Process audio in separate threads** to avoid blocking

## Troubleshooting

### Common Issues

1. **"Failed to find loopback device"**
   - Ensure PyAudioWPatch is installed (not regular PyAudio)
   - Check Windows version is 1803 or later

2. **"Access denied" errors**
   - Run with appropriate permissions
   - Check if audio device is in use by another application

3. **High latency**
   - Reduce buffer size
   - Use WASAPI exclusive mode
   - Close other audio applications

4. **Choppy audio**
   - Increase buffer size
   - Check CPU usage
   - Use lower sample rates

## Examples

See the `Examples` directory for complete working examples:
- `basic_recording.py` - Simple file recording
- `loopback_recording.py` - System audio capture
- `network_streaming.py` - TCP audio streaming
- `real_time_processing.py` - Live audio effects
- `device_management.py` - Device enumeration and control

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built using [sounddevice](https://github.com/spatialaudio/python-sounddevice)
- Loopback support via [PyAudioWPatch](https://github.com/s0d3s/PyAudioWPatch)
- Windows audio control with [pycaw](https://github.com/AndreMiras/pycaw)