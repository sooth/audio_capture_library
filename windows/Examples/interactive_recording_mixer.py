#!/usr/bin/env python3
"""
Interactive Recording Mixer - Windows AudioCaptureKit Example

This example demonstrates:
- Interactive device selection for input (microphone)
- Optional system output recording (what's playing on speakers)
- Recording duration prompt
- Proper audio mixing of both sources using ConvertingBufferCollector
- Saving to a single WAV file

Features:
- Records from microphone and optionally system audio simultaneously
- Automatically converts all audio to 48kHz stereo as buffers arrive
- Mixes both audio streams together
- Saves the result as a single WAV file
"""

import asyncio
import sys
import os
import threading
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Tuple
import numpy as np
import wave

# Add parent directory to path for imports
sys.path.append(str(Path(__file__).parent.parent.parent))

from windows.API import (
    AudioCaptureKit,
    AudioDevice,
    DeviceType,
    AudioFormat,
    AudioBuffer,
    ConvertingBufferCollector,
    WavFileWriter,
    SessionState,
    AudioLoopbackPermissionError,
    DeviceNotFoundError,
    SessionStartFailedError
)


class InteractiveRecordingMixer:
    """Interactive recording application with audio mixing using ConvertingBufferCollector"""
    
    def __init__(self):
        self.kit = AudioCaptureKit()
        self.input_session = None
        self.output_session = None
        self.writer = None
        self.recording_duration = 0
        
        # ConvertingBufferCollectors - will be created with actual sample rates
        self.input_collector = None
        self.output_collector = None
        
        # Target format for all audio (48kHz stereo, like macOS)
        self.target_sample_rate = 48000
        self.target_channels = 2
        
        # Store detected channel counts and sample rates
        self.input_channel_count = None
        self.output_channel_count = None
        self.detected_input_rate = None
        self.detected_output_rate = None
        
        # Recording control
        self.recording_active = False
        self.recording_start_time = None
        
    def list_devices_numbered(self, devices: List[AudioDevice], device_type: str) -> None:
        """List devices with numbers for selection"""
        print(f"\n{device_type} Devices:")
        if not devices:
            print("  No devices found")
            return
            
        for i, device in enumerate(devices):
            default = " (DEFAULT)" if device.is_default else ""
            print(f"  {i}: {device.name}{default}")
    
    def get_user_device_selection(self, devices: List[AudioDevice], prompt: str) -> Optional[AudioDevice]:
        """Get user's device selection"""
        if not devices:
            return None
            
        while True:
            try:
                choice = input(f"\n{prompt} (0-{len(devices)-1}): ").strip()
                index = int(choice)
                if 0 <= index < len(devices):
                    return devices[index]
                else:
                    print(f"Please enter a number between 0 and {len(devices)-1}")
            except ValueError:
                print("Please enter a valid number")
            except KeyboardInterrupt:
                return None
    
    async def select_input_device(self) -> Optional[AudioDevice]:
        """Prompt user to select input device"""
        # Get all recording devices (excluding loopback)
        all_devices = self.kit.get_recording_devices()
        input_devices = [d for d in all_devices if d.type != DeviceType.LOOPBACK]
        
        if not input_devices:
            print("No input devices found!")
            return None
        
        self.list_devices_numbered(input_devices, "Input")
        selected = self.get_user_device_selection(input_devices, "Select input device")
        
        if selected:
            print(f"\nSelected input device: {selected.name}")
        
        return selected
    
    async def select_output_device(self) -> Optional[AudioDevice]:
        """Prompt user if they want to record system output"""
        # Find loopback devices
        all_devices = self.kit.get_recording_devices()
        loopback_devices = [d for d in all_devices if d.type == DeviceType.LOOPBACK]
        
        if not loopback_devices:
            print("\nNo loopback device found. System audio recording not available.")
            print("This typically requires Windows 10 version 1803 or later.")
            return None
        
        # Find the default playback device
        playback_devices = self.kit.get_playback_devices()
        default_playback = None
        for device in playback_devices:
            if device.is_default:
                default_playback = device
                break
        
        # Ask user if they want to record system audio
        while True:
            choice = input("\nDo you want to record system audio output? (y/n): ").strip().lower()
            if choice == 'y':
                # If we have multiple loopback devices, let user choose
                if len(loopback_devices) > 1:
                    print("\nAvailable output devices for loopback recording:")
                    for i, device in enumerate(loopback_devices):
                        # Mark default if it matches
                        is_default = ""
                        if default_playback and any(name in device.name for name in default_playback.name.split()):
                            is_default = " (DEFAULT)"
                        print(f"  {i}: {device.name}{is_default}")
                    
                    while True:
                        try:
                            idx = int(input(f"Select output device (0-{len(loopback_devices)-1}): ").strip())
                            if 0 <= idx < len(loopback_devices):
                                device = loopback_devices[idx]
                                break
                            else:
                                print(f"Please enter a number between 0 and {len(loopback_devices)-1}")
                        except ValueError:
                            print("Please enter a valid number")
                else:
                    # Only one loopback device
                    device = loopback_devices[0]
                
                print(f"\nWill record system audio from: {device.name}")
                return device
            elif choice == 'n':
                print("System audio will not be recorded")
                return None
            else:
                print("Please enter 'y' for yes or 'n' for no")
    
    async def get_recording_duration(self) -> float:
        """Prompt user for recording duration"""
        while True:
            try:
                duration = input("\nHow many seconds to record? ").strip()
                seconds = float(duration)
                if seconds > 0:
                    return seconds
                else:
                    print("Please enter a positive number")
            except ValueError:
                print("Please enter a valid number")
            except KeyboardInterrupt:
                return 0
    
    def create_input_callback(self):
        """Create callback for input device audio"""
        first_buffer = [True]  # Use list to allow modification in closure
        
        def callback(audio_data):
            # Stop processing if recording is no longer active
            if not self.recording_active:
                return
            # Convert memoryview to numpy array if needed
            if isinstance(audio_data, memoryview):
                audio_data = np.frombuffer(audio_data, dtype=np.float32)
            
            # On first buffer, detect channel count and create collector if needed
            if first_buffer[0] and self.input_collector is None and self.detected_input_rate is not None:
                first_buffer[0] = False
                
                # Detect channel count from buffer shape
                if hasattr(audio_data, 'shape') and audio_data.ndim == 2:
                    # 2D array - channels are in second dimension
                    self.input_channel_count = audio_data.shape[1]
                else:
                    # 1D array - assume mono
                    self.input_channel_count = 1
                
                print(f"\n[Input] First buffer received:")
                print(f"  Shape: {audio_data.shape if hasattr(audio_data, 'shape') else f'1D, len={len(audio_data)}'} ")
                print(f"  Detected channels: {self.input_channel_count}")
                print(f"  Sample rate: {self.detected_input_rate}Hz")
                
                # Create input format
                # If 2D array, it's non-interleaved (samples x channels)
                is_interleaved = audio_data.ndim == 1 if hasattr(audio_data, 'ndim') else True
                
                input_format = AudioFormat(
                    sample_rate=float(self.detected_input_rate),
                    channel_count=self.input_channel_count,
                    bit_depth=32,
                    is_float=True,
                    is_interleaved=is_interleaved
                )
                
                # Create target format - non-interleaved for easier mixing
                target_format = AudioFormat(
                    sample_rate=float(self.target_sample_rate),
                    channel_count=self.target_channels,
                    bit_depth=32,
                    is_float=True,
                    is_interleaved=False  # Non-interleaved for easier mixing
                )
                
                # Create ConvertingBufferCollector
                self.input_collector = ConvertingBufferCollector(
                    input_format=input_format,
                    target_format=target_format
                )
                print(f"  Created ConvertingBufferCollector: {input_format.sample_rate}Hz/{input_format.channel_count}ch -> {target_format.sample_rate}Hz/{target_format.channel_count}ch")
            
            if self.input_collector:
                # Create AudioBuffer
                buffer = AudioBuffer(
                    data=audio_data,
                    format=self.input_collector.input_format
                )
                self.input_collector.add_buffer(buffer)
        return callback
    
    def create_output_callback(self):
        """Create callback for output device audio"""
        first_buffer = [True]
        
        def callback(audio_data):
            # Stop processing if recording is no longer active
            if not self.recording_active:
                return
            # Convert memoryview to numpy array if needed
            if isinstance(audio_data, memoryview):
                audio_data = np.frombuffer(audio_data, dtype=np.float32)
            
            # On first buffer, detect channel count and create collector if needed
            if first_buffer[0] and self.output_collector is None and self.detected_output_rate is not None:
                first_buffer[0] = False
                
                # Detect channel count from buffer shape
                if hasattr(audio_data, 'shape') and audio_data.ndim == 2:
                    self.output_channel_count = audio_data.shape[1]
                else:
                    # Assume stereo for system audio
                    self.output_channel_count = 2
                
                print(f"\n[Output] First buffer received:")
                print(f"  Shape: {audio_data.shape if hasattr(audio_data, 'shape') else f'1D, len={len(audio_data)}'} ")
                print(f"  Detected channels: {self.output_channel_count}")
                print(f"  Sample rate: {self.detected_output_rate}Hz")
                
                # Create input format
                # If 2D array, it's non-interleaved (samples x channels)
                is_interleaved = audio_data.ndim == 1 if hasattr(audio_data, 'ndim') else True
                
                input_format = AudioFormat(
                    sample_rate=float(self.detected_output_rate),
                    channel_count=self.output_channel_count,
                    bit_depth=32,
                    is_float=True,
                    is_interleaved=is_interleaved
                )
                
                # Create target format - non-interleaved for easier mixing
                target_format = AudioFormat(
                    sample_rate=float(self.target_sample_rate),
                    channel_count=self.target_channels,
                    bit_depth=32,
                    is_float=True,
                    is_interleaved=False  # Non-interleaved for easier mixing
                )
                
                # Create ConvertingBufferCollector
                self.output_collector = ConvertingBufferCollector(
                    input_format=input_format,
                    target_format=target_format
                )
                print(f"  Created ConvertingBufferCollector: {input_format.sample_rate}Hz/{input_format.channel_count}ch -> {target_format.sample_rate}Hz/{target_format.channel_count}ch")
            
            if self.output_collector:
                # Create AudioBuffer
                buffer = AudioBuffer(
                    data=audio_data,
                    format=self.output_collector.input_format
                )
                self.output_collector.add_buffer(buffer)
        return callback
    
    def mix_audio_buffers(self) -> Tuple[np.ndarray, int]:
        """Mix audio buffers that have already been converted to target format"""
        # Get converted buffers (already at 48kHz stereo)
        input_buffers = self.input_collector.get_all_buffers() if self.input_collector else []
        output_buffers = self.output_collector.get_all_buffers() if self.output_collector else []
        
        if not input_buffers and not output_buffers:
            return np.array([], dtype=np.float32), self.target_sample_rate
        
        # If only one source, return it
        if input_buffers and not output_buffers:
            return np.vstack(input_buffers), self.target_sample_rate
        elif output_buffers and not input_buffers:
            return np.vstack(output_buffers), self.target_sample_rate
        
        # Mix both sources (exactly like macOS mixAudioBuffers)
        print("\nMixing audio streams...")
        print(f"  Format: {self.target_sample_rate}Hz, {self.target_channels}ch")
        print(f"  Input buffers: {len(input_buffers)}")
        print(f"  Output buffers: {len(output_buffers)}")
        
        # Combine all input buffers
        combined_input = np.vstack(input_buffers)
        
        # Mix with output buffers
        mixed = []
        input_offset = 0
        
        for output_buffer in output_buffers:
            mixed_buffer = np.zeros_like(output_buffer)
            
            for frame in range(len(output_buffer)):
                for channel in range(self.target_channels):
                    output_sample = output_buffer[frame, channel]
                    
                    if input_offset < len(combined_input):
                        input_sample = combined_input[input_offset, channel]
                    else:
                        input_sample = 0.0
                    
                    mixed_buffer[frame, channel] = output_sample * 0.5 + input_sample * 0.5
                
                input_offset += 1
            
            mixed.append(mixed_buffer)
        
        print(f"  Mixed {len(mixed)} buffers")
        return np.vstack(mixed), self.target_sample_rate
    
    async def record_audio(self, input_device: Optional[AudioDevice], output_device: Optional[AudioDevice], duration: float) -> None:
        """Record audio from selected devices"""
        if not input_device and not output_device:
            print("No devices selected for recording!")
            return
        
        try:
            # Start input recording if device selected
            if input_device:
                print(f"\n📡 Starting input recording from: {input_device.name}")
                
                self.input_session = await self.kit.stream_audio(
                    self.create_input_callback(),
                    device=input_device
                )
                
                # Wait for initialization
                await asyncio.sleep(0.1)
                
                # Detect actual sample rate
                if hasattr(self.input_session, '_recorder') and hasattr(self.input_session._recorder, 'actual_sample_rate'):
                    self.detected_input_rate = self.input_session._recorder.actual_sample_rate
                    print(f"  ✅ Input hardware sample rate: {self.detected_input_rate}Hz")
                    # Note: ConvertingBufferCollector will be created in the callback when we know the channel count
                else:
                    print(f"  ❌ Could not detect input sample rate")
                    return
            
            # Start output recording if device selected
            if output_device:
                print(f"📡 Starting system audio recording from: {output_device.name}")
                
                try:
                    self.output_session = await self.kit.stream_audio(
                        self.create_output_callback(),
                        device=output_device
                    )
                    
                    # Wait for initialization
                    await asyncio.sleep(0.1)
                    
                    # Detect actual sample rate
                    if hasattr(self.output_session, '_recorder') and hasattr(self.output_session._recorder, 'actual_sample_rate'):
                        self.detected_output_rate = self.output_session._recorder.actual_sample_rate
                        print(f"  ✅ Output hardware sample rate: {self.detected_output_rate}Hz")
                        # Note: ConvertingBufferCollector will be created in the callback
                    else:
                        print(f"  ❌ Could not detect output sample rate")
                except (AudioLoopbackPermissionError, SessionStartFailedError) as e:
                    print(f"\nFailed to start loopback recording: {e}")
                    print("\nPossible solutions:")
                    print("1. Make sure you have Windows 10 version 1803 or later")
                    print("2. Try running the script as administrator")
                    print("3. Check Windows privacy settings for microphone access")
                    print("4. Ensure no other application is using exclusive mode on the audio device")
                    print("5. Verify PyAudioWPatch is properly installed: pip install PyAudioWPatch")
                    self.output_session = None
                    
                    # Ask if user wants to continue with just microphone
                    if input_device:
                        choice = input("\nContinue with just microphone recording? (y/n): ").strip().lower()
                        if choice != 'y':
                            raise
            
            # Show recording progress
            print(f"\nRecording for {duration} seconds...")
            if output_device:
                print("Make some noise to test both inputs!\n")
            else:
                print("Recording microphone only...\n")
            
            # Mark recording as active
            self.recording_active = True
            self.recording_start_time = datetime.now()
            
            for i in range(int(duration)):
                await asyncio.sleep(1)
                input_count = len(self.input_collector.get_all_buffers()) if self.input_collector else 0
                output_count = len(self.output_collector.get_all_buffers()) if self.output_collector else 0
                
                if self.output_collector:
                    print(f"  {i+1}/{int(duration)}s... (Input: {input_count} buffers, Output: {output_count} buffers)")
                else:
                    print(f"  {i+1}/{int(duration)}s... (Input: {input_count} buffers)")
            
            # Handle fractional seconds
            remaining = duration - int(duration)
            if remaining > 0:
                await asyncio.sleep(remaining)
            
            # Mark recording as inactive BEFORE stopping
            self.recording_active = False
            
            print(f"\n\nRecording complete!")
            
            # Stop sessions IMMEDIATELY
            print("\nStopping capture sessions...")
            if self.input_session:
                print("  Stopping input session...")
                await self.kit.stop_capture(self.input_session)
                print("  ✓ Input session stopped")
            if self.output_session:
                print("  Stopping output session...")
                await self.kit.stop_capture(self.output_session)
                print("  ✓ Output session stopped")
            
            # Give a moment for buffers to finish
            print("  Waiting for buffers to settle...")
            await asyncio.sleep(0.1)
            print("  ✓ Buffer wait complete")
            
            # Print final collector statistics
            if self.input_collector:
                print("\nGetting input collector statistics...")
                try:
                    stats = self.input_collector.get_statistics()
                    print(f"Input collector final stats:")
                    print(f"  Buffers: {stats['total_buffers_added']}, Errors: {stats.get('conversion_errors', 0)}")
                    print(f"  Duration: {stats['duration']:.2f}s")
                except Exception as e:
                    print(f"  Error getting stats: {e}")
            
            print("\n✓ record_audio() completed")
                
        except Exception as e:
            print(f"\nRecording failed: {e}")
            raise
    
    async def save_mixed_audio(self, audio_data: np.ndarray, sample_rate: int) -> str:
        """Save mixed audio to WAV file"""
        if len(audio_data) == 0:
            print("\nNo audio to save!")
            return ""
        
        # Generate filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        if self.input_collector and self.output_collector:
            filename = f"mixed_recording_{timestamp}.wav"
        else:
            filename = f"mic_recording_{timestamp}.wav"
        
        filepath = Path(filename)
        
        print(f"\n💾 Saving to: {filename}")
        print(f"  Target sample rate: {sample_rate}Hz")
        print(f"  Audio shape: {audio_data.shape}")
        
        # Calculate actual frame count based on shape
        if audio_data.ndim == 2:
            # Non-interleaved: shape is (frames, channels)
            frame_count = audio_data.shape[0]
            print(f"  Total frames: {frame_count} (non-interleaved stereo)")
        else:
            # Interleaved or mono
            frame_count = len(audio_data)
            if sample_rate == 48000 and self.target_channels == 2:
                # Interleaved stereo
                frame_count = frame_count // 2
            print(f"  Total frames: {frame_count}")
        
        print(f"  Duration at {sample_rate}Hz: {frame_count / sample_rate:.2f} seconds")
        
        # Debug info about collectors
        if self.input_collector:
            stats = self.input_collector.get_statistics()
            print(f"\n  Input collector stats:")
            print(f"    Total buffers added: {stats['total_buffers_added']}")
            print(f"    Total frames converted: {stats['total_frames_converted']}")
            print(f"    Conversion errors: {stats.get('conversion_errors', 0)}")
        
        # Convert float32 to int16
        audio_int16 = (np.clip(audio_data, -1.0, 1.0) * 32767).astype(np.int16)
        
        # Ensure interleaved format for WAV file
        if audio_int16.ndim == 2:
            # Convert non-interleaved to interleaved
            audio_int16 = audio_int16.flatten('C')
        
        # Write WAV file
        with wave.open(str(filepath), 'wb') as wf:
            wf.setnchannels(2)  # Always stereo
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(sample_rate)  # Target rate
            wf.writeframes(audio_int16.tobytes())
        
        print(f"✅ File saved successfully: {filepath.absolute()}")
        print(f"  File size: {filepath.stat().st_size / 1024 / 1024:.2f} MB")
        
        return str(filepath)
    
    async def run(self) -> None:
        """Run the interactive recording mixer"""
        print("Interactive Recording Mixer - Using ConvertingBufferCollector")
        print("=============================================================")
        print("This tool records from your microphone and optionally system audio,")
        print("converts all audio to 48kHz stereo as it arrives (macOS pattern),")
        print("mixes them together, and saves to a single WAV file.")
        
        try:
            # Step 1: Select input device
            input_device = await self.select_input_device()
            if not input_device:
                print("\nNo input device selected. Exiting.")
                return
            
            # Step 2: Ask about system audio
            output_device = await self.select_output_device()
            
            # Step 3: Get recording duration
            duration = await self.get_recording_duration()
            if duration <= 0:
                print("\nInvalid duration. Exiting.")
                return
            
            # Step 4: Record audio
            print("\n[Step 4] Starting recording...")
            await self.record_audio(input_device, output_device, duration)
            print("[Step 4] ✓ Recording completed")
            
            # Step 5: Mix audio (all buffers already converted to target format)
            print("\n[Step 5] Mixing audio buffers...")
            mixed_audio, final_sample_rate = self.mix_audio_buffers()
            print(f"[Step 5] ✓ Mixed audio: shape={mixed_audio.shape if hasattr(mixed_audio, 'shape') else len(mixed_audio)}")
            
            # Step 6: Save to file
            print("\n[Step 6] Saving to file...")
            await self.save_mixed_audio(mixed_audio, final_sample_rate)
            print("[Step 6] ✓ File saved")
                
        except KeyboardInterrupt:
            print("\n\nRecording cancelled by user")
        except Exception as e:
            print(f"\n\nError: {e}")
            import traceback
            traceback.print_exc()
        finally:
            # Cleanup
            await self.kit.cleanup()
            print("\nDone!")


async def main():
    """Main entry point"""
    # Check Python version
    if sys.version_info < (3, 7):
        print("Error: Python 3.7 or later required")
        sys.exit(1)
    
    # Create and run the mixer
    mixer = InteractiveRecordingMixer()
    await mixer.run()


if __name__ == "__main__":
    # Run the application
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nApplication interrupted by user")
    except Exception as e:
        print(f"\nFatal error: {e}")
        import traceback
        traceback.print_exc()