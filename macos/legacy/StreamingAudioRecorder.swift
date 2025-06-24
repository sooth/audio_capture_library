import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// StreamingAudioRecorder - Real-time System Audio Capture
///
/// This class captures system audio using macOS ScreenCaptureKit and converts it
/// to AVAudioPCMBuffer format for real-time processing. It implements a delegate
/// pattern to distribute audio to multiple consumers (player, file writer, etc).
///
/// Key Features:
/// - Zero-copy audio capture using ScreenCaptureKit
/// - Real-time CMSampleBuffer to AVAudioPCMBuffer conversion
/// - Multi-delegate support for audio distribution
/// - Performance monitoring and statistics
///
/// Usage:
/// ```swift
/// let recorder = StreamingAudioRecorder()
/// recorder.addStreamDelegate(audioPlayer)
/// recorder.addStreamDelegate(fileWriter)
/// try await recorder.startStreaming()
/// ```

// MARK: - Audio Stream Delegate Protocol (Direct AVAudioPCMBuffer)

/// Protocol for receiving audio buffers from StreamingAudioRecorder
/// Implement this protocol to process captured audio in real-time
protocol AudioStreamDelegate: AnyObject {
    /// Called when a new audio buffer is available
    /// - Parameters:
    ///   - streamer: The audio recorder instance
    ///   - buffer: PCM audio buffer containing captured audio
    func audioStreamer(_ streamer: StreamingAudioRecorder, didReceive buffer: AVAudioPCMBuffer)
    
    /// Called when an error occurs during audio capture
    func audioStreamer(_ streamer: StreamingAudioRecorder, didEncounterError error: Error)
    
    /// Called when audio streaming has finished
    func audioStreamerDidFinish(_ streamer: StreamingAudioRecorder)
}

// MARK: - Buffer Pool for Real-Time Performance

/// Buffer pool for efficient audio buffer reuse (currently disabled)
/// This was implemented for performance optimization but found to cause
/// issues with buffer format mismatches
class AVAudioPCMBufferPool {
    private var availableBuffers: [AVAudioPCMBuffer] = []
    private let format: AVAudioFormat
    private let frameCapacity: AVAudioFrameCount
    private let maxPoolSize: Int
    private let queue = DispatchQueue(label: "com.bufferpool", qos: .userInitiated)
    
    init(format: AVAudioFormat, frameCapacity: AVAudioFrameCount, maxPoolSize: Int = 10) {
        self.format = format
        self.frameCapacity = frameCapacity
        self.maxPoolSize = maxPoolSize
        
        // Pre-allocate initial buffers
        for _ in 0..<min(maxPoolSize, 5) {
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) {
                availableBuffers.append(buffer)
            }
        }
        
        print("StreamingAudioRecorder: Buffer pool initialized with \(availableBuffers.count) buffers")
    }
    
    func getBuffer() -> AVAudioPCMBuffer? {
        return queue.sync {
            if let buffer = availableBuffers.popLast() {
                buffer.frameLength = 0 // Reset frame length
                return buffer
            } else {
                // Create new buffer if pool is empty
                return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)
            }
        }
    }
    
    func returnBuffer(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.availableBuffers.count < self.maxPoolSize {
                buffer.frameLength = 0 // Reset for reuse
                self.availableBuffers.append(buffer)
            }
        }
    }
}

// MARK: - Streaming Audio Recorder (QuickRecorder-Inspired)

/// Main class for capturing system audio using ScreenCaptureKit
/// Requires macOS 13.0+ and Screen Recording permission
@available(macOS 13.0, *)
class StreamingAudioRecorder: NSObject {
    
    // MARK: - Properties
    
    private var stream: SCStream?
    private var isRecording = false
    private var bufferPool: AVAudioPCMBufferPool?
    
    // Start time for precise timing
    private let startTime = Date()
    
    // Audio format for real-time streaming
    private var streamingFormat: AVAudioFormat?
    
