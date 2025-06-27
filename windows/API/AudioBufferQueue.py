"""
AudioBufferQueue - Thread-safe queue for audio buffers with async stream support

This module provides thread-safe queues for audio buffers with support for
async/await patterns. It includes backpressure handling, overflow protection,
and seamless integration with Python's asyncio.
"""

import asyncio
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from enum import IntEnum
from threading import Lock, RLock
from typing import Optional, List, AsyncIterator, Callable, Tuple
import numpy as np
from scipy import signal

from .AudioFormat import AudioBuffer, AudioFormat


@dataclass
class QueueStatistics:
    """Queue statistics"""
    current_size: int = 0
    peak_size: int = 0
    total_enqueued: int = 0
    total_dequeued: int = 0
    dropped_buffers: int = 0
    error_count: int = 0
    
    @property
    def drop_rate(self) -> float:
        """Buffer drop rate (0.0 to 1.0)"""
        if self.total_enqueued == 0:
            return 0.0
        return self.dropped_buffers / self.total_enqueued
    
    @property
    def utilization(self) -> float:
        """Average queue utilization (0.0 to 1.0)"""
        if self.peak_size == 0:
            return 0.0
        return self.current_size / self.peak_size


class AudioBufferQueue:
    """Thread-safe queue for audio buffers with async stream support"""
    
    def __init__(self, max_size: int = 32):
        """
        Initialize the audio buffer queue.
        
        Args:
            max_size: Maximum number of buffers in the queue
        """
        self.max_size = max_size
        self._buffers: deque[AudioBuffer] = deque()
        self._lock = Lock()
        self._is_finished = False
        self._last_error: Optional[Exception] = None
        self._statistics = QueueStatistics()
        
        # Async stream support
        self._queue: asyncio.Queue[Optional[AudioBuffer]] = asyncio.Queue(maxsize=max_size)
        self._stream_task: Optional[asyncio.Task] = None
    
    async def enqueue(self, buffer: AudioBuffer) -> None:
        """
        Enqueue a buffer.
        
        Args:
            buffer: Audio buffer to enqueue
        """
        if self._is_finished:
            return
        
        with self._lock:
            self._statistics.total_enqueued += 1
            
            # Check for overflow
            if len(self._buffers) >= self.max_size:
                self._statistics.dropped_buffers += 1
                # Drop oldest buffer (FIFO)
                if self._buffers:
                    self._buffers.popleft()
            
            # Add to queue
            self._buffers.append(buffer)
            self._statistics.current_size = len(self._buffers)
            self._statistics.peak_size = max(self._statistics.peak_size, len(self._buffers))
        
        # Add to async queue (non-blocking)
        try:
            self._queue.put_nowait(buffer)
        except asyncio.QueueFull:
            # Queue is full, drop the buffer
            self._statistics.dropped_buffers += 1
    
    async def dequeue(self) -> Optional[AudioBuffer]:
        """
        Dequeue a buffer (for pull-based consumers).
        
        Returns:
            Audio buffer or None if queue is empty
        """
        with self._lock:
            if not self._buffers:
                return None
            
            buffer = self._buffers.popleft()
            self._statistics.total_dequeued += 1
            self._statistics.current_size = len(self._buffers)
            
            return buffer
    
    def dequeue_sync(self) -> Optional[AudioBuffer]:
        """
        Synchronously dequeue a buffer.
        
        Returns:
            Audio buffer or None if queue is empty
        """
        with self._lock:
            if not self._buffers:
                return None
            
            buffer = self._buffers.popleft()
            self._statistics.total_dequeued += 1
            self._statistics.current_size = len(self._buffers)
            
            return buffer
    
    def peek(self) -> Optional[AudioBuffer]:
        """
        Peek at next buffer without removing.
        
        Returns:
            Next audio buffer or None if queue is empty
        """
        with self._lock:
            return self._buffers[0] if self._buffers else None
    
    def clear(self) -> None:
        """Clear all buffers"""
        with self._lock:
            dropped = len(self._buffers)
            self._buffers.clear()
            self._statistics.dropped_buffers += dropped
            self._statistics.current_size = 0
        
        # Clear async queue
        while not self._queue.empty():
            try:
                self._queue.get_nowait()
            except asyncio.QueueEmpty:
                break
    
    @property
    def count(self) -> int:
        """Get current queue count"""
        with self._lock:
            return len(self._buffers)
    
    @property
    def is_empty(self) -> bool:
        """Check if queue is empty"""
        with self._lock:
            return len(self._buffers) == 0
    
    @property
    def is_full(self) -> bool:
        """Check if queue is full"""
        with self._lock:
            return len(self._buffers) >= self.max_size
    
    async def stream(self) -> AsyncIterator[AudioBuffer]:
        """
        Get async stream of audio buffers.
        
        Yields:
            Audio buffers as they become available
        """
        while not self._is_finished:
            try:
                buffer = await asyncio.wait_for(self._queue.get(), timeout=0.1)
                if buffer is not None:
                    yield buffer
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                self.handle_error(e)
                break
    
    def handle_error(self, error: Exception) -> None:
        """Handle error"""
        with self._lock:
            self._last_error = error
            self._statistics.error_count += 1
    
    async def finish(self) -> None:
        """Finish the stream"""
        self._is_finished = True
        
        # Signal stream completion
        await self._queue.put(None)
        
        # Clear buffers
        with self._lock:
            self._buffers.clear()
    
    def get_last_error(self) -> Optional[Exception]:
        """Get last error"""
        with self._lock:
            return self._last_error
    
    def get_statistics(self) -> QueueStatistics:
        """Get queue statistics"""
        with self._lock:
            return self._statistics
    
    def reset_statistics(self) -> None:
        """Reset statistics"""
        with self._lock:
            current_size = len(self._buffers)
            self._statistics = QueueStatistics()
            self._statistics.current_size = current_size


