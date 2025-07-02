"""
AudioDevice - Represents an audio input or output device on Windows

This module encapsulates all relevant information about an audio device,
including its capabilities, supported formats, and current status.
"""

import asyncio
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum, auto
from typing import List, Optional, Callable, Dict, Any
import uuid

try:
    import sounddevice as sd
    try:
        import pyaudiowpatch as pyaudio  # For loopback support
        HAS_PYAUDIOWPATCH = True
    except ImportError:
        import pyaudio  # Fall back to regular PyAudio
        HAS_PYAUDIOWPATCH = False
        print("Warning: PyAudioWPatch not found, loopback recording will not be available")
    from pycaw.pycaw import AudioUtilities, IMMDeviceEnumerator, EDataFlow, ERole, DEVICE_STATE
except ImportError as e:
    print(f"Required audio libraries not installed: {e}")
    print("Please install: pip install sounddevice PyAudioWPatch pycaw")
    raise

from .AudioFormat import AudioFormat
from .AudioError import (
    DeviceNotFoundError, DeviceEnumerationFailedError,
    DeviceSelectionFailedError, InvalidDeviceError
)


class DeviceType(Enum):
    """Device type enumeration"""
    INPUT = "input"
    OUTPUT = "output"
    LOOPBACK = "loopback"  # Windows-specific: system audio capture


class DeviceStatus(Enum):
    """Device status"""
    CONNECTED = "connected"
    DISCONNECTED = "disconnected"
    UNAVAILABLE = "unavailable"


class DeviceAPI(Enum):
    """Windows audio APIs"""
    MME = "MME"
    DIRECTSOUND = "DirectSound"
    WASAPI = "WASAPI"
    WDM_KS = "WDM-KS"
    ASIO = "ASIO"


@dataclass
class DeviceCapabilities:
    """Device capabilities"""
    hardware_monitoring: bool
    exclusive_mode: bool
    min_latency: float  # seconds
    max_channels: int
    sample_rates: List[float]
    supports_loopback: bool = False


@dataclass
class AudioDevice:
    """
    Represents an audio input or output device.
    
    Attributes:
        id: Unique device identifier
        name: Human-readable device name
        manufacturer: Device manufacturer (if available)
        type: Device type (input/output/loopback)
        device_index: sounddevice device index
        wasapi_id: Windows Audio Session API ID
        supported_formats: List of supported audio formats
        is_default: Whether this is the default device for its type
        status: Current device status
        capabilities: Device capabilities
        host_api: Audio API used by this device
    """
    id: str
    name: str
    manufacturer: Optional[str]
    type: DeviceType
    device_index: int
    wasapi_id: Optional[str]
    supported_formats: List[AudioFormat]
    is_default: bool
    status: DeviceStatus
    capabilities: DeviceCapabilities
    host_api: DeviceAPI


class DeviceChangeEvent(Enum):
    """Device change event types"""
    DEVICE_ADDED = auto()
    DEVICE_REMOVED = auto()
    DEFAULT_CHANGED = auto()


@dataclass
class DeviceChange:
    """Device change information"""
    event: DeviceChangeEvent
    device: Optional[AudioDevice]
    device_type: Optional[DeviceType]