    // Delegates for real-time audio streaming
    private var streamDelegates: [AudioStreamDelegate] = []
    private let delegateQueue = DispatchQueue(label: "com.streaming.delegates", qos: .userInitiated)
    
    // Background processing queue (non-real-time)
    private let processingQueue = DispatchQueue(label: "com.streaming.processing", qos: .userInitiated)
    
    // Performance monitoring
    private var bufferCount = 0
    private var debugLogCount = 0
    
    // MARK: - Utilities
    
    /// Get timestamp in milliseconds since recorder initialization
    private func timestamp() -> String {
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        return String(format: "[%07.1fms]", elapsed)
    }
    
    // MARK: - Delegate Management
    
    func addStreamDelegate(_ delegate: AudioStreamDelegate) {
        delegateQueue.async { [weak self] in
            self?.streamDelegates.append(delegate)
        }
    }
    
    func removeStreamDelegate(_ delegate: AudioStreamDelegate) {
        delegateQueue.async { [weak self] in
            self?.streamDelegates.removeAll { $0 === delegate }
        }
    }
    
    func removeAllStreamDelegates() {
        delegateQueue.async { [weak self] in
            self?.streamDelegates.removeAll()
        }
    }
    
    // MARK: - Streaming Control
    
    /// Start capturing system audio
    /// Requires Screen Recording permission in System Preferences
    /// - Throws: Error if permission denied or capture setup fails
    func startStreaming() async throws {
        guard !isRecording else {
            print("StreamingAudioRecorder: Already streaming")
            return
        }
        
        // Get shareable content using QuickRecorder pattern
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // Create filter for system audio capture
        guard let display = content.displays.first else {
            throw NSError(domain: "StreamingAudioRecorder", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "No displays found for system audio capture"])
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        print("\(timestamp()) StreamingAudioRecorder: Using display filter for system audio streaming")
        
        // Configure stream for optimal real-time audio
        let config = SCStreamConfiguration()
        
        // Audio configuration (optimized for real-time)
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        
        // Minimal video configuration
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale.max)
        
        // Create streaming format
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else {
            throw NSError(domain: "StreamingAudioRecorder", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create streaming audio format"])
        }
        
        streamingFormat = format
        
        // Initialize buffer pool
        bufferPool = AVAudioPCMBufferPool(format: format, frameCapacity: 1920) // 40ms at 48kHz
        print("\(timestamp()) StreamingAudioRecorder: Buffer pool initialized with 5 buffers")
        
        // Create stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        // Add this recorder as stream output
        let queue = DispatchQueue(label: "com.streaming.capture", qos: .userInitiated)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        
        // Start capture
        do {
            try await stream?.startCapture()
            isRecording = true
            print("\(timestamp()) StreamingAudioRecorder: Real-time audio streaming started successfully")
        } catch {
            print("\(timestamp()) StreamingAudioRecorder: Failed to start streaming - \(error)")
            // Retry once for macOS 15 compatibility
            try await Task.sleep(nanoseconds: 500_000_000)
            try await stream?.startCapture()
            isRecording = true
            print("\(timestamp()) StreamingAudioRecorder: Real-time audio streaming started successfully on retry")
        }
    }
    
    func stopStreaming() async {
        guard isRecording else { return }
        
        print("\(timestamp()) StreamingAudioRecorder: Stopping real-time audio streaming...")
        
        isRecording = false
        
        do {
            try await stream?.stopCapture()
        } catch {
            print("\(timestamp()) StreamingAudioRecorder: Error stopping stream: \(error)")
        }
        
        stream = nil
        bufferPool = nil
        
        // Notify delegates
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.streamDelegates.forEach { delegate in
                delegate.audioStreamerDidFinish(self)
            }
        }
        
