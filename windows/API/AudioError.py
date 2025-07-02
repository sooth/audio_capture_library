"""
AudioCaptureError - Comprehensive error types for the Windows audio capture library
"""

from datetime import datetime
from typing import Dict, Any, Optional, Callable
from enum import Enum, auto
import uuid
import time


class ErrorRecoveryStrategy(Enum):
    """Error recovery strategies"""
    RETRY = auto()
    FALLBACK = auto()
    IGNORE = auto()
    FAIL = auto()


class AudioCaptureError(Exception):
    """Base exception class for audio capture errors"""
    
    def __init__(self, message: str, details: Optional[str] = None):
        self.message = message
        self.details = details
        super().__init__(self.message)
    
    @property
    def failure_reason(self) -> Optional[str]:
        """Get the failure reason for this error"""
        return None
    
    @property
    def recovery_suggestion(self) -> Optional[str]:
        """Get recovery suggestion for this error"""
        return None
    
    @property
    def help_anchor(self) -> Optional[str]:
        """Get help documentation anchor for this error"""
        return None


# Device Errors
class DeviceNotFoundError(AudioCaptureError):
    """Audio device not found"""
    def __init__(self, device_name: str):
        super().__init__(f"Audio device '{device_name}' not found")
        self.device_name = device_name
    
    @property
    def help_anchor(self) -> str:
        return "devices"


class DeviceEnumerationFailedError(AudioCaptureError):
    """Failed to enumerate audio devices"""
    def __init__(self):
        super().__init__("Failed to enumerate audio devices")
    
    @property
    def help_anchor(self) -> str:
        return "devices"


class DeviceSelectionFailedError(AudioCaptureError):
    """Failed to select audio device"""
    def __init__(self):
        super().__init__("Failed to select audio device")
    
    @property
    def help_anchor(self) -> str:
        return "devices"


class DevicePropertyReadFailedError(AudioCaptureError):
    """Failed to read device properties"""
    def __init__(self):
        super().__init__("Failed to read device properties")


class InvalidDeviceError(AudioCaptureError):
    """Invalid device"""
    def __init__(self, reason: str):
        super().__init__(f"Invalid device: {reason}")
        self.reason = reason
    
    @property
    def help_anchor(self) -> str:
        return "devices"


class DeviceDisconnectedError(AudioCaptureError):
    """Device was disconnected"""
    def __init__(self, device_name: str):
        super().__init__(f"Device '{device_name}' was disconnected")
        self.device_name = device_name
    
    @property
    def recovery_suggestion(self) -> str:
        return "Reconnect the audio device or select a different device"
    
    @property
    def help_anchor(self) -> str:
        return "devices"


class DeviceInUseError(AudioCaptureError):
    """Device is already in use"""
    def __init__(self, device_name: str):
        super().__init__(f"Device '{device_name}' is already in use")
        self.device_name = device_name
    
    @property
    def help_anchor(self) -> str:
        return "devices"


# Permission Errors
class PermissionDeniedError(AudioCaptureError):
    """Permission denied"""
    def __init__(self):
        super().__init__("Permission denied")


class AudioLoopbackPermissionError(AudioCaptureError):
    """System audio loopback permission required"""
    def __init__(self, message=None):
        if message:
            super().__init__(message)
        else:
            super().__init__(
                "System audio loopback permission is required. "
                "This feature requires Windows 10 version 1803 or later"
            )
    
    @property
    def failure_reason(self) -> str:
        return "The app needs access to system audio"
    
    @property
    def recovery_suggestion(self) -> str:
        return "Ensure you're running Windows 10 version 1803 or later and have appropriate permissions"
    
    @property
    def help_anchor(self) -> str:
        return "permissions"


class MicrophonePermissionError(AudioCaptureError):
    """Microphone permission required"""
    def __init__(self):
        super().__init__(
            "Microphone permission is required. "
            "Please grant permission in Windows Settings > Privacy > Microphone"
        )
    
    @property
    def failure_reason(self) -> str:
        return "The app needs access to microphone input"
    
    @property
    def recovery_suggestion(self) -> str:
        return "Open Windows Settings and grant Microphone permission to this app"
    
    @property
    def help_anchor(self) -> str:
        return "permissions"


# Session Errors
class SessionNotFoundError(AudioCaptureError):
    """Session not found"""
    def __init__(self, session_id: uuid.UUID):
        super().__init__(f"Session with ID {session_id} not found")
        self.session_id = session_id


