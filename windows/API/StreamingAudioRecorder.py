"""
StreamingAudioRecorder - Real-time Audio Capture

This class captures audio from system (loopback) or microphone using PyAudioWPatch
and sounddevice. It implements a delegate pattern to distribute audio to multiple
consumers.

Key Features:
- System audio capture using WASAPI loopback
- Microphone capture with device selection
- Real-time buffer processing
- Multi-delegate support for audio distribution
- Performance monitoring and statistics
"""

import asyncio
import threading
import time
import sys
from datetime import datetime
from typing import Optional, List, Callable, Union
import numpy as np
import sounddevice as sd

# Try to import PyAudioWPatch for loopback support
LOOPBACK_SUPPORTED = False
pyaudio = None

# First, try to import pyaudiowpatch
try:
    import pyaudiowpatch
    pyaudio = pyaudiowpatch
    
    # Verify it has loopback support by checking for the method
    test_p = pyaudio.PyAudio()
    try:
        # Check if it has the loopback device generator method
        if hasattr(test_p, 'get_loopback_device_info_generator'):
            LOOPBACK_SUPPORTED = True
            print("PyAudioWPatch detected with loopback support")
        else:
            print("PyAudioWPatch found but no loopback support detected")
    finally:
        test_p.terminate()
except ImportError:
    # Fall back to regular pyaudio if available
    try:
        import pyaudio as regular_pyaudio
        pyaudio = regular_pyaudio
        print("Warning: PyAudioWPatch not found, using regular PyAudio (no loopback support)")
    except ImportError:
        print("Warning: Neither PyAudioWPatch nor PyAudio found")

from .AudioFormat import AudioFormat, AudioBuffer
from .AudioDevice import AudioDevice, DeviceType
from .AudioError import (
    DeviceNotFoundError, SessionStartFailedError,
    AudioLoopbackPermissionError
)


class AudioStreamDelegate:
    """Protocol for receiving audio buffers from StreamingAudioRecorder"""
    
    async def audio_streamer_did_receive(self, streamer: 'StreamingAudioRecorder', buffer: AudioBuffer):
        """
        Called when a new audio buffer is available.
        
        Args:
            streamer: The audio recorder instance
            buffer: Audio buffer containing captured audio
        """
        pass
    
    async def audio_streamer_did_encounter_error(self, streamer: 'StreamingAudioRecorder', error: Exception):
        """
        Called when an error occurs during audio capture.
        
        Args:
            streamer: The audio recorder instance
            error: The exception that occurred
        """
        pass
    
    async def audio_streamer_did_finish(self, streamer: 'StreamingAudioRecorder'):
        """
        Called when audio streaming has finished.
        
        Args:
            streamer: The audio recorder instance
        """
        pass


