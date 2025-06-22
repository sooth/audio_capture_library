# Interactive Audio Capture Applications

This directory contains Python applications that provide interactive interfaces for controlling the audio capture API. These applications prompt users for their preferences and then instruct the underlying API to perform the audio recording.

## Available Applications

### 1. `audio_capture_interactive.py` - Full Interactive Application
A comprehensive interactive application with all features:
- Device selection menu
- System audio capture option
- Manual or automatic recording duration
- Custom filename support
- Multiple recording sessions
- Real-time status monitoring

**Usage:**
```bash
python3 audio_capture_interactive.py
```

### 2. `record_audio_cli.py` - Simple CLI Recorder
A streamlined command-line interface for quick recordings:
- Numbered device selection
- System audio yes/no prompt
- Duration input (with default)
- Automatic filename generation

**Usage:**
```bash
python3 record_audio_cli.py
```

### 3. `audio_capture_app.py` - Advanced Interactive App
An advanced version with additional features:
- Detailed recording settings confirmation
- Live recording status updates
- File size and location reporting
- Recursive session management

**Usage:**
```bash
python3 audio_capture_app.py
```

## How It Works

The interactive applications follow this control flow:

1. **Start Server**: Python automatically starts the Swift audio server
2. **Query Devices**: Request available microphones from the API
3. **User Input**: Present choices and collect user preferences
   - Select microphone from numbered list
   - Choose whether to capture system audio
   - Set recording duration or manual control
   - Specify output filename
4. **Instruct API**: Send user's choices to the audio capture API
5. **Control Recording**: Start/stop recording based on user input
6. **Display Results**: Show file location, size, and duration

## Example Interaction

```
🎙️  Audio Capture Application
============================================================

Available Microphones:
----------------------------------------
1. MacBook Pro Microphone
2. USB Microphone
3. External Audio Interface

Select microphone number (1-3): 1

System Audio Capture:
----------------------------------------
Would you like to also capture system audio? (y/n): y

Recording Duration:
----------------------------------------
Enter duration in seconds (or Enter for manual): 10

Output File:
----------------------------------------
Enter filename (press Enter for 'recording_20240318_143022.wav'): my_recording.wav

📋 RECORDING SETTINGS
============================================================
Microphone: MacBook Pro Microphone
System Audio: Yes
Duration: 10 seconds
Output File: my_recording.wav

Proceed with recording? (y/n): y

🔴 RECORDING
============================================================
Recording for 10 seconds...
⏱️  Recording complete!

✅ RECORDING COMPLETED
============================================================
File: my_recording.wav
Duration: 10.00 seconds
Size: 3,840,000 bytes (3.66 MB)
Location: /Users/you/audio_capture_library/macos/my_recording.wav
```

## Features

- **Automatic Server Management**: The Swift server starts automatically when needed
- **Device Discovery**: Dynamically lists all available microphones
- **Flexible Recording**: Choose manual control or automatic duration
- **System Audio**: Optional capture of all system sounds
- **Real-time Monitoring**: See buffer counts and elapsed time during recording
- **Multiple Sessions**: Record multiple files without restarting

## Requirements

- macOS 13.0 or later
- Python 3.7 or later
- Microphone permission granted
- Screen recording permission (for system audio)

## Notes

- Recordings are saved as WAV files
- The Swift audio server runs in the background
- Server automatically shuts down when the Python app exits
- All recordings are saved to the `macos/` directory by default