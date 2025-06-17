import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreVideo

// MARK: - CMSampleBuffer Extension (QuickRecorder Pattern)
extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        do {
            return try self.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
                guard let absd = self.formatDescription?.audioStreamBasicDescription else { return nil }
                guard let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else { return nil }
                return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
            }
        } catch {
            print("Error converting CMSampleBuffer to PCMBuffer: \(error)")
            return nil
        }
    }
}

// MARK: - Audio Data Delegate Protocol
protocol AudioDataDelegate: AnyObject {
    func audioRecorder(_ recorder: AudioRecorder, didReceiveAudioData data: Data, format: AVAudioFormat)
}

@available(macOS 13.0, *)
class AudioRecorder: NSObject {
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var isRecording = false
    private var startTime: CMTime?
    
    // Audio data delegates
    private var audioDataDelegates: [AudioDataDelegate] = []
    private let delegateQueue = DispatchQueue(label: "com.audiorecorder.delegates", attributes: .concurrent)
    
    // Audio format for in-memory data
    private var audioFormat: AVAudioFormat?
    
    // Initialize the asset writer for audio recording
    func startRecording(to url: URL) throws {
        // Create asset writer for WAV file
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .wav)
        
        // Configure audio settings for Linear PCM (uncompressed)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,  // Match SCStreamConfiguration
            AVNumberOfChannelsKey: 2,   // Stereo
            AVLinearPCMBitDepthKey: 16, // 16-bit integer PCM for WAV
            AVLinearPCMIsFloatKey: false, // Integer format required for WAV
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false // Interleaved is simpler
        ]
        
        // Create audio input
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        
        // Add input to asset writer
        if let audioInput = audioInput {
            assetWriter?.add(audioInput)
        }
        
        // Initialize audio format for in-memory processing
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000.0,
            channels: 2,
            interleaved: true
        )
        
        // Start writing
        assetWriter?.startWriting()
        isRecording = true
        
        print("Started recording to \(url.lastPathComponent)")
    }
    
    // Start streaming mode (no file recording, only delegate callbacks)
    func startStreamingMode() throws {
        // Initialize audio format for in-memory processing
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000.0,
            channels: 2,
            interleaved: true
        )
        
        isRecording = true
        print("Started streaming mode - audio will be sent to delegates")
    }
    
    // Stop recording and finalize the file
    func stopRecording(completion: @escaping (Bool) -> Void) {
        isRecording = false
        
        audioInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            let success = self?.assetWriter?.status == .completed
            if success {
                print("Recording completed successfully")
            } else if let error = self?.assetWriter?.error {
                print("Recording failed with error: \(error)")
            }
            completion(success)
        }
    }
    
    // MARK: - Audio Data Delegate Management
    
    /// Add a delegate to receive audio data callbacks
    func addAudioDataDelegate(_ delegate: AudioDataDelegate) {
        delegateQueue.async(flags: .barrier) { [weak self] in
            self?.audioDataDelegates.append(delegate)
        }
    }
    
    /// Remove a delegate from receiving audio data callbacks
    func removeAudioDataDelegate(_ delegate: AudioDataDelegate) {
        delegateQueue.async(flags: .barrier) { [weak self] in
            self?.audioDataDelegates.removeAll { $0 === delegate }
        }
    }
    
    /// Remove all audio data delegates
    func removeAllAudioDataDelegates() {
        delegateQueue.async(flags: .barrier) { [weak self] in
            self?.audioDataDelegates.removeAll()
        }
    }
}

// MARK: - SCStreamOutput Extension
@available(macOS 13.0, *)
extension AudioRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        
        // Only process audio samples
        guard outputType == .audio else { return }
        guard isRecording else { return }
        
        // Start session on first sample
        if startTime == nil {
            startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: startTime!)
            print("Audio session started at time: \(startTime!.seconds)")
        }
        
        // Append the audio sample buffer to file (only if recording to file)
        if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
            audioInput.append(sampleBuffer)
        }
        
        // Extract audio data for in-memory callbacks using simplified approach
        if let audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
           let audioFormat = audioFormat {
            
            let dataLength = CMBlockBufferGetDataLength(audioBuffer)
            var audioData = Data(count: dataLength)
            
            let result = audioData.withUnsafeMutableBytes { bytes in
                return CMBlockBufferCopyDataBytes(audioBuffer, atOffset: 0, dataLength: dataLength, destination: bytes.bindMemory(to: UInt8.self).baseAddress!)
            }
            
            guard result == noErr else {
                print("AudioRecorder: Failed to copy audio data from buffer")
                return
            }
            
            // Notify all delegates with audio data
            delegateQueue.async { [weak self] in
                guard let self = self else { return }
                self.audioDataDelegates.forEach { delegate in
                    delegate.audioRecorder(self, didReceiveAudioData: audioData, format: audioFormat)
                }
            }
        }
    }
}

