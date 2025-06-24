"""
AudioOutput - Protocol and implementations for audio output destinations

This module provides the base protocol and various implementations for
audio output destinations including file writing, streaming, callbacks,
playback, and ring buffers.
"""

import asyncio
import os
from abc import ABC, abstractmethod
from datetime import datetime
from pathlib import Path
from threading import Lock
from typing import Optional, Callable, Union
import uuid
import numpy as np
import queue

from .AudioFormat import AudioFormat, AudioBuffer
from .AudioBufferQueue import AudioBufferQueue, CircularAudioBufferQueue
from .AudioError import OutputNotConfiguredError, BufferAllocationFailedError


class AudioOutput(ABC):
    """Base class for audio output destinations"""
    
    def __init__(self):
        """Initialize audio output"""
        self._id = uuid.uuid4()
    
    @property
    def id(self) -> uuid.UUID:
        """Unique identifier for this output"""
        return self._id
    
    @abstractmethod
    async def configure(self, format: AudioFormat) -> None:
        """
        Configure the output with a specific audio format.
        
        Args:
            format: Audio format specification
        """
        pass
    
    @abstractmethod
    async def process(self, buffer: AudioBuffer) -> None:
        """
        Process an audio buffer.
        
        Args:
            buffer: Audio buffer to process
        """
        pass
    
    @abstractmethod
    async def handle_error(self, error: Exception) -> None:
        """
        Handle errors during processing.
        
        Args:
            error: Exception that occurred
        """
        pass
    
    @abstractmethod
    async def finish(self) -> None:
        """Finish and cleanup the output"""
        pass


class FileOutput(AudioOutput):
    """Writes audio to a WAV file"""
    
    def __init__(self, file_path: Union[str, Path]):
        """
        Initialize file output.
        
        Args:
            file_path: Path to output file
        """
        super().__init__()
        self.file_path = Path(file_path)
        self._writer = None
        self._is_configured = False
        self._write_lock = Lock()
    
    async def configure(self, format: AudioFormat) -> None:
        """Configure the output with audio format"""
        if self._is_configured:
            return
        
        # Import WavFileWriter when needed
        from .WavFileWriter import WavFileWriter
        
        # Create writer with format
        self._writer = WavFileWriter(
            file_path=self.file_path,
            sample_rate=int(format.sample_rate),
            channels=format.channel_count,
            bit_depth=format.bit_depth
        )
        
        # Start writing
        await self._writer.start_writing()
        self._is_configured = True
    
    async def process(self, buffer: AudioBuffer) -> None:
        """Process audio buffer by writing to file"""
        if not self._is_configured or not self._writer:
            raise OutputNotConfiguredError()
        
        # Write buffer to file in thread-safe manner
        with self._write_lock:
            await self._writer.write(buffer.data)
    
    async def handle_error(self, error: Exception) -> None:
        """Handle errors during file writing"""
        print(f"FileOutput error: {error}")
    
    async def finish(self) -> None:
        """Finish writing and close the file"""
        if self._writer:
            await self._writer.stop_writing()
            self._writer = None
        self._is_configured = False


class StreamOutput(AudioOutput):
    """Provides audio buffers to external consumers via async stream"""
    
    def __init__(self, queue_size: int = 32):
        """
        Initialize stream output.
        
        Args:
            queue_size: Maximum size of the buffer queue
        """
        super().__init__()
        self._buffer_queue = AudioBufferQueue(max_size=queue_size)
        self._format = None
        self._is_configured = False
    
    @property
    def buffer_stream(self):
        """Get async stream of audio buffers"""
        return self._buffer_queue.stream()
    
    async def configure(self, format: AudioFormat) -> None:
        """Configure the output with audio format"""
        self._format = format
        self._is_configured = True
    
    async def process(self, buffer: AudioBuffer) -> None:
        """Process audio buffer by adding to queue"""
        if not self._is_configured:
            raise OutputNotConfiguredError()
        
        await self._buffer_queue.enqueue(buffer)
    
    async def handle_error(self, error: Exception) -> None:
        """Handle errors during streaming"""
        self._buffer_queue.handle_error(error)
    
    async def finish(self) -> None:
        """Finish streaming"""
        await self._buffer_queue.finish()
        self._is_configured = False
    
    async def get_queue_depth(self) -> int:
        """Get current queue depth"""
        return self._buffer_queue.count
    
    async def clear_queue(self) -> None:
        """Clear the buffer queue"""
        self._buffer_queue.clear()


