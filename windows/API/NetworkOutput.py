"""
NetworkOutput - Streams audio over TCP/IP network

This module creates a TCP server that streams audio buffers to connected clients.
It's designed for inter-process communication, particularly with Python clients
that want to receive real-time audio.

Protocol:
- Header: Format information (sent once per connection)
- Packets: Audio data with timestamps
"""

import asyncio
import struct
import time
from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional, Set, AsyncIterator
import numpy as np

from .AudioFormat import AudioFormat, AudioBuffer
from .AudioError import NetworkConnectionFailedError, StreamingProtocolError


# Protocol constants
PROTOCOL_MAGIC = b'AUDIO'
PROTOCOL_VERSION = 1
PACKET_TYPE_AUDIO = 0x01
PACKET_TYPE_FORMAT = 0x02
PACKET_TYPE_END = 0xFF


@dataclass
class NetworkStatistics:
    """Network streaming statistics"""
    connection_count: int
    packets_sent: int
    bytes_sent: int
    duration: float
    throughput_mbps: float


class NetworkAudioServer:
    """TCP server for streaming audio to network clients"""
    
    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = 9876,
        format: Optional[AudioFormat] = None
    ):
        """
        Initialize network audio server.
        
        Args:
            host: Host address to bind to
            port: Port number to listen on
            format: Audio format (can be set later)
        """
        self.host = host
        self.port = port
        self.format = format
        
        # Server state
        self._server = None
        self._clients: Set[asyncio.StreamWriter] = set()
        self._is_running = False
        
        # Statistics
        self._packets_sent = 0
        self._bytes_sent = 0
        self._start_time = time.time()
        
        # Lock for client list
        self._clients_lock = asyncio.Lock()
    
    async def start(self) -> None:
        """Start the TCP server"""
        if self._is_running:
            return
        
        self._server = await asyncio.start_server(
            self._handle_client,
            self.host,
            self.port
        )
        
        self._is_running = True
        self._start_time = time.time()
        
        # Get actual port if 0 was specified
        actual_port = self._server.sockets[0].getsockname()[1]
        print(f"NetworkOutput: Started TCP server on {self.host}:{actual_port}")
    
    async def stop(self) -> None:
        """Stop the TCP server"""
        if not self._is_running:
            return
        
        # Send end packet to all clients
        end_packet = self._create_end_packet()
        await self._broadcast_data(end_packet)
        
        # Close all client connections
        async with self._clients_lock:
            for writer in list(self._clients):
                try:
                    writer.close()
                    await writer.wait_closed()
                except Exception:
                    pass
            self._clients.clear()
        
        # Stop server
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        
        self._is_running = False
        
        # Print statistics
        duration = time.time() - self._start_time
        mb_sent = self._bytes_sent / (1024 * 1024)
        print(f"NetworkOutput: Stopped")
        print(f"  Packets sent: {self._packets_sent}")
        print(f"  Data sent: {mb_sent:.2f} MB")
        print(f"  Duration: {duration:.1f}s")
        if duration > 0:
            print(f"  Throughput: {mb_sent / duration:.2f} MB/s")
    
    async def set_format(self, format: AudioFormat) -> None:
        """Set or update the audio format"""
        self.format = format
        
        # Send format header to all connected clients
        if self._is_running:
            header = self._create_format_header(format)
            await self._broadcast_data(header)
    
    async def broadcast_buffer(self, buffer: AudioBuffer) -> None:
        """
        Broadcast audio buffer to all connected clients.
        
        Args:
            buffer: Audio buffer to broadcast
        """
        if not self._is_running:
            raise NetworkConnectionFailedError("Server is not running")
        
        # Create audio packet
        packet = self._create_audio_packet(buffer)
        
        # Send to all clients
        await self._broadcast_data(packet)
        
        self._packets_sent += 1
        self._bytes_sent += len(packet)
    
    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter
    ) -> None:
        """Handle a new client connection"""
        client_addr = writer.get_extra_info('peername')
        print(f"NetworkOutput: New client connected from {client_addr}")
        
        # Add to client list
        async with self._clients_lock:
            self._clients.add(writer)
        
        try:
            # Send format header if available
            if self.format:
                header = self._create_format_header(self.format)
                writer.write(header)
                await writer.drain()
                print(f"NetworkOutput: Sent format header to {client_addr}")
            
            # Keep connection alive until client disconnects
            while True:
                # Read from client (for ping/keepalive)
                try:
                    data = await asyncio.wait_for(reader.read(1), timeout=30.0)
                    if not data:
                        break
                except asyncio.TimeoutError:
                    # Send keepalive
                    try:
                        writer.write(b'\x00')
                        await writer.drain()
                    except Exception:
                        break
                
        except Exception as e:
            print(f"NetworkOutput: Client error: {e}")
        
        finally:
            # Remove from client list
            async with self._clients_lock:
                self._clients.discard(writer)
            
            # Close connection
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass
            
            print(f"NetworkOutput: Client disconnected. Active connections: {len(self._clients)}")
    
    async def _broadcast_data(self, data: bytes) -> None:
        """Broadcast data to all connected clients"""
        disconnected = []
        
        async with self._clients_lock:
            for writer in self._clients:
                try:
                    writer.write(data)
                    await writer.drain()
                except Exception as e:
                    print(f"NetworkOutput: Failed to send to client: {e}")
                    disconnected.append(writer)
        
        # Remove disconnected clients
        if disconnected:
            async with self._clients_lock:
                for writer in disconnected:
                    self._clients.discard(writer)
                    try:
                        writer.close()
                        await writer.wait_closed()
                    except Exception:
                        pass
    
    def _create_format_header(self, format: AudioFormat) -> bytes:
        """Create format header packet"""
        header = bytearray()
        
        # Magic bytes
        header.extend(PROTOCOL_MAGIC)
        
        # Version
        header.append(PROTOCOL_VERSION)
        
        # Packet type
        header.append(PACKET_TYPE_FORMAT)
        
        # Sample rate (4 bytes, little-endian)
        header.extend(struct.pack('<I', int(format.sample_rate)))
        
        # Channels (2 bytes, little-endian)
        header.extend(struct.pack('<H', format.channel_count))
        
        # Bit depth (2 bytes, little-endian)
        header.extend(struct.pack('<H', format.bit_depth))
        
        # Format flags (4 bytes, little-endian)
        flags = 0
        if format.is_float:
            flags |= 0x01
        if format.is_interleaved:
            flags |= 0x02
        header.extend(struct.pack('<I', flags))
        
        return bytes(header)
    
    def _create_audio_packet(self, buffer: AudioBuffer) -> bytes:
        """Create audio data packet"""
        packet = bytearray()
        
        # Packet type
        packet.append(PACKET_TYPE_AUDIO)
        
        # Timestamp (8 bytes, microseconds since start)
        timestamp_us = int((time.time() - self._start_time) * 1_000_000)
        packet.extend(struct.pack('<Q', timestamp_us))
        
        # Frame count (4 bytes)
        frame_count = buffer.frame_count
        packet.extend(struct.pack('<I', frame_count))
        
        # Audio data
        audio_data = self._extract_audio_data(buffer)
        packet.extend(audio_data)
        
        return bytes(packet)
    
    def _create_end_packet(self) -> bytes:
        """Create end-of-stream packet"""
        packet = bytearray()
        
        # Packet type
        packet.append(PACKET_TYPE_END)
        
        # Final timestamp
        timestamp_us = int((time.time() - self._start_time) * 1_000_000)
        packet.extend(struct.pack('<Q', timestamp_us))
        
        return bytes(packet)
    
    def _extract_audio_data(self, buffer: AudioBuffer) -> bytes:
        """Extract audio data from buffer for network transport"""
        data = buffer.data
        format = buffer.format
        
        # Ensure data is in the correct format for transport
        if format.is_float:
            # Float32 format
            if format.is_interleaved or data.ndim == 1:
                # Already interleaved or mono
                return data.astype('<f4').tobytes()
            else:
                # Non-interleaved - need to interleave
                interleaved = buffer.to_interleaved()
                return interleaved.data.astype('<f4').tobytes()
        else:
            # Integer format
            if format.bit_depth == 16:
                dtype = '<i2'
            elif format.bit_depth == 32:
                dtype = '<i4'
            else:
                dtype = '<i4'  # Default to 32-bit
            
            if format.is_interleaved or data.ndim == 1:
                return data.astype(dtype).tobytes()
            else:
                interleaved = buffer.to_interleaved()
                return interleaved.data.astype(dtype).tobytes()
    
    def get_connection_count(self) -> int:
        """Get current number of connected clients"""
        return len(self._clients)
    
    def get_statistics(self) -> NetworkStatistics:
        """Get network statistics"""
        duration = time.time() - self._start_time
        throughput_mbps = (self._bytes_sent / (1024 * 1024) / duration) if duration > 0 else 0
        
        return NetworkStatistics(
            connection_count=len(self._clients),
            packets_sent=self._packets_sent,
            bytes_sent=self._bytes_sent,
            duration=duration,
            throughput_mbps=throughput_mbps
        )


