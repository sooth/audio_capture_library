# Audio Capture Library - Technical Architecture

## Overview

This document describes the technical architecture of the macOS Audio Capture Library, which provides high-performance system audio capture and playback using modern Apple frameworks.

## Core Technologies

- **ScreenCaptureKit**: System audio capture (macOS 13.0+)
- **AVAudioEngine**: Hardware-accelerated audio playback
- **AVFoundation**: Audio format conversion and file I/O
- **CoreMedia**: Low-level audio buffer management

## Component Architecture

### 1. StreamingAudioRecorder

**Purpose**: Captures system audio using ScreenCaptureKit

**Key Components**:
- `SCStream`: ScreenCaptureKit stream for audio capture
- `SCStreamDelegate`: Handles stream lifecycle events
- `SCStreamOutput`: Receives audio sample buffers
- `AudioStreamDelegate`: Custom protocol for audio distribution

**Audio Flow**:
```
System Audio → SCStream → CMSampleBuffer → createPCMBuffer() → AVAudioPCMBuffer → Delegates
```

**Technical Details**:
- Captures at 48kHz, stereo, Float32 format
- Uses display filter (not app-specific) for system-wide audio
- Converts CMSampleBuffer to AVAudioPCMBuffer for compatibility
- Multi-delegate pattern allows multiple consumers

### 2. StreamingAudioPlayer

**Purpose**: Real-time audio playback with delay support

**Key Components**:
- `AVAudioEngine`: Core audio processing engine
- `AVAudioPlayerNode`: Hardware-accelerated playback node
- `AVAudioMixerNode`: Audio routing and mixing
- Delay management system

**Audio Graph**:
```
AVAudioPCMBuffer → PlayerNode → MixerNode → OutputNode → USB SPDIF
```

**Delay Implementation**:
- During delay: Audio engine is NOT started, buffers are dropped
- After delay: Engine starts fresh, ensuring clean playback
- This prevents "stale player node" issues

**Technical Details**:
- Direct PCM buffer scheduling (zero-copy)
- Automatic USB SPDIF adapter detection
- Volume control via player node
- Buffer queue management for continuous playback

### 3. WavFileWriter

**Purpose**: Saves audio to standard WAV files

**Key Components**:
- `AVAudioFile`: File I/O with format support
- Format conversion pipeline
- Background write queue

**Format Conversion**:
```
Input: Float32, 48kHz, 2ch, deinterleaved
  ↓
Step 1: Interleave channels (manual)
  ↓
Intermediate: Float32, 48kHz, 2ch, interleaved
  ↓
Step 2: Convert to Int16 (manual)
  ↓
Output: Int16, 48kHz, 2ch, interleaved (WAV)
```

**Why Manual Conversion?**:
- AVAudioConverter fails with deinterleaved→interleaved Int16
- Two-step conversion ensures compatibility
- Manual interleaving preserves audio quality

## Audio Formats

### Capture Format (ScreenCaptureKit)
- Sample Rate: 48000 Hz
- Bit Depth: 32-bit float
- Channels: 2 (stereo)
- Interleaving: Non-interleaved (planar)
- Format Flag: 0x29 (Float32, non-interleaved)

### Playback Format (AVAudioEngine)
- Sample Rate: 48000 Hz
- Bit Depth: 32-bit float
- Channels: 2 (stereo)
- Interleaving: Non-interleaved
- Direct compatibility with capture format

### WAV File Format
- Sample Rate: 48000 Hz
- Bit Depth: 16-bit integer
- Channels: 2 (stereo)
- Interleaving: Interleaved
- Standard PCM WAV format

## Threading Model

### Main Thread
- CLI interface
- Initial setup
- RunLoop management

### Capture Thread (ScreenCaptureKit)
- High-priority audio capture
- Minimal processing
- Hands off to processing queue

### Processing Queue
- CMSampleBuffer → AVAudioPCMBuffer conversion
- Performance logging
- Delegate dispatch