class Priority(IntEnum):
    """Buffer priority levels"""
    LOW = 0
    NORMAL = 1
    HIGH = 2
    CRITICAL = 3


@dataclass
class PriorityBuffer:
    """Buffer with priority information"""
    buffer: AudioBuffer
    priority: Priority
    timestamp: datetime = field(default_factory=datetime.now)


class PriorityAudioBufferQueue:
    """Priority buffer queue with multiple priority levels"""
    
    def __init__(self, max_size: int = 32):
        """
        Initialize priority audio buffer queue.
        
        Args:
            max_size: Maximum number of buffers in the queue
        """
        self.max_size = max_size
        self._buffers: List[PriorityBuffer] = []
        self._lock = Lock()
        self._is_finished = False
        self._queue: asyncio.Queue[Optional[AudioBuffer]] = asyncio.Queue()
    
    async def enqueue(self, buffer: AudioBuffer, priority: Priority = Priority.NORMAL) -> None:
        """
        Enqueue buffer with priority.
        
        Args:
            buffer: Audio buffer to enqueue
            priority: Buffer priority
        """
        if self._is_finished:
            return
        
        priority_buffer = PriorityBuffer(
            buffer=buffer,
            priority=priority,
            timestamp=datetime.now()
        )
        
        with self._lock:
            # Check for overflow
            if len(self._buffers) >= self.max_size:
                # Remove lowest priority buffer
                lowest_idx = self._find_lowest_priority_index()
                if lowest_idx is not None:
                    self._buffers.pop(lowest_idx)
            
            # Insert in priority order
            insert_idx = self._find_insert_index(priority)
            self._buffers.insert(insert_idx, priority_buffer)
        
        # Send highest priority buffer to stream
        highest = self._dequeue_highest()
        if highest:
            try:
                await self._queue.put(highest.buffer)
            except asyncio.QueueFull:
                pass
    
    def _find_insert_index(self, priority: Priority) -> int:
        """Find index to insert buffer with given priority"""
        # Binary search for insertion point
        low = 0
        high = len(self._buffers)
        
        while low < high:
            mid = (low + high) // 2
            if self._buffers[mid].priority >= priority:
                low = mid + 1
            else:
                high = mid
        
        return low
    
    def _find_lowest_priority_index(self) -> Optional[int]:
        """Find index of lowest priority buffer"""
        if not self._buffers:
            return None
        
        lowest_idx = 0
        lowest_priority = self._buffers[0].priority
        
        for idx, buffer in enumerate(self._buffers):
            if buffer.priority < lowest_priority:
                lowest_priority = buffer.priority
                lowest_idx = idx
        
        return lowest_idx
    
    def _dequeue_highest(self) -> Optional[PriorityBuffer]:
        """Dequeue highest priority buffer"""
        with self._lock:
            if self._buffers:
                return self._buffers.pop(0)
        return None
    
    async def stream(self) -> AsyncIterator[AudioBuffer]:
        """Get async stream of audio buffers in priority order"""
        while not self._is_finished:
            try:
                buffer = await asyncio.wait_for(self._queue.get(), timeout=0.1)
                if buffer is not None:
                    yield buffer
            except asyncio.TimeoutError:
                continue
    
    async def finish(self) -> None:
        """Finish the queue"""
        self._is_finished = True
        
        # Send remaining buffers in priority order
        with self._lock:
            for priority_buffer in self._buffers:
                try:
                    await self._queue.put(priority_buffer.buffer)
                except asyncio.QueueFull:
                    break
            self._buffers.clear()
        
        # Signal completion
        await self._queue.put(None)