class StreamingAudioRecorder:
    """Real-time audio recorder with streaming support"""
    
    def __init__(
        self,
        sample_rate: int = 48000,
        channels: int = 2,
        blocksize: int = 1024,
        device: Optional[AudioDevice] = None
    ):
        """
        Initialize streaming audio recorder.
        
        Args:
            sample_rate: Sample rate in Hz (fallback, actual device rate will be detected)
            channels: Number of channels
            blocksize: Audio block size
            device: Audio device to use (None for default)
        """
        self.requested_sample_rate = sample_rate  # What was requested
        self.actual_sample_rate = sample_rate     # What device actually uses
        self.sample_rate = sample_rate            # For backward compatibility
        self.channels = channels
        self.blocksize = blocksize
        self.device = device
        
        # State
        self._is_recording = False
        self._stream = None
        self._pyaudio = None
        self._start_time = datetime.now()
        
        # Audio format
        self._format = AudioFormat(
            sample_rate=float(sample_rate),
            channel_count=channels,
            bit_depth=32,
            is_interleaved=True,
            is_float=True
        )
        
        # Delegates
        self._delegates: List[AudioStreamDelegate] = []
        self._delegate_lock = threading.Lock()
        
        # Performance monitoring
        self._buffer_count = 0
        self._debug_log_count = 0
        
        # Async event loop for delegates
        self._loop = None
        self._delegate_thread = None
        
        print(f"[{self._timestamp()}] StreamingAudioRecorder: Initialized")
        print(f"[{self._timestamp()}]   Sample Rate: {sample_rate}Hz")
        print(f"[{self._timestamp()}]   Channels: {channels}")
        print(f"[{self._timestamp()}]   Block Size: {blocksize}")
    
    def _timestamp(self) -> str:
        """Get timestamp in milliseconds since recorder initialization"""
        elapsed = (datetime.now() - self._start_time).total_seconds() * 1000
        return f"{elapsed:07.1f}ms"
    
    def add_delegate(self, delegate: AudioStreamDelegate) -> None:
        """Add a delegate to receive audio buffers"""
        with self._delegate_lock:
            if delegate not in self._delegates:
                self._delegates.append(delegate)
    
    def remove_delegate(self, delegate: AudioStreamDelegate) -> None:
        """Remove a delegate"""
        with self._delegate_lock:
            if delegate in self._delegates:
                self._delegates.remove(delegate)
    
    def remove_all_delegates(self) -> None:
        """Remove all delegates"""
        with self._delegate_lock:
            self._delegates.clear()
    
    async def start_streaming(self) -> None:
        """Start capturing audio"""
        if self._is_recording:
            print(f"[{self._timestamp()}] StreamingAudioRecorder: Already streaming")
            return
        
        # Start delegate thread if needed
        if not self._delegate_thread or not self._delegate_thread.is_alive():
            self._start_delegate_thread()
        
        # Determine capture method based on device type
        if self.device and self.device.type == DeviceType.LOOPBACK:
            await self._start_loopback_capture()
        else:
            await self._start_microphone_capture()
        
        self._is_recording = True
        print(f"[{self._timestamp()}] StreamingAudioRecorder: Real-time audio streaming started successfully")
    
    async def stop_streaming(self) -> None:
        """Stop capturing audio"""
        if not self._is_recording:
            return
        
        print(f"[{self._timestamp()}] StreamingAudioRecorder: Stopping real-time audio streaming...")
        
        self._is_recording = False
        
        # Stop stream
        if self._stream:
            if hasattr(self._stream, 'stop_stream'):
                # PyAudio stream
                self._stream.stop_stream()
                self._stream.close()
            else:
                # sounddevice stream
                self._stream.stop()
                self._stream.close()
            self._stream = None
        
        # Cleanup PyAudio if used
        if self._pyaudio:
            self._pyaudio.terminate()
            self._pyaudio = None
        
        # Notify delegates
        await self._notify_delegates_finished()
        
        print(f"[{self._timestamp()}] StreamingAudioRecorder: Real-time audio streaming stopped")
    
    async def _start_loopback_capture(self) -> None:
        """Start capturing system audio using loopback"""
        print(f"[{self._timestamp()}] StreamingAudioRecorder: Starting loopback capture")
        
        if not LOOPBACK_SUPPORTED:
            raise AudioLoopbackPermissionError(
                "Loopback recording is not available. "
                "Please install PyAudioWPatch: pip install PyAudioWPatch"
            )
        
        # Initialize PyAudioWPatch
        self._pyaudio = pyaudio.PyAudio()
        
        # Find the loopback device
        loopback_device = None
        
        if self.device and self.device.type == DeviceType.LOOPBACK:
            # Use the provided loopback device
            # The device should already have the correct PyAudioWPatch index
            device_name = self.device.name
            
            # Find the PyAudioWPatch loopback device
            for i in range(self._pyaudio.get_device_count()):
                info = self._pyaudio.get_device_info_by_index(i)
                # Check if it's a loopback device with matching name
                if (info.get('isLoopbackDevice', False) and 
                    (device_name in info['name'] or info['name'] in device_name)):
                    loopback_device = info
                    break
            
            # If not found, try the loopback generator
            if not loopback_device:
                for loopback in self._pyaudio.get_loopback_device_info_generator():
                    if device_name in loopback['name'] or loopback['name'] in device_name:
                        loopback_device = loopback
                        break
        else:
            # Find default output device and its loopback
            try:
                # Get WASAPI info
                wasapi_info = self._pyaudio.get_host_api_info_by_type(pyaudio.paWASAPI)
                default_speakers = self._pyaudio.get_device_info_by_index(
                    wasapi_info["defaultOutputDevice"]
                )
                
                print(f"[{self._timestamp()}] StreamingAudioRecorder: Default output device is '{default_speakers['name']}'")
                
                # If it's not already a loopback device, find the matching loopback
                if not default_speakers.get("isLoopbackDevice", False):
                    # Look for exact match first, then partial match
                    for loopback in self._pyaudio.get_loopback_device_info_generator():
                        # Exact match (device name is contained in loopback name)
                        if default_speakers["name"] in loopback["name"]:
                            loopback_device = loopback
                            print(f"[{self._timestamp()}] StreamingAudioRecorder: Found exact match loopback: '{loopback['name']}'")
                            break
                    
                    # If no exact match, try to find by common words
                    if not loopback_device:
                        default_words = set(default_speakers["name"].lower().split())
                        best_match = None
                        best_score = 0
                        
                        for loopback in self._pyaudio.get_loopback_device_info_generator():
                            loopback_words = set(loopback["name"].lower().split())
                            common_words = default_words & loopback_words
                            score = len(common_words)
                            
                            if score > best_score:
                                best_score = score
                                best_match = loopback
                        
                        if best_match and best_score > 0:
                            loopback_device = best_match
                            print(f"[{self._timestamp()}] StreamingAudioRecorder: Found partial match loopback: '{loopback_device['name']}'")
                else:
                    loopback_device = default_speakers
                    
            except Exception as e:
                raise DeviceNotFoundError("Default loopback device") from e
        
        if not loopback_device:
            raise DeviceNotFoundError("Loopback device not found")
        
        # Store the actual sample rate being used
        self.actual_sample_rate = int(loopback_device["defaultSampleRate"])
        
        print(f"[{self._timestamp()}] StreamingAudioRecorder: Using loopback device '{loopback_device['name']}'")
        print(f"[{self._timestamp()}]   Channels: {loopback_device['maxInputChannels']}")
        print(f"[{self._timestamp()}]   Actual Sample Rate: {self.actual_sample_rate}Hz")
        print(f"[{self._timestamp()}]   Requested Sample Rate: {self.requested_sample_rate}Hz")
        
        # Open loopback stream at device's native rate
        try:
            self._stream = self._pyaudio.open(
                format=pyaudio.paFloat32,
                channels=min(self.channels, loopback_device["maxInputChannels"]),
                rate=self.actual_sample_rate,
                input=True,
                input_device_index=loopback_device["index"],
                frames_per_buffer=self.blocksize,
                stream_callback=self._pyaudio_callback
            )
            
            self._stream.start_stream()
            print(f"[{self._timestamp()}] StreamingAudioRecorder: Loopback stream started successfully")
            
        except Exception as e:
            raise SessionStartFailedError(f"Failed to start loopback capture: {e}")
    
    async def _start_microphone_capture(self) -> None:
        """Start capturing from microphone"""
        print(f"[{self._timestamp()}] StreamingAudioRecorder: Starting microphone capture")
        
        # Determine device index
        device_index = None
        if self.device and hasattr(self.device, 'device_index'):
            device_index = self.device.device_index
        
        # Get the device's reported default sample rate
        if device_index is not None:
            try:
                device_info = sd.query_devices(device_index)
                device_default_rate = int(device_info['default_samplerate'])
                print(f"[{self._timestamp()}] StreamingAudioRecorder: Device reports default rate: {device_default_rate}Hz")
            except Exception as e:
                print(f"[{self._timestamp()}] StreamingAudioRecorder: Could not query device rate: {e}")
                device_default_rate = self.requested_sample_rate
        else:
            device_default_rate = self.requested_sample_rate
        
        # Open sounddevice stream and let it choose the rate, then get the actual rate
        try:
            self._stream = sd.InputStream(
                samplerate=None,  # Let sounddevice choose the best rate
                channels=self.channels,
                device=device_index,
                blocksize=self.blocksize,
                callback=self._sounddevice_callback,
                dtype='float32'
            )
            
            self._stream.start()
            
            # Get the ACTUAL sample rate that the stream is using
            self.actual_sample_rate = int(self._stream.samplerate)
            print(f"[{self._timestamp()}] StreamingAudioRecorder: Stream opened successfully")
            print(f"[{self._timestamp()}] StreamingAudioRecorder: Requested rate: {self.requested_sample_rate}Hz")
            print(f"[{self._timestamp()}] StreamingAudioRecorder: Device default rate: {device_default_rate}Hz")
            print(f"[{self._timestamp()}] StreamingAudioRecorder: ACTUAL stream rate: {self.actual_sample_rate}Hz")
            
        except Exception as e:
            raise SessionStartFailedError(str(e))
    
    def _pyaudio_callback(self, in_data, frame_count, time_info, status):
        """PyAudio callback for loopback capture"""
        if status:
            print(f"[{self._timestamp()}] StreamingAudioRecorder: Stream status: {status}")
        
        if not self._is_recording:
            return (None, pyaudio.paComplete)
        
        # Convert bytes to numpy array
        audio_data = np.frombuffer(in_data, dtype=np.float32)
        
        # Reshape if multi-channel
        if self.channels > 1:
            audio_data = audio_data.reshape(-1, self.channels)
        
        # Process buffer
        self._process_audio_data(audio_data)
        
        return (None, pyaudio.paContinue)
    
    def _sounddevice_callback(self, indata, frames, time_info, status):
        """sounddevice callback for microphone capture"""
        if status:
            print(f"[{self._timestamp()}] StreamingAudioRecorder: Stream status: {status}")
        
        if not self._is_recording:
            return
        
        # Process buffer (indata is already numpy array)
        self._process_audio_data(indata.copy())
    
    def _process_audio_data(self, audio_data: np.ndarray):
        """Process captured audio data"""
        # Log initial debugging info
        if self._debug_log_count < 3:
            print(f"[{self._timestamp()}] StreamingAudioRecorder: Received audio buffer #{self._debug_log_count + 1}")
            print(f"[{self._timestamp()}]   Shape: {audio_data.shape}")
            print(f"[{self._timestamp()}]   dtype: {audio_data.dtype}")
            self._debug_log_count += 1
        
        # Create audio buffer
        buffer = AudioBuffer(
            data=audio_data,
            format=self._format,
            timestamp=datetime.now()
        )
        
        # Update statistics
        self._buffer_count += 1
        if self._buffer_count % 100 == 0:
            duration = self._buffer_count * self.blocksize / self.sample_rate
            print(f"[{self._timestamp()}] StreamingAudioRecorder: Processed {self._buffer_count} buffers ({duration:.1f}s of audio)")
        
        # Notify delegates asynchronously
        if self._loop:
            asyncio.run_coroutine_threadsafe(
                self._notify_delegates_buffer(buffer),
                self._loop
            )
    
    def _start_delegate_thread(self):
        """Start thread for async delegate notifications"""
        def run_loop():
            self._loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._loop)
            self._loop.run_forever()
        
        self._delegate_thread = threading.Thread(target=run_loop, daemon=True)
        self._delegate_thread.start()
        
        # Wait for loop to be ready
        while self._loop is None:
            time.sleep(0.01)
    
    async def _notify_delegates_buffer(self, buffer: AudioBuffer):
        """Notify all delegates of new buffer"""
        with self._delegate_lock:
            delegates = list(self._delegates)
        
        for delegate in delegates:
            try:
                await delegate.audio_streamer_did_receive(self, buffer)
            except Exception as e:
                print(f"[{self._timestamp()}] StreamingAudioRecorder: Delegate error: {e}")
    
    async def _notify_delegates_error(self, error: Exception):
        """Notify all delegates of error"""
        with self._delegate_lock:
            delegates = list(self._delegates)
        
        for delegate in delegates:
            try:
                await delegate.audio_streamer_did_encounter_error(self, error)
            except Exception as e:
                print(f"[{self._timestamp()}] StreamingAudioRecorder: Delegate notification error: {e}")
    
    async def _notify_delegates_finished(self):
        """Notify all delegates that streaming finished"""
        with self._delegate_lock:
            delegates = list(self._delegates)
        
        for delegate in delegates:
            try:
                await delegate.audio_streamer_did_finish(self)
            except Exception as e:
                print(f"[{self._timestamp()}] StreamingAudioRecorder: Delegate notification error: {e}")
    
    @property
    def is_recording(self) -> bool:
        """Check if currently recording"""
        return self._is_recording
    
    def get_statistics(self) -> dict:
        """Get recording statistics"""
        duration = self._buffer_count * self.blocksize / self.sample_rate if self._buffer_count > 0 else 0
        
        return {
            "is_recording": self._is_recording,
            "buffer_count": self._buffer_count,
            "duration": duration,
            "sample_rate": self.sample_rate,
            "channels": self.channels,
            "device": self.device.name if self.device else "Default"
        }
    
    def __del__(self):
        """Cleanup on deletion"""
        if self._loop:
            self._loop.call_soon_threadsafe(self._loop.stop)
        
        if self._stream:
            try:
                if hasattr(self._stream, 'stop_stream'):
                    self._stream.stop_stream()
                    self._stream.close()
                else:
                    self._stream.stop()
                    self._stream.close()
            except Exception:
                pass
        
        if self._pyaudio:
            try:
                self._pyaudio.terminate()
            except Exception:
                pass