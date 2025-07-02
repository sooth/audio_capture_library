#!/usr/bin/env python3
"""
Setup script for Windows AudioCaptureKit

This script ensures proper installation of all dependencies,
especially handling the PyAudio/PyAudioWPatch conflict.
"""

import sys
import subprocess
import os

def run_command(cmd, check=True):
    """Run a command and return the result"""
    print(f"Running: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)
    if check and result.returncode != 0:
        print(f"Command failed with return code {result.returncode}")
        return False
    return True

def main():
    print("Windows AudioCaptureKit Setup")
    print("=" * 50)
    print()
    
    # Check Python version
    if sys.version_info < (3, 7):
        print("ERROR: Python 3.7 or later is required")
        sys.exit(1)
    
    print(f"Using Python {sys.version}")
    print(f"Python executable: {sys.executable}")
    print()
    
    # Step 1: Check for PyAudio conflict
    print("Step 1: Checking for PyAudio conflicts...")
    print("-" * 40)
    
    # Check if regular PyAudio is installed
    result = subprocess.run(
        [sys.executable, "-m", "pip", "show", "pyaudio"],
        capture_output=True
    )
    
    if result.returncode == 0:
        print("⚠️  Regular PyAudio is installed and conflicts with PyAudioWPatch")
        print("   PyAudioWPatch is required for system audio (loopback) recording")
        print()
        response = input("Uninstall PyAudio? (y/n): ").strip().lower()
        
        if response == 'y':
            print("Uninstalling PyAudio...")
            if not run_command(f"{sys.executable} -m pip uninstall -y pyaudio"):
                print("Failed to uninstall PyAudio. Please run manually:")
                print(f"  {sys.executable} -m pip uninstall pyaudio")
                sys.exit(1)
            print("✓ PyAudio uninstalled")
        else:
            print("⚠️  WARNING: Keeping PyAudio will prevent loopback recording from working!")
            response = input("Continue anyway? (y/n): ").strip().lower()
            if response != 'y':
                print("Setup cancelled.")
                sys.exit(0)
    else:
        print("✓ No PyAudio conflicts found")
    
    print()
    
    # Step 2: Upgrade pip
    print("Step 2: Upgrading pip...")
    print("-" * 40)
    run_command(f"{sys.executable} -m pip install --upgrade pip", check=False)
    print()
    
    # Step 3: Install requirements
    print("Step 3: Installing requirements...")
    print("-" * 40)
    
    requirements_file = os.path.join(os.path.dirname(__file__), "requirements.txt")
    if not os.path.exists(requirements_file):
        print(f"ERROR: requirements.txt not found at {requirements_file}")
        sys.exit(1)
    
    print(f"Installing from: {requirements_file}")
    if not run_command(f"{sys.executable} -m pip install -r \"{requirements_file}\""):
        print("Failed to install requirements")
        sys.exit(1)
    
    print()
    
    # Step 4: Verify installation
    print("Step 4: Verifying installation...")
    print("-" * 40)
    
    required_packages = [
        ("numpy", "NumPy"),
        ("scipy", "SciPy"),
        ("sounddevice", "sounddevice"),
        ("pyaudiowpatch", "PyAudioWPatch"),
        ("pycaw", "pycaw")
    ]
    
    all_good = True
    for module, name in required_packages:
        try:
            __import__(module)
            print(f"✓ {name} is installed")
        except ImportError:
            print(f"✗ {name} is NOT installed")
            all_good = False
    
    print()
    
    # Step 5: Test loopback support
    print("Step 5: Testing loopback support...")
    print("-" * 40)
    
    try:
        import pyaudiowpatch as pyaudio
        p = pyaudio.PyAudio()
        
        # Check for loopback support
        if hasattr(p, 'get_loopback_device_info_generator'):
            print("✓ PyAudioWPatch has loopback support")
            
            # Try to find a loopback device
            try:
                loopback_found = False
                for loopback in p.get_loopback_device_info_generator():
                    print(f"  Found loopback device: {loopback['name']}")
                    loopback_found = True
                    break
                
                if loopback_found:
                    print("✓ Loopback devices are available!")
                else:
                    print("⚠️  No loopback devices found (this might be normal)")
                    
            except Exception as e:
                print(f"⚠️  Error enumerating loopback devices: {e}")
        else:
            print("✗ This PyAudioWPatch doesn't have loopback support")
            print("  You may have regular PyAudio installed instead")
            all_good = False
            
        p.terminate()
    except ImportError:
        print("✗ PyAudioWPatch is not installed")
        all_good = False
    
    print()
    print("=" * 50)
    
    if all_good:
        print("✓ Setup completed successfully!")
        print()
        print("You can now run the examples:")
        print("  python Examples/audio_capture_demo.py")
        print("  python Examples/interactive_recording_mixer.py")
        print()
        print("To test loopback recording specifically:")
        print("  python Examples/test_loopback.py")
    else:
        print("✗ Setup completed with errors")
        print()
        print("Please fix the issues above and run setup again.")
        print()
        print("Common issues:")
        print("1. Regular PyAudio is still installed - uninstall it first")
        print("2. Missing Visual C++ build tools - install from Microsoft")
        print("3. Permission issues - try running as administrator")
    
    return 0 if all_good else 1

if __name__ == "__main__":
    sys.exit(main())