// MARK: - Screen Recorder
@available(macOS 13.0, *)
class ScreenRecorder: NSObject {
    let audioRecorder = AudioRecorder()
    var stream: SCStream?
    
    // MARK: - Permission Checking
    
    func checkPermissions() {
        print("=== macOS 15 ScreenCaptureKit Permission Status ===")
        
        // Check if we can get shareable content (indicates screen recording permission)
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                print("✅ Screen Recording Permission: Available")
                print("   - Found \(content.displays.count) displays")
                print("   - Found \(content.windows.count) windows")
                print("   - Found \(content.applications.count) applications")
            } catch {
                print("❌ Screen Recording Permission: DENIED or ERROR")
                print("   Error: \(error)")
                print("   Solution: Go to System Preferences → Privacy & Security → Screen Recording")
                print("   Add your terminal or application and enable it")
            }
        }
        
        print("📝 Note: On macOS 15, permissions may need to be re-granted monthly")
        print("📝 Error -3805 is common and may require application restart")
    }
    
    func startCapture(outputFile: String) async throws {
        // Get shareable content - use QuickRecorder approach
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // Create filter for system audio capture (QuickRecorder pattern)
        guard let display = content.displays.first else {
            throw NSError(domain: "ScreenRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No displays found for system audio capture"])
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        print("Capturing system audio using display filter (QuickRecorder pattern)")
        
        // Configure stream using QuickRecorder pattern
        let config = SCStreamConfiguration()
        
        // Audio configuration (QuickRecorder pattern)
        config.capturesAudio = true          // Enable system audio capture
        config.sampleRate = 48000           // 48kHz sample rate
        config.channelCount = 2             // Stereo
        config.excludesCurrentProcessAudio = true  // CRITICAL: Prevent feedback loop!
        
        // Video configuration for audio-only capture (QuickRecorder pattern)
        config.width = 2                    // QuickRecorder uses 2x2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale.max) // Audio-only optimization
        
        // Create stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        // Add audio recorder as output
        let queue = DispatchQueue(label: "com.audio.capture.macos15", qos: .userInitiated)
        try stream?.addStreamOutput(audioRecorder, type: .audio, sampleHandlerQueue: queue)
        
        // Start audio file recording
        var finalOutputFile = outputFile
        if !finalOutputFile.hasSuffix(".wav") {
            finalOutputFile += ".wav"
        }
        let audioURL = URL(fileURLWithPath: finalOutputFile)
        try audioRecorder.startRecording(to: audioURL)
        
        // Start capture with retry logic for macOS 15
        do {
            try await stream?.startCapture()
            print("System audio capture started successfully on macOS 15")
        } catch {
            print("Initial capture failed, implementing macOS 15 retry logic...")
            // Wait briefly and retry once for connection issues
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
            try await stream?.startCapture()
            print("System audio capture started successfully on retry")
        }
    }
    
    func startStreamingCapture() async throws {
        // Get shareable content - use QuickRecorder approach
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // Create filter for system audio capture (QuickRecorder pattern)
        guard let display = content.displays.first else {
            throw NSError(domain: "ScreenRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No displays found for system audio capture"])
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        print("Capturing system audio using display filter for streaming (QuickRecorder pattern)")
        
        // Configure stream using QuickRecorder pattern
        let config = SCStreamConfiguration()
        
        // Audio configuration (QuickRecorder pattern)
        config.capturesAudio = true          // Enable system audio capture
        config.sampleRate = 48000           // 48kHz sample rate
        config.channelCount = 2             // Stereo
        config.excludesCurrentProcessAudio = true  // CRITICAL: Prevent feedback loop!
        
        // Video configuration for audio-only capture (QuickRecorder pattern)
        config.width = 2                    // QuickRecorder uses 2x2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale.max) // Audio-only optimization
        
        // Create stream with proper delegate
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        // Add audio recorder as output (for streaming, no file recording)
        let queue = DispatchQueue(label: "com.audio.capture.macos15", qos: .userInitiated)
        try stream?.addStreamOutput(audioRecorder, type: .audio, sampleHandlerQueue: queue)
        
        // Start streaming mode (no file recording)
        try audioRecorder.startStreamingMode()
        
        // Start capture with retry logic for macOS 15
        do {
            try await stream?.startCapture()
            print("System audio streaming started successfully on macOS 15")
        } catch {
            print("Initial capture failed, implementing macOS 15 retry logic...")
            // Wait briefly and retry once for connection issues
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
            try await stream?.startCapture()
            print("System audio streaming started successfully on retry")
        }
    }
    
    func stopCapture() async {
        print("Stopping capture...")
        
        do {
            try await stream?.stopCapture()
        } catch {
            print("Error stopping stream: \(error)")
        }
        
        await withCheckedContinuation { continuation in
            audioRecorder.stopRecording { success in
                print("Recording saved: \(success)")
                continuation.resume()
            }
        }
    }
}