class CircularAudioBufferQueue:
    """Circular buffer queue for lock-free-style operations"""
    
    def __init__(self, capacity: int = 32):
        """
        Initialize circular audio buffer queue.
        
        Args:
            capacity: Queue capacity
        """
        self.capacity = capacity
        self._buffers: List[Optional[AudioBuffer]] = [None] * capacity
        self._head = 0
        self._tail = 0
        self._lock = RLock()  # Reentrant lock for nested calls
    
    def try_enqueue(self, buffer: AudioBuffer) -> bool:
        """
        Try to enqueue a buffer.
        
        Args:
            buffer: Audio buffer to enqueue
            
        Returns:
            True if successful, False if queue is full
        """
        with self._lock:
            next_tail = (self._tail + 1) % self.capacity
            
            # Check if full
            if next_tail == self._head:
                return False
            
            self._buffers[self._tail] = buffer
            self._tail = next_tail
            
            return True
    
    def try_dequeue(self) -> Optional[AudioBuffer]:
        """
        Try to dequeue a buffer.
        
        Returns:
            Audio buffer or None if queue is empty
        """
        with self._lock:
            # Check if empty
            if self._head == self._tail:
                return None
            
            buffer = self._buffers[self._head]
            self._buffers[self._head] = None
            self._head = (self._head + 1) % self.capacity
            
            return buffer
    
    @property
    def count(self) -> int:
        """Get current count"""
        with self._lock:
            if self._tail >= self._head:
                return self._tail - self._head
            else:
                return self.capacity - self._head + self._tail
    
    @property
    def is_empty(self) -> bool:
        """Check if empty"""
        with self._lock:
            return self._head == self._tail
    
    @property
    def is_full(self) -> bool:
        """Check if full"""
        with self._lock:
            return (self._tail + 1) % self.capacity == self._head
    
    def clear(self) -> None:
        """Clear all buffers"""
        with self._lock:
            self._head = 0
            self._tail = 0
            self._buffers = [None] * self.capacity
    
    def peek(self) -> Optional[AudioBuffer]:
        """Peek at next buffer without removing"""
        with self._lock:
            if self._head == self._tail:
                return None
            return self._buffers[self._head]


