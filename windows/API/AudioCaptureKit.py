"""
AudioCaptureKit - Main API Entry Point for Windows

This is the primary interface for the audio capture library, providing a clean
and intuitive API for audio capture, playback, and streaming operations.

Key Features:
- Device enumeration and management
- Session-based recording and playback
- Multiple output support (file, stream, playback)
- Format negotiation and conversion
- Comprehensive error handling
"""

import asyncio
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum, auto
from pathlib import Path
from typing import List, Dict, Optional, Callable, Union, Any
import numpy as np

from .AudioDevice import AudioDevice, AudioDeviceManager
from .AudioSession import (
    AudioCaptureSession, AudioPlaybackSession,
    CaptureConfiguration, PlaybackConfiguration,
    SessionState, SessionStatistics
)
from .AudioOutput import (
    FileOutput, StreamOutput, CallbackOutput,
    PlaybackOutput, NetworkOutput
)
from .AudioFormat import AudioFormat, AudioBuffer
from .AudioError import SessionNotFoundError


class ProcessingPriority(Enum):
    """Processing priority modes"""
    REALTIME = auto()    # Lowest latency, highest CPU
    BALANCED = auto()    # Balanced performance
    EFFICIENCY = auto()  # Lower CPU, higher latency


@dataclass
class AudioCaptureConfiguration:
    """Global audio capture configuration"""
    sample_rate: float = 48000.0
    channel_count: int = 2
    buffer_size: int = 1024
    enable_monitoring: bool = True
    max_memory_usage: int = 100  # MB
    processing_priority: ProcessingPriority = ProcessingPriority.BALANCED


@dataclass
class AudioCaptureStatistics:
    """Library statistics"""
    capture_session_count: int
    playback_session_count: int
    capture_statistics: List[SessionStatistics]
    playback_statistics: List[SessionStatistics]
    timestamp: datetime = field(default_factory=datetime.now)


