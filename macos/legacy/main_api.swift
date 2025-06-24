import Foundation
import AVFoundation

/// Audio Capture Library - API Demo
///
/// This demonstrates the new standardized API interface layer
/// with various usage patterns and examples.

@available(macOS 13.0, *)
func runAPIDemo() async {
    print("Audio Capture Library - API Demo")
    print("================================\n")
    
    // Get command line arguments
    let args = CommandLine.arguments
    let command = args.count > 1 ? args[1] : "help"
    
    do {
        switch command {
        case "devices":
            try await listDevices()
            
        case "record":
            let duration = args.count > 2 ? Double(args[2]) ?? 10.0 : 10.0
            let filename = args.count > 3 ? args[3] : "api_recording"
            try await recordToFile(duration: duration, filename: filename)
            
        case "stream":
            let duration = args.count > 2 ? Double(args[2]) ?? 30.0 : 30.0
            try await streamWithPlayback(duration: duration)
            
        case "monitor":
            let duration = args.count > 2 ? Double(args[2]) ?? 30.0 : 30.0
            try await monitorAudioLevels(duration: duration)
            
        case "multi":
            let duration = args.count > 2 ? Double(args[2]) ?? 10.0 : 10.0
            try await multiOutputDemo(duration: duration)
            
        case "examples":
            await runAllExamples()
            
        case "help", "-h", "--help":
            printHelp()
            
        default:
            print("Unknown command: \(command)")
            printHelp()
        }
    } catch {
        print("\nError: \(error.localizedDescription)")
        
        if let captureError = error as? AudioCaptureError {
            if let suggestion = captureError.recoverySuggestion {
                print("Suggestion: \(suggestion)")
            }
        }
        
        exit(1)
    }
}

// MARK: - Command Implementations

@available(macOS 13.0, *)
func listDevices() async throws {
    print("Enumerating Audio Devices...")
    print("============================\n")
    
    let kit = AudioCaptureKit.shared
    
    // List playback devices
    print("Playback Devices:")
    print("-----------------")
    let playbackDevices = try await kit.getPlaybackDevices()
    for device in playbackDevices {
        printDevice(device)
    }
    
    // List recording devices
    print("\nRecording Devices:")
    print("------------------")
    let recordingDevices = try await kit.getRecordingDevices()
    for device in recordingDevices {
        printDevice(device)
    }
    
    // Show current devices
    print("\nCurrent Devices:")
    print("----------------")
    if let current = try await kit.getCurrentPlaybackDevice() {
        print("Playback: \(current.name)")
    }
    if let current = try await kit.getCurrentRecordingDevice() {
        print("Recording: \(current.name)")
    }
}

@available(macOS 13.0, *)
func recordToFile(duration: TimeInterval, filename: String) async throws {
    print("Recording to File")
    print("=================")
    print("Duration: \(duration) seconds")
    print("Filename: \(filename).wav\n")
    
    let kit = AudioCaptureKit.shared
    let url = URL(fileURLWithPath: "\(filename).wav")
    
    print("Recording...")
    try await kit.recordToFile(url: url, duration: duration)
    
    print("\n✓ Recording completed successfully")
    print("File saved to: \(url.path)")
    
    // Show file info
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
        let size = attrs[.size] as? Int64 ?? 0
        let sizeKB = Double(size) / 1024.0
        print("File size: \(String(format: "%.1f", sizeKB)) KB")
    }
}

@available(macOS 13.0, *)
func streamWithPlayback(duration: TimeInterval) async throws {
    print("Audio Stream with Playback")
    print("==========================")
    print("Duration: \(duration) seconds\n")
    
    let kit = AudioCaptureKit.shared
    
    // Start capture
    print("Starting audio capture...")
    let captureSession = try await kit.startCapture()
    print("✓ Capture session started: \(captureSession.id)")
    
    // Start playback
    print("\nStarting audio playback...")
    var playbackConfig = PlaybackConfiguration()
    playbackConfig.delay = 2.0  // 2 second delay
    playbackConfig.volume = 0.5
    
    let playbackSession = try await kit.startPlayback(configuration: playbackConfig)
    print("✓ Playback session started with 2s delay")
    
    // Connect capture to playback
    try await playbackSession.setInput(captureSession)
    print("✓ Audio routing configured")
    
    // Add file output
    let fileOutput = FileOutput(url: URL(fileURLWithPath: "stream_output.wav"))
    try await captureSession.addOutput(fileOutput)
    print("✓ Recording to: stream_output.wav")
    
    print("\nStreaming for \(duration) seconds...")
    print("(Playback will start after 2 second delay)")
    
    // Monitor for duration
    for i in 0..<Int(duration) {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("  \(i + 1)/\(Int(duration))s", terminator: i < Int(duration) - 1 ? "\r" : "\n")
        fflush(stdout)
    }
    
    // Stop sessions
    print("\nStopping sessions...")
    try await kit.stopPlayback(session: playbackSession)
    try await kit.stopCapture(session: captureSession)
    
    print("✓ Streaming completed successfully")
}