class NetworkAudioClient:
    """TCP client for receiving audio from network server"""
    
    def __init__(self, host: str = "localhost", port: int = 9876):
        """
        Initialize network audio client.
        
        Args:
            host: Server host address
            port: Server port number
        """
        self.host = host
        self.port = port
        
        self._reader = None
        self._writer = None
        self._format = None
        self._is_connected = False
    
    async def connect(self) -> AudioFormat:
        """
        Connect to audio server and receive format header.
        
        Returns:
            Audio format from server
        """
        if self._is_connected:
            return self._format
        
        try:
            self._reader, self._writer = await asyncio.open_connection(
                self.host, self.port
            )
            
            # Read format header
            header = await self._read_format_header()
            self._format = header
            self._is_connected = True
            
            print(f"NetworkAudioClient: Connected to {self.host}:{self.port}")
            print(f"  Format: {self._format.description}")
            
            return self._format
            
        except Exception as e:
            raise NetworkConnectionFailedError(f"Failed to connect: {e}")
    
    async def disconnect(self) -> None:
        """Disconnect from server"""
        if not self._is_connected:
            return
        
        if self._writer:
            self._writer.close()
            await self._writer.wait_closed()
        
        self._reader = None
        self._writer = None
        self._is_connected = False
        
        print("NetworkAudioClient: Disconnected")
    
    async def receive_audio(self) -> AsyncIterator[AudioBuffer]:
        """
        Receive audio buffers from server.
        
        Yields:
            Audio buffers as they arrive
        """
        if not self._is_connected:
            raise NetworkConnectionFailedError("Not connected to server")
        
        while self._is_connected:
            try:
                # Read packet type
                packet_type = await self._reader.read(1)
                if not packet_type:
                    break
                
                packet_type = packet_type[0]
                
                if packet_type == PACKET_TYPE_AUDIO:
                    # Read audio packet
                    buffer = await self._read_audio_packet()
                    if buffer:
                        yield buffer
                        
                elif packet_type == PACKET_TYPE_END:
                    # End of stream
                    await self._reader.read(8)  # Skip timestamp
                    break
                    
                elif packet_type == 0x00:
                    # Keepalive - ignore
                    continue
                    
                else:
                    print(f"NetworkAudioClient: Unknown packet type: {packet_type}")
                    
            except Exception as e:
                print(f"NetworkAudioClient: Receive error: {e}")
                break
        
        await self.disconnect()
    
    async def _read_format_header(self) -> AudioFormat:
        """Read and parse format header"""
        # Read magic bytes
        magic = await self._reader.read(len(PROTOCOL_MAGIC))
        if magic != PROTOCOL_MAGIC:
            raise StreamingProtocolError("Invalid protocol magic")
        
        # Read version
        version = await self._reader.read(1)
        if version[0] != PROTOCOL_VERSION:
            raise StreamingProtocolError(f"Unsupported protocol version: {version[0]}")
        
        # Read packet type
        packet_type = await self._reader.read(1)
        if packet_type[0] != PACKET_TYPE_FORMAT:
            raise StreamingProtocolError("Expected format packet")
        
        # Read format data
        format_data = await self._reader.read(14)  # 4 + 2 + 2 + 4 bytes
        
        sample_rate, channels, bit_depth, flags = struct.unpack('<IHHI', format_data)
        
        is_float = bool(flags & 0x01)
        is_interleaved = bool(flags & 0x02)
        
        return AudioFormat(
            sample_rate=float(sample_rate),
            channel_count=channels,
            bit_depth=bit_depth,
            is_interleaved=is_interleaved,
            is_float=is_float
        )
    
    async def _read_audio_packet(self) -> Optional[AudioBuffer]:
        """Read and parse audio packet"""
        # Read header
        header = await self._reader.read(12)  # 8 + 4 bytes
        if len(header) < 12:
            return None
        
        timestamp_us, frame_count = struct.unpack('<QI', header)
        
        # Calculate data size
        bytes_per_sample = self._format.bit_depth // 8
        total_samples = frame_count * self._format.channel_count
        data_size = total_samples * bytes_per_sample
        
        # Read audio data
        audio_data = await self._reader.read(data_size)
        if len(audio_data) < data_size:
            return None
        
        # Convert to numpy array
        if self._format.is_float:
            dtype = '<f4' if self._format.bit_depth == 32 else '<f8'
        else:
            if self._format.bit_depth == 16:
                dtype = '<i2'
            elif self._format.bit_depth == 32:
                dtype = '<i4'
            else:
                dtype = '<i4'
        
        samples = np.frombuffer(audio_data, dtype=dtype)
        
        # Reshape based on format
        if self._format.is_interleaved and self._format.channel_count > 1:
            # Reshape from interleaved to (frames, channels)
            samples = samples.reshape(-1, self._format.channel_count)
        
        # Create timestamp
        timestamp = datetime.fromtimestamp(self._start_time + timestamp_us / 1_000_000)
        
        return AudioBuffer(
            data=samples,
            format=self._format,
            timestamp=timestamp
        )