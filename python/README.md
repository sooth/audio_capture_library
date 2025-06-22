# Audio Capture Python Client

A Python client for capturing audio streamed from the macOS Audio Capture Library's network output.

## Overview

This client connects to the Swift audio capture API's `NetworkOutput` and saves the streamed audio to a WAV file. It provides real-time audio streaming over TCP/IP, allowing you to capture system audio on macOS and process it in Python.

## Features

- **Real-time streaming**: Receive audio with minimal latency
- **Format detection**: Automatically detects audio format from server
- **Flexible recording**: Record for specific duration or until interrupted
- **Statistics**: Monitor packets received and data throughput
- **Robust protocol**: Handles connection issues gracefully

## Requirements

```bash
pip install numpy scipy
```

- Python 3.6+
- numpy (for audio data handling)
- scipy (for WAV file writing)

## Installation

1. Clone the repository or download `audio_capture_client.py`
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

## Usage

### Basic Usage

1. First, start the Swift audio capture with network output:
   ```bash
   # Using the API
   ./build/audio_capture_api network 30 9876
   
   # Or using the example
   swift network_streaming_example.swift 30 9876
   ```

2. Then run the Python client:
   ```bash
   python audio_capture_client.py
   ```

### Command Line Options

```bash
python audio_capture_client.py [options]

Options:
  --host HOST         Server host (default: localhost)
  --port PORT         Server port (default: 9876)
  --output OUTPUT     Output WAV file (default: captured_audio.wav)
  --duration DURATION Recording duration in seconds (default: unlimited)
```

### Examples

Record for 10 seconds:
```bash
python audio_capture_client.py --duration 10 --output recording.wav
```

Connect to remote host:
```bash
python audio_capture_client.py --host 192.168.1.100 --port 9876
```

Record until interrupted (Ctrl+C):
```bash
python audio_capture_client.py --output long_recording.wav
```

## Protocol Details

The client communicates with the Swift NetworkOutput using a simple binary protocol:

### Format Header (18 bytes)
- Magic: "AUDIO" (5 bytes)
- Version: 1 (1 byte)
- Sample Rate: 32-bit unsigned (4 bytes)
- Channels: 16-bit unsigned (2 bytes)
- Bit Depth: 16-bit unsigned (2 bytes)
- Flags: 32-bit unsigned (4 bytes)
  - Bit 0: Is float format
  - Bit 1: Is interleaved

### Audio Packets
- Type: 0x01 (1 byte)
- Timestamp: 64-bit unsigned microseconds (8 bytes)
- Frame Count: 32-bit unsigned (4 bytes)
- Audio Data: Variable length

### End Packet
- Type: 0xFF (1 byte)
- Final Timestamp: 64-bit unsigned (8 bytes)

## Python API Usage

You can also use the client programmatically:

```python
from audio_capture_client import AudioCaptureClient

# Create client
client = AudioCaptureClient(host='localhost', port=9876)

# Connect to server
if client.connect():
    # Record for 10 seconds
    client.record_for_duration(10.0, 'output.wav')
    
    # Or record until stopped
    client.start_receiving()
    # ... do something ...
    client.is_running = False
    client.save_to_wav('output.wav')
    
    # Disconnect
    client.disconnect()
```

## Integration Example

Here's a complete example that captures audio and performs real-time analysis:

```python
import numpy as np
from audio_capture_client import AudioCaptureClient
import matplotlib.pyplot as plt
from scipy import signal

class AudioAnalyzer(AudioCaptureClient):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.spectrum_data = []
    
    def _handle_audio_packet(self):
        # Call parent method
        super()._handle_audio_packet()
        
        # Get latest audio data
        if not self.audio_queue.empty():
            timestamp, audio_data = self.audio_queue.get()
            
            # Perform FFT for spectrum analysis
            if len(audio_data) > 0:
                # Use first channel if stereo
                if audio_data.ndim > 1:
                    data = audio_data[:, 0]
                else:
                    data = audio_data
                
                # Compute spectrum
                frequencies, spectrum = signal.periodogram(
                    data, 
                    fs=self.format.sample_rate
                )
                
                # Store for visualization
                self.spectrum_data.append({
                    'timestamp': timestamp,
                    'frequencies': frequencies,
                    'spectrum': spectrum
                })

# Use the analyzer
analyzer = AudioAnalyzer()
if analyzer.connect():
    analyzer.record_for_duration(5.0, 'analyzed.wav')
    
    # Plot spectrum
    if analyzer.spectrum_data:
        last_spectrum = analyzer.spectrum_data[-1]
        plt.semilogy(
            last_spectrum['frequencies'], 
            last_spectrum['spectrum']
        )
        plt.xlabel('Frequency [Hz]')
        plt.ylabel('Power Spectral Density')
        plt.title('Audio Spectrum')
        plt.show()
```

## Troubleshooting

### Connection Refused
- Ensure the Swift audio capture is running with NetworkOutput
- Check that the port matches (default: 9876)
- Verify firewall settings allow the connection

### No Audio Data
- Check that system audio is playing on macOS
- Verify Screen Recording permission is granted to Terminal/IDE
- Ensure the Swift capture session is active

### Format Errors
- The client supports Float32 and Int16 formats
- Other formats will need conversion in the Swift NetworkOutput

### Performance Issues
- Use release builds of the Swift application
- Ensure network latency is low (use localhost when possible)
- Adjust buffer sizes if experiencing dropouts

## Advanced Features

### Multi-Client Support
The Swift NetworkOutput supports multiple simultaneous clients:
```bash
# Terminal 1
python audio_capture_client.py --output client1.wav

# Terminal 2
python audio_capture_client.py --output client2.wav
```

### Custom Processing
Extend the `AudioCaptureClient` class to add custom processing:

```python
class CustomProcessor(AudioCaptureClient):
    def _handle_audio_packet(self):
        super()._handle_audio_packet()
        # Add your processing here
```

### Streaming to Other Applications
You can pipe the audio data to other applications instead of saving to file:

```python
# Stream to ffmpeg for encoding
# Implement custom client that writes to stdout
python audio_stream_pipe.py | ffmpeg -f f32le -ar 48000 -ac 2 -i - output.mp3
```

## Performance

- Typical latency: < 50ms
- Network overhead: ~5% for Float32 stereo at 48kHz
- CPU usage: < 5% for receiving and saving

## License

This is part of the macOS Audio Capture Library project.