class AudioCaptureKit:
    """
    Main API entry point for audio capture and playback.
    
    This class provides a high-level interface for audio operations including:
    - Device management
    - Session-based capture and playback
    - Multiple output destinations
    - Format handling and conversion
    """
    
    _instance = None
    
    def __new__(cls):
        """Implement singleton pattern for shared instance"""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    def __init__(self):
        """Initialize AudioCaptureKit"""
        if not hasattr(self, '_initialized'):
            self._device_manager = AudioDeviceManager()
            self._capture_sessions: Dict[uuid.UUID, AudioCaptureSession] = {}
            self._playback_sessions: Dict[uuid.UUID, AudioPlaybackSession] = {}
            self._configuration = AudioCaptureConfiguration()
            self._initialized = True
    
    @classmethod
    def shared(cls) -> 'AudioCaptureKit':
        """Get singleton instance for convenient access"""
        return cls()
    
    # Device Management
    
    def get_playback_devices(self) -> List[AudioDevice]:
        """Get available playback devices"""
        return self._device_manager.get_playback_devices()
    
    def get_recording_devices(self) -> List[AudioDevice]:
        """Get available recording devices (including loopback)"""
        return self._device_manager.get_recording_devices()
    
    def set_playback_device(self, device: AudioDevice) -> None:
        """Set the default playback device"""
        self._device_manager.set_playback_device(device)
    
    def set_recording_device(self, device: AudioDevice) -> None:
        """Set the default recording device"""
        self._device_manager.set_recording_device(device)
    
    def get_current_playback_device(self) -> Optional[AudioDevice]:
        """Get current default playback device"""
        return self._device_manager.get_current_playback_device()
    
    def get_current_recording_device(self) -> Optional[AudioDevice]:
        """Get current default recording device"""
        return self._device_manager.get_current_recording_device()
    
    # Capture Operations
    
    async def start_capture(
        self,
        configuration: Optional[CaptureConfiguration] = None
    ) -> AudioCaptureSession:
        """
        Start audio capture with configuration.
        
        Args:
            configuration: Capture configuration (uses defaults if None)
            
        Returns:
            AudioCaptureSession instance
        """
        config = configuration or CaptureConfiguration()
        session = AudioCaptureSession(config)
        
        # Store session
        self._capture_sessions[session.id] = session
        
        # Start capture
        await session.start()
        
        return session
    
    async def stop_capture(self, session: AudioCaptureSession) -> None:
        """
        Stop audio capture for session.
        
        Args:
            session: The capture session to stop
        """
        await session.stop()
        self._capture_sessions.pop(session.id, None)
    
    def get_active_capture_sessions(self) -> List[AudioCaptureSession]:
        """Get all active capture sessions"""
        return list(self._capture_sessions.values())
    
    # Playback Operations
    
    async def start_playback(
        self,
        configuration: Optional[PlaybackConfiguration] = None
    ) -> AudioPlaybackSession:
        """
        Start audio playback with configuration.
        
        Args:
            configuration: Playback configuration (uses defaults if None)
            
        Returns:
            AudioPlaybackSession instance
        """
        config = configuration or PlaybackConfiguration()
        session = AudioPlaybackSession(config)
        
        # Store session
        self._playback_sessions[session.id] = session
        
        # Start playback
        await session.start()
        
        return session
    
    async def stop_playback(self, session: AudioPlaybackSession) -> None:
        """
        Stop audio playback for session.
        
        Args:
            session: The playback session to stop
        """
        await session.stop()
        self._playback_sessions.pop(session.id, None)
    
    def get_active_playback_sessions(self) -> List[AudioPlaybackSession]:
        """Get all active playback sessions"""
        return list(self._playback_sessions.values())
    
    # Quick Operations
    
    async def record_to_file(
        self,
        file_path: Union[str, Path],
        duration: Optional[float] = None,
        device: Optional[AudioDevice] = None
    ) -> AudioCaptureSession:
        """
        Record audio to file with default settings.
        
        Args:
            file_path: Path to output file
            duration: Recording duration in seconds (None for manual stop)
            device: Audio device to use (None for default)
            
        Returns:
            AudioCaptureSession instance
        """
        config = CaptureConfiguration()
        if device:
            config.device = device
        
        session = await self.start_capture(config)
        file_output = FileOutput(file_path)
        await session.add_output(file_output)
        
        if duration:
            await asyncio.sleep(duration)
            await self.stop_capture(session)
        
        return session
    
    async def stream_audio(
        self,
        buffer_handler: Callable[[np.ndarray], None],
        device: Optional[AudioDevice] = None
    ) -> AudioCaptureSession:
        """
        Stream audio with callback.
        
        Args:
            buffer_handler: Callback function for audio buffers
            device: Audio device to use (None for default)
            
        Returns:
            AudioCaptureSession instance
        """
        config = CaptureConfiguration()
        if device:
            config.device = device
        
        session = await self.start_capture(config)
        callback_output = CallbackOutput(buffer_handler)
        await session.add_output(callback_output)
        
        return session
    
    async def play_system_audio(
        self,
        playback_device: Optional[AudioDevice] = None,
        capture_device: Optional[AudioDevice] = None,
        delay: float = 0.0
    ) -> AudioCaptureSession:
        """
        Play system audio through speakers.
        
        Args:
            playback_device: Output device (None for default)
            capture_device: Input device (None for default loopback)
            delay: Playback delay in seconds
            
        Returns:
            AudioCaptureSession instance
        """
        # Find loopback device if not specified
        if capture_device is None:
            recording_devices = self.get_recording_devices()
            loopback_devices = [d for d in recording_devices if "Loopback" in d.name]
            if loopback_devices:
                capture_device = loopback_devices[0]
        
        config = CaptureConfiguration()
        if capture_device:
            config.device = capture_device
        
        session = await self.start_capture(config)
        
        # Get device index for playback
        device_index = playback_device.device_index if playback_device else None
        playback_output = PlaybackOutput(device_index=device_index, delay=delay)
        await session.add_output(playback_output)
        
        return session
    
    async def start_network_stream(
        self,
        host: str = "0.0.0.0",
        port: int = 9876,
        device: Optional[AudioDevice] = None
    ) -> AudioCaptureSession:
        """
        Start network audio streaming server.
        
        Args:
            host: Host address to bind to
            port: Port number
            device: Audio device to use (None for default)
            
        Returns:
            AudioCaptureSession instance
        """
        config = CaptureConfiguration()
        if device:
            config.device = device
        
        session = await self.start_capture(config)
        network_output = NetworkOutput(host=host, port=port)
        await session.add_output(network_output)
        
        return session
    
    # Configuration
    
    def set_configuration(self, configuration: AudioCaptureConfiguration) -> None:
        """Set global configuration"""
        self._configuration = configuration
    
    def get_configuration(self) -> AudioCaptureConfiguration:
        """Get current configuration"""
        return self._configuration
    
    # Monitoring
    
    async def get_statistics(self) -> AudioCaptureStatistics:
        """Get library statistics"""
        capture_stats = []
        for session in self._capture_sessions.values():
            capture_stats.append(session.get_statistics())
        
        playback_stats = []
        for session in self._playback_sessions.values():
            playback_stats.append(session.get_statistics())
        
        return AudioCaptureStatistics(
            capture_session_count=len(self._capture_sessions),
            playback_session_count=len(self._playback_sessions),
            capture_statistics=capture_stats,
            playback_statistics=playback_stats
        )
    
    # Cleanup
    
    async def cleanup(self) -> None:
        """Stop all sessions and cleanup resources"""
        # Stop all capture sessions
        for session in list(self._capture_sessions.values()):
            try:
                await session.stop()
            except Exception:
                pass
        self._capture_sessions.clear()
        
        # Stop all playback sessions
        for session in list(self._playback_sessions.values()):
            try:
                await session.stop()
            except Exception:
                pass
        self._playback_sessions.clear()
        
        # Stop device monitoring if active
        await self._device_manager.stop_monitoring()
    
    def __del__(self):
        """Cleanup on deletion"""
        try:
            # Try to get the current event loop
            try:
                loop = asyncio.get_running_loop()
                # Schedule the cleanup coroutine on the existing loop
                loop.create_task(self.cleanup())
            except RuntimeError:
                # No running loop, create a new one
                asyncio.run(self.cleanup())
        except Exception:
            pass


# Convenience functions for quick access

def get_default_kit() -> AudioCaptureKit:
    """Get the default AudioCaptureKit instance"""
    return AudioCaptureKit.shared()


async def quick_record(
    file_path: Union[str, Path],
    duration: float = 5.0
) -> None:
    """
    Quick record audio to file.
    
    Args:
        file_path: Output file path
        duration: Recording duration in seconds
    """
    kit = get_default_kit()
    await kit.record_to_file(file_path, duration)


async def quick_play_loopback(duration: Optional[float] = None) -> None:
    """
    Quick play system audio through speakers.
    
    Args:
        duration: Playback duration (None for continuous)
    """
    kit = get_default_kit()
    session = await kit.play_system_audio()
    
    if duration:
        await asyncio.sleep(duration)
        await kit.stop_capture(session)