class InvalidStateError(AudioCaptureError):
    """Invalid session state"""
    def __init__(self, message: str):
        super().__init__(f"Invalid session state: {message}")


class SessionAlreadyActiveError(AudioCaptureError):
    """Session is already active"""
    def __init__(self):
        super().__init__("Session is already active")


class SessionNotActiveError(AudioCaptureError):
    """Session is not active"""
    def __init__(self):
        super().__init__("Session is not active")


class SessionStartFailedError(AudioCaptureError):
    """Failed to start session"""
    def __init__(self, reason: str):
        super().__init__(f"Failed to start session: {reason}")
        self.reason = reason


# Format Errors
class UnsupportedFormatError(AudioCaptureError):
    """Unsupported audio format"""
    def __init__(self, format_desc: str):
        super().__init__(f"Unsupported audio format: {format_desc}")
        self.format_desc = format_desc
    
    @property
    def help_anchor(self) -> str:
        return "formats"


class FormatConversionFailedError(AudioCaptureError):
    """Format conversion failed"""
    def __init__(self, reason: str):
        super().__init__(f"Format conversion failed: {reason}")
        self.reason = reason
    
    @property
    def help_anchor(self) -> str:
        return "formats"


class FormatMismatchError(AudioCaptureError):
    """Audio format mismatch"""
    def __init__(self, details: str):
        super().__init__(f"Audio format mismatch: {details}")
        self.details = details
    
    @property
    def recovery_suggestion(self) -> str:
        return "Check that all audio components are using compatible formats"
    
    @property
    def help_anchor(self) -> str:
        return "formats"


class FormatNegotiationFailedError(AudioCaptureError):
    """Failed to negotiate compatible audio format"""
    def __init__(self):
        super().__init__("Failed to negotiate compatible audio format")
    
    @property
    def help_anchor(self) -> str:
        return "formats"


# Output Errors
class OutputNotConfiguredError(AudioCaptureError):
    """Output is not configured"""
    def __init__(self):
        super().__init__("Output is not configured")


class OutputConfigurationFailedError(AudioCaptureError):
    """Output configuration failed"""
    def __init__(self, reason: str):
        super().__init__(f"Output configuration failed: {reason}")
        self.reason = reason


class OutputProcessingFailedError(AudioCaptureError):
    """Output processing failed"""
    def __init__(self, reason: str):
        super().__init__(f"Output processing failed: {reason}")
        self.reason = reason


class FileWriteFailedError(AudioCaptureError):
    """File write failed"""
    def __init__(self, reason: str):
        super().__init__(f"File write failed: {reason}")
        self.reason = reason


class StreamingFailedError(AudioCaptureError):
    """Streaming failed"""
    def __init__(self, reason: str):
        super().__init__(f"Streaming failed: {reason}")
        self.reason = reason


# Buffer Errors
class BufferAllocationFailedError(AudioCaptureError):
    """Failed to allocate audio buffer"""
    def __init__(self):
        super().__init__("Failed to allocate audio buffer")


class BufferOverflowError(AudioCaptureError):
    """Audio buffer overflow"""
    def __init__(self):
        super().__init__("Audio buffer overflow")
    
    @property
    def failure_reason(self) -> str:
        return "Audio processing can't keep up with input rate"
    
    @property
    def recovery_suggestion(self) -> str:
        return "Try reducing the audio quality or closing other applications"
    
    @property
    def help_anchor(self) -> str:
        return "performance"


class BufferUnderrunError(AudioCaptureError):
    """Audio buffer underrun"""
    def __init__(self):
        super().__init__("Audio buffer underrun")
    
    @property
    def failure_reason(self) -> str:
        return "Audio input is not providing data fast enough"
    
    @property
    def help_anchor(self) -> str:
        return "performance"


class InvalidBufferSizeError(AudioCaptureError):
    """Invalid buffer size"""
    def __init__(self):
        super().__init__("Invalid buffer size")


# System Errors
class SystemResourcesExhaustedError(AudioCaptureError):
    """System resources exhausted"""
    def __init__(self):
        super().__init__("System resources exhausted")
    
    @property
    def failure_reason(self) -> str:
        return "Not enough CPU or memory available"
    
    @property
    def recovery_suggestion(self) -> str:
        return "Close other applications to free up system resources"


