"""
WavFileWriter - High-Quality WAV File Recording

This class handles writing audio buffers to standard WAV files with proper
format conversion. It supports various audio formats and provides thread-safe
file writing.

Key Features:
- Standard WAV file format support (16/24/32-bit PCM, float32)
- Format conversion for compatibility
- Thread-safe file writing
- Real-time progress monitoring
- Flexible sample rate and channel configuration
"""

import asyncio
import os
import struct
import wave
from datetime import datetime
from pathlib import Path
from threading import Lock
from typing import Optional, Union, Dict, Any
import numpy as np
import scipy.io.wavfile as wavfile

from .AudioFormat import AudioFormat, AudioBuffer
from .AudioError import FileWriteFailedError


class WavFileWriter:
    """WAV file writer with format conversion support"""
    
    def __init__(
        self,
        file_path: Union[str, Path],
        sample_rate: int = 48000,
        channels: int = 2,
        bit_depth: int = 16
    ):
        """
        Initialize WAV file writer.
        
        Args:
            file_path: Path to output WAV file
            sample_rate: Sample rate in Hz
            channels: Number of channels
            bit_depth: Bit depth (16, 24, or 32)
        """
        self.file_path = Path(file_path)
        self.sample_rate = sample_rate
        self.channels = channels
        self.bit_depth = bit_depth
        
        # Ensure .wav extension
        if self.file_path.suffix.lower() != '.wav':
            self.file_path = self.file_path.with_suffix('.wav')
        
        # State
        self._is_writing = False
        self._wave_file = None
        self._write_lock = Lock()
        self._start_time = datetime.now()
        
        # Statistics
        self._buffers_written = 0
        self._samples_written = 0
        
        # Determine data type
        if bit_depth == 16:
            self._dtype = np.int16
            self._sample_width = 2
        elif bit_depth == 24:
            self._dtype = np.int32  # 24-bit stored as 32-bit
            self._sample_width = 3
        elif bit_depth == 32:
            self._dtype = np.float32
            self._sample_width = 4
        else:
            raise ValueError(f"Unsupported bit depth: {bit_depth}")
        
        print(f"[{self._timestamp()}] WavFileWriter: Initialized with format:")
        print(f"[{self._timestamp()}]   Sample Rate: {sample_rate}Hz")
        print(f"[{self._timestamp()}]   Channels: {channels}")
        print(f"[{self._timestamp()}]   Bit Depth: {bit_depth}-bit")
        print(f"[{self._timestamp()}]   Format: PCM WAV")
    
    def _timestamp(self) -> str:
        """Get timestamp in milliseconds since writer initialization"""
        elapsed = (datetime.now() - self._start_time).total_seconds() * 1000
        return f"{elapsed:07.1f}ms"
    
    async def start_writing(self) -> None:
        """Start writing to WAV file"""
        if self._is_writing:
            raise FileWriteFailedError("Already writing to a file")
        
        # Create directory if needed
        self.file_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Open WAV file for writing
        try:
            self._wave_file = wave.open(str(self.file_path), 'wb')
            self._wave_file.setnchannels(self.channels)
            self._wave_file.setsampwidth(self._sample_width)
            self._wave_file.setframerate(self.sample_rate)
            
            self._is_writing = True
            self._buffers_written = 0
            self._samples_written = 0
            
            print(f"[{self._timestamp()}] WavFileWriter: Started writing to {self.file_path}")
            
        except Exception as e:
            raise FileWriteFailedError(f"Failed to open WAV file: {e}")
    
    async def write(self, audio_data: np.ndarray) -> None:
        """
        Write audio data to WAV file.
        
        Args:
            audio_data: NumPy array of audio samples
        """
        if not self._is_writing:
            return
        
        # Run in thread pool to avoid blocking
        await asyncio.get_event_loop().run_in_executor(
            None, self._write_sync, audio_data
        )
    
    def _write_sync(self, audio_data: np.ndarray) -> None:
        """Synchronous write operation"""
        with self._write_lock:
            if not self._is_writing or not self._wave_file:
                return
            
            try:
                # Convert format if needed
                converted_data = self._convert_audio_format(audio_data)
                
                # Handle 24-bit special case
                if self.bit_depth == 24:
                    # Convert 32-bit int to 24-bit bytes
                    frames = self._pack_24bit_samples(converted_data)
                else:
                    # Standard conversion
                    frames = converted_data.tobytes()
                
                # Write to file
                self._wave_file.writeframes(frames)
                
                # Update statistics
                self._buffers_written += 1
                if audio_data.ndim == 1:
                    self._samples_written += len(audio_data)
                else:
                    self._samples_written += audio_data.shape[0]
                
                # Log progress periodically
                if self._buffers_written % 100 == 0:
                    duration = self._samples_written / self.sample_rate
                    print(f"[{self._timestamp()}] WavFileWriter: Written {self._buffers_written} buffers ({duration:.1f}s)")
                
                # Debug logging for first few buffers
                if self._buffers_written <= 3:
                    print(f"[{self._timestamp()}] WavFileWriter: Buffer #{self._buffers_written} - shape: {audio_data.shape}")
                
            except Exception as e:
                print(f"[{self._timestamp()}] WavFileWriter: Error writing buffer: {e}")
    
    def _convert_audio_format(self, audio_data: np.ndarray) -> np.ndarray:
        """
        Convert audio data to the target format.
        
        Args:
            audio_data: Input audio data
            
        Returns:
            Converted audio data
        """
        # Ensure correct shape (samples, channels) for multi-channel
        if audio_data.ndim == 1 and self.channels > 1:
            # Mono to multi-channel: duplicate
            audio_data = np.tile(audio_data[:, np.newaxis], (1, self.channels))
        elif audio_data.ndim == 2 and audio_data.shape[1] != self.channels:
            # Channel count mismatch
            if audio_data.shape[1] > self.channels:
                # Downmix
                audio_data = audio_data[:, :self.channels]
            else:
                # Upmix by duplicating last channel
                padding = self.channels - audio_data.shape[1]
                last_channel = audio_data[:, -1:]
                audio_data = np.hstack([audio_data] + [last_channel] * padding)
        
        # Flatten to interleaved format if multi-channel
        if audio_data.ndim == 2:
            audio_data = audio_data.flatten('C')  # Row-major (interleaved)
        
        # Convert data type
        if self._dtype == np.int16:
            # Convert to 16-bit integer
            if audio_data.dtype == np.float32 or audio_data.dtype == np.float64:
                # Float to int16: scale from [-1, 1] to [-32768, 32767]
                audio_data = np.clip(audio_data, -1.0, 1.0)
                audio_data = (audio_data * 32767).astype(np.int16)
            else:
                audio_data = audio_data.astype(np.int16)
                
        elif self._dtype == np.int32 and self.bit_depth == 24:
            # Convert to 24-bit (stored as 32-bit)
            if audio_data.dtype == np.float32 or audio_data.dtype == np.float64:
                # Float to 24-bit: scale from [-1, 1] to [-8388608, 8388607]
                audio_data = np.clip(audio_data, -1.0, 1.0)
                audio_data = (audio_data * 8388607).astype(np.int32)
            else:
                # Scale other integer types to 24-bit range
                if audio_data.dtype == np.int16:
                    audio_data = audio_data.astype(np.int32) << 8
                else:
                    audio_data = audio_data.astype(np.int32)
                    
        elif self._dtype == np.float32:
            # Convert to float32
            if audio_data.dtype != np.float32:
                if audio_data.dtype == np.int16:
                    # Int16 to float: scale from [-32768, 32767] to [-1, 1]
                    audio_data = audio_data.astype(np.float32) / 32768.0
                else:
                    audio_data = audio_data.astype(np.float32)
        
        return audio_data
    
    def _pack_24bit_samples(self, samples: np.ndarray) -> bytes:
        """
        Pack 32-bit integers as 24-bit samples.
        
        Args:
            samples: Array of 32-bit integers representing 24-bit samples
            
        Returns:
            Packed bytes
        """
        # Pack as 24-bit little-endian
        packed = bytearray()
        for sample in samples:
            # Take lower 24 bits
            packed.extend(struct.pack('<I', sample & 0xFFFFFF)[:3])
        return bytes(packed)
    
    async def stop_writing(self) -> None:
        """Stop writing and close the file"""
        if not self._is_writing:
            return
        
        with self._write_lock:
            self._is_writing = False
            
            if self._wave_file:
                self._wave_file.close()
                self._wave_file = None
        
        duration = self._samples_written / self.sample_rate / self.channels
        print(f"[{self._timestamp()}] WavFileWriter: Stopped writing")
        print(f"[{self._timestamp()}]   Total buffers written: {self._buffers_written}")
        print(f"[{self._timestamp()}]   Total samples written: {self._samples_written}")
        print(f"[{self._timestamp()}]   Duration: {duration:.2f} seconds")
    
    def get_info(self) -> Dict[str, Any]:
        """Get file writer information"""
        duration = self._samples_written / self.sample_rate / self.channels if self._samples_written > 0 else 0
        
        return {
            "is_writing": self._is_writing,
            "file_path": str(self.file_path),
            "buffers_written": self._buffers_written,
            "samples_written": self._samples_written,
            "duration": duration,
            "format": {
                "sample_rate": self.sample_rate,
                "channels": self.channels,
                "bit_depth": self.bit_depth
            }
        }


class SimpleWavWriter:
    """Simple WAV writer using scipy for one-shot writing"""
    
    @staticmethod
    def write(
        file_path: Union[str, Path],
        audio_data: np.ndarray,
        sample_rate: int,
        bit_depth: int = 16
    ) -> None:
        """
        Write audio data to WAV file in one operation.
        
        Args:
            file_path: Output file path
            audio_data: Audio data as numpy array
            sample_rate: Sample rate in Hz
            bit_depth: Bit depth (16 or 32)
        """
        file_path = Path(file_path)
        
        # Ensure .wav extension
        if file_path.suffix.lower() != '.wav':
            file_path = file_path.with_suffix('.wav')
        
        # Create directory if needed
        file_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Convert format
        if bit_depth == 16:
            if audio_data.dtype in (np.float32, np.float64):
                # Float to int16
                audio_data = np.clip(audio_data, -1.0, 1.0)
                audio_data = (audio_data * 32767).astype(np.int16)
            else:
                audio_data = audio_data.astype(np.int16)
        elif bit_depth == 32:
            audio_data = audio_data.astype(np.float32)
        else:
            raise ValueError(f"Unsupported bit depth: {bit_depth}")
        
        # Write file
        wavfile.write(str(file_path), sample_rate, audio_data)