@available(macOS 13.0, *)
func monitorAudioLevels(duration: TimeInterval) async throws {
    print("Audio Level Monitoring")
    print("======================")
    print("Duration: \(duration) seconds\n")
    
    let kit = AudioCaptureKit.shared
    
    // Start capture
    let session = try await kit.startCapture()
    
    // Add callback output for monitoring
    var peakLevel: Float = -Float.infinity
    let callbackOutput = CallbackOutput { buffer in
        let level = calculateLevel(buffer: buffer)
        if level > peakLevel {
            peakLevel = level
        }
        
        // Create level meter
        let meterWidth = 40
        let normalizedLevel = (level + 60) / 60  // Normalize -60dB to 0dB
        let filledBars = Int(normalizedLevel * Float(meterWidth))
        let meter = String(repeating: "█", count: max(0, filledBars)) +
                   String(repeating: "░", count: max(0, meterWidth - filledBars))
        
        print("\rLevel: [\(meter)] \(String(format: "%6.1f", level)) dB", terminator: "")
        fflush(stdout)
    }
    
    try await session.addOutput(callbackOutput)
    
    print("Monitoring audio levels...")
    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    
    print("\n\nPeak level: \(String(format: "%.1f", peakLevel)) dB")
    
    try await kit.stopCapture(session: session)
    print("✓ Monitoring completed")
}

@available(macOS 13.0, *)
func multiOutputDemo(duration: TimeInterval) async throws {
    print("Multi-Output Demo")
    print("=================")
    print("Duration: \(duration) seconds\n")
    
    let kit = AudioCaptureKit.shared
    
    // Start capture
    let session = try await kit.startCapture()
    print("✓ Capture session started")
    
    // Add multiple outputs
    
    // 1. File output
    let fileOutput = FileOutput(url: URL(fileURLWithPath: "multi_output.wav"))
    try await session.addOutput(fileOutput)
    print("✓ Added file output: multi_output.wav")
    
    // 2. Stream output for processing
    let streamOutput = StreamOutput()
    try await session.addOutput(streamOutput)
    print("✓ Added stream output")
    
    // 3. Playback output
    let playbackOutput = PlaybackOutput(delay: 1.0)
    try await session.addOutput(playbackOutput)
    print("✓ Added playback output (1s delay)")
    
    // Process stream in background
    Task {
        var bufferCount = 0
        for await buffer in streamOutput.bufferStream {
            bufferCount += 1
            if bufferCount % 100 == 0 {
                print("\n  Processed \(bufferCount) buffers")
            }
        }
    }
    
    print("\nRunning multi-output for \(duration) seconds...")
    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    
    // Stop capture
    try await kit.stopCapture(session: session)
    
    print("\n✓ Multi-output demo completed")
    
    // Show statistics
    let stats = await kit.getStatistics()
    print("\nStatistics:")
    print("  Capture sessions: \(stats.captureSessionCount)")
    if let sessionStats = stats.captureStatistics.first {
        print("  Buffers processed: \(sessionStats.bufferCount)")
        print("  Duration: \(String(format: "%.1f", sessionStats.duration))s")
    }
}

// MARK: - Helper Functions

@available(macOS 13.0, *)
func printDevice(_ device: AudioDevice) {
    print("\n• \(device.name)")
    print("  ID: \(device.id)")
    print("  Type: \(device.type)")
    if let manufacturer = device.manufacturer {
        print("  Manufacturer: \(manufacturer)")
    }
    print("  Status: \(device.status)")
    print("  Default: \(device.isDefault)")
    print("  Capabilities:")
    print("    - Max channels: \(device.capabilities.maxChannels)")
    print("    - Min latency: \(String(format: "%.1f", device.capabilities.minLatency * 1000))ms")
    print("    - Sample rates: \(device.capabilities.sampleRates.map { "\(Int($0))Hz" }.joined(separator: ", "))")
}

func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData else { return -Float.infinity }
    
    let channelCount = Int(buffer.format.channelCount)
    let frameLength = Int(buffer.frameLength)
    var maxSample: Float = 0.0
    
    for channel in 0..<channelCount {
        for frame in 0..<frameLength {
            let sample = abs(channelData[channel][frame])
            if sample > maxSample {
                maxSample = sample
            }
        }
    }
    
    return 20 * log10(max(maxSample, 0.00001))
}

func printHelp() {
    print("""
    Audio Capture Library - API Demo
    
    Usage: audio_capture_api <command> [options]
    
    Commands:
      devices              List all audio devices
      record <duration> <filename>
                          Record audio to WAV file
      stream <duration>   Stream audio with playback
      monitor <duration>  Monitor audio levels
      multi <duration>    Multi-output demonstration
      examples            Run all API examples
      help               Show this help message
    
    Examples:
      audio_capture_api devices
      audio_capture_api record 10 meeting
      audio_capture_api stream 30
      audio_capture_api monitor 5
      audio_capture_api multi 10
    
    Note: Requires macOS 13.0+ and Screen Recording permission
    """)
}

// MARK: - Entry Point

if #available(macOS 13.0, *) {
    // Run async main
    Task {
        await runAPIDemo()
        exit(0)
    }
    
    // Keep RunLoop alive
    RunLoop.main.run()
} else {
    print("This application requires macOS 13.0 or later")
    exit(1)
}