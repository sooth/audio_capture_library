#!/usr/bin/env python3
"""
Interactive Audio Capture Application (Simplified)

Prompts user to select microphone and recording options,
then controls the audio capture API based on user choices.
"""

from audio_capture_client import AudioCaptureClient, AsyncAudioRecorder
import time
import os
from datetime import datetime


def print_header():
    """Print application header."""
    print("\n" + "="*60)
    print("🎙️  Audio Capture Application")
    print("="*60)
    print("Control audio recording with microphone and system audio\n")


def select_microphone(devices):
    """Let user select a microphone from available devices."""
    print("\nAvailable Microphones:")
    print("-" * 40)
    for i, device in enumerate(devices, 1):
        print(f"{i}. {device['name']}")
    print("-" * 40)
    
    while True:
        try:
            choice = input("\nSelect microphone number (1-{}): ".format(len(devices)))
            index = int(choice) - 1
            if 0 <= index < len(devices):
                return devices[index]
            else:
                print("❌ Invalid selection. Please try again.")
        except ValueError:
            print("❌ Please enter a valid number.")


def ask_yes_no(prompt):
    """Ask a yes/no question."""
    while True:
        choice = input(f"\n{prompt} (y/n): ").lower().strip()
        if choice in ['y', 'yes']:
            return True
        elif choice in ['n', 'no']:
            return False
        else:
            print("❌ Please enter 'y' for yes or 'n' for no.")


def get_recording_duration():
    """Get desired recording duration from user."""
    print("\nRecording Duration:")
    print("-" * 40)
    print("Enter duration in seconds, or leave empty for manual control")
    print("(you'll press Enter to stop recording)")
    print("-" * 40)
    
    while True:
        try:
            duration = input("\nDuration (seconds, or Enter for manual): ").strip()
            if duration == "":
                return None  # Manual control
            
            duration = float(duration)
            if duration > 0:
                return duration
            else:
                print("❌ Duration must be positive.")
        except ValueError:
            print("❌ Please enter a valid number or press Enter for manual control.")


def get_output_filename():
    """Get output filename from user."""
    print("\nOutput File:")
    print("-" * 40)
    
    default_name = f"recording_{datetime.now().strftime('%Y%m%d_%H%M%S')}.wav"
    filename = input(f"Enter filename (press Enter for '{default_name}'): ").strip()
    
    if not filename:
        filename = default_name
    elif not filename.endswith('.wav'):
        filename += '.wav'
        
    return filename


def countdown(seconds):
    """Show a countdown timer."""
    for i in range(int(seconds), 0, -1):
        print(f"\r⏱️  {i} seconds remaining...", end='', flush=True)
        time.sleep(1)
    print("\r⏱️  Recording complete!        ")


def main():
    """Main application logic."""
    print_header()
    
    try:
        # Initialize client
        print("🚀 Initializing audio capture system...")
        with AudioCaptureClient(auto_start_server=True) as client:
            print("✓ Connected to audio capture server\n")
            
            recorder = AsyncAudioRecorder(client)
            
            # Continue recording until user chooses to exit
            while True:
                # Get available devices
                devices = client.list_devices()
                if not devices:
                    print("❌ No microphones found!")
                    break
                
                # User selections
                selected_device = select_microphone(devices)
                
                print("\nSystem Audio Capture:")
                print("-" * 40)
                print("System audio capture records all sounds from your computer")
                print("(music, videos, notifications, etc.)")
                capture_system_audio = ask_yes_no("Capture system audio?")
                
                duration = get_recording_duration()
                output_filename = get_output_filename()
                
                # Confirm settings
                print("\n" + "="*60)
                print("📋 RECORDING SETTINGS")
                print("="*60)
                print(f"Microphone: {selected_device['name']}")
                print(f"System Audio: {'Yes' if capture_system_audio else 'No'}")
                print(f"Duration: {'Manual control' if duration is None else f'{duration} seconds'}")
                print(f"Output File: {output_filename}")
                print("="*60)
                
                if not ask_yes_no("Proceed with recording?"):
                    print("\n❌ Recording cancelled.")
                    continue
                
                # Perform recording
                print("\n" + "="*60)
                print("🔴 RECORDING")
                print("="*60)
                
                if duration is None:
                    # Manual control
                    print("Press ENTER to start recording...")
                    input()
                    
                    result = client.start_recording(
                        device_id=selected_device['id'],
                        capture_system_audio=capture_system_audio,
                        output_path=output_filename
                    )
                    
                    print("\n🔴 RECORDING IN PROGRESS...")
                    print("Press ENTER to stop recording")
                    
                    start_time = time.time()
                    
                    # Simple status display
                    def show_status():
                        while True:
                            try:
                                elapsed = time.time() - start_time
                                status = client.get_status()
                                if not status['is_recording']:
                                    break
                                print(f"\r⏱️  Time: {elapsed:.1f}s | Mic buffers: {status.get('mic_buffers', 0)} | System buffers: {status.get('system_buffers', 0)}     ", end='', flush=True)
                                time.sleep(0.5)
                            except:
                                break
                    
                    # Start status thread
                    import threading
                    status_thread = threading.Thread(target=show_status, daemon=True)
                    status_thread.start()
                    
                    # Wait for user to stop
                    input()
                    print("\n\nStopping recording...")
                    result = client.stop_recording()
                    
                else:
                    # Automatic duration
                    print(f"Recording for {duration} seconds...")
                    
                    # Start recording
                    client.start_recording(
                        device_id=selected_device['id'],
                        capture_system_audio=capture_system_audio,
                        output_path=output_filename
                    )
                    
                    # Show countdown
                    countdown(duration)
                    
                    # Stop recording
                    result = client.stop_recording()
                
                # Display results
                print("\n" + "="*60)
                print("✅ RECORDING COMPLETED")
                print("="*60)
                print(f"File: {result['output_path']}")
                print(f"Duration: {result['duration']:.2f} seconds")
                print(f"Size: {result['file_size']:,} bytes ({result['file_size']/1024/1024:.2f} MB)")
                
                # Check file location
                for base_path in ["../macos", "."]:
                    full_path = os.path.join(base_path, result['output_path'])
                    if os.path.exists(full_path):
                        print(f"Location: {os.path.abspath(full_path)}")
                        break
                
                # Ask if user wants to record again
                print("\n" + "-"*60)
                if not ask_yes_no("Record another file?"):
                    break
                    
    except KeyboardInterrupt:
        print("\n\n⚠️  Recording interrupted by user")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
    
    print("\n👋 Thank you for using Audio Capture Application!\n")


if __name__ == "__main__":
    main()