// MARK: - SCStreamDelegate
@available(macOS 13.0, *)
extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
        
        // Handle ScreenCaptureKit errors using QuickRecorder pattern
        if let scError = error as? SCStreamError {
            switch scError {
            case SCStreamError.userDeclined:
                print("User declined screen recording permission")
                print("QuickRecorder pattern: Will retry after delay")
                // Implement QuickRecorder retry pattern
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    // Could implement automatic retry here
                    print("Ready for retry - user should re-grant permissions")
                }
            default:
                print("SCStreamError: \(scError.localizedDescription)")
            }
        } else if let nsError = error as NSError? {
            switch nsError.code {
            case -3805:
                print("ScreenCaptureKit connection interrupted (error -3805)")
                print("This is a known issue on macOS 15. Possible solutions:")
                print("1. Check Screen Recording permissions in System Preferences")
                print("2. Restart the application")
                print("3. Reset TCC database if needed: sudo tccutil reset ScreenCapture")
                break
            default:
                print("ScreenCaptureKit error code: \(nsError.code)")
                print("Error domain: \(nsError.domain)")
                if let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                    print("Description: \(description)")
                }
            }
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        // This method is called when we receive samples
        // For our use case, we handle this in the SCStreamOutput protocol (AudioRecorder)
    }
}

// MARK: - Command Line Interface
@available(macOS 13.0, *)
class CommandLineInterface {
    private let recorder = ScreenRecorder()
    private var playbackConsumer: AudioPlaybackConsumer?
    private var isRecording = false
    private var isStreaming = false
    
    func run() {
        print("Audio Recorder - macOS System Audio Capture & Streaming")
        print("Commands: start <filename>, stream, stop, status, quit")
        print("  start <filename> - Record audio to file")
        print("  stream          - Stream system audio to speakers")
        print("  stop            - Stop current recording/streaming")
        print("  status          - Show current status")
        print("  quit/exit       - Exit application")
        
        while true {
            print("> ", terminator: "")
            guard let input = readLine() else { break }
            
            let components = input.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            guard !components.isEmpty else { continue }
            
            let command = components[0].lowercased()
            
            switch command {
            case "start":
                if components.count < 2 {
                    print("Usage: start <filename>")
                } else {
                    let filename = components[1]
                    startRecording(filename: filename)
                }
                
            case "stream":
                startStreaming()
                
            case "stop":
                stopAll()
                
            case "status":
                showStatus()
                
            case "quit", "exit":
                stopAll()
                // Wait a bit for operations to finish
                Thread.sleep(forTimeInterval: 1.0)
                print("Goodbye!")
                return
                
            default:
                print("Unknown command: \(command)")
                print("Available commands: start <filename>, stream, stop, status, quit")
            }
        }
    }
    
    private func startRecording(filename: String) {
        guard !isRecording && !isStreaming else {
            print("Already recording or streaming. Use 'stop' first.")
            return
        }
        
        Task {
            do {
                try await recorder.startCapture(outputFile: filename)
                isRecording = true
                print("Recording started to \(filename).wav")
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    private func startStreaming() {
        guard !isRecording && !isStreaming else {
            print("Already recording or streaming. Use 'stop' first.")
            return
        }
        
        playbackConsumer = AudioPlaybackConsumer()
        
        Task {
            do {
                // Add playback consumer as delegate
                recorder.audioRecorder.addAudioDataDelegate(playbackConsumer!)
                
                // Start streaming capture
                try await recorder.startStreamingCapture()
                isStreaming = true
                print("Audio streaming started - system audio will play through speakers")
                print("Use 'stop' to end streaming")
            } catch {
                print("Failed to start streaming: \(error)")
                playbackConsumer?.stopPlayback()
                playbackConsumer = nil
            }
        }
    }
    
    private func stopAll() {
        if isRecording {
            print("Stopping recording...")
            Task {
                await recorder.stopCapture()
                isRecording = false
                print("Recording stopped")
            }
        } else if isStreaming {
            print("Stopping streaming...")
            Task {
                await recorder.stopCapture()
                playbackConsumer?.stopPlayback()
                playbackConsumer = nil
                isStreaming = false
                print("Streaming stopped")
            }
        } else {
            print("Not recording or streaming")
        }
    }
    
    private func showStatus() {
        if isRecording {
            print("Status: Recording to file")
        } else if isStreaming {
            print("Status: Streaming to system output")
            if let consumer = playbackConsumer {
                let status = consumer.getPlaybackStatus()
                print("  - Engine running: \(status["isEngineRunning"] ?? false)")
                print("  - Playing: \(status["isPlaying"] ?? false)")
                print("  - Volume: \(status["volume"] ?? 0.0)")
                print("  - Buffer count: \(status["pendingBufferCount"] ?? 0)")
            }
        } else {
            print("Status: Idle")
        }
    }
}