class AudioDeviceManager:
    """Manages audio device enumeration and selection on Windows"""
    
    def __init__(self):
        """Initialize the device manager"""
        self._device_change_handler: Optional[Callable[[DeviceChange], None]] = None
        self._cached_devices: List[AudioDevice] = []
        self._last_scan_time: Optional[datetime] = None
        self._scan_interval = 1.0  # seconds
        self._pyaudio = pyaudio.PyAudio()
        self._monitoring_task: Optional[asyncio.Task] = None
        
    def __del__(self):
        """Cleanup resources"""
        if hasattr(self, '_pyaudio'):
            self._pyaudio.terminate()
    
    async def start_monitoring(self):
        """Start monitoring for device changes"""
        if self._monitoring_task is None:
            self._monitoring_task = asyncio.create_task(self._monitor_devices())
    
    async def stop_monitoring(self):
        """Stop monitoring for device changes"""
        if self._monitoring_task:
            self._monitoring_task.cancel()
            try:
                await self._monitoring_task
            except asyncio.CancelledError:
                pass
            self._monitoring_task = None
    
    def get_playback_devices(self) -> List[AudioDevice]:
        """Get all available playback devices"""
        self._refresh_device_list_if_needed()
        return [d for d in self._cached_devices if d.type == DeviceType.OUTPUT]
    
    def get_recording_devices(self) -> List[AudioDevice]:
        """Get all available recording devices (including loopback)"""
        self._refresh_device_list_if_needed()
        return [d for d in self._cached_devices if d.type in (DeviceType.INPUT, DeviceType.LOOPBACK)]
    
    def get_device_by_id(self, device_id: str) -> Optional[AudioDevice]:
        """Get device by ID"""
        self._refresh_device_list_if_needed()
        return next((d for d in self._cached_devices if d.id == device_id), None)
    
    def set_playback_device(self, device: AudioDevice) -> None:
        """Set the default playback device"""
        if device.type != DeviceType.OUTPUT:
            raise InvalidDeviceError("Device is not an output device")
        
        # Note: Setting default device programmatically on Windows requires
        # elevated permissions and is not straightforward. This is a limitation.
        # Users typically need to set default devices through Windows settings.
        print(f"Note: Setting default device '{device.name}' requires Windows audio settings")
    
    def set_recording_device(self, device: AudioDevice) -> None:
        """Set the default recording device"""
        if device.type not in (DeviceType.INPUT, DeviceType.LOOPBACK):
            raise InvalidDeviceError("Device is not an input device")
        
        if device.type == DeviceType.LOOPBACK:
            # Loopback devices don't change hardware settings
            return
        
        # Same limitation as playback devices
        print(f"Note: Setting default device '{device.name}' requires Windows audio settings")
    
    def get_current_playback_device(self) -> Optional[AudioDevice]:
        """Get current default playback device"""
        self._refresh_device_list_if_needed()
        return next((d for d in self._cached_devices if d.type == DeviceType.OUTPUT and d.is_default), None)
    
    def get_current_recording_device(self) -> Optional[AudioDevice]:
        """Get current default recording device"""
        self._refresh_device_list_if_needed()
        return next((d for d in self._cached_devices if d.type == DeviceType.INPUT and d.is_default), None)
    
    def set_device_change_handler(self, handler: Callable[[DeviceChange], None]) -> None:
        """Set device change handler"""
        self._device_change_handler = handler
    
    def remove_device_change_handler(self) -> None:
        """Remove device change handler"""
        self._device_change_handler = None
    
    def _should_refresh_device_list(self) -> bool:
        """Check if device list should be refreshed"""
        if self._last_scan_time is None:
            return True
        
        elapsed = (datetime.now() - self._last_scan_time).total_seconds()
        return elapsed > self._scan_interval
    
    def _refresh_device_list_if_needed(self) -> None:
        """Refresh device list if needed"""
        if self._should_refresh_device_list():
            self._refresh_device_list()
    
    def _refresh_device_list(self) -> None:
        """Refresh the cached device list"""
        try:
            devices = []
            
            # Get devices from sounddevice
            sd_devices = sd.query_devices()
            
            for idx, device_info in enumerate(sd_devices):
                try:
                    audio_device = self._create_audio_device_from_sounddevice(idx, device_info)
                    if audio_device:
                        devices.append(audio_device)
                except Exception as e:
                    print(f"Failed to create AudioDevice for index {idx}: {e}")
            
            # If PyAudioWPatch is available, add loopback devices
            if HAS_PYAUDIOWPATCH and hasattr(self._pyaudio, 'get_loopback_device_info_generator'):
                try:
                    # Get loopback devices from PyAudioWPatch
                    for loopback_info in self._pyaudio.get_loopback_device_info_generator():
                        loopback_device = self._create_loopback_device_from_pyaudiowpatch(loopback_info)
                        if loopback_device:
                            devices.append(loopback_device)
                except Exception as e:
                    print(f"Error enumerating loopback devices: {e}")
            
            self._cached_devices = devices
            self._last_scan_time = datetime.now()
            
        except Exception as e:
            raise DeviceEnumerationFailedError() from e
    
    def _create_audio_device_from_sounddevice(self, index: int, info: Dict[str, Any]) -> Optional[AudioDevice]:
        """Create AudioDevice from sounddevice info"""
        # Skip devices with 0 channels
        if info['max_input_channels'] == 0 and info['max_output_channels'] == 0:
            return None
        
        # Determine device type
        if info['max_output_channels'] > 0 and info['max_input_channels'] == 0:
            device_type = DeviceType.OUTPUT
        elif info['max_input_channels'] > 0 and info['max_output_channels'] == 0:
            device_type = DeviceType.INPUT
        else:
            # Skip devices that are both input and output for now
            return None
        
        # Get host API info
        host_api_info = sd.query_hostapis(info['hostapi'])
        host_api = self._get_device_api(host_api_info['name'])
        
        # Generate unique ID
        device_id = f"{host_api.value}_{index}_{info['name'].replace(' ', '_')}"
        
        # Get supported formats
        supported_formats = self._get_supported_formats(info, device_type)
        
        # Check if default
        is_default = (
            (device_type == DeviceType.OUTPUT and index == sd.default.device[1]) or
            (device_type == DeviceType.INPUT and index == sd.default.device[0])
        )
        
        # Get capabilities
        capabilities = DeviceCapabilities(
            hardware_monitoring=False,
            exclusive_mode=(host_api == DeviceAPI.WASAPI),
            min_latency=info.get('default_low_output_latency', 0.01) if device_type == DeviceType.OUTPUT 
                       else info.get('default_low_input_latency', 0.01),
            max_channels=info['max_output_channels'] if device_type == DeviceType.OUTPUT 
                        else info['max_input_channels'],
            sample_rates=[44100.0, 48000.0, 96000.0],  # Common rates
            supports_loopback=(host_api == DeviceAPI.WASAPI and device_type == DeviceType.OUTPUT)
        )
        
        return AudioDevice(
            id=device_id,
            name=info['name'],
            manufacturer=None,  # Not available from sounddevice
            type=device_type,
            device_index=index,
            wasapi_id=None,  # Would need pycaw for this
            supported_formats=supported_formats,
            is_default=is_default,
            status=DeviceStatus.CONNECTED,
            capabilities=capabilities,
            host_api=host_api
        )
    
    def _create_loopback_device_from_pyaudiowpatch(self, loopback_info: Dict[str, Any]) -> Optional[AudioDevice]:
        """Create a loopback device from PyAudioWPatch info"""
        try:
            # Generate unique ID
            device_id = f"loopback_{loopback_info['index']}_{loopback_info['name'].replace(' ', '_')}"
            
            # Get supported formats (use common formats for loopback)
            supported_formats = [
                AudioFormat(
                    sample_rate=float(loopback_info['defaultSampleRate']),
                    channel_count=loopback_info['maxInputChannels'],
                    bit_depth=16,
                    is_interleaved=True,
                    is_float=False
                ),
                AudioFormat(
                    sample_rate=float(loopback_info['defaultSampleRate']),
                    channel_count=loopback_info['maxInputChannels'],
                    bit_depth=32,
                    is_interleaved=True,
                    is_float=True
                )
            ]
            
            # Get host API
            host_api_info = self._pyaudio.get_host_api_info_by_index(loopback_info['hostApi'])
            host_api = self._get_device_api(host_api_info['name'])
            
            # Create capabilities
            capabilities = DeviceCapabilities(
                hardware_monitoring=False,
                exclusive_mode=False,
                min_latency=loopback_info.get('defaultLowInputLatency', 0.020),
                max_channels=loopback_info['maxInputChannels'],
                sample_rates=[float(loopback_info['defaultSampleRate'])],
                supports_loopback=True
            )
            
            return AudioDevice(
                id=device_id,
                name=loopback_info['name'],
                manufacturer=None,
                type=DeviceType.LOOPBACK,
                device_index=loopback_info['index'],  # PyAudioWPatch index
                wasapi_id=None,
                supported_formats=supported_formats,
                is_default=False,
                status=DeviceStatus.CONNECTED,
                capabilities=capabilities,
                host_api=host_api
            )
        except Exception as e:
            print(f"Error creating loopback device: {e}")
            return None
    
    def _get_device_api(self, api_name: str) -> DeviceAPI:
        """Convert API name to DeviceAPI enum"""
        api_map = {
            "MME": DeviceAPI.MME,
            "Windows DirectSound": DeviceAPI.DIRECTSOUND,
            "Windows WASAPI": DeviceAPI.WASAPI,
            "Windows WDM-KS": DeviceAPI.WDM_KS,
            "ASIO": DeviceAPI.ASIO
        }
        return api_map.get(api_name, DeviceAPI.MME)
    
    def _get_supported_formats(self, device_info: Dict[str, Any], device_type: DeviceType) -> List[AudioFormat]:
        """Get supported formats for a device"""
        # Common formats that most devices support
        formats = []
        
        # Standard sample rates to test
        sample_rates = [44100.0, 48000.0]
        if device_info.get('default_samplerate', 44100) > 48000:
            sample_rates.append(96000.0)
        
        max_channels = (device_info['max_output_channels'] if device_type == DeviceType.OUTPUT 
                       else device_info['max_input_channels'])
        
        for rate in sample_rates:
            # 16-bit integer
            formats.append(AudioFormat(
                sample_rate=rate,
                channel_count=min(2, max_channels),
                bit_depth=16,
                is_interleaved=True,
                is_float=False
            ))
            
            # 32-bit float (common for WASAPI)
            formats.append(AudioFormat(
                sample_rate=rate,
                channel_count=min(2, max_channels),
                bit_depth=32,
                is_interleaved=False,
                is_float=True
            ))
        
        return formats
    
    async def _monitor_devices(self):
        """Monitor for device changes"""
        previous_devices = set()
        
        while True:
            try:
                # Get current devices
                self._refresh_device_list()
                current_devices = {d.id for d in self._cached_devices}
                
                # Check for changes
                added = current_devices - previous_devices
                removed = previous_devices - current_devices
                
                # Notify handler
                if self._device_change_handler:
                    for device_id in added:
                        device = self.get_device_by_id(device_id)
                        if device:
                            self._device_change_handler(DeviceChange(
                                event=DeviceChangeEvent.DEVICE_ADDED,
                                device=device,
                                device_type=device.type
                            ))
                    
                    for device_id in removed:
                        self._device_change_handler(DeviceChange(
                            event=DeviceChangeEvent.DEVICE_REMOVED,
                            device=None,
                            device_type=None
                        ))
                
                previous_devices = current_devices
                
            except Exception as e:
                print(f"Error monitoring devices: {e}")
            
            await asyncio.sleep(2.0)  # Check every 2 seconds