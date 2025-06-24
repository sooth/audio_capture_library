"""
AudioSession - Session management for audio capture and playback

This module provides session management for audio operations, including
state tracking, output management, and configuration handling.
"""

import asyncio
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum, auto
from typing import List, Dict, Optional, Callable, Any
import numpy as np

from .AudioFormat import AudioFormat, AudioBuffer
from .AudioOutput import AudioOutput
from .AudioDevice import AudioDevice
from .StreamingAudioRecorder import StreamingAudioRecorder, AudioStreamDelegate
from .StreamingAudioPlayer import StreamingAudioPlayer
from .AudioError import InvalidStateError, SessionNotFoundError


class SessionState(Enum):
    """Session state enumeration"""
    IDLE = "idle"
    STARTING = "starting"
    ACTIVE = "active"
    PAUSED = "paused"
    STOPPING = "stopping"
    STOPPED = "stopped"
    ERROR = "error"


@dataclass
class SessionStatistics:
    """Session statistics"""
    session_id: uuid.UUID
    state: SessionState
    buffer_count: int
    duration: float
    format: Optional[AudioFormat]
    created_at: datetime = field(default_factory=datetime.now)
    
    @property
    def uptime(self) -> float:
        """Get session uptime in seconds"""
        return (datetime.now() - self.created_at).total_seconds()


@dataclass
class CaptureConfiguration:
    """Audio capture configuration"""
    device: Optional[AudioDevice] = None
    format: Optional[AudioFormat] = None
    buffer_size: int = 1024
    
    def __post_init__(self):
        if self.format is None:
            self.format = AudioFormat.default_format()


@dataclass
class PlaybackConfiguration:
    """Audio playback configuration"""
    device: Optional[AudioDevice] = None
    format: Optional[AudioFormat] = None
    volume: float = 1.0
    delay: float = 0.0
    buffer_size: int = 1024
    
    def __post_init__(self):
        if self.format is None:
            self.format = AudioFormat.default_format()
        self.volume = max(0.0, min(1.0, self.volume))
        self.delay = max(0.0, self.delay)


class AudioStreamMultiplexer(AudioStreamDelegate):
    """Distributes audio to multiple outputs"""
    
    def __init__(self):
        """Initialize audio stream multiplexer"""
        self._outputs: List[AudioOutput] = []
        self._is_paused = False
        self._buffer_count = 0
        self._lock = asyncio.Lock()
    
    async def add_output(self, output: AudioOutput) -> None:
        """Add an output"""
        async with self._lock:
            if output not in self._outputs:
                self._outputs.append(output)
    
    async def remove_output(self, output: AudioOutput) -> None:
        """Remove an output"""
        async with self._lock:
            if output in self._outputs:
                self._outputs.remove(output)
    
    async def remove_all_outputs(self) -> None:
        """Remove all outputs"""
        async with self._lock:
            self._outputs.clear()
    
    async def set_paused(self, paused: bool) -> None:
        """Set paused state"""
        self._is_paused = paused
    
    async def audio_streamer_did_receive(self, streamer: StreamingAudioRecorder, buffer: AudioBuffer):
        """Handle received audio buffer"""
        if self._is_paused:
            return
        
        self._buffer_count += 1
        
        # Distribute to all outputs
        async with self._lock:
            outputs = list(self._outputs)
        
        # Process outputs concurrently
        tasks = []
        for output in outputs:
            tasks.append(self._process_output(output, buffer))
        
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
    
    async def _process_output(self, output: AudioOutput, buffer: AudioBuffer):
        """Process buffer for a single output"""
        try:
            await output.process(buffer)
        except Exception as e:
            print(f"Output {output.id} failed to process buffer: {e}")
    
    async def audio_streamer_did_encounter_error(self, streamer: StreamingAudioRecorder, error: Exception):
        """Handle error from streamer"""
        async with self._lock:
            outputs = list(self._outputs)
        
        for output in outputs:
            try:
                await output.handle_error(error)
            except Exception:
                pass
    
    async def audio_streamer_did_finish(self, streamer: StreamingAudioRecorder):
        """Handle streamer finish"""
        async with self._lock:
            outputs = list(self._outputs)
        
        for output in outputs:
            try:
                await output.finish()
            except Exception:
                pass