class CallbackOutput(AudioOutput):
    """Delivers audio buffers via callback function"""
    
    def __init__(
        self,
        handler: Callable[[np.ndarray], None],
        use_thread: bool = True
    ):
        """
        Initialize callback output.
        
        Args:
            handler: Callback function that receives numpy arrays
            use_thread: Whether to call handler in separate thread
        """
        super().__init__()
        self._handler = handler
        self._use_thread = use_thread
        self._is_configured = False
        
        if use_thread:
            self._callback_queue = queue.Queue()
            self._callback_task = None
    
    async def configure(self, format: AudioFormat) -> None:
        """Configure the output"""
        self._is_configured = True
        
        if self._use_thread:
            # Start callback thread
            import threading
            self._callback_task = threading.Thread(
                target=self._callback_worker,
                daemon=True
            )
            self._callback_task.start()
    
    def _callback_worker(self):
        """Worker thread for callbacks"""
        while self._is_configured:
            try:
                buffer_data = self._callback_queue.get(timeout=0.1)
                if buffer_data is not None:
                    self._handler(buffer_data)
            except queue.Empty:
                continue
            except Exception as e:
                print(f"Callback error: {e}")
    
    async def process(self, buffer: AudioBuffer) -> None:
        """Process audio buffer by calling handler"""
        if not self._is_configured:
            raise OutputNotConfiguredError()
        
        if self._use_thread:
            # Queue for thread
            self._callback_queue.put(buffer.data.copy())
        else:
            # Direct call
            self._handler(buffer.data.copy())
    
    async def handle_error(self, error: Exception) -> None:
        """Handle errors during callback"""
        print(f"CallbackOutput error: {error}")
    
    async def finish(self) -> None:
        """Finish callback output"""
        self._is_configured = False
        
        if self._use_thread and self._callback_queue:
            # Signal thread to stop
            self._callback_queue.put(None)


class PlaybackOutput(AudioOutput):
    """Plays audio through speakers using sounddevice"""
    
    def __init__(
        self,
        device_index: Optional[int] = None,
        delay: float = 0.0
    ):
        """
        Initialize playback output.
        
        Args:
            device_index: sounddevice device index (None for default)
            delay: Playback delay in seconds
        """
        super().__init__()
        self._device_index = device_index
        self._delay = delay
        self._player = None
        self._is_configured = False
        self._volume = 1.0
    
    async def configure(self, format: AudioFormat) -> None:
        """Configure the output with audio format"""
        if self._is_configured:
            return
        
        # Import player when needed
        from .StreamingAudioPlayer import StreamingAudioPlayer
        
        self._player = StreamingAudioPlayer(
            sample_rate=int(format.sample_rate),
            channels=format.channel_count,
            device_index=self._device_index,
            delay=self._delay
        )
        
        await self._player.start_playback()
        self._is_configured = True
    
    async def process(self, buffer: AudioBuffer) -> None:
        """Process audio buffer by playing it"""
        if not self._is_configured or not self._player:
            raise OutputNotConfiguredError()
        
        # Apply volume
        audio_data = buffer.data * self._volume
        await self._player.schedule_buffer(audio_data)
    
    async def handle_error(self, error: Exception) -> None:
        """Handle errors during playback"""
        print(f"PlaybackOutput error: {error}")
    
    async def finish(self) -> None:
        """Stop playback"""
        if self._player:
            await self._player.stop_playback()
            self._player = None
        self._is_configured = False
    
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


