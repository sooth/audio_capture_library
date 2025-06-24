# Windows AudioCaptureKit Integration Guide

This guide provides detailed instructions for integrating the Windows AudioCaptureKit into your Python applications.

## Table of Contents
1. [Installation](#installation)
2. [Project Setup](#project-setup)
3. [Basic Integration](#basic-integration)
4. [Advanced Integration](#advanced-integration)
5. [Cross-Platform Compatibility](#cross-platform-compatibility)
6. [Best Practices](#best-practices)
7. [Migration from macOS](#migration-from-macos)

## Installation

### Prerequisites

- Windows 10 version 1803 or later (required for loopback recording)
- Python 3.7 or later
- Visual C++ Build Tools (for some dependencies)

### Install Dependencies

```bash
# Core dependencies
pip install numpy scipy

# Audio libraries
pip install sounddevice
pip install PyAudioWPatch  # NOT regular pyaudio
pip install pycaw

# Optional dependencies
pip install asyncio  # Usually included with Python
```

### Verify Installation

```python
# test_installation.py
import sys
print(f"Python version: {sys.version}")

try:
    import numpy
    print(f"NumPy: {numpy.__version__}")
except ImportError:
    print("NumPy not installed")

try:
    import sounddevice as sd
    print(f"sounddevice: {sd.__version__}")
    print(f"Available devices: {len(sd.query_devices())}")
except ImportError:
    print("sounddevice not installed")

try:
    import pyaudiowpatch
    print("PyAudioWPatch: Installed")
except ImportError:
    print("PyAudioWPatch not installed")

try:
    from pycaw.pycaw import AudioUtilities
    print("pycaw: Installed")
except ImportError:
    print("pycaw not installed")
```

## Project Setup

### Directory Structure

```
your_project/
├── main.py
├── audio_processing/
│   └── __init__.py
├── requirements.txt
└── windows_audio/
    └── API/  # Copy the Windows API folder here
        ├── __init__.py
        ├── AudioCaptureKit.py
        ├── AudioDevice.py
        ├── AudioError.py
        ├── AudioFormat.py
        ├── AudioOutput.py
        ├── AudioSession.py
        ├── AudioBufferQueue.py
        ├── StreamingAudioPlayer.py
        ├── StreamingAudioRecorder.py
        ├── NetworkOutput.py
        └── WavFileWriter.py
```

### Requirements File

```txt
# requirements.txt
numpy>=1.19.0
scipy>=1.5.0
sounddevice>=0.4.0
PyAudioWPatch>=0.2.12.5
pycaw>=20240316
```

## Basic Integration

### Simple Recording Application

```python
# main.py
import asyncio
import sys
from pathlib import Path

# Add API to path
sys.path.append(str(Path(__file__).parent))

from windows_audio.API import AudioCaptureKit, FileOutput

class AudioRecorder:
    def __init__(self):
        self.kit = AudioCaptureKit()
        self.session = None
    
    async def start_recording(self, filename):
        """Start recording to file"""
        try:
            # Start capture session
            self.session = await self.kit.start_capture()
            
            # Add file output
            output = FileOutput(filename)
            await self.session.add_output(output)
            
            print(f"Recording started: {filename}")
            return True
            
        except Exception as e:
            print(f"Failed to start recording: {e}")
            return False
    
    async def stop_recording(self):
        """Stop current recording"""
        if self.session:
            await self.kit.stop_capture(self.session)
            self.session = None
            print("Recording stopped")

# Usage
async def main():
    recorder = AudioRecorder()
    
    # Record for 10 seconds
    if await recorder.start_recording("test_recording.wav"):
        await asyncio.sleep(10)
        await recorder.stop_recording()

if __name__ == "__main__":
    asyncio.run(main())
```

### Real-time Audio Processor

```python
# audio_processor.py
import asyncio
import numpy as np
from windows_audio.API import AudioCaptureKit, CallbackOutput

class AudioProcessor:
    def __init__(self):
        self.kit = AudioCaptureKit()
        self.session = None
        
    async def start_processing(self):
        """Start audio processing"""
        self.session = await self.kit.start_capture()
        
        # Create callback output
        output = CallbackOutput(self.process_audio)
        await self.session.add_output(output)
    
    def process_audio(self, audio_data):
        """Process audio data in real-time"""
        # Calculate RMS level
        rms = np.sqrt(np.mean(audio_data**2))
        db = 20 * np.log10(rms) if rms > 0 else -np.inf
        
        # Print level meter
        meter_length = int((db + 60) / 60 * 50)  # Scale -60 to 0 dB
        meter = '█' * max(0, meter_length)
        print(f"\rLevel: {meter:<50} {db:6.1f} dB", end='')
    
    async def stop_processing(self):
        """Stop processing"""
        if self.session:
            await self.kit.stop_capture(self.session)

# Usage
async def main():
    processor = AudioProcessor()
    await processor.start_processing()
    
    # Run for 30 seconds
    await asyncio.sleep(30)
    await processor.stop_processing()

if __name__ == "__main__":
    asyncio.run(main())
```

## Advanced Integration

### Multi-threaded Audio Application

```python
# advanced_app.py
import asyncio
import threading
import queue
from concurrent.futures import ThreadPoolExecutor
from windows_audio.API import AudioCaptureKit, StreamOutput

class AdvancedAudioApp:
    def __init__(self):
        self.kit = AudioCaptureKit()
        self.audio_queue = queue.Queue(maxsize=100)
        self.processing_thread = None
        self.is_running = False
        
    async def start(self):
        """Start audio capture and processing"""
        self.is_running = True
        
        # Start processing thread
        self.processing_thread = threading.Thread(
            target=self._processing_worker,
            daemon=True
        )
        self.processing_thread.start()
        
        # Start audio capture
        session = await self.kit.start_capture()
        stream_output = StreamOutput()
        await session.add_output(stream_output)
        
        # Stream audio to processing thread
        async for buffer in stream_output.buffer_stream:
            if not self.is_running:
                break
            
            try:
                self.audio_queue.put_nowait(buffer.data)
            except queue.Full:
                print("Warning: Audio queue full, dropping buffer")
        
        await self.kit.stop_capture(session)
    
    def _processing_worker(self):
        """Worker thread for audio processing"""
        with ThreadPoolExecutor(max_workers=4) as executor:
            while self.is_running:
                try:
                    audio_data = self.audio_queue.get(timeout=1.0)
                    # Submit processing to thread pool
                    executor.submit(self._process_chunk, audio_data)
                except queue.Empty:
                    continue
    
    def _process_chunk(self, audio_data):
        """Process a single audio chunk"""
        # Your heavy processing here
        # This runs in parallel thread pool
        pass
    
    def stop(self):
        """Stop the application"""
        self.is_running = False
        if self.processing_thread:
            self.processing_thread.join()
```

### Network Audio Streaming Application

```python
# streaming_app.py
import asyncio
from windows_audio.API import (
    AudioCaptureKit, 
    NetworkAudioServer,
    NetworkAudioClient
)

class AudioStreamingServer:
    def __init__(self, port=9876):
        self.kit = AudioCaptureKit()
        self.port = port
        self.session = None
    
    async def start_server(self):
        """Start audio streaming server"""
        print(f"Starting audio server on port {self.port}")
        
        # Start network stream
        self.session = await self.kit.start_network_stream(
            host="0.0.0.0",
            port=self.port
        )
        
        print("Server is running. Press Ctrl+C to stop.")
        
        # Keep server running
        try:
            while True:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            await self.stop_server()
    
    async def stop_server(self):
        """Stop the server"""
        if self.session:
            await self.kit.stop_capture(self.session)
            print("Server stopped")

class AudioStreamingClient:
    def __init__(self, host="localhost", port=9876):
        self.client = NetworkAudioClient(host, port)
    
    async def start_client(self):
        """Start receiving audio from server"""
        try:
            # Connect to server
            format = await self.client.connect()
            print(f"Connected to server. Format: {format.description}")
            
            # Receive and process audio
            async for buffer in self.client.receive_audio():
                # Process received audio
                print(f"Received: {buffer.data.shape}")
                
        except Exception as e:
            print(f"Client error: {e}")
        finally:
            await self.client.disconnect()

# Server usage
async def run_server():
    server = AudioStreamingServer()
    await server.start_server()

# Client usage
async def run_client():
    client = AudioStreamingClient()
    await client.start_client()
```

## Cross-Platform Compatibility

### Platform Detection

```python
# platform_audio.py
import platform
import sys

def get_audio_kit():
    """Get platform-specific AudioCaptureKit"""
    system = platform.system()
    
    if system == "Windows":
        from windows_audio.API import AudioCaptureKit
        return AudioCaptureKit()
    elif system == "Darwin":  # macOS
        # Import macOS version
        from macos_audio.API import AudioCaptureKit
        return AudioCaptureKit()
    else:
        raise NotImplementedError(f"Platform {system} not supported")

# Usage
kit = get_audio_kit()
```

### Unified Interface

```python
# unified_audio.py
from abc import ABC, abstractmethod
import platform

class UnifiedAudioInterface(ABC):
    """Abstract interface for cross-platform audio"""
    
    @abstractmethod
    async def record_to_file(self, filename, duration):
        pass
    
    @abstractmethod
    async def stream_audio(self, callback):
        pass

class WindowsAudio(UnifiedAudioInterface):
    def __init__(self):
        from windows_audio.API import AudioCaptureKit
        self.kit = AudioCaptureKit()
    
    async def record_to_file(self, filename, duration):
        await self.kit.record_to_file(filename, duration)
    
    async def stream_audio(self, callback):
        return await self.kit.stream_audio(callback)

class MacOSAudio(UnifiedAudioInterface):
    def __init__(self):
        from macos_audio.API import AudioCaptureKit
        self.kit = AudioCaptureKit()
    
    async def record_to_file(self, filename, duration):
        await self.kit.record_to_file(filename, duration)
    
    async def stream_audio(self, callback):
        return await self.kit.stream_audio(callback)

def create_audio_interface():
    """Factory function for platform-specific audio"""
    system = platform.system()
    if system == "Windows":
        return WindowsAudio()
    elif system == "Darwin":
        return MacOSAudio()
    else:
        raise NotImplementedError(f"Platform {system} not supported")
```

## Best Practices

### 1. Error Handling

```python
import logging
from windows_audio.API import (
    AudioCaptureKit,
    AudioCaptureError,
    DeviceNotFoundError,
    AudioLoopbackPermissionError
)

logger = logging.getLogger(__name__)

async def safe_audio_operation():
    kit = AudioCaptureKit()
    
    try:
        session = await kit.start_capture()
        # Your audio logic here
        
    except AudioLoopbackPermissionError:
        logger.error("Loopback recording not available on this Windows version")
        # Fallback to microphone recording
        
    except DeviceNotFoundError as e:
        logger.error(f"Audio device not found: {e}")
        # List available devices for user
        
    except AudioCaptureError as e:
        logger.error(f"Audio capture error: {e}")
        # Handle specific audio errors
        
    except Exception as e:
        logger.exception("Unexpected error in audio operation")
        # Handle unexpected errors
        
    finally:
        # Cleanup
        await kit.cleanup()
```

### 2. Resource Management

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def audio_session(kit, config=None):
    """Context manager for audio sessions"""
    session = None
    try:
        session = await kit.start_capture(config)
        yield session
    finally:
        if session:
            await kit.stop_capture(session)

# Usage
async def record_with_context():
    kit = AudioCaptureKit()
    
    async with audio_session(kit) as session:
        output = FileOutput("recording.wav")
        await session.add_output(output)
        await asyncio.sleep(10)
    # Session automatically stopped
```

### 3. Performance Optimization

```python
from windows_audio.API import (
    AudioCaptureKit,
    CaptureConfiguration,
    ProcessingPriority
)

# Configure for low latency
config = CaptureConfiguration()
config.buffer_size = 256  # Smaller buffer for lower latency

# Set global configuration
kit = AudioCaptureKit()
kit_config = kit.get_configuration()
kit_config.processing_priority = ProcessingPriority.REALTIME
kit_config.buffer_size = 256
kit.set_configuration(kit_config)
```

## Migration from macOS

### API Compatibility

The Windows implementation maintains API compatibility with the macOS version. Most code can be used unchanged:

```python
# This code works on both platforms
async def cross_platform_recording():
    kit = AudioCaptureKit()
    session = await kit.start_capture()
    
    output = FileOutput("recording.wav")
    await session.add_output(output)
    
    await asyncio.sleep(10)
    await kit.stop_capture(session)
```

### Platform-Specific Features

```python
# Windows-specific: Loopback device selection
def get_loopback_device():
    kit = AudioCaptureKit()
    devices = kit.get_recording_devices()
    
    # Windows: Look for loopback devices
    for device in devices:
        if device.type == DeviceType.LOOPBACK:
            return device
    
    # macOS: System audio is handled differently
    # (through ScreenCaptureKit)
    return None

# Platform-specific device handling
import platform

async def platform_system_audio():
    kit = AudioCaptureKit()
    
    if platform.system() == "Windows":
        # Windows: Use loopback device
        device = get_loopback_device()
        config = CaptureConfiguration()
        config.device = device
        session = await kit.start_capture(config)
        
    else:  # macOS
        # macOS: System audio captured by default
        session = await kit.start_capture()
    
    return session
```

### Permission Differences

```python
# Windows permissions
async def check_windows_audio_permissions():
    """Check Windows audio capabilities"""
    import platform
    
    if platform.system() != "Windows":
        return True
    
    # Check Windows version for loopback support
    import sys
    if sys.getwindowsversion().build < 17134:  # Windows 10 1803
        print("Warning: Loopback recording requires Windows 10 1803 or later")
        return False
    
    return True

# macOS permissions (for reference)
async def check_macos_audio_permissions():
    """Check macOS audio permissions"""
    # macOS requires screen recording permission
    # This is handled by the macOS API
    pass
```

## Troubleshooting Integration Issues

### Import Errors

```python
# debug_imports.py
import sys
import importlib

def check_module(module_name):
    try:
        module = importlib.import_module(module_name)
        print(f"✓ {module_name} imported successfully")
        return True
    except ImportError as e:
        print(f"✗ {module_name} import failed: {e}")
        return False

# Check all required modules
modules = [
    'numpy',
    'scipy',
    'sounddevice',
    'pyaudiowpatch',
    'pycaw.pycaw'
]

all_good = all(check_module(m) for m in modules)
if all_good:
    print("\nAll dependencies installed correctly!")
else:
    print("\nSome dependencies are missing. Please install them.")
```

### Performance Issues

```python
# performance_test.py
import asyncio
import time
from windows_audio.API import AudioCaptureKit, CallbackOutput

class PerformanceMonitor:
    def __init__(self):
        self.buffer_count = 0
        self.start_time = time.time()
        self.last_time = time.time()
        
    def process_audio(self, audio_data):
        self.buffer_count += 1
        current_time = time.time()
        
        # Calculate statistics every 100 buffers
        if self.buffer_count % 100 == 0:
            elapsed = current_time - self.start_time
            rate = self.buffer_count / elapsed
            latency = (current_time - self.last_time) * 1000
            
            print(f"Buffers: {self.buffer_count}, "
                  f"Rate: {rate:.1f}/s, "
                  f"Latency: {latency:.1f}ms")
        
        self.last_time = current_time

async def test_performance():
    kit = AudioCaptureKit()
    monitor = PerformanceMonitor()
    
    session = await kit.start_capture()
    output = CallbackOutput(monitor.process_audio, use_thread=True)
    await session.add_output(output)
    
    # Run for 30 seconds
    await asyncio.sleep(30)
    await kit.stop_capture(session)

if __name__ == "__main__":
    asyncio.run(test_performance())
```

This integration guide should help you successfully integrate the Windows AudioCaptureKit into your projects!