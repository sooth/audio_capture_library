#!/usr/bin/env python3
"""
Windows AudioCaptureKit Demo Application

This example demonstrates the main features of the Windows AudioCaptureKit:
- Device enumeration
- Audio recording to file
- System audio loopback recording
- Real-time audio streaming
- Network audio streaming
"""

import asyncio
import sys
import os
from pathlib import Path
from datetime import datetime

# Add parent directory to path for imports
sys.path.append(str(Path(__file__).parent.parent.parent))

from windows.API import (
    AudioCaptureKit,
    DeviceType,
    FileOutput,
    CallbackOutput,
    NetworkOutput,
    SessionState,
    AudioLoopbackPermissionError,
    DeviceNotFoundError
)


class AudioCaptureDemo:
    """Demo application for Windows AudioCaptureKit"""
    
    def __init__(self):
        self.kit = AudioCaptureKit()
        self.current_session = None
        
    async def list_devices(self):
        """List all available audio devices"""
        print("\n=== Audio Devices ===")
        
        print("\nPlayback Devices:")
        playback_devices = self.kit.get_playback_devices()
        for i, device in enumerate(playback_devices):
            default = " (DEFAULT)" if device.is_default else ""
            print(f"  {i}: {device.name} [{device.host_api.value}]{default}")
        
        print("\nRecording Devices:")
        recording_devices = self.kit.get_recording_devices()
        for i, device in enumerate(recording_devices):
            default = " (DEFAULT)" if device.is_default else ""
            device_type = f" ({device.type.value})" if device.type == DeviceType.LOOPBACK else ""
            print(f"  {i}: {device.name} [{device.host_api.value}]{default}{device_type}")
        
        return playback_devices, recording_devices
    
    async def record_to_file(self, duration=10):
        """Record audio to WAV file"""
        print(f"\n=== Recording to File ({duration}s) ===")
        
        try:
            # Generate filename with timestamp
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"recording_{timestamp}.wav"
            
            # Start recording
            self.current_session = await self.kit.record_to_file(
                filename,
                duration=duration
            )
            
            print(f"Recording saved to: {filename}")
            
        except Exception as e:
            print(f"Recording failed: {e}")
    
    async def record_system_audio(self, duration=10):
        """Record system audio using loopback"""
        print(f"\n=== Recording System Audio ({duration}s) ===")
        
        try:
            # Find loopback device
            devices = self.kit.get_recording_devices()
            loopback_device = None
            
            for device in devices:
                if device.type == DeviceType.LOOPBACK:
                    loopback_device = device
                    break
            
            if not loopback_device:
                print("No loopback device found. Using default recording device.")
                print("Note: This will record from microphone, not system audio.")
            else:
                print(f"Using loopback device: {loopback_device.name}")
            
            # Generate filename
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"system_audio_{timestamp}.wav"
            
            # Start recording
            self.current_session = await self.kit.record_to_file(
                filename,
                duration=duration,
                device=loopback_device
            )
            
            print(f"System audio saved to: {filename}")
            
        except AudioLoopbackPermissionError:
            print("Loopback recording not supported on this Windows version.")
            print("Requires Windows 10 version 1803 or later.")
        except Exception as e:
            print(f"System audio recording failed: {e}")
    
    async def stream_audio_levels(self, duration=10):
        """Stream audio and display levels"""
        print(f"\n=== Audio Level Monitor ({duration}s) ===")
        
        import numpy as np
        
        def process_audio(audio_data):
            """Calculate and display audio levels"""
            # Calculate RMS
            rms = np.sqrt(np.mean(audio_data**2))
            
            # Convert to dB
            if rms > 0:
                db = 20 * np.log10(rms)
            else:
                db = -96
            
            # Create level meter
            level = int((db + 60) / 60 * 50)  # Map -60 to 0 dB
            level = max(0, min(50, level))
            meter = '█' * level + '░' * (50 - level)
            
            # Display
            print(f"\r{meter} {db:6.1f} dB", end='', flush=True)
        
        try:
            # Start streaming
            self.current_session = await self.kit.stream_audio(process_audio)
            
            # Run for specified duration
            await asyncio.sleep(duration)
            
            # Stop
            await self.kit.stop_capture(self.current_session)
            print("\n")  # New line after meter
            
        except Exception as e:
            print(f"\nStreaming failed: {e}")
    
    async def start_network_server(self, port=9876):
        """Start network audio streaming server"""
        print(f"\n=== Network Audio Server (Port {port}) ===")
        
        try:
            # Start server
            self.current_session = await self.kit.start_network_stream(
                host="0.0.0.0",
                port=port
            )
            
            print(f"Audio server started on port {port}")
            print("Clients can connect to receive audio stream")
            print("Press Ctrl+C to stop server")
            
            # Keep running until interrupted
            while True:
                await asyncio.sleep(1)
                
        except KeyboardInterrupt:
            print("\nStopping server...")
            if self.current_session:
                await self.kit.stop_capture(self.current_session)
        except Exception as e:
            print(f"Server failed: {e}")
    
    async def interactive_menu(self):
        """Interactive menu for demo"""
        while True:
            print("\n=== Windows AudioCaptureKit Demo ===")
            print("1. List audio devices")
            print("2. Record to file (10s)")
            print("3. Record system audio (10s)")
            print("4. Monitor audio levels")
            print("5. Start network server")
            print("6. Run all demos")
            print("0. Exit")
            
            try:
                choice = input("\nSelect option: ").strip()
                
                if choice == '0':
                    break
                elif choice == '1':
                    await self.list_devices()
                elif choice == '2':
                    await self.record_to_file()
                elif choice == '3':
                    await self.record_system_audio()
                elif choice == '4':
                    await self.stream_audio_levels()
                elif choice == '5':
                    await self.start_network_server()
                elif choice == '6':
                    await self.run_all_demos()
                else:
                    print("Invalid option")
                    
            except KeyboardInterrupt:
                print("\nOperation cancelled")
                continue
            except Exception as e:
                print(f"Error: {e}")
                continue
        
        # Cleanup
        await self.kit.cleanup()
        print("\nGoodbye!")
    
    async def run_all_demos(self):
        """Run all demos in sequence"""
        print("\n=== Running All Demos ===")
        
        # List devices
        await self.list_devices()
        await asyncio.sleep(2)
        
        # Record to file
        print("\nDemo 1: Basic recording")
        await self.record_to_file(duration=5)
        
        # Record system audio
        print("\nDemo 2: System audio recording")
        await self.record_system_audio(duration=5)
        
        # Monitor levels
        print("\nDemo 3: Audio level monitoring")
        await self.stream_audio_levels(duration=5)
        
        print("\n=== All demos completed ===")