class MemoryAllocationFailedError(AudioCaptureError):
    """Memory allocation failed"""
    def __init__(self):
        super().__init__("Memory allocation failed")


class AudioEngineStartFailedError(AudioCaptureError):
    """Audio engine failed to start"""
    def __init__(self, reason: str):
        super().__init__(f"Audio engine failed to start: {reason}")
        self.reason = reason


class UnknownError(AudioCaptureError):
    """Unknown error"""
    def __init__(self, message: str):
        super().__init__(f"Unknown error: {message}")


# Network Errors
class NetworkConnectionFailedError(AudioCaptureError):
    """Network connection failed"""
    def __init__(self, reason: str):
        super().__init__(f"Network connection failed: {reason}")
        self.reason = reason


class StreamingProtocolError(AudioCaptureError):
    """Streaming protocol error"""
    def __init__(self, reason: str):
        super().__init__(f"Streaming protocol error: {reason}")
        self.reason = reason


# Windows-specific Errors
class WASAPIError(AudioCaptureError):
    """Windows Audio Session API error"""
    def __init__(self, error_code: int, message: str):
        super().__init__(f"WASAPI error {error_code}: {message}")
        self.error_code = error_code


class MMEError(AudioCaptureError):
    """Windows Multimedia Extension error"""
    def __init__(self, error_code: int, message: str):
        super().__init__(f"MME error {error_code}: {message}")
        self.error_code = error_code


class DirectSoundError(AudioCaptureError):
    """DirectSound error"""
    def __init__(self, error_code: int, message: str):
        super().__init__(f"DirectSound error {error_code}: {message}")
        self.error_code = error_code


class ErrorHandler:
    """Error handler with recovery strategies"""
    
    @staticmethod
    async def handle(
        error: Exception,
        strategy: ErrorRecoveryStrategy = ErrorRecoveryStrategy.FAIL,
        max_attempts: int = 3,
        delay: float = 1.0,
        fallback_action: Optional[Callable] = None
    ):
        """Handle error with recovery strategy"""
        print(f"Error occurred: {error}")
        
        if strategy == ErrorRecoveryStrategy.RETRY:
            # Retry logic would be implemented by caller
            raise error
            
        elif strategy == ErrorRecoveryStrategy.FALLBACK:
            if fallback_action:
                await fallback_action()
            else:
                raise error
                
        elif strategy == ErrorRecoveryStrategy.IGNORE:
            # Log and continue
            print(f"Ignoring error: {error}")
            
        elif strategy == ErrorRecoveryStrategy.FAIL:
            raise error
    
    @staticmethod
    def suggested_strategy(error: Exception) -> tuple[ErrorRecoveryStrategy, dict]:
        """Get suggested recovery strategy for error"""
        if isinstance(error, DeviceDisconnectedError):
            return ErrorRecoveryStrategy.RETRY, {"max_attempts": 3, "delay": 1.0}
        elif isinstance(error, (BufferOverflowError, BufferUnderrunError)):
            return ErrorRecoveryStrategy.IGNORE, {}
        elif isinstance(error, SessionStartFailedError):
            return ErrorRecoveryStrategy.RETRY, {"max_attempts": 2, "delay": 0.5}
        else:
            return ErrorRecoveryStrategy.FAIL, {}


class ErrorContext:
    """Error context for detailed debugging"""
    
    def __init__(
        self,
        error: Exception,
        session_id: Optional[uuid.UUID] = None,
        operation: str = "",
        additional_info: Optional[Dict[str, Any]] = None
    ):
        self.error = error
        self.timestamp = datetime.now()
        self.session_id = session_id
        self.operation = operation
        self.additional_info = additional_info or {}
    
    def report(self) -> str:
        """Create detailed error report"""
        report = f"""Audio Capture Error Report
========================
Timestamp: {self.timestamp}
Operation: {self.operation}
Error: {self.error}
"""
        
        if self.session_id:
            report += f"\nSession ID: {self.session_id}"
        
        if self.additional_info:
            report += "\n\nAdditional Information:"
            for key, value in self.additional_info.items():
                report += f"\n  {key}: {value}"
        
        if isinstance(self.error, AudioCaptureError):
            if self.error.recovery_suggestion:
                report += f"\n\nRecovery Suggestion: {self.error.recovery_suggestion}"
        
        return report