class ConvertingBufferCollector:
    """
    Converting Buffer Collector - Converts audio buffers to target format as they arrive
    
    This class implements the same pattern as the macOS ConvertingBufferCollector:
    1. Convert each buffer to target format as it arrives
    2. Store all buffers in common format (default: 48kHz stereo)
    3. Enable mixing of pre-converted buffers without resampling
    
    This approach ensures consistent sample rate conversion quality and simplifies
    mixing operations by handling format conversion at the point of capture.
    """
    
    def __init__(self, 
                 input_format: AudioFormat, 
                 target_format: Optional[AudioFormat] = None,
                 max_buffers: int = 1000):
        """
        Initialize the converting buffer collector.
        
        Args:
            input_format: Format of incoming audio buffers
            target_format: Target format for conversion (default: 48kHz stereo)
            max_buffers: Maximum number of buffers to store
        """
        self.input_format = input_format
        
        # Default target format: 48kHz stereo float32
        if target_format is None:
            self.target_format = AudioFormat(
                sample_rate=48000.0,
                channels=2,
                bit_depth=32,
                is_float=True,
                is_interleaved=True
            )
        else:
            self.target_format = target_format
        
        self.max_buffers = max_buffers
        self._buffers: List[np.ndarray] = []
        self._lock = Lock()
        
        # Pre-calculate conversion parameters
        self.sample_rate_ratio = self.target_format.sample_rate / self.input_format.sample_rate
        self.needs_resampling = abs(self.sample_rate_ratio - 1.0) > 0.001
        
        # Statistics
        self._total_buffers_added = 0
        self._total_frames_converted = 0
        self._conversion_errors = 0
        self._cached_total_frames = 0  # Cache frame count
        
        print(f"ConvertingBufferCollector initialized:")
        print(f"  Input: {input_format.sample_rate}Hz, {input_format.channel_count}ch")
        print(f"  Target: {target_format.sample_rate}Hz, {target_format.channel_count}ch")
        print(f"  Needs resampling: {self.needs_resampling}")
        if self.needs_resampling:
            print(f"  Sample rate ratio: {self.sample_rate_ratio:.6f}")
    
    def add_buffer(self, buffer: AudioBuffer) -> None:
        """
        Add and convert a buffer to the target format.
        
        Args:
            buffer: Audio buffer to add and convert
        """
        with self._lock:
            # Check buffer limit
            if len(self._buffers) >= self.max_buffers:
                # Drop oldest buffer
                self._buffers.pop(0)
            
            # Convert buffer to target format
            converted = self._convert_buffer(buffer)
            if converted is not None:
                self._buffers.append(converted)
                self._total_buffers_added += 1
                
                # Update frame count based on buffer shape
                if converted.ndim == 2:
                    # Non-interleaved: frames are first dimension
                    frame_count = converted.shape[0]
                elif self.target_format.is_interleaved and self.target_format.channel_count == 2:
                    # Interleaved stereo
                    frame_count = len(converted) // 2
                else:
                    # Mono or non-standard
                    frame_count = len(converted)
                    
                self._total_frames_converted += frame_count
                self._cached_total_frames += frame_count
                
                # Debug output for first few buffers
                if self._total_buffers_added <= 3:
                    print(f"[ConvertingBufferCollector] Buffer {self._total_buffers_added}:")
                    print(f"  Input: {len(buffer.data)} samples")
                    print(f"  Output: {len(converted)} samples (shape: {converted.shape if hasattr(converted, 'shape') else 'N/A'})")
                    print(f"  Frames: {frame_count}")
                    print(f"  Ratio: {len(converted) / len(buffer.data):.6f}")
            else:
                self._conversion_errors += 1
    
    def _convert_buffer(self, buffer: AudioBuffer) -> Optional[np.ndarray]:
        """
        Convert a single buffer to the target format.
        
        Args:
            buffer: Audio buffer to convert
            
        Returns:
            Converted audio data as numpy array, or None if conversion fails
        """
        try:
            audio_data = buffer.data
            
            # Ensure we have a numpy array
            if not isinstance(audio_data, np.ndarray):
                # Try to convert to numpy array
                if hasattr(audio_data, '__array__'):
                    audio_data = np.asarray(audio_data, dtype=np.float32)
                else:
                    # Assume it's a buffer-like object
                    audio_data = np.frombuffer(audio_data, dtype=np.float32)
            
            # Ensure audio_data is at least 1D
            audio_data = np.atleast_1d(audio_data)
            
            # Handle channel conversion first
            if self.input_format.channel_count != self.target_format.channel_count:
                if self.input_format.channel_count == 2 and self.target_format.channel_count == 1:
                    # Stereo to mono
                    if audio_data.ndim == 2:
                        # Non-interleaved: shape is (samples, channels)
                        audio_data = np.mean(audio_data, axis=1)
                    else:
                        # Interleaved stereo - ensure we have even number of samples
                        if len(audio_data) % 2 == 0:
                            # Deinterleave and average
                            left = audio_data[0::2]
                            right = audio_data[1::2]
                            audio_data = (left + right) / 2.0
                        else:
                            # Odd number of samples, just use as-is
                            print(f"Warning: Odd number of samples for stereo: {len(audio_data)}")
                elif self.input_format.channel_count == 1 and self.target_format.channel_count == 2:
                    # Mono to stereo
                    if audio_data.ndim == 1:
                        # Duplicate mono to both channels
                        audio_data = np.column_stack([audio_data, audio_data])
                        if self.target_format.is_interleaved:
                            audio_data = audio_data.flatten('C')  # Row-major order for interleaving
            
            # Handle sample rate conversion
            if self.needs_resampling:
                if audio_data.ndim == 2:
                    # Non-interleaved multi-channel: resample each channel separately
                    channels = []
                    for ch in range(audio_data.shape[1]):
                        ch_data = audio_data[:, ch]
                        target_length = int(len(ch_data) * self.sample_rate_ratio)
                        resampled = signal.resample(ch_data, target_length)
                        channels.append(resampled)
                    audio_data = np.column_stack(channels)
                else:
                    # Single channel or interleaved
                    target_length = int(len(audio_data) * self.sample_rate_ratio)
                    audio_data = signal.resample(audio_data, target_length)
            
            # Ensure float32 format
            if audio_data.dtype != np.float32:
                audio_data = audio_data.astype(np.float32)
            
            # Final step: ensure output matches target format's interleaving
            if audio_data.ndim == 2:
                if self.target_format.is_interleaved:
                    # Convert non-interleaved to interleaved
                    audio_data = audio_data.flatten('C')  # Row-major for proper interleaving
                # else: already non-interleaved, which is what we want
            elif audio_data.ndim == 1 and not self.target_format.is_interleaved and self.target_format.channel_count == 2:
                # Convert interleaved to non-interleaved stereo
                if len(audio_data) % 2 == 0:
                    audio_data = audio_data.reshape(-1, 2)
            
            return audio_data
            
        except Exception as e:
            print(f"[ConvertingBufferCollector] Error converting buffer: {e}")
            if self._conversion_errors == 0:
                # Print detailed error info for first error
                import traceback
                traceback.print_exc()
            return None
    
    def get_all_buffers(self) -> List[np.ndarray]:
        """
        Get all converted buffers.
        
        Returns:
            List of converted audio buffers
        """
        with self._lock:
            return self._buffers.copy()
    
    def get_all_audio(self) -> np.ndarray:
        """
        Get all converted audio as a single array.
        
        Returns:
            Concatenated audio data in target format
        """
        with self._lock:
            if not self._buffers:
                return np.array([], dtype=np.float32)
            
            # All buffers are already converted - just concatenate
            return np.concatenate(self._buffers)
    
    def clear(self) -> None:
        """Clear all buffers"""
        with self._lock:
            self._buffers.clear()
            self._total_buffers_added = 0
            self._total_frames_converted = 0
            self._cached_total_frames = 0
    
    @property
    def buffer_count(self) -> int:
        """Get number of buffers collected"""
        with self._lock:
            return len(self._buffers)
    
    @property
    def total_frames(self) -> int:
        """Get total number of frames collected"""
        with self._lock:
            return self._cached_total_frames
    
    @property
    def duration(self) -> float:
        """Get total duration in seconds"""
        # Use cached frame count directly
        return self._cached_total_frames / self.target_format.sample_rate
    
    def get_statistics(self) -> dict:
        """Get collector statistics"""
        with self._lock:
            return {
                'buffer_count': len(self._buffers),
                'total_buffers_added': self._total_buffers_added,
                'total_frames_converted': self._total_frames_converted,
                'duration': self.duration,
                'input_format': f"{self.input_format.sample_rate}Hz/{self.input_format.channel_count}ch",
                'target_format': f"{self.target_format.sample_rate}Hz/{self.target_format.channel_count}ch",
                'conversion_errors': self._conversion_errors
            }