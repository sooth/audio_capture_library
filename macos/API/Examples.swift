import Foundation
import AVFoundation

/// Examples demonstrating the AudioCaptureKit API usage
///
/// This file contains comprehensive examples showing how to use the audio capture
/// library for various common scenarios.

@available(macOS 13.0, *)
class AudioCaptureExamples {
    
    // MARK: - Basic Recording Example
    
    /// Record system audio to a WAV file
    static func basicRecordingExample() async throws {
        print("=== Basic Recording Example ===")
        
        // Initialize the audio capture kit
        let audioCaptureKit = AudioCaptureKit.shared
        
        // Record to file for 10 seconds
        let fileURL = URL(fileURLWithPath: "recording.wav")
        try await audioCaptureKit.recordToFile(url: fileURL, duration: 10.0)
        
        print("Recording saved to: \(fileURL.path)")
    }
    
    // MARK: - Advanced Recording with Multiple Outputs
    
    /// Record system audio to file while streaming to callback
    static func multiOutputExample() async throws {
        print("=== Multi-Output Recording Example ===")
        
        let audioCaptureKit = AudioCaptureKit.shared
        
        // Start capture session
        let session = try await audioCaptureKit.startCapture()
        print("Capture session started: \(session.id)")
        
        // Add file output
        let fileOutput = FileOutput(url: URL(fileURLWithPath: "multi-output.wav"))
        try await session.addOutput(fileOutput)
        print("Added file output")
        
        // Add callback output for real-time processing
        var bufferCount = 0
        let callbackOutput = CallbackOutput { buffer in
            bufferCount += 1
            if bufferCount % 100 == 0 {
                print("Processed \(bufferCount) buffers")
            }
        }
        try await session.addOutput(callbackOutput)
        print("Added callback output")
        
        // Record for 10 seconds
        try await Task.sleep(nanoseconds: 10_000_000_000)
        
        // Stop recording
        try await audioCaptureKit.stopCapture(session: session)
        print("Recording completed")
    }
    
    // MARK: - Real-time Audio Streaming
    
    /// Stream system audio with async processing
    static func streamingExample() async throws {
        print("=== Audio Streaming Example ===")
        
        let audioCaptureKit = AudioCaptureKit.shared
        
        // Start capture session
        let session = try await audioCaptureKit.startCapture()
        
        // Create stream output
        let streamOutput = StreamOutput(queueSize: 64)
        try await session.addOutput(streamOutput)
        
        // Process audio stream
        Task {
            var processedBuffers = 0
            for await audioBuffer in streamOutput.bufferStream {
                processedBuffers += 1
                
                // Process buffer (e.g., analyze audio levels)
                let level = calculateAudioLevel(buffer: audioBuffer.pcmBuffer)
                
                if processedBuffers % 50 == 0 {
                    print("Audio level: \(level) dB")
                }
                
                // Stop after 500 buffers
                if processedBuffers >= 500 {
                    break
                }
            }
            print("Stream processing completed")
        }
        
        // Let streaming run for a while
        try await Task.sleep(nanoseconds: 10_000_000_000)
        
        // Stop capture
        try await audioCaptureKit.stopCapture(session: session)
    }
    
    // MARK: - Device Management Example
    
    /// Enumerate and select audio devices
    static func deviceManagementExample() async throws {
        print("=== Device Management Example ===")
        
        let audioCaptureKit = AudioCaptureKit.shared
        
        // Get available devices
        let playbackDevices = try await audioCaptureKit.getPlaybackDevices()
        let recordingDevices = try await audioCaptureKit.getRecordingDevices()
        
        print("\nPlayback Devices:")
        for device in playbackDevices {
            print("  - \(device.name) [\(device.id)]")
            print("    Manufacturer: \(device.manufacturer ?? "Unknown")")
            print("    Channels: \(device.capabilities.maxChannels)")
            print("    Default: \(device.isDefault)")
        }
        
        print("\nRecording Devices:")
        for device in recordingDevices {
            print("  - \(device.name) [\(device.id)]")
            print("    Type: \(device.type)")
            if device.type == .system {
                print("    (System Audio Capture)")
            }
        }
        
        // Select USB SPDIF if available
        if let usbSpdif = playbackDevices.first(where: { $0.name.contains("USB SPDIF") }) {
            try await audioCaptureKit.setPlaybackDevice(usbSpdif)
            print("\nSelected USB SPDIF Adapter for playback")
        }
    }
    
