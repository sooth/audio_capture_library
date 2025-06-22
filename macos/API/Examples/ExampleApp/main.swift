#!/usr/bin/env swift

// Example: Using AudioCaptureKit as a library
// This demonstrates how another application would import and use the library

import Foundation
import AudioCaptureKit

// Simple command-line app using the library
@main
struct AudioCaptureExample {
    static func main() async {
        print("AudioCaptureKit Example App")
        print("==========================\n")
        
        do {
            // List available devices
            print("Available Audio Devices:")
            let devices = await AudioCaptureKit.shared.listAudioDevices()
            for (index, device) in devices.enumerated() {
                print("\(index + 1). \(device.name) (ID: \(device.id))")
            }
            
            // Get default device
            if let defaultDevice = await AudioCaptureKit.shared.getDefaultInputDevice() {
                print("\nDefault device: \(defaultDevice.name)")
                
                // Record 5 seconds
                print("\nRecording 5 seconds from default device...")
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("example_recording.wav")
                
                let url = try await AudioCaptureKit.shared.recordToFile(
                    from: defaultDevice,
                    duration: 5.0,
                    outputURL: outputURL,
                    captureSystemAudio: false
                )
                
                print("✅ Recording saved to: \(url.path)")
                
                // Get file info
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? Int {
                    print("   File size: \(fileSize / 1024) KB")
                }
                
                // Stream audio for real-time processing
                print("\nStreaming 3 seconds of audio...")
                let stream = try await AudioCaptureKit.shared.streamAudio(
                    from: defaultDevice,
                    duration: 3.0
                )
                
                var bufferCount = 0
                var totalFrames: UInt32 = 0
                
                for await buffer in stream {
                    bufferCount += 1
                    totalFrames += buffer.frameLength
                }
                
                print("✅ Streaming complete")
                print("   Buffers received: \(bufferCount)")
                print("   Total frames: \(totalFrames)")
                
            } else {
                print("❌ No default audio device found")
            }
            
        } catch {
            print("❌ Error: \(error.localizedDescription)")
            if let captureError = error as? AudioCaptureError {
                if let suggestion = captureError.recoverySuggestion {
                    print("   Suggestion: \(suggestion)")
                }
            }
        }
        
        print("\n✅ Example complete!")
    }
}