class BaseAudioSession:
    """Base class for audio sessions"""
    
    def __init__(self):
        """Initialize base audio session"""
        self.id = uuid.uuid4()
        self.created_at = datetime.now()
        self._state = SessionState.IDLE
        self._statistics = SessionStatistics(
            session_id=self.id,
            state=SessionState.IDLE,
            buffer_count=0,
            duration=0.0,
            format=None
        )
        self._state_observers: Dict[uuid.UUID, Callable[[SessionState], None]] = {}
        self._error_handler: Optional[Callable[[Exception], None]] = None
        self._state_lock = asyncio.Lock()
    
    async def update_state(self, new_state: SessionState) -> None:
        """Update session state"""
        async with self._state_lock:
            old_state = self._state
            self._state = new_state
            self._statistics.state = new_state
            
            # Notify observers
            observers = list(self._state_observers.values())
        
        # Notify outside of lock
        for observer in observers:
            try:
                observer(new_state)
            except Exception as e:
                print(f"State observer error: {e}")
    
    def add_state_observer(self, observer: Callable[[SessionState], None]) -> uuid.UUID:
        """
        Add state observer.
        
        Args:
            observer: Callback function for state changes
            
        Returns:
            Observer ID for removal
        """
        observer_id = uuid.uuid4()
        self._state_observers[observer_id] = observer
        return observer_id
    
    def remove_state_observer(self, observer_id: uuid.UUID) -> None:
        """Remove state observer"""
        self._state_observers.pop(observer_id, None)
    
    def set_error_handler(self, handler: Callable[[Exception], None]) -> None:
        """Set error handler"""
        self._error_handler = handler
    
    async def handle_error(self, error: Exception) -> None:
        """Handle error"""
        await self.update_state(SessionState.ERROR)
        if self._error_handler:
            try:
                self._error_handler(error)
            except Exception:
                pass
    
    def get_statistics(self) -> SessionStatistics:
        """Get session statistics"""
        return self._statistics
    
    @property
    def state(self) -> SessionState:
        """Get current state"""
        return self._state


class AudioCaptureSession(BaseAudioSession):
    """Manages an audio capture session"""
    
    def __init__(self, configuration: CaptureConfiguration):
        """
        Initialize audio capture session.
        
        Args:
            configuration: Capture configuration
        """
        super().__init__()
        self._configuration = configuration
        self._recorder: Optional[StreamingAudioRecorder] = None
        self._outputs: List[AudioOutput] = []
        self._multiplexer = AudioStreamMultiplexer()
        self._session_format = configuration.format
    
    async def start(self) -> None:
        """Start capture session"""
        if self._state not in (SessionState.IDLE, SessionState.STOPPED):
            raise InvalidStateError("Session is already active")
        
        await self.update_state(SessionState.STARTING)
        
        try:
            # Create recorder
            self._recorder = StreamingAudioRecorder(
                sample_rate=int(self._session_format.sample_rate),
                channels=self._session_format.channel_count,
                blocksize=self._configuration.buffer_size,
                device=self._configuration.device
            )
            
            # Set up multiplexer as delegate
            self._recorder.add_delegate(self._multiplexer)
            
            # Start recording
            await self._recorder.start_streaming()
            
            # Update statistics
            self._statistics.format = self._session_format
            
            await self.update_state(SessionState.ACTIVE)
            
        except Exception as e:
            await self.handle_error(e)
            raise
    
    async def stop(self) -> None:
        """Stop capture session"""
        if self._state not in (SessionState.ACTIVE, SessionState.PAUSED):
            raise InvalidStateError("Session is not active")
        
        await self.update_state(SessionState.STOPPING)
        
        # Stop recorder
        if self._recorder:
            await self._recorder.stop_streaming()
        
        # Notify outputs
        for output in self._outputs:
            try:
                await output.finish()
            except Exception:
                pass
        
        # Clear outputs
        self._outputs.clear()
        await self._multiplexer.remove_all_outputs()
        
        await self.update_state(SessionState.STOPPED)
    
    async def pause(self) -> None:
        """Pause capture session"""
        if self._state != SessionState.ACTIVE:
            raise InvalidStateError("Session is not active")
        
        await self.update_state(SessionState.PAUSED)
        await self._multiplexer.set_paused(True)
    
    async def resume(self) -> None:
        """Resume capture session"""
        if self._state != SessionState.PAUSED:
            raise InvalidStateError("Session is not paused")
        
        await self._multiplexer.set_paused(False)
        await self.update_state(SessionState.ACTIVE)
    
    async def add_output(self, output: AudioOutput) -> None:
        """
        Add an output to the session.
        
        Args:
            output: Audio output to add
        """
        if self._state not in (SessionState.ACTIVE, SessionState.PAUSED):
            raise InvalidStateError("Session must be active to add outputs")
        
        # Configure output with session format
        if self._session_format:
            await output.configure(self._session_format)
        
        # Add to multiplexer
        await self._multiplexer.add_output(output)
        
        # Track output
        self._outputs.append(output)
    
    async def remove_output(self, output: AudioOutput) -> None:
        """Remove an output from the session"""
        await self._multiplexer.remove_output(output)
        if output in self._outputs:
            self._outputs.remove(output)
        await output.finish()
    
    def get_outputs(self) -> List[AudioOutput]:
        """Get all active outputs"""
        return list(self._outputs)
    
    def get_configuration(self) -> CaptureConfiguration:
        """Get session configuration"""
        return self._configuration
    
    def get_format(self) -> Optional[AudioFormat]:
        """Get session format"""
        return self._session_format


