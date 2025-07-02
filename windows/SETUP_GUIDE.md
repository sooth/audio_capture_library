# Windows AudioCaptureKit Setup Guide

## Prerequisites

- Windows 10 version 1803 or later (for loopback recording)
- Python 3.7 or later
- Administrator privileges (recommended for loopback recording)

## Quick Setup

1. **Run the automated setup script:**
   ```bash
   python setup.py
   ```

2. **Or manually install:**
   ```bash
   # IMPORTANT: Uninstall regular PyAudio first if installed
   pip uninstall pyaudio
   
   # Install requirements
   pip install -r requirements.txt
   ```

## Important: PyAudio vs PyAudioWPatch

This library requires **PyAudioWPatch**, not regular PyAudio:

- **PyAudio**: Standard audio library (no loopback support)
- **PyAudioWPatch**: Fork with Windows loopback recording support

⚠️ **These two packages conflict!** You must uninstall PyAudio before installing PyAudioWPatch.

## Troubleshooting

### 1. "as_loopback" Error

If you see:
```
Stream.__init__() got an unexpected keyword argument 'as_loopback'
```

This means regular PyAudio is installed instead of PyAudioWPatch:
```bash
pip uninstall pyaudio
pip install PyAudioWPatch
```

### 2. Loopback Recording Fails

If system audio recording doesn't work:

1. **Check Windows version**: Need Windows 10 1803+
2. **Run as administrator**: Some audio devices require elevated permissions
3. **Check privacy settings**: Windows Settings > Privacy > Microphone
4. **Close other audio apps**: Exclusive mode conflicts

### 3. Installation Errors

If pip install fails:

1. **Update pip**: `python -m pip install --upgrade pip`
2. **Install Visual C++ Build Tools**: Required for compiling PyAudioWPatch
3. **Try pre-built wheels**: `pip install PyAudioWPatch --prefer-binary`

## Testing Your Installation

1. **Check installation:**
   ```bash
   python Examples/check_audio_libs.py
   ```

2. **Test loopback support:**
   ```bash
   python Examples/test_loopback.py
   ```

3. **Run the interactive mixer:**
   ```bash
   python Examples/interactive_recording_mixer.py
   ```

## Features

- ✅ Microphone recording
- ✅ System audio (loopback) recording  
- ✅ Real-time audio streaming
- ✅ Multiple audio formats
- ✅ Device enumeration
- ✅ Audio mixing

## Example Usage

```python
from windows.API import AudioCaptureKit

# Initialize
kit = AudioCaptureKit()

# Record from microphone
session = await kit.record_to_file("recording.wav", duration=10)

# Record system audio (requires PyAudioWPatch)
devices = kit.get_recording_devices()
loopback = next(d for d in devices if d.type == DeviceType.LOOPBACK)
session = await kit.record_to_file("system_audio.wav", duration=10, device=loopback)
```

## Support

If you continue to have issues:

1. Run the diagnostic tools in the Examples folder
2. Check that all prerequisites are met
3. Try running as administrator
4. Ensure no antivirus is blocking audio access