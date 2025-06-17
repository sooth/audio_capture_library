import Foundation

/// Audio Capture Library - Command Line Interface
///
/// This is the main entry point for the audio capture system. It provides
/// several command-line modes for different use cases:
///
/// Commands:
/// - record: Silent recording to WAV file (no playback)
/// - stream: Real-time audio streaming with optional recording
/// - test-tone: Generate test tone for audio verification
/// - check-permissions: Verify Screen Recording permission
///
/// The program supports both command-line arguments and interactive mode.
///
/// Architecture:
/// - Uses async/await for modern concurrency
/// - Delegates audio processing to specialized classes
/// - Maintains clean separation between capture, playback, and file writing

// MARK: - Entry Point
if #available(macOS 13.0, *) {
    // Check if we have command line arguments for automated testing
    if CommandLine.arguments.count > 1 {
        let command = CommandLine.arguments[1]
        
        if command == "test" && CommandLine.arguments.count >= 4 {
            let duration = Double(CommandLine.arguments[2]) ?? 10.0
            let filename = CommandLine.arguments[3]
            
            print("Starting automated test: recording for \(duration) seconds to \(filename)")
            
            let recorder = ScreenRecorder()
            
            Task {
                do {
                    try await recorder.startCapture(outputFile: filename)
                    
                    // Wait for specified duration
                    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    
                    await recorder.stopCapture()
                    print("Test completed")
                    exit(0)
                } catch {
                    print("Test failed: \(error)")
                    exit(1)
                }
            }
            
            // Keep the run loop alive
            RunLoop.main.run()
            
        } else if command == "stream" {
            let duration = CommandLine.arguments.count >= 3 ? Double(CommandLine.arguments[2]) ?? 30.0 : 30.0
            let delay = CommandLine.arguments.count >= 4 ? Double(CommandLine.arguments[3]) ?? 0.0 : 0.0
            let saveFilename = CommandLine.arguments.count >= 5 ? CommandLine.arguments[4] : nil
            
            print("Starting real-time audio streaming (direct PCM buffer) for \(duration) seconds...")
            if delay > 0 {
                print("Playback delay: \(delay) seconds")
            }
            if let filename = saveFilename {
                print("Saving to WAV file: \(filename).wav")
            }
            print("Press Ctrl+C to stop early")
            
            let streamingRecorder = StreamingAudioRecorder()
            let streamingPlayer = StreamingAudioPlayer(delay: delay)
            var wavWriter: WavFileWriter?
            
            Task {
                do {
                    // Always add streaming player for stream command
                    streamingRecorder.addStreamDelegate(streamingPlayer)
                    
                    // Add WAV writer if filename provided (records while playing)
                    if let filename = saveFilename {
                        wavWriter = try WavFileWriter(sampleRate: 48000.0, channels: 2)
                        try wavWriter?.startWriting(to: filename)
                        streamingRecorder.addStreamDelegate(wavWriter!)
                        print("WAV file recording started (with playback)")
                    }
                    
                    // Start real-time streaming capture
                    try await streamingRecorder.startStreaming()
                    
                    print("Real-time audio streaming started - zero-copy PCM buffer streaming to USB SPDIF Adapter")
                    if delay > 0 {
                        print("Note: Program will run for \(duration + delay) seconds total to allow delayed playback")
                    }
                    
                    // Wait for recording duration PLUS delay to ensure audio is available after delay expires
                    let totalRecordingTime = duration + delay
                    try await Task.sleep(nanoseconds: UInt64(totalRecordingTime * 1_000_000_000))
                    
                    // Stop recording - delayed audio should have already played
                    await streamingRecorder.stopStreaming()
                    print("Recording stopped after delayed playback completed")
                    
                    streamingPlayer.stopPlayback()
                    
                    if let writer = wavWriter {
                        writer.stopWriting()
                        if let info = writer.getFileInfo() as? [String: Any],
                           let duration = info["duration"] as? Double {
                            print("WAV file saved: \(String(format: "%.2f", duration)) seconds")
                        }
                    }
                    
                    print("Real-time streaming completed")
                    exit(0)
                } catch {
                    print("Real-time streaming failed: \(error)")
                    streamingPlayer.stopPlayback()
                    wavWriter?.stopWriting()
                    exit(1)
                }
            }
            
            // Keep the run loop alive
            RunLoop.main.run()
            
        } else if command == "record" {
            // Silent recording - no playback
            let duration = CommandLine.arguments.count >= 3 ? Double(CommandLine.arguments[2]) ?? 10.0 : 10.0
            let filename = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : "recording"
            
            print("Starting silent WAV recording for \(duration) seconds...")
            print("Output file: \(filename).wav")
            print("Press Ctrl+C to stop early")
            
            let streamingRecorder = StreamingAudioRecorder()
            var wavWriter: WavFileWriter?
            
            Task {
                do {
                    // Only add WAV writer - no audio playback
                    wavWriter = try WavFileWriter(sampleRate: 48000.0, channels: 2)
                    try wavWriter?.startWriting(to: filename)
                    streamingRecorder.addStreamDelegate(wavWriter!)
                    
                    // Start recording
                    try await streamingRecorder.startStreaming()
                    print("Silent recording started - capturing system audio to WAV file")
                    
                    // Wait for recording duration
                    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    
                    // Stop recording
                    await streamingRecorder.stopStreaming()
                    
                    wavWriter?.stopWriting()
                    if let info = wavWriter?.getFileInfo() as? [String: Any],
                       let recordedDuration = info["duration"] as? Double {
                        print("WAV file saved: \(filename).wav (\(String(format: "%.2f", recordedDuration)) seconds)")
                    }
                    
                    print("Silent recording completed")
                    exit(0)
                } catch {
                    print("Recording failed: \(error)")
                    wavWriter?.stopWriting()
                    exit(1)
                }
            }
            
            // Keep the run loop alive
            RunLoop.main.run()
            
        } else if command == "test-tone" {
            let duration = CommandLine.arguments.count >= 3 ? Double(CommandLine.arguments[2]) ?? 5.0 : 5.0
            
            print("Playing test tone for \(duration) seconds with new streaming player...")
            print("This tests the audio playback pipeline with a clean sine wave")
            
            let streamingPlayer = StreamingAudioPlayer()
            
            Task {
                do {
                    try streamingPlayer.playTestTone(duration: duration)
                    print("Test tone completed")
                    exit(0)
                } catch {
                    print("Test tone failed: \(error)")
                    exit(1)
                }
            }
            
            // Keep the run loop alive
            RunLoop.main.run()
            
        } else if command == "check-permissions" {
            print("Checking macOS 15 ScreenCaptureKit permissions...")
            
            let recorder = ScreenRecorder()
            recorder.checkPermissions()
            
            // Wait a bit for async permission check to complete
            Thread.sleep(forTimeInterval: 2.0)
            exit(0)
            
        } else {
            print("Usage:")
            print("  record <duration> <filename>          - Silent recording to WAV file (no playback)")
            print("  stream [duration] [delay] [filename]  - Real-time playback to USB SPDIF")
            print("                                          duration: recording time in seconds (default: 30s)")
            print("                                          delay: playback delay in seconds (default: 0s)")
            print("                                          filename: also save to WAV while playing")
            print("  test <duration_seconds> <filename>    - Record to file (legacy)")
            print("  test-tone [duration_seconds]          - Play test tone via streaming player (default: 5s)")
            print("  check-permissions                     - Check macOS 15 permissions status")
            print("")
            print("Examples:")
            print("  record 30 meeting        - Silent recording for 30s to meeting.wav")
            print("  stream                   - Stream for 30s with no delay")
            print("  stream 10 2.5            - Stream for 10s with 2.5s playback delay")
            print("  stream 30 0 audio        - Stream for 30s AND save to audio.wav")
            print("  stream 20 3 recording    - Stream for 20s with 3s delay, also save to recording.wav")
        }
    } else {
        // Interactive mode
        let cli = CommandLineInterface()
        cli.run()
    }
} else {
    print("This application requires macOS 13.0 or later")
}