class RingBufferOutput(AudioOutput):
    """Provides lock-free-style ring buffer access"""
    
    def __init__(self, buffer_duration: float = 1.0):
        """
        Initialize ring buffer output.
        
        Args:
            buffer_duration: Buffer duration in seconds
        """
        super().__init__()
        self._buffer_duration = buffer_duration
        self._ring_buffer = None
        self._format = None
        self._is_configured = False
        self._total_samples = 0
        self._sample_size = 0
    
    async def configure(self, format: AudioFormat) -> None:
        """Configure the output with audio format"""
        self._format = format
        
        # Calculate buffer size in samples
        samples_per_second = int(format.sample_rate * format.channel_count)
        buffer_samples = int(samples_per_second * self._buffer_duration)
        
        # Create circular buffer
        self._ring_buffer = CircularAudioBufferQueue(capacity=buffer_samples)
        self._sample_size = format.bit_depth // 8
        
        self._is_configured = True
    
    async def process(self, buffer: AudioBuffer) -> None:
        """Process audio buffer by adding to ring buffer"""
        if not self._is_configured or not self._ring_buffer:
            raise OutputNotConfiguredError()
        
        # Flatten buffer data if needed
        if buffer.data.ndim > 1:
            data = buffer.data.flatten()
        else:
            data = buffer.data
        
        # Add samples to ring buffer
        for sample in data:
            audio_buffer = AudioBuffer(
                data=np.array([sample]),
                format=self._format,
                timestamp=datetime.now()
            )
            
            if not self._ring_buffer.try_enqueue(audio_buffer):
                # Buffer overflow - drop oldest by dequeuing
                self._ring_buffer.try_dequeue()
                self._ring_buffer.try_enqueue(audio_buffer)
        
        self._total_samples += len(data)
    
    async def handle_error(self, error: Exception) -> None:
        """Handle errors"""
        print(f"RingBufferOutput error: {error}")
    
    async def finish(self) -> None:
        """Finish and cleanup"""
        if self._ring_buffer:
            self._ring_buffer.clear()
        self._is_configured = False
    
    def read(self, num_samples: int) -> Optional[np.ndarray]:
        """
        Read samples from ring buffer.
        
        Args:
            num_samples: Number of samples to read
            
        Returns:
            NumPy array of samples or None if not enough available
        """
        if not self._ring_buffer:
            return None
        
        samples = []
        for _ in range(num_samples):
            buffer = self._ring_buffer.try_dequeue()
            if buffer is None:
                break
            samples.extend(buffer.data.tolist())
        
        if not samples:
            return None
        
        return np.array(samples, dtype=self._format.numpy_dtype)
    
    def available_samples(self) -> int:
        """Get number of available samples in buffer"""
        if not self._ring_buffer:
            return 0
        return self._ring_buffer.count
    
    def clear(self) -> None:
        """Clear the ring buffer"""
        if self._ring_buffer:
            self._ring_buffer.clear()


class NetworkOutput(AudioOutput):
    """Streams audio over network using TCP"""
    
    def __init__(self, host: str = "localhost", port: int = 5555):
        """
        Initialize network output.
        
        Args:
            host: Host address to bind to
            port: Port number to listen on
        """
        super().__init__()
        self._host = host
        self._port = port
        self._server = None
        self._is_configured = False
    
    async def configure(self, format: AudioFormat) -> None:
        """Configure the output with audio format"""
        if self._is_configured:
            return
        
        # Import network output when needed
        from .NetworkOutput import NetworkAudioServer
        
        self._server = NetworkAudioServer(
            host=self._host,
            port=self._port,
            format=format
        )
        
        await self._server.start()
        self._is_configured = True
    
    async def process(self, buffer: AudioBuffer) -> None:
        """Process audio buffer by sending over network"""
        if not self._is_configured or not self._server:
            raise OutputNotConfiguredError()
        
        await self._server.broadcast_buffer(buffer)
    
    async def handle_error(self, error: Exception) -> None:
        """Handle network errors"""
        print(f"NetworkOutput error: {error}")
    
    async def finish(self) -> None:
        """Stop network server"""
        if self._server:
            await self._server.stop()
            self._server = None
        self._is_configured = False