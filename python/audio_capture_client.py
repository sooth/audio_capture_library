#!/usr/bin/env python3
"""
Audio Capture Client Library

A comprehensive Python client for controlling the macOS Audio Capture Server.
Provides full control over audio recording including device selection,
system audio capture, and file management.
"""

import json
import socket
import time
import uuid
import base64
from typing import Dict, List, Optional, Any, Tuple
from contextlib import contextmanager
import threading
from pathlib import Path


class AudioCaptureError(Exception):
    """Base exception for audio capture operations."""
    pass


class ConnectionError(AudioCaptureError):
    """Raised when unable to connect to server."""
    pass


class ServerError(AudioCaptureError):
    """Raised when server returns an error."""
    pass


class AudioCaptureClient:
    """
    Client for communicating with the Audio Capture Server.
    
    Provides low-level API access for audio recording control.
    """
    
    def __init__(self, host: str = "localhost", port: Optional[int] = None, timeout: float = 30.0,
                 auto_start_server: bool = True, server_path: Optional[str] = None):
        """
        Initialize client.
        
        Args:
            host: Server hostname
            port: Server port (auto-detected if None)
            timeout: Socket timeout in seconds
            auto_start_server: Whether to automatically start the server if not running
            server_path: Path to audio_capture_server binary
        """
        self.host = host
        self.port = port
        self.timeout = timeout
        self.auto_start_server = auto_start_server
        self.server_path = server_path or self._find_server_binary()
        self._socket: Optional[socket.socket] = None
        self._lock = threading.Lock()
        self._server_process = None
        
        # Auto-start server if enabled
        if self.auto_start_server and not self.port:
            self.port = self._ensure_server_running()
        elif not self.port:
            self.port = self._auto_detect_port()
    
    def _find_server_binary(self) -> str:
        """Find the audio_capture_server binary."""
        possible_paths = [
            # Current directory
            "./audio_capture_server",
            # Relative paths
            "../macos/audio_capture_server",
            "./macos/audio_capture_server",
            # Common installation paths
            "/usr/local/bin/audio_capture_server",
            # Development paths
            Path(__file__).parent.parent / "macos" / "audio_capture_server",
        ]
        
        for path in possible_paths:
            path = Path(path)
            if path.exists() and path.is_file():
                return str(path.absolute())
        
        raise AudioCaptureError("Could not find audio_capture_server binary. Please specify server_path.")
    
    def _ensure_server_running(self) -> int:
        """Ensure server is running and return its port."""
        # First check if server is already running
        existing_port = self._check_existing_server()
        if existing_port:
            print(f"✓ Found existing server on port {existing_port}")
            return existing_port
        
        # Start new server
        print(f"🚀 Starting audio capture server...")
        return self._start_server()
    
    def _check_existing_server(self) -> Optional[int]:
        """Check if a server is already running."""
        # Try to read port file
        port = self._auto_detect_port(silent=True)
        if port:
            # Test connection
            test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            test_socket.settimeout(0.5)
            try:
                test_socket.connect((self.host, port))
                test_socket.close()
                return port
            except:
                pass
        return None
    
    def _start_server(self) -> int:
        """Start the server and return its port."""
        import subprocess
        import tempfile
        
        # Create a temporary file for server output
        server_log = tempfile.NamedTemporaryFile(mode='w+', prefix='audio_server_', suffix='.log', delete=False)
        
        # Start server process
        self._server_process = subprocess.Popen(
            [self.server_path],
            stdout=server_log,
            stderr=subprocess.STDOUT,
            cwd=Path(self.server_path).parent
        )
        
        # Wait for server to start and write port file
        port = None
        for i in range(30):  # Wait up to 3 seconds
            time.sleep(0.1)
            
            # Check if process is still running
            if self._server_process.poll() is not None:
                # Server exited, read log
                server_log.seek(0)
                error_output = server_log.read()
                server_log.close()
                raise AudioCaptureError(f"Server failed to start:\n{error_output}")
            
            # Try to read port
            port = self._auto_detect_port(silent=True)
            if port:
                # Test connection
                test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                test_socket.settimeout(0.5)
                try:
                    test_socket.connect((self.host, port))
                    test_socket.close()
                    print(f"✓ Server started on port {port}")
                    server_log.close()
                    return port
                except:
                    pass
        
        # Timeout
        if self._server_process:
            self._server_process.terminate()
        server_log.close()
        raise AudioCaptureError("Server failed to start within timeout")
    
    def _auto_detect_port(self, silent: bool = False) -> Optional[int]:
        """Auto-detect server port from file."""
        try:
            # Look for port file in multiple locations
            port_files = [
                "server_port.txt",
                "../macos/server_port.txt",
                "./macos/server_port.txt",
                Path(self.server_path).parent / "server_port.txt" if self.server_path else None,
            ]
            
            for port_file in port_files:
                if port_file:
                    try:
                        with open(port_file, 'r') as f:
                            detected_port = int(f.read().strip())
                            if not silent:
                                print(f"🔍 Auto-detected server port: {detected_port}")
                            return detected_port
                    except (FileNotFoundError, ValueError):
                        continue
            
            return None
        except:
            return None
    
    def connect(self) -> None:
        """Connect to the server."""
        try:
            self._socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self._socket.settimeout(self.timeout)
            self._socket.connect((self.host, self.port))
        except Exception as e:
            raise ConnectionError(f"Failed to connect to {self.host}:{self.port}: {e}")
    
    def disconnect(self) -> None:
        """Disconnect from the server."""
        if self._socket:
            try:
                self._socket.close()
            except:
                pass
            self._socket = None
    
    def stop_server(self) -> None:
        """Stop the server if we started it."""
        if self._server_process:
            try:
                # Try graceful shutdown first
                try:
                    self.shutdown_server()
                except:
                    pass
                
                # Wait a bit for graceful shutdown
                time.sleep(0.5)
                
                # Force terminate if still running
                if self._server_process.poll() is None:
                    self._server_process.terminate()
                    self._server_process.wait(timeout=2)
            except:
                # Force kill if terminate doesn't work
                try:
                    self._server_process.kill()
                except:
                    pass
            finally:
                self._server_process = None
    
    def _send_request(self, command: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Send a request to the server and get response.
        
        Args:
            command: Command to execute
            params: Optional parameters
            
        Returns:
            Server response data
            
        Raises:
            ConnectionError: If not connected or connection fails
            ServerError: If server returns an error
        """
        if not self._socket:
            raise ConnectionError("Not connected to server")
        
        with self._lock:
            request_id = str(uuid.uuid4())
            request = {
                "id": request_id,
                "command": command,
                "params": params or {}
            }
            
            # Send request
            try:
                request_json = json.dumps(request) + '\n'
                self._socket.send(request_json.encode('utf-8'))
            except Exception as e:
                raise ConnectionError(f"Failed to send request: {e}")
            
            # Receive response
            try:
                response_data = b""
                while b'\n' not in response_data:
                    chunk = self._socket.recv(4096)
                    if not chunk:
                        raise ConnectionError("Server closed connection")
                    response_data += chunk
                
                response_line = response_data.split(b'\n')[0]
                response = json.loads(response_line.decode('utf-8'))
                
                if response["id"] != request_id:
                    raise ServerError("Response ID mismatch")
                
                if not response["success"]:
                    raise ServerError(response.get("error", "Unknown server error"))
                
                return response.get("data", {})
                
            except json.JSONDecodeError as e:
                raise ServerError(f"Invalid JSON response: {e}")
            except Exception as e:
                raise ConnectionError(f"Failed to receive response: {e}")
    
    def list_devices(self) -> List[Dict[str, Any]]:
        """
        Get list of available microphones.
        
        Returns:
            List of devices with 'id' and 'name' keys
        """
        response = self._send_request("LIST_DEVICES")
        devices = response.get("devices", [])
        
        # Clean up the response - handle AnyCodable wrapper from Swift
        cleaned_devices = []
        for device in devices:
            cleaned_device = {}
            for key, value in device.items():
                # Extract actual value from AnyCodable wrapper if present
                if isinstance(value, dict) and "value" in value:
                    cleaned_device[key] = value["value"]
                else:
                    cleaned_device[key] = value
            cleaned_devices.append(cleaned_device)
        
        return cleaned_devices
    
    def start_recording(self, device_id: int, capture_system_audio: bool = False, 
                       output_path: Optional[str] = None) -> Dict[str, Any]:
        """
        Start recording.
        
        Args:
            device_id: Audio device ID to use for microphone
            capture_system_audio: Whether to also capture system audio
            output_path: Optional custom output path
            
        Returns:
            Recording details including output_path and started_at
        """
        params = {
            "device_id": device_id,
            "capture_system_audio": capture_system_audio
        }
        if output_path:
            params["output_path"] = output_path
        
        return self._send_request("START_RECORDING", params)
    
    def stop_recording(self) -> Dict[str, Any]:
        """
        Stop current recording.
        
        Returns:
            Recording results including output_path, duration, and file_size
        """
        return self._send_request("STOP_RECORDING")
    
    def get_status(self) -> Dict[str, Any]:
        """
        Get current recording status.
        
        Returns:
            Status information including is_recording and duration
        """
        return self._send_request("GET_STATUS")
    
    def download_file(self, path: str, local_path: Optional[str] = None) -> str:
        """
        Download a file from the server.
        
        Args:
            path: Remote file path
            local_path: Optional local path to save file
            
        Returns:
            Local file path where file was saved
        """
        response = self._send_request("GET_FILE", {"path": path})
        
        # Decode base64 data
        file_data = base64.b64decode(response["data"])
        
        # Determine local path
        if not local_path:
            local_path = Path(path).name
        
        # Write file
        with open(local_path, 'wb') as f:
            f.write(file_data)
        
        return local_path
    
    def shutdown_server(self) -> None:
        """Gracefully shutdown the server."""
        try:
            self._send_request("SHUTDOWN")
        except (ConnectionError, ServerError):
            # Server shutdown is expected to close connection
            pass
        finally:
            self.disconnect()
    
    def __enter__(self):
        """Context manager entry."""
        self.connect()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.disconnect()
        # Only stop server if we started it
        if self.auto_start_server and self._server_process:
            self.stop_server()


class AsyncAudioRecorder:
    """
    High-level async interface for audio recording.
    
    Provides convenient methods for recording with automatic cleanup.
    """
    
    def __init__(self, client: AudioCaptureClient):
        """
        Initialize recorder.
        
        Args:
            client: Connected AudioCaptureClient instance
        """
        self.client = client
        self._recording = False
    
    def start(self, device_id: int, capture_system_audio: bool = False,
              output_path: Optional[str] = None) -> Dict[str, Any]:
        """Start recording with the specified device."""
        if self._recording:
            raise AudioCaptureError("Recording already in progress")
        
        result = self.client.start_recording(device_id, capture_system_audio, output_path)
        self._recording = True
        return result
    
    def stop(self) -> Dict[str, Any]:
        """Stop recording and return results."""
        if not self._recording:
            raise AudioCaptureError("No recording in progress")
        
        result = self.client.stop_recording()
        self._recording = False
        return result
    
    def record_for_duration(self, device_id: int, duration: float,
                           capture_system_audio: bool = False,
                           output_path: Optional[str] = None) -> Dict[str, Any]:
        """
        Record for a specific duration.
        
        Args:
            device_id: Audio device ID
            duration: Recording duration in seconds
            capture_system_audio: Whether to capture system audio
            output_path: Optional output path
            
        Returns:
            Recording results
        """
        self.start(device_id, capture_system_audio, output_path)
        try:
            time.sleep(duration)
            return self.stop()
        except:
            # Ensure recording is stopped on error
            if self._recording:
                try:
                    self.stop()
                except:
                    pass
            raise
    
    @property
    def is_recording(self) -> bool:
        """Check if currently recording."""
        return self._recording
    
    def get_status(self) -> Dict[str, Any]:
        """Get current status from server."""
        return self.client.get_status()


# Convenience functions
def list_microphones(host: str = "localhost", port: Optional[int] = None,
                    auto_start_server: bool = True) -> List[Dict[str, Any]]:
    """
    Quick function to list available microphones.
    
    Args:
        host: Server hostname
        port: Server port (auto-detected if None)
        auto_start_server: Whether to auto-start server if not running
    
    Returns:
        List of microphone devices
    """
    with AudioCaptureClient(host, port, auto_start_server=auto_start_server) as client:
        return client.list_devices()


def record_audio(device_id: int, duration: float, capture_system_audio: bool = False,
                output_path: Optional[str] = None, host: str = "localhost", 
                port: Optional[int] = None, auto_start_server: bool = True) -> str:
    """
    Convenience function to record audio for a specific duration.
    
    Args:
        device_id: Microphone device ID
        duration: Recording duration in seconds
        capture_system_audio: Whether to capture system audio
        output_path: Optional output path
        host: Server host
        port: Server port
        auto_start_server: Whether to auto-start server if not running
        
    Returns:
        Path to recorded file
    """
    with AudioCaptureClient(host, port, auto_start_server=auto_start_server) as client:
        recorder = AsyncAudioRecorder(client)
        result = recorder.record_for_duration(
            device_id, duration, capture_system_audio, output_path
        )
        return result["output_path"]


def find_device_by_name(name: str, host: str = "localhost", port: Optional[int] = None) -> Optional[Dict[str, Any]]:
    """
    Find a device by name (case-insensitive partial match).
    
    Args:
        name: Device name to search for
        host: Server host
        port: Server port
        
    Returns:
        Device info if found, None otherwise
    """
    devices = list_microphones(host, port)
    name_lower = name.lower()
    
    for device in devices:
        if name_lower in device["name"].lower():
            return device
    
    return None


@contextmanager
def audio_recording_session(host: str = "localhost", port: Optional[int] = None):
    """
    Context manager for audio recording sessions.
    
    Automatically connects and disconnects from server.
    
    Yields:
        AudioCaptureClient instance
    """
    client = AudioCaptureClient(host, port)
    try:
        client.connect()
        yield client
    finally:
        client.disconnect()


class AudioCaptureManager:
    """
    High-level manager for audio capture operations.
    
    Provides the most convenient interface for common recording tasks.
    """
    
    def __init__(self, host: str = "localhost", port: Optional[int] = None):
        """Initialize manager."""
        self.host = host
        self.port = port
        self._client: Optional[AudioCaptureClient] = None
        self._recorder: Optional[AsyncAudioRecorder] = None
    
    def __enter__(self):
        """Context manager entry."""
        self._client = AudioCaptureClient(self.host, self.port)
        self._client.connect()
        self._recorder = AsyncAudioRecorder(self._client)
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        if self._recorder and self._recorder.is_recording:
            try:
                self._recorder.stop()
            except:
                pass
        
        if self._client:
            self._client.disconnect()
    
    def list_devices(self) -> List[Dict[str, Any]]:
        """List available devices."""
        return self._client.list_devices()
    
    def find_device(self, name: str) -> Optional[Dict[str, Any]]:
        """Find device by name."""
        devices = self.list_devices()
        name_lower = name.lower()
        
        for device in devices:
            if name_lower in device["name"].lower():
                return device
        return None
    
    def record(self, device_name_or_id, duration: float = 10.0,
              capture_system_audio: bool = False, output_path: Optional[str] = None) -> Dict[str, Any]:
        """
        Record audio using device name or ID.
        
        Args:
            device_name_or_id: Device name (string) or ID (int)
            duration: Recording duration in seconds
            capture_system_audio: Whether to capture system audio
            output_path: Optional output path
            
        Returns:
            Recording results
        """
        # Resolve device ID
        if isinstance(device_name_or_id, str):
            device = self.find_device(device_name_or_id)
            if not device:
                raise AudioCaptureError(f"Device not found: {device_name_or_id}")
            device_id = device["id"]
        else:
            device_id = device_name_or_id
        
        return self._recorder.record_for_duration(
            device_id, duration, capture_system_audio, output_path
        )
    
    def start_recording(self, device_name_or_id, capture_system_audio: bool = False,
                       output_path: Optional[str] = None) -> Dict[str, Any]:
        """Start recording (manual control)."""
        if isinstance(device_name_or_id, str):
            device = self.find_device(device_name_or_id)
            if not device:
                raise AudioCaptureError(f"Device not found: {device_name_or_id}")
            device_id = device["id"]
        else:
            device_id = device_name_or_id
        
        return self._recorder.start(device_id, capture_system_audio, output_path)
    
    def stop_recording(self) -> Dict[str, Any]:
        """Stop recording."""
        return self._recorder.stop()
    
    def get_status(self) -> Dict[str, Any]:
        """Get current status."""
        return self._recorder.get_status()
    
    @property
    def is_recording(self) -> bool:
        """Check if recording."""
        return self._recorder.is_recording if self._recorder else False


if __name__ == "__main__":
    # Example usage
    print("Audio Capture Client Library")
    print("===========================")
    
    try:
        # List devices
        print("\nAvailable microphones:")
        devices = list_microphones()
        for i, device in enumerate(devices):
            print(f"  {i+1}. {device['name']} (ID: {device['id']})")
        
        if not devices:
            print("No microphones found!")
            exit(1)
        
        # Use the first device for a test recording
        test_device = devices[0]
        print(f"\nTesting with: {test_device['name']}")
        
        # Quick 3-second recording
        output_file = record_audio(
            device_id=test_device["id"],
            duration=3.0,
            capture_system_audio=True
        )
        
        print(f"✓ Test recording completed: {output_file}")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        print("\nMake sure the audio_capture_server is running!")