async def main():
    """Main entry point"""
    print("Windows AudioCaptureKit Demo")
    print("============================")
    
    # Check Python version
    if sys.version_info < (3, 7):
        print("Error: Python 3.7 or later required")
        sys.exit(1)
    
    # Create demo instance
    demo = AudioCaptureDemo()
    
    # Check for command line arguments
    if len(sys.argv) > 1:
        arg = sys.argv[1].lower()
        if arg == "devices":
            await demo.list_devices()
        elif arg == "record":
            duration = int(sys.argv[2]) if len(sys.argv) > 2 else 10
            await demo.record_to_file(duration)
        elif arg == "loopback":
            duration = int(sys.argv[2]) if len(sys.argv) > 2 else 10
            await demo.record_system_audio(duration)
        elif arg == "levels":
            duration = int(sys.argv[2]) if len(sys.argv) > 2 else 10
            await demo.stream_audio_levels(duration)
        elif arg == "server":
            port = int(sys.argv[2]) if len(sys.argv) > 2 else 9876
            await demo.start_network_server(port)
        elif arg == "all":
            await demo.run_all_demos()
        else:
            print(f"Unknown command: {arg}")
            print("\nUsage:")
            print("  python audio_capture_demo.py [command] [args]")
            print("\nCommands:")
            print("  devices              - List audio devices")
            print("  record [duration]    - Record to file")
            print("  loopback [duration]  - Record system audio")
            print("  levels [duration]    - Monitor audio levels")
            print("  server [port]        - Start network server")
            print("  all                  - Run all demos")
    else:
        # Interactive mode
        await demo.interactive_menu()


if __name__ == "__main__":
    # Run the demo
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nDemo interrupted by user")
    except Exception as e:
        print(f"\nFatal error: {e}")
        import traceback
        traceback.print_exc()