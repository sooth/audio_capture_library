# macOS Audio Capture Library

A high-performance system audio capture and playback library for macOS using ScreenCaptureKit and AVAudioEngine.

## Features

- **Silent Recording**: Record system audio to WAV files without playback
- **Real-time Streaming**: Stream system audio to USB SPDIF adapter with minimal latency
- **Delayed Playback**: Add configurable delay before playback starts
- **Simultaneous Record & Play**: Stream audio while saving to WAV file
- **Zero-copy Performance**: Direct PCM buffer streaming for optimal performance

## Requirements

- macOS 13.0+ (Ventura or later)
- Screen Recording permission
- USB SPDIF Adapter (for audio playback)

## Quick Start

```bash
# Compile the project
./compile.sh

# Silent recording (no playback)
./run.sh record 30 meeting          # Record 30 seconds to meeting.wav

# Stream audio (real-time playback)
./run.sh stream                     # Stream for 30 seconds (default)
./run.sh stream 60                  # Stream for 60 seconds
./run.sh stream 20 5                # Stream for 20s with 5s delay

# Stream and save
./run.sh stream 30 0 audio          # Stream for 30s AND save to audio.wav
./run.sh stream 20 3 recording      # Stream for 20s with 3s delay, save to recording.wav

# Test audio output
./run.sh test-tone 5                # Play 440Hz test tone for 5 seconds
```

## Architecture

### Core Components

1. **StreamingAudioRecorder.swift** - Captures system audio using ScreenCaptureKit
2. **StreamingAudioPlayer.swift** - Plays audio through USB SPDIF adapter with delay support
3. **WavFileWriter.swift** - Saves audio to standard WAV files (16-bit PCM)
4. **main.swift** - Command-line interface and program entry point

### Audio Flow

```
System Audio → ScreenCaptureKit → CMSampleBuffer → AVAudioPCMBuffer
                                                    ↓
                                              ┌─────┴─────┐
                                              ↓           ↓
                                    StreamingAudioPlayer  WavFileWriter
                                              ↓           ↓
                                      USB SPDIF Output   WAV File
```

## Swift Files Documentation

### StreamingAudioRecorder.swift

Captures system audio using ScreenCaptureKit API. Key features:

- **Real-time Capture**: Uses `SCStream` to capture system audio
- **Buffer Conversion**: Converts `CMSampleBuffer` to `AVAudioPCMBuffer`
- **Delegate Pattern**: Distributes audio to multiple consumers (player, writer)
- **Performance Monitoring**: Tracks buffer processing statistics

Key Classes:
- `StreamingAudioRecorder`: Main capture class
- `AudioStreamDelegate`: Protocol for audio consumers
- `AVAudioPCMBufferPool`: Efficient buffer reuse (currently disabled)

### StreamingAudioPlayer.swift

Real-time audio playback with delay support. Key features:

- **AVAudioEngine**: Hardware-accelerated audio playback
- **Delay Management**: Configurable delay before playback starts
- **USB SPDIF Routing**: Automatic output device selection
- **Buffer Scheduling**: Continuous playback with queue management

Key Methods:
- `init(delay:)`: Initialize with playback delay
- `scheduleBuffer()`: Queue audio for playback
- `startPlayback()`: Start the audio engine

### WavFileWriter.swift

Saves audio to standard WAV files. Key features:

- **Format Conversion**: Float32 deinterleaved → Int16 interleaved
- **Thread-safe Writing**: Background queue for file I/O
- **Standard WAV Format**: 16-bit PCM, 48kHz, stereo

Key Methods:
- `startWriting(to:)`: Begin recording to file
- `write(_:)`: Add audio buffer to file
- `convertBuffer(_:)`: Format conversion pipeline

### main.swift

Command-line interface and program coordination. Commands:

- `record`: Silent recording mode
- `stream`: Real-time playback mode
- `test-tone`: Audio test utility
- `check-permissions`: Verify system permissions

## Audio Formats

- **Capture Format**: Float32, 48kHz, 2 channels, deinterleaved
- **Playback Format**: Float32, 48kHz, 2 channels, deinterleaved
- **WAV File Format**: Int16, 48kHz, 2 channels, interleaved

## Permissions

The app requires Screen Recording permission:

1. System Preferences → Security & Privacy → Privacy → Screen Recording
2. Grant permission to Terminal or your IDE
3. Restart the app after granting permission

## Performance

- **Latency**: < 40ms (typical)
- **Buffer Size**: 960 frames (20ms @ 48kHz)
- **CPU Usage**: < 5% (typical)
- **Memory Usage**: < 50MB

## Troubleshooting

1. **No Audio Output**: Check USB SPDIF Adapter is connected
2. **Permission Denied**: Grant Screen Recording permission
3. **No Audio Captured**: Check system audio is playing
4. **Crackling Audio**: Increase buffer size or check CPU load

## Building

```bash
# Debug build
./compile.sh

# Release build (optimized)
./compile.sh release

# Clean build
rm -rf build/
./compile.sh
```

## License

This project is for educational and personal use.