    // MARK: - Playback with Delay Example
    
    /// Play system audio with configurable delay
    static func delayedPlaybackExample() async throws {
        print("=== Delayed Playback Example ===")
        
        let audioCaptureKit = AudioCaptureKit.shared
        
        // Start capture
        let captureSession = try await audioCaptureKit.startCapture()
        
        // Start playback with 3 second delay
        let playbackConfig = PlaybackConfiguration()
        playbackConfig.delay = 3.0
        playbackConfig.volume = 0.7
        
        let playbackSession = try await audioCaptureKit.startPlayback(configuration: playbackConfig)
        
        // Connect capture to playback
        try await playbackSession.setInput(captureSession)
        
        print("Audio playback will start in 3 seconds...")
        
        // Run for 15 seconds
        try await Task.sleep(nanoseconds: 15_000_000_000)
        
        // Stop sessions
        try await audioCaptureKit.stopPlayback(session: playbackSession)
        try await audioCaptureKit.stopCapture(session: captureSession)
        
        print("Playback completed")
    }
    
    // MARK: - Format Conversion Example
    
    /// Capture audio and convert format
    static func formatConversionExample() async throws {
        print("=== Format Conversion Example ===")
        
        let audioCaptureKit = AudioCaptureKit.shared
        
        // Configure capture with specific format
        var captureConfig = CaptureConfiguration()
        captureConfig.format = AudioFormat(
            sampleRate: 48000.0,
            channelCount: 2,
            bitDepth: 32,
            isInterleaved: false,
            isFloat: true
        )
        
        let session = try await audioCaptureKit.startCapture(configuration: captureConfig)
        
        // Add output with different format (16-bit WAV)
        let wavOutput = FileOutput(url: URL(fileURLWithPath: "converted.wav"))
        try await session.addOutput(wavOutput)
        
        print("Capturing at: \(captureConfig.format?.description ?? "default")")
        print("Converting to: 16-bit WAV")
        
        // Record for 5 seconds
        try await Task.sleep(nanoseconds: 5_000_000_000)
        
        try await audioCaptureKit.stopCapture(session: session)
        print("Format conversion completed")
    }
    
    // MARK: - Error Handling Example
    
    /// Demonstrate error handling and recovery
    static func errorHandlingExample() async throws {
        print("=== Error Handling Example ===")
        
        let audioCaptureKit = AudioCaptureKit.shared
        
        do {
            // Attempt to start capture
            let session = try await audioCaptureKit.startCapture()
            
            // Set error handler
            await session.setErrorHandler { error in
                print("Session error: \(error.localizedDescription)")
                
                // Create error context
                let context = ErrorContext(
                    error: error,
                    sessionId: session.id,
                    operation: "Audio Capture",
                    additionalInfo: [
                        "timestamp": Date(),
                        "format": session.getFormat()?.description ?? "unknown"
                    ]
                )
                
                print(context.report())
            }
            
            // Add output that might fail
            let output = FileOutput(url: URL(fileURLWithPath: "/invalid/path/file.wav"))
            
            do {
                try await session.addOutput(output)
            } catch {
                print("Expected error caught: \(error.localizedDescription)")
                
                // Try recovery with valid path
                let recoveryOutput = FileOutput(url: URL(fileURLWithPath: "recovery.wav"))
                try await session.addOutput(recoveryOutput)
                print("Recovery successful - using alternative path")
            }
            
            // Run briefly
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            try await audioCaptureKit.stopCapture(session: session)
            
        } catch AudioCaptureError.screenRecordingPermissionRequired {
            print("Screen Recording permission required!")
            print("Please grant permission in System Settings > Privacy & Security > Screen Recording")
        } catch {
            print("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Performance Monitoring Example
    
    /// Monitor library performance and statistics
    static func performanceMonitoringExample() async throws {
        print("=== Performance Monitoring Example ===")
        
        let audioCaptureKit = AudioCaptureKit.shared
        
        // Configure for performance
        var config = AudioCaptureConfiguration()
        config.processingPriority = .realtime
        config.enableMonitoring = true
        await audioCaptureKit.setConfiguration(config)
        
        // Start capture with stream output
        let session = try await audioCaptureKit.startCapture()
        let streamOutput = StreamOutput()
        try await session.addOutput(streamOutput)
        
        // Monitor statistics
        Task {
            for _ in 0..<10 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                
                let stats = await audioCaptureKit.getStatistics()
                print("\nLibrary Statistics:")
                print("  Active capture sessions: \(stats.captureSessionCount)")
                print("  Active playback sessions: \(stats.playbackSessionCount)")
                
                if let sessionStats = stats.captureStatistics.first {
                    print("  Session state: \(sessionStats.state)")
                    print("  Buffers processed: \(sessionStats.bufferCount)")
                    print("  Duration: \(String(format: "%.1f", sessionStats.duration))s")
                }
                
                let queueDepth = await streamOutput.getQueueDepth()
                print("  Stream queue depth: \(queueDepth)")
            }
        }
        
        // Run for 10 seconds
        try await Task.sleep(nanoseconds: 10_000_000_000)
        
        try await audioCaptureKit.stopCapture(session: session)
    }
    
    // MARK: - Helper Functions
    
    /// Calculate audio level from buffer
    static func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -Float.infinity }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                let sample = channelData[channel][frame]
                sum += sample * sample
            }
        }
        
        let rms = sqrt(sum / Float(channelCount * frameLength))
        let db = 20 * log10(max(rms, 0.00001))
        
        return db
    }
}