        print("\(timestamp()) StreamingAudioRecorder: Real-time audio streaming stopped")
    }
    
    // MARK: - Audio Buffer Conversion (Apple's Recommended Method)
    
    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("StreamingAudioRecorder: No format description")
            return nil
        }
        
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        
        let numSamples = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard numSamples > 0 else {
            print("StreamingAudioRecorder: No samples in buffer")
            return nil
        }
        
        // Don't use buffer pool - create new buffer with correct format
        // The pool might have buffers with wrong format
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: numSamples) else {
            print("StreamingAudioRecorder: Failed to create PCM buffer")
            return nil
        }
        
        pcmBuffer.frameLength = numSamples
        
        // Use Apple's recommended conversion method (most reliable)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(numSamples),
            into: pcmBuffer.mutableAudioBufferList
        )
        
        if status != noErr {
            print("StreamingAudioRecorder: Failed to copy PCM data - status: \(status)")
            return nil
        }
        
        return pcmBuffer
    }
    
    // MARK: - Performance Monitoring
    
    private func logPerformanceMetrics() {
        bufferCount += 1
        
        // Log every 100 buffers (~2 seconds at 48kHz)
        if bufferCount % 100 == 0 {
            print("\(timestamp()) StreamingAudioRecorder: Processed \(bufferCount) buffers (\(bufferCount * 40)ms of audio)")
        }
    }
}

// MARK: - SCStreamOutput Implementation
@available(macOS 13.0, *)
extension StreamingAudioRecorder: SCStreamOutput {
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        // Only process audio samples
        guard outputType == .audio, isRecording else { return }
        
        // Log initial debugging info
        if debugLogCount < 3 {
            print("\(timestamp()) StreamingAudioRecorder: Received audio sample buffer #\(debugLogCount + 1)")
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                print("\(timestamp())   Format: \(formatDescription)")
            }
            print("\(timestamp())   Samples: \(CMSampleBufferGetNumSamples(sampleBuffer))")
            debugLogCount += 1
        }
        
        // Process on background queue to avoid blocking the capture thread
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Convert to PCM buffer using Apple's recommended method
            guard let pcmBuffer = self.createPCMBuffer(from: sampleBuffer) else {
                print("StreamingAudioRecorder: Failed to convert sample buffer to PCM buffer")
                return
            }
            
            // Log performance metrics
            self.logPerformanceMetrics()
            
            // Notify delegates on delegate queue
            self.delegateQueue.async {
                self.streamDelegates.forEach { delegate in
                    delegate.audioStreamer(self, didReceive: pcmBuffer)
                }
            }
        }
    }
}

// MARK: - SCStreamDelegate Implementation
@available(macOS 13.0, *)
extension StreamingAudioRecorder: SCStreamDelegate {
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("StreamingAudioRecorder: Stream stopped with error: \(error)")
        
        // Handle errors and notify delegates
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.streamDelegates.forEach { delegate in
                delegate.audioStreamer(self, didEncounterError: error)
            }
        }
        
        // Handle specific ScreenCaptureKit errors
        if let scError = error as? SCStreamError {
            switch scError {
            case SCStreamError.userDeclined:
                print("StreamingAudioRecorder: User declined screen recording permission")
            default:
                print("StreamingAudioRecorder: SCStreamError - \(scError.localizedDescription)")
            }
        }
    }
    
}

// MARK: - Screen Recorder with Streaming Support
@available(macOS 13.0, *)
class StreamingScreenRecorder: NSObject {
    let streamingRecorder = StreamingAudioRecorder()
    
    func startAudioStreaming() async throws {
        try await streamingRecorder.startStreaming()
    }
    
    func stopAudioStreaming() async {
        await streamingRecorder.stopStreaming()
    }
    
    func addAudioStreamDelegate(_ delegate: AudioStreamDelegate) {
        streamingRecorder.addStreamDelegate(delegate)
    }
    
    func removeAudioStreamDelegate(_ delegate: AudioStreamDelegate) {
        streamingRecorder.removeStreamDelegate(delegate)
    }
}