### Delegate Queue
- Distributes buffers to consumers
- Ensures thread safety
- Prevents capture thread blocking

### File Write Queue
- Background file I/O
- Format conversion
- Prevents blocking audio pipeline

## Performance Optimizations

1. **Zero-Copy Buffer Passing**
   - Direct AVAudioPCMBuffer scheduling
   - No intermediate copies

2. **Lock-Free Audio Path**
   - Capture → Process → Playback without locks
   - File writing on separate queue

3. **Buffer Pooling (Disabled)**
   - Implemented but caused format issues
   - Direct allocation more reliable

4. **Minimal Processing**
   - Format conversion only when necessary
   - Direct pass-through for playback

## Memory Management

- **Buffer Lifecycle**: Create → Use → Release (ARC)
- **Peak Memory**: ~50MB typical
- **Buffer Size**: 960 frames (20ms @ 48kHz)
- **Queue Depth**: 8 buffers max

## Error Handling

1. **Permission Errors**
   - Screen Recording permission check
   - User-friendly error messages

2. **Audio Device Errors**
   - Fallback to default output
   - Device enumeration logging

3. **Format Conversion Errors**
   - Detailed error logging
   - Graceful degradation

## Security Considerations

- Requires Screen Recording permission
- No network access
- Local file system only
- No sensitive data logging

## Swift File Documentation

### main.swift (Entry Point)
- **Purpose**: Command-line interface and program entry point
- **Commands**:
  - `record`: Silent recording to WAV file (no playback)
  - `stream`: Real-time playback with optional recording
  - `test-tone`: Audio system verification
  - `check-permissions`: Screen Recording permission check
- **Architecture**: Async/await for modern concurrency
- **Key Logic**: Routes commands to appropriate handlers

### StreamingAudioRecorder.swift (Audio Capture)
- **Purpose**: Captures system audio using ScreenCaptureKit
- **Key Classes**:
  - `StreamingAudioRecorder`: Main capture class
  - `AudioStreamDelegate`: Protocol for audio consumers
  - `AVAudioPCMBufferPool`: Buffer reuse (disabled)
- **Audio Path**: SCStream → CMSampleBuffer → AVAudioPCMBuffer → Delegates
- **Threading**: Separate queues for capture, processing, and delegate dispatch
- **Format**: 48kHz, stereo, Float32 deinterleaved

### StreamingAudioPlayer.swift (Audio Playback)
- **Purpose**: Real-time playback with delay support
- **Key Features**:
  - AVAudioEngine for hardware acceleration
  - Delay implementation (engine starts after delay)
  - USB SPDIF adapter auto-detection
  - Volume control
- **Audio Path**: AVAudioPCMBuffer → PlayerNode → MixerNode → Output
- **Delay Logic**: Drops buffers during delay, starts engine when expired

### WavFileWriter.swift (File Recording)
- **Purpose**: Saves audio to standard WAV files
- **Format Conversion**:
  - Input: Float32 deinterleaved (from capture)
  - Step 1: Manual interleaving to Float32
  - Step 2: Float32 to Int16 conversion
  - Output: Standard 16-bit PCM WAV
- **Threading**: Background queue for file I/O
- **Integration**: Implements AudioStreamDelegate

## Key Design Decisions

1. **Direct Buffer Passing**: Zero-copy AVAudioPCMBuffer throughout pipeline
2. **Delay Implementation**: Engine start delay vs. buffer queuing
3. **Format Conversion**: Manual two-step process for WAV compatibility
4. **Multi-Delegate Pattern**: Flexible audio routing to multiple consumers
5. **Thread Safety**: Careful queue management for real-time performance

## Future Improvements

1. **Compressed Audio Support**
   - AAC encoding for smaller files
   - Real-time compression

2. **Network Streaming**
   - RTMP/HLS support
   - Low-latency protocols

3. **Multi-channel Support**
   - 5.1/7.1 audio capture
   - Channel mapping

4. **GUI Interface**
   - SwiftUI application
   - Real-time visualizations