// MARK: - SwiftUI Integration Example

#if canImport(SwiftUI)
import SwiftUI

/// Example SwiftUI view for audio capture
@available(macOS 13.0, *)
struct AudioCaptureView: View {
    @State private var isRecording = false
    @State private var audioLevel: Float = -60.0
    @State private var session: AudioCaptureSession?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Audio Capture Demo")
                .font(.title)
            
            // Audio level meter
            ProgressView(value: (audioLevel + 60) / 60)
                .progressViewStyle(.linear)
                .frame(height: 20)
            
            Text("Level: \(String(format: "%.1f", audioLevel)) dB")
            
            // Control button
            Button(action: toggleRecording) {
                Label(
                    isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: isRecording ? "stop.circle.fill" : "record.circle"
                )
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .blue)
        }
        .padding()
        .frame(width: 300, height: 200)
    }
    
    func toggleRecording() {
        Task {
            if isRecording {
                await stopRecording()
            } else {
                await startRecording()
            }
        }
    }
    
    func startRecording() async {
        do {
            let audioCaptureKit = AudioCaptureKit.shared
            session = try await audioCaptureKit.startCapture()
            
            // Add callback output for level monitoring
            let callbackOutput = CallbackOutput { buffer in
                let level = AudioCaptureExamples.calculateAudioLevel(buffer: buffer)
                Task { @MainActor in
                    self.audioLevel = level
                }
            }
            
            try await session?.addOutput(callbackOutput)
            
            await MainActor.run {
                isRecording = true
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() async {
        guard let session = session else { return }
        
        do {
            try await AudioCaptureKit.shared.stopCapture(session: session)
            
            await MainActor.run {
                isRecording = false
                audioLevel = -60.0
            }
        } catch {
            print("Failed to stop recording: \(error)")
        }
    }
}
#endif

// MARK: - Main Example Runner

@available(macOS 13.0, *)
func runAllExamples() async {
    print("AudioCaptureKit API Examples")
    print("===========================\n")
    
    do {
        // Run examples
        try await AudioCaptureExamples.deviceManagementExample()
        print("\n" + String(repeating: "-", count: 50) + "\n")
        
        try await AudioCaptureExamples.basicRecordingExample()
        print("\n" + String(repeating: "-", count: 50) + "\n")
        
        try await AudioCaptureExamples.errorHandlingExample()
        print("\n" + String(repeating: "-", count: 50) + "\n")
        
        print("All examples completed successfully!")
        
    } catch {
        print("Example failed with error: \(error)")
    }
}