class AudioPlaybackSession(BaseAudioSession):
    """Manages an audio playback session"""
    
    def __init__(self, configuration: PlaybackConfiguration):
        """
        Initialize audio playback session.
        
        Args:
            configuration: Playback configuration
        """
        super().__init__()
        self._configuration = configuration
        self._player: Optional[StreamingAudioPlayer] = None
        self._input_source = None
        self._session_format = configuration.format
    
    async def start(self) -> None:
        """Start playback session"""
        if self._state not in (SessionState.IDLE, SessionState.STOPPED):
            raise InvalidStateError("Session is already active")
        
        await self.update_state(SessionState.STARTING)
        
        try:
            # Create player
            device_index = self._configuration.device.device_index if self._configuration.device else None
            self._player = StreamingAudioPlayer(
                sample_rate=int(self._session_format.sample_rate),
                channels=self._session_format.channel_count,
                device_index=device_index,
                delay=self._configuration.delay,
                blocksize=self._configuration.buffer_size
            )
            
            # Set volume
            self._player.set_volume(self._configuration.volume)
            
            # Start playback
            await self._player.start_playback()
            
            # Update statistics
            self._statistics.format = self._session_format
            
            await self.update_state(SessionState.ACTIVE)
            
        except Exception as e:
            await self.handle_error(e)
            raise
    
    async def stop(self) -> None:
        """Stop playback session"""
        if self._state not in (SessionState.ACTIVE, SessionState.PAUSED):
            raise InvalidStateError("Session is not active")
        
        await self.update_state(SessionState.STOPPING)
        
        # Stop player
        if self._player:
            await self._player.stop_playback()
        
        # Disconnect input
        if self._input_source:
            await self._input_source.disconnect()
        
        await self.update_state(SessionState.STOPPED)
    
    async def pause(self) -> None:
        """Pause playback session"""
        if self._state != SessionState.ACTIVE:
            raise InvalidStateError("Session is not active")
        
        # TODO: Implement pause in StreamingAudioPlayer
        await self.update_state(SessionState.PAUSED)
    
    async def resume(self) -> None:
        """Resume playback session"""
        if self._state != SessionState.PAUSED:
            raise InvalidStateError("Session is not paused")
        
        # TODO: Implement resume in StreamingAudioPlayer
        await self.update_state(SessionState.ACTIVE)
    
    async def schedule_buffer(self, buffer: AudioBuffer) -> None:
        """Schedule a buffer for playback"""
        if not self._player:
            raise InvalidStateError("Player not initialized")
        
        await self._player.schedule_buffer(buffer.data)
        self._statistics.buffer_count += 1
    
    def set_volume(self, volume: float) -> None:
        """Set playback volume (0.0 to 1.0)"""
        if self._player:
            self._player.set_volume(volume)
    
    def get_volume(self) -> float:
        """Get current volume"""
        if self._player:
            return self._player.get_volume()
        return self._configuration.volume
    
    def get_configuration(self) -> PlaybackConfiguration:
        """Get session configuration"""
        return self._configuration
    
    def get_format(self) -> Optional[AudioFormat]:
        """Get session format"""
        return self._session_format