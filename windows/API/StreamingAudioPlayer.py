"""
StreamingAudioPlayer - Real-time Audio Playback with Delay Support

This class provides high-performance audio playback using sounddevice with
support for delayed playback. It handles format conversion and provides
real-time buffer scheduling.

Key Features:
- Real-time audio buffer playback with minimal latency
- Configurable playback delay
- Automatic device selection
- Volume control and playback status monitoring
- Thread-safe buffer queue management
"""

import asyncio
import queue
import threading
import time
from datetime import datetime
from typing import Optional, Dict, Any, List
import numpy as np
import sounddevice as sd

from .AudioFormat import AudioFormat, AudioBuffer
from .AudioBufferQueue import AudioBufferQueue


class StreamingAudioPlayer:
    """Real-time audio player with streaming support"""
    
    def __init__(
        self,
        sample_rate: int = 48000,
        channels: int = 2,
        device_index: Optional[int] = None,
        delay: float = 0.0,
        blocksize: int = 1024,
        latency: str = 'low'
    ):
        """
        Initialize streaming audio player.
        
        Args:
            sample_rate: Sample rate in Hz
            channels: Number of channels
            device_index: sounddevice device index (None for default)
            delay: Playback delay in seconds
            blocksize: Audio block size
            latency: Latency setting ('low', 'high', or float value)
        """
        self.sample_rate = sample_rate
        self.channels = channels
        self.device_index = device_index
        self.delay = delay
        self.blocksize = blocksize
        self.latency = latency
        
        # State
        self._stream = None
        self._is_playing = False
        self._start_time = datetime.now()
        self._volume = 0.5
        
        # Delay management
        self._delay_start_time = None
        self._is_delay_active = delay > 0
        
        # Buffer queue for continuous playback
        self._buffer_queue = queue.Queue(maxsize=32)
        self._current_buffer = None
        self._current_position = 0
        
        # Statistics
        self._buffers_scheduled = 0
        self._buffers_played = 0
        self._underruns = 0
        
        # Debug logging
        self._debug_log_count = 0
        
        print(f"[{self._timestamp()}] StreamingAudioPlayer: Initialized")
        print(f"[{self._timestamp()}]   Sample Rate: {sample_rate}Hz")
        print(f"[{self._timestamp()}]   Channels: {channels}")
        print(f"[{self._timestamp()}]   Device: {self._get_device_name()}")
        print(f"[{self._timestamp()}]   Blocksize: {blocksize}")
        print(f"[{self._timestamp()}]   Latency: {latency}")
        if delay > 0:
            print(f"[{self._timestamp()}]   Playback delay: {delay}s")
    
    def _timestamp(self) -> str:
        """Get timestamp in milliseconds since player initialization"""
        elapsed = (datetime.now() - self._start_time).total_seconds() * 1000
        return f"{elapsed:07.1f}ms"
    
    def _get_device_name(self) -> str:
        """Get the name of the current output device"""
        if self.device_index is None:
            device_info = sd.query_devices(kind='output')
        else:
            device_info = sd.query_devices(self.device_index)
        return device_info['name'] if device_info else "Unknown"
    
    async def start_playback(self) -> None:
        """Start audio playback"""
        if self._is_playing:
            return
        
        # Don't start stream during delay period
        if self._is_delay_active and self._delay_start_time is None:
            self._delay_start_time = time.time()
            print(f"[{self._timestamp()}] StreamingAudioPlayer: Delay timer started - {self.delay}s")
            return
        
        # Create and start output stream
        self._stream = sd.OutputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            device=self.device_index,
            blocksize=self.blocksize,
            latency=self.latency,
            callback=self._audio_callback,
            finished_callback=self._finished_callback
        )
        
        self._stream.start()
        self._is_playing = True
        
        print(f"[{self._timestamp()}] StreamingAudioPlayer: Playback started")
    
    async def stop_playback(self) -> None:
        """Stop audio playback"""
        if not self._is_playing:
            return
        
        self._is_playing = False
        
        if self._stream:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        
        # Clear buffer queue
        while not self._buffer_queue.empty():
            try:
                self._buffer_queue.get_nowait()
            except queue.Empty:
                break
        
        # Clear delay state
        self._delay_start_time = None
        self._is_delay_active = self.delay > 0
        
        print(f"[{self._timestamp()}] StreamingAudioPlayer: Playback stopped")
        print(f"[{self._timestamp()}]   Buffers played: {self._buffers_played}")
        print(f"[{self._timestamp()}]   Underruns: {self._underruns}")
    
    async def schedule_buffer(self, audio_data: np.ndarray) -> None:
        """
        Schedule an audio buffer for playback.
        
        Args:
            audio_data: Audio data as numpy array
        """
        # Handle delay
        if self._is_delay_active:
            if self._delay_start_time is None:
                self._delay_start_time = time.time()
                print(f"[{self._timestamp()}] StreamingAudioPlayer: Delay timer started - {self.delay}s")
                return
            
            elapsed = time.time() - self._delay_start_time
            if elapsed < self.delay:
                remaining = self.delay - elapsed
                if int(elapsed * 2) % 1 == 0:  # Log every 0.5s
                    print(f"[{self._timestamp()}] StreamingAudioPlayer: Delay in progress ({remaining:.1f}s remaining)")
                return
            else:
                # Delay expired - start playback
                if not self._is_playing:
                    print(f"[{self._timestamp()}] StreamingAudioPlayer: Delay expired - starting playback")
                    self._is_delay_active = False
                    await self.start_playback()
        
        # Ensure playback is started
        if not self._is_playing:
            await self.start_playback()
        
        # Convert format if needed
        if audio_data.dtype != np.float32:
            if audio_data.dtype == np.int16:
                audio_data = audio_data.astype(np.float32) / 32768.0
            else:
                audio_data = audio_data.astype(np.float32)
        
        # Apply volume
        audio_data = audio_data * self._volume
        
        # Ensure correct shape
        if audio_data.ndim == 1 and self.channels > 1:
            # Mono to multi-channel
            audio_data = np.tile(audio_data[:, np.newaxis], (1, self.channels))
        elif audio_data.ndim == 2 and audio_data.shape[1] != self.channels:
            # Channel count mismatch
            if audio_data.shape[1] > self.channels:
                audio_data = audio_data[:, :self.channels]
            else:
                # Duplicate last channel
                padding = self.channels - audio_data.shape[1]
                last_channel = audio_data[:, -1:]
                audio_data = np.hstack([audio_data] + [last_channel] * padding)
        
        # Debug logging for first few buffers
        if self._debug_log_count < 3:
            print(f"[{self._timestamp()}] StreamingAudioPlayer: Scheduling buffer #{self._debug_log_count + 1}")
            print(f"[{self._timestamp()}]   Shape: {audio_data.shape}")
            print(f"[{self._timestamp()}]   dtype: {audio_data.dtype}")
            self._debug_log_count += 1
        
        # Add to queue
        try:
            self._buffer_queue.put_nowait(audio_data)
            self._buffers_scheduled += 1
            
            if self._buffers_scheduled % 50 == 0:
                latency = self._buffers_scheduled - self._buffers_played
                print(f"[{self._timestamp()}] StreamingAudioPlayer: Scheduled {self._buffers_scheduled} buffers, latency: {latency}")
        
        except queue.Full:
            print(f"[{self._timestamp()}] StreamingAudioPlayer: Buffer queue full, dropping buffer")
    
    def _audio_callback(self, outdata, frames, time_info, status):
        """Audio stream callback"""
        if status:
            print(f"[{self._timestamp()}] StreamingAudioPlayer: Stream status: {status}")
            if status.output_underflow:
                self._underruns += 1
        
        # Fill output buffer
        samples_needed = frames
        write_position = 0
        
        while samples_needed > 0:
            # Get current buffer if needed
            if self._current_buffer is None or self._current_position >= len(self._current_buffer):
                try:
                    self._current_buffer = self._buffer_queue.get_nowait()
                    self._current_position = 0
                    self._buffers_played += 1
                except queue.Empty:
                    # No data available - fill with silence
                    outdata[write_position:] = 0
                    return
            
            # Copy data from current buffer
            available = len(self._current_buffer) - self._current_position
            to_copy = min(samples_needed, available)
            
            end_pos = self._current_position + to_copy
            outdata[write_position:write_position + to_copy] = \
                self._current_buffer[self._current_position:end_pos]
            
            self._current_position = end_pos
            write_position += to_copy
            samples_needed -= to_copy
    
    def _finished_callback(self):
        """Called when stream finishes"""
        print(f"[{self._timestamp()}] StreamingAudioPlayer: Stream finished")
    
    def set_volume(self, volume: float) -> None:
        """
        Set playback volume.
        
        Args:
            volume: Volume level (0.0 to 1.0)
        """
        self._volume = max(0.0, min(1.0, volume))
    
    def get_volume(self) -> float:
        """Get current volume"""
        return self._volume
    
    def set_delay(self, delay: float) -> None:
        """
        Set playback delay.
        
        Args:
            delay: Delay in seconds
        """
        self.delay = max(0.0, delay)
        self._is_delay_active = self.delay > 0
        
        if self._is_delay_active:
            print(f"[{self._timestamp()}] StreamingAudioPlayer: Playback delay set to {self.delay}s")
        else:
            print(f"[{self._timestamp()}] StreamingAudioPlayer: No playback delay")
    
    @property
    def is_active(self) -> bool:
        """Check if playback is active"""
        return self._is_playing
    
    def get_status(self) -> Dict[str, Any]:
        """Get playback status"""
        queue_size = self._buffer_queue.qsize()
        
        remaining_delay = 0.0
        if self._is_delay_active and self._delay_start_time:
            elapsed = time.time() - self._delay_start_time
            remaining_delay = max(0.0, self.delay - elapsed)
        
        return {
            "is_playing": self._is_playing,
            "volume": self._volume,
            "buffers_scheduled": self._buffers_scheduled,
            "buffers_played": self._buffers_played,
            "queued_buffers": queue_size,
            "underruns": self._underruns,
            "sample_rate": self.sample_rate,
            "channels": self.channels,
            "device": self._get_device_name(),
            "playback_delay": self.delay,
            "is_delay_active": self._is_delay_active,
            "remaining_delay": remaining_delay
        }
    
    async def play_test_tone(self, duration: float = 1.0, frequency: float = 440.0) -> None:
        """
        Play a test tone.
        
        Args:
            duration: Duration in seconds
            frequency: Tone frequency in Hz
        """
        print(f"[{self._timestamp()}] StreamingAudioPlayer: Generating {duration}s test tone at {frequency}Hz")
        
        # Generate sine wave
        t = np.linspace(0, duration, int(self.sample_rate * duration))
        tone = np.sin(2 * np.pi * frequency * t) * 0.3
        
        # Make stereo if needed
        if self.channels > 1:
            tone = np.tile(tone[:, np.newaxis], (1, self.channels))
        
        # Schedule in chunks
        chunk_size = self.blocksize * 4  # 4 blocks at a time
        for i in range(0, len(tone), chunk_size):
            chunk = tone[i:i + chunk_size]
            await self.schedule_buffer(chunk)
        
        # Wait for playback to complete
        await asyncio.sleep(duration + 0.5)
        await self.stop_playback()


class AudioStreamDelegate:
    """Protocol for audio stream delegates (for compatibility with macOS API)"""
    
    async def audio_streamer_did_receive(self, streamer, buffer: AudioBuffer):
        """Called when audio buffer is received"""
        pass
    
    async def audio_streamer_did_encounter_error(self, streamer, error: Exception):
        """Called when error occurs"""
        pass
    
    async def audio_streamer_did_finish(self, streamer):
        """Called when streaming finishes"""
        pass