"""
AudioFormat - Represents an audio format configuration

This module encapsulates all parameters needed to describe an audio format,
including sample rate, channel configuration, bit depth, and data layout.
"""

from dataclasses import dataclass
from datetime import datetime
from enum import Enum, auto
from typing import Optional, Tuple
import numpy as np


class AudioCommonFormat(Enum):
    """Common audio format types"""
    PCM_FORMAT_INT16 = auto()
    PCM_FORMAT_INT32 = auto()
    PCM_FORMAT_FLOAT32 = auto()
    PCM_FORMAT_FLOAT64 = auto()


@dataclass(frozen=True)
class AudioFormat:
    """
    Represents an audio format configuration.
    
    Attributes:
        sample_rate: Sample rate in Hz
        channel_count: Number of channels
        bit_depth: Bit depth (16, 24, 32, 64)
        is_interleaved: Whether samples are interleaved
        is_float: Whether format uses floating point
    """
    sample_rate: float
    channel_count: int
    bit_depth: int
    is_interleaved: bool
    is_float: bool = False
    
    def __post_init__(self):
        """Validate and adjust format parameters"""
        if self.bit_depth == 32 and not self.is_float:
            # Default to float for 32-bit
            object.__setattr__(self, 'is_float', True)
    
    @property
    def bytes_per_frame(self) -> int:
        """Calculate bytes per frame"""
        return (self.bit_depth // 8) * (self.channel_count if self.is_interleaved else 1)
    
    @property
    def bytes_per_packet(self) -> int:
        """Calculate bytes per packet"""
        return self.bytes_per_frame * (1 if self.is_interleaved else self.channel_count)
    
    @property
    def common_format(self) -> AudioCommonFormat:
        """Get common format type"""
        if self.bit_depth == 16 and not self.is_float:
            return AudioCommonFormat.PCM_FORMAT_INT16
        elif self.bit_depth == 32 and self.is_float:
            return AudioCommonFormat.PCM_FORMAT_FLOAT32
        elif self.bit_depth == 32 and not self.is_float:
            return AudioCommonFormat.PCM_FORMAT_INT32
        elif self.bit_depth == 64 and self.is_float:
            return AudioCommonFormat.PCM_FORMAT_FLOAT64
        elif self.bit_depth == 24 and not self.is_float:
            # 24-bit is typically converted to 32-bit
            return AudioCommonFormat.PCM_FORMAT_INT32
        else:
            return AudioCommonFormat.PCM_FORMAT_FLOAT32
    
    @property
    def numpy_dtype(self) -> np.dtype:
        """Get NumPy dtype for this format"""
        if self.bit_depth == 16 and not self.is_float:
            return np.dtype('int16')
        elif self.bit_depth == 32 and self.is_float:
            return np.dtype('float32')
        elif self.bit_depth == 32 and not self.is_float:
            return np.dtype('int32')
        elif self.bit_depth == 64 and self.is_float:
            return np.dtype('float64')
        else:
            return np.dtype('float32')
    
    def is_compatible(self, other: 'AudioFormat') -> bool:
        """Check if format is compatible with another format"""
        return (self.sample_rate == other.sample_rate and
                self.channel_count == other.channel_count and
                self.bit_depth == other.bit_depth and
                self.is_interleaved == other.is_interleaved and
                self.is_float == other.is_float)
    
    def requires_conversion(self, other: 'AudioFormat') -> bool:
        """Check if format requires conversion to another format"""
        return not self.is_compatible(other)
    
    @property
    def description(self) -> str:
        """Human-readable description"""
        format_type = "Float" if self.is_float else "Int"
        layout = "Interleaved" if self.is_interleaved else "Non-interleaved"
        return f"{int(self.sample_rate)}Hz, {self.channel_count}ch, {self.bit_depth}-bit {format_type}, {layout}"
    
    # Common format presets
    @classmethod
    def default_format(cls) -> 'AudioFormat':
        """Default capture format (48kHz, 2ch, 32-bit float, non-interleaved)"""
        return cls(
            sample_rate=48000.0,
            channel_count=2,
            bit_depth=32,
            is_interleaved=False,
            is_float=True
        )
    
    @classmethod
    def cd_quality(cls) -> 'AudioFormat':
        """CD quality format (44.1kHz, 2ch, 16-bit int, interleaved)"""
        return cls(
            sample_rate=44100.0,
            channel_count=2,
            bit_depth=16,
            is_interleaved=True,
            is_float=False
        )
    
    @classmethod
    def standard_wav(cls) -> 'AudioFormat':
        """Standard WAV format (48kHz, 2ch, 16-bit int, interleaved)"""
        return cls(
            sample_rate=48000.0,
            channel_count=2,
            bit_depth=16,
            is_interleaved=True,
            is_float=False
        )
    
    @classmethod
    def high_quality(cls) -> 'AudioFormat':
        """High quality format (96kHz, 2ch, 24-bit int, interleaved)"""
        return cls(
            sample_rate=96000.0,
            channel_count=2,
            bit_depth=24,
            is_interleaved=True,
            is_float=False
        )


class FormatPriority(Enum):
    """Format negotiation priority"""
    QUALITY = auto()        # Prefer highest quality
    COMPATIBILITY = auto()  # Prefer most compatible format
    PERFORMANCE = auto()    # Prefer least conversion
    BALANCED = auto()       # Balance all factors


@dataclass
class FormatPreferences:
    """Format negotiation preferences"""
    priority: FormatPriority
    max_sample_rate: Optional[float] = None
    max_bit_depth: Optional[int] = None
    prefer_interleaved: bool = True
    prefer_float: bool = False
    
    @classmethod
    def default(cls) -> 'FormatPreferences':
        """Default preferences"""
        return cls(
            priority=FormatPriority.BALANCED,
            max_sample_rate=None,
            max_bit_depth=None,
            prefer_interleaved=True,
            prefer_float=False
        )
    
    @classmethod
    def high_quality(cls) -> 'FormatPreferences':
        """High quality preferences"""
        return cls(
            priority=FormatPriority.QUALITY,
            max_sample_rate=192000.0,
            max_bit_depth=32,
            prefer_interleaved=False,
            prefer_float=True
        )
    
    @classmethod
    def performance(cls) -> 'FormatPreferences':
        """Performance preferences"""
        return cls(
            priority=FormatPriority.PERFORMANCE,
            max_sample_rate=48000.0,
            max_bit_depth=16,
            prefer_interleaved=True,
            prefer_float=False
        )


class AudioFormatNegotiator:
    """Handles format negotiation and conversion"""
    
    @staticmethod
    def negotiate(
        source: AudioFormat,
        destination: AudioFormat,
        preferences: FormatPreferences = None
    ) -> AudioFormat:
        """Find best common format between source and destination"""
        if preferences is None:
            preferences = FormatPreferences.default()
        
        # If formats match, no negotiation needed
        if source.is_compatible(destination):
            return source
        
        # Apply preferences
        if preferences.priority == FormatPriority.QUALITY:
            # Prefer higher sample rate and bit depth
            return AudioFormat(
                sample_rate=max(source.sample_rate, destination.sample_rate),
                channel_count=max(source.channel_count, destination.channel_count),
                bit_depth=max(source.bit_depth, destination.bit_depth),
                is_interleaved=destination.is_interleaved,
                is_float=source.is_float or destination.is_float
            )
        
        elif preferences.priority == FormatPriority.COMPATIBILITY:
            # Prefer destination format for maximum compatibility
            return destination
        
        elif preferences.priority == FormatPriority.PERFORMANCE:
            # Prefer source format to minimize conversion
            return source
        
        else:  # BALANCED
            # Find middle ground
            return AudioFormat(
                sample_rate=destination.sample_rate,  # Use destination sample rate
                channel_count=min(source.channel_count, destination.channel_count),
                bit_depth=destination.bit_depth,
                is_interleaved=destination.is_interleaved,
                is_float=destination.is_float
            )
    
    @staticmethod
    def can_convert(source: AudioFormat, destination: AudioFormat) -> bool:
        """Check if direct conversion is possible"""
        # Sample rate conversion is supported
        if source.sample_rate != destination.sample_rate:
            return True
        
        # Channel count mismatch - check if downmix/upmix is possible
        if source.channel_count != destination.channel_count:
            if source.channel_count > 2 and destination.channel_count == 2:
                return True  # Can downmix to stereo
            if source.channel_count == 1 and destination.channel_count == 2:
                return True  # Can upmix mono to stereo
        
        # Format conversion is generally possible
        return True
    
    @staticmethod
    def conversion_complexity(source: AudioFormat, destination: AudioFormat) -> float:
        """Get conversion complexity score (0.0 = simple, 1.0 = complex)"""
        complexity = 0.0
        
        # Sample rate conversion
        if source.sample_rate != destination.sample_rate:
            complexity += 0.3
        
        # Channel conversion
        if source.channel_count != destination.channel_count:
            complexity += 0.2
        
        # Bit depth conversion
        if source.bit_depth != destination.bit_depth:
            complexity += 0.2
        
        # Float/Int conversion
        if source.is_float != destination.is_float:
            complexity += 0.2
        
        # Interleaving conversion
        if source.is_interleaved != destination.is_interleaved:
            complexity += 0.1
        
        return min(complexity, 1.0)


class AudioBuffer:
    """Audio buffer wrapper for format-aware operations"""
    
    def __init__(
        self,
        data: np.ndarray,
        format: AudioFormat,
        timestamp: Optional[datetime] = None
    ):
        """
        Initialize audio buffer.
        
        Args:
            data: NumPy array containing audio data
            format: Audio format specification
            timestamp: Timestamp of buffer capture
        """
        self.data = data
        self.format = format
        self.timestamp = timestamp or datetime.now()
        
        # Validate data shape
        expected_shape = self._calculate_expected_shape()
        if self.data.shape != expected_shape and len(expected_shape) > 0:
            raise ValueError(
                f"Data shape {self.data.shape} doesn't match format. "
                f"Expected {expected_shape}"
            )
    
    def _calculate_expected_shape(self) -> Tuple[int, ...]:
        """Calculate expected data shape based on format"""
        if len(self.data.shape) == 1:
            # 1D array for mono or interleaved
            return self.data.shape
        
        if self.format.is_interleaved:
            # Interleaved: (frames, channels)
            if len(self.data.shape) == 2:
                return self.data.shape
        else:
            # Non-interleaved: (channels, frames)
            if len(self.data.shape) == 2:
                return self.data.shape
        
        return tuple()
    
    @property
    def frame_count(self) -> int:
        """Get number of audio frames"""
        if self.format.is_interleaved:
            return self.data.shape[0] if len(self.data.shape) > 0 else 0
        else:
            return self.data.shape[1] if len(self.data.shape) > 1 else len(self.data)
    
    @property
    def duration(self) -> float:
        """Get duration in seconds"""
        return self.frame_count / self.format.sample_rate
    
    def to_interleaved(self) -> 'AudioBuffer':
        """Convert to interleaved format"""
        if self.format.is_interleaved:
            return self
        
        # Transpose data from (channels, frames) to (frames, channels)
        interleaved_data = self.data.T
        interleaved_format = AudioFormat(
            sample_rate=self.format.sample_rate,
            channel_count=self.format.channel_count,
            bit_depth=self.format.bit_depth,
            is_interleaved=True,
            is_float=self.format.is_float
        )
        
        return AudioBuffer(interleaved_data, interleaved_format, self.timestamp)
    
    def to_non_interleaved(self) -> 'AudioBuffer':
        """Convert to non-interleaved format"""
        if not self.format.is_interleaved:
            return self
        
        # Transpose data from (frames, channels) to (channels, frames)
        non_interleaved_data = self.data.T
        non_interleaved_format = AudioFormat(
            sample_rate=self.format.sample_rate,
            channel_count=self.format.channel_count,
            bit_depth=self.format.bit_depth,
            is_interleaved=False,
            is_float=self.format.is_float
        )
        
        return AudioBuffer(non_interleaved_data, non_interleaved_format, self.timestamp)