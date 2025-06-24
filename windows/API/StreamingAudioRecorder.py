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
from datetime import datetime
from typing import Optional, List, Callable, Union
import numpy as np
import pyaudiowpatch as pyaudio
import sounddevice as sd

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
            sample_rate: Sample rate in Hz
            channels: Number of channels
            blocksize: Audio block size
            device: Audio device to use (None for default)
        """
        self.sample_rate = sample_rate
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
        
        # Initialize PyAudioWPatch
        self._pyaudio = pyaudio.PyAudio()
        
        # Find the loopback device
        loopback_device_index = None
        if self.device and hasattr(self.device, 'device_index'):
            # Use specified device
            loopback_device_index = self.device.device_index
        else:
            # Find default output device for loopback
            try:
                default_speakers = self._pyaudio.get_default_output_device_info()
                loopback_device_index = default_speakers["index"]
            except Exception as e:
                raise DeviceNotFoundError("Default output device") from e
        
        if loopback_device_index is None:
            raise DeviceNotFoundError("Loopback device")
        
        # Get device info
        device_info = self._pyaudio.get_device_info_by_index(loopback_device_index)
        print(f"[{self._timestamp()}] StreamingAudioRecorder: Using device '{device_info['name']}' for loopback")
        
        # Open loopback stream
        try:
            self._stream = self._pyaudio.open(
                format=pyaudio.paFloat32,
                channels=self.channels,
                rate=self.sample_rate,
                input=True,
                input_device_index=loopback_device_index,
                frames_per_buffer=self.blocksize,
                stream_callback=self._pyaudio_callback,
                as_loopback=True  # Enable loopback mode
            )
            
            self._stream.start_stream()
            
        except Exception as e:
            if "as_loopback" in str(e):
                raise AudioLoopbackPermissionError()
            else:
                raise SessionStartFailedError(str(e))
    
    async def _start_microphone_capture(self) -> None:
        """Start capturing from microphone"""
        print(f"[{self._timestamp()}] StreamingAudioRecorder: Starting microphone capture")
        
        # Determine device index
        device_index = None
        if self.device and hasattr(self.device, 'device_index'):
            device_index = self.device.device_index
        
        # Open sounddevice stream
        try:
            self._stream = sd.InputStream(
                samplerate=self.sample_rate,
                channels=self.channels,
                device=device_index,
                blocksize=self.blocksize,
                callback=self._sounddevice_callback,
                dtype='float32'
            )
            
            self._stream.start()
            
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