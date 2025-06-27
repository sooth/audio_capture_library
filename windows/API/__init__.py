"""
Windows AudioCaptureKit API

A comprehensive audio capture and playback library for Windows, providing
functionality equivalent to the macOS AudioCaptureKit.

Key Features:
- System audio capture (loopback recording)
- Microphone recording
- Real-time audio playback
- Multiple output destinations (file, network, callback)
- Device enumeration and management
- Format conversion and negotiation
- Session-based architecture
"""

__version__ = "1.0.0"
__author__ = "AudioCaptureKit Windows Team"

# Import main components
from .AudioCaptureKit import (
    AudioCaptureKit,
    get_default_kit,
    quick_record,
    quick_play_loopback,
    ProcessingPriority,
    AudioCaptureConfiguration,
    AudioCaptureStatistics
)

from .AudioSession import (
    AudioCaptureSession,
    AudioPlaybackSession,
    CaptureConfiguration,
    PlaybackConfiguration,
    SessionState,
    SessionStatistics
)

from .AudioDevice import (
    AudioDevice,
    AudioDeviceManager,
    DeviceType,
    DeviceStatus,
    DeviceAPI,
    DeviceCapabilities,
    DeviceChangeEvent,
    DeviceChange
)

from .AudioFormat import (
    AudioFormat,
    AudioBuffer,
    AudioFormatNegotiator,
    FormatPriority,
    FormatPreferences
)

from .AudioOutput import (
    AudioOutput,
    FileOutput,
    StreamOutput,
    CallbackOutput,
    PlaybackOutput,
    RingBufferOutput,
    NetworkOutput
)

from .AudioError import (
    AudioCaptureError,
    DeviceNotFoundError,
    DeviceEnumerationFailedError,
    DeviceSelectionFailedError,
    InvalidDeviceError,
    DeviceDisconnectedError,
    DeviceInUseError,
    PermissionDeniedError,
    AudioLoopbackPermissionError,
    MicrophonePermissionError,
    SessionNotFoundError,
    InvalidStateError,
    SessionAlreadyActiveError,
    SessionNotActiveError,
    SessionStartFailedError,
    UnsupportedFormatError,
    FormatConversionFailedError,
    FormatMismatchError,
    FormatNegotiationFailedError,
    OutputNotConfiguredError,
    OutputConfigurationFailedError,
    OutputProcessingFailedError,
    FileWriteFailedError,
    StreamingFailedError,
    BufferAllocationFailedError,
    BufferOverflowError,
    BufferUnderrunError,
    InvalidBufferSizeError,
    SystemResourcesExhaustedError,
    MemoryAllocationFailedError,
    AudioEngineStartFailedError,
    UnknownError,
    NetworkConnectionFailedError,
    StreamingProtocolError,
    WASAPIError,
    MMEError,
    DirectSoundError,
    ErrorRecoveryStrategy,
    ErrorHandler,
    ErrorContext
)

from .StreamingAudioRecorder import (
    StreamingAudioRecorder,
    AudioStreamDelegate
)

from .StreamingAudioPlayer import (
    StreamingAudioPlayer
)

from .AudioBufferQueue import (
    AudioBufferQueue,
    PriorityAudioBufferQueue,
    CircularAudioBufferQueue,
    Priority,
    QueueStatistics,
    ConvertingBufferCollector
)

from .WavFileWriter import (
    WavFileWriter,
    SimpleWavWriter
)

from .NetworkOutput import (
    NetworkAudioServer,
    NetworkAudioClient,
    NetworkStatistics
)

# Convenience shortcuts
Kit = AudioCaptureKit
Session = AudioCaptureSession

__all__ = [
    # Main API
    'AudioCaptureKit',
    'get_default_kit',
    'quick_record',
    'quick_play_loopback',
    'Kit',
    
    # Sessions
    'AudioCaptureSession',
    'AudioPlaybackSession',
    'CaptureConfiguration',
    'PlaybackConfiguration',
    'SessionState',
    'SessionStatistics',
    'Session',
    
    # Devices
    'AudioDevice',
    'AudioDeviceManager',
    'DeviceType',
    'DeviceStatus',
    'DeviceAPI',
    'DeviceCapabilities',
    'DeviceChangeEvent',
    'DeviceChange',
    
    # Formats
    'AudioFormat',
    'AudioBuffer',
    'AudioFormatNegotiator',
    'FormatPriority',
    'FormatPreferences',
    
    # Outputs
    'AudioOutput',
    'FileOutput',
    'StreamOutput',
    'CallbackOutput',
    'PlaybackOutput',
    'RingBufferOutput',
    'NetworkOutput',
    
    # Recording/Playback
    'StreamingAudioRecorder',
    'StreamingAudioPlayer',
    'AudioStreamDelegate',
    
    # Buffers
    'AudioBufferQueue',
    'PriorityAudioBufferQueue',
    'CircularAudioBufferQueue',
    'Priority',
    'QueueStatistics',
    'ConvertingBufferCollector',
    
    # File Writing
    'WavFileWriter',
    'SimpleWavWriter',
    
    # Network
    'NetworkAudioServer',
    'NetworkAudioClient',
    'NetworkStatistics',
    
    # Configuration
    'ProcessingPriority',
    'AudioCaptureConfiguration',
    'AudioCaptureStatistics',
    
    # Errors
    'AudioCaptureError',
    'DeviceNotFoundError',
    'DeviceEnumerationFailedError',
    'DeviceSelectionFailedError',
    'InvalidDeviceError',
    'DeviceDisconnectedError',
    'DeviceInUseError',
    'PermissionDeniedError',
    'AudioLoopbackPermissionError',
    'MicrophonePermissionError',
    'SessionNotFoundError',
    'InvalidStateError',
    'SessionAlreadyActiveError',
    'SessionNotActiveError',
    'SessionStartFailedError',
    'UnsupportedFormatError',
    'FormatConversionFailedError',
    'FormatMismatchError',
    'FormatNegotiationFailedError',
    'OutputNotConfiguredError',
    'OutputConfigurationFailedError',
    'OutputProcessingFailedError',
    'FileWriteFailedError',
    'StreamingFailedError',
    'BufferAllocationFailedError',
    'BufferOverflowError',
    'BufferUnderrunError',
    'InvalidBufferSizeError',
    'SystemResourcesExhaustedError',
    'MemoryAllocationFailedError',
    'AudioEngineStartFailedError',
    'UnknownError',
    'NetworkConnectionFailedError',
    'StreamingProtocolError',
    'WASAPIError',
    'MMEError',
    'DirectSoundError',
    'ErrorRecoveryStrategy',
    'ErrorHandler',
    'ErrorContext',
]