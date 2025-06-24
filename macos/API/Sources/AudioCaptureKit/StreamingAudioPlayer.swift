import Foundation
import AVFoundation

/// StreamingAudioPlayer - Real-time Audio Playback with Delay Support
///
/// This class provides high-performance audio playback using AVAudioEngine with
/// support for delayed playback. It automatically routes audio to USB SPDIF adapter
/// and handles format conversion as needed.
///
/// Key Features:
/// - Real-time PCM buffer playback with minimal latency
/// - Configurable playback delay (audio engine starts after delay)
/// - Automatic USB SPDIF adapter detection and routing
/// - Direct AVAudioPCMBuffer scheduling for zero-copy performance
/// - Volume control and playback status monitoring
///
/// Usage:
/// ```swift
/// let player = StreamingAudioPlayer(delay: 2.0) // 2 second delay
/// try player.startPlayback()
/// player.scheduleBuffer(audioBuffer)
/// ```
///
/// Technical Details:
/// - Uses AVAudioPlayerNode for hardware-accelerated playback
/// - Implements AudioStreamDelegate to receive buffers from recorder
/// - Handles Float32 deinterleaved format natively
/// - Delay is implemented by postponing audio engine start

// MARK: - Streaming Audio Player (Direct AVAudioPCMBuffer Support)
@available(macOS 13.0, *)
public class StreamingAudioPlayer: NSObject {
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let mixerNode = AVAudioMixerNode()
    
    // Start time for precise timing
    private let startTime = Date()
    
    private var isEngineRunning = false
    private var isPlayerPlaying = false
    private var outputFormat: AVAudioFormat?
    
    // Buffer management for continuous playback
    private var bufferQueue: [AVAudioPCMBuffer] = []
    private let bufferQueueLock = NSLock()
    private let maxQueueSize = 8
    private var isSchedulingBuffers = false
    
    // Performance monitoring
    private var buffersScheduled = 0
    private var buffersPlayed = 0
    private var debugLogCount = 0
    
    // Delay functionality
    private var playbackDelay: TimeInterval = 0.0
    private var delayStartTime: Date?
    private var delayBufferQueue: [AVAudioPCMBuffer] = []
    private let delayBufferLock = NSLock()
    private var isDelayActive = false
    
    // MARK: - Utilities
    
    /// Get timestamp in milliseconds since player initialization
    private func timestamp() -> String {
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        return String(format: "[%07.1fms]", elapsed)
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupAudioEngine()
    }
    
    convenience init(delay: TimeInterval) {
        self.init()
        setPlaybackDelay(delay)
    }
    
    deinit {
        stopPlayback()
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        // Set the output device to USB SPDIF Adapter
        setOutputDevice()
        
        // Attach nodes to engine
        audioEngine.attach(playerNode)
        audioEngine.attach(mixerNode)
        
        // Get the engine's output format
        outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        
        print("\(timestamp()) StreamingAudioPlayer: Engine output format: \(outputFormat!)")
        print("\(timestamp())   Sample Rate: \(outputFormat!.sampleRate)Hz")
        print("\(timestamp())   Channels: \(outputFormat!.channelCount)")
        print("\(timestamp())   Format: \(outputFormat!.commonFormat.rawValue)")
        print("\(timestamp())   Interleaved: \(outputFormat!.isInterleaved)")
        
        // Connect player to mixer, then to output
        audioEngine.connect(playerNode, to: mixerNode, format: outputFormat)
        audioEngine.connect(mixerNode, to: audioEngine.outputNode, format: nil)
        
        // Set initial volume
        playerNode.volume = 0.5
        
        print("\(timestamp()) StreamingAudioPlayer: Audio engine configured for direct PCM buffer streaming")
    }
    
    private func setOutputDevice() {
        // Find USB SPDIF Adapter device ID
        guard let usbSpdifDeviceID = findAudioDevice(named: "USB SPDIF Adapter") else {
            print("\(timestamp()) StreamingAudioPlayer: USB SPDIF Adapter not found, using default output")
            return
        }
        
        print("\(timestamp()) StreamingAudioPlayer: Setting output device to USB SPDIF Adapter (ID: \(usbSpdifDeviceID))")
        
        // Set the default output device
        var deviceID = usbSpdifDeviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        
        if result == noErr {
            print("\(timestamp()) StreamingAudioPlayer: Successfully set USB SPDIF Adapter as output device")
        } else {
            print("\(timestamp()) StreamingAudioPlayer: Failed to set USB SPDIF Adapter as output device (error: \(result))")
        }
    }
    
    private func findAudioDevice(named targetName: String) -> AudioDeviceID? {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &devices)
        
        for device in devices {
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            let result = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)
            if result == noErr {
                let deviceName = name as String
                if deviceName == targetName {
                    return device
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Playback Control
    
    public func startPlayback() throws {
        guard !isEngineRunning else { return }
        
        // Prepare and start the engine
        audioEngine.prepare()
        try audioEngine.start()
        isEngineRunning = true
        
        print("\(timestamp()) StreamingAudioPlayer: Audio engine started")
        
        // Start the player node
        if !playerNode.isPlaying {
            playerNode.play()
            isPlayerPlaying = true
            print("\(timestamp()) StreamingAudioPlayer: Player node started")
        }
    }
    
    public func stopPlayback() {
        if playerNode.isPlaying {
            playerNode.stop()
            isPlayerPlaying = false
        }
        
        if isEngineRunning {
            audioEngine.stop()
            isEngineRunning = false
        }
        
        // Clear buffer queue
        bufferQueueLock.lock()
        bufferQueue.removeAll()
        bufferQueueLock.unlock()
        
        // Clear delay state
        clearDelayState()
        
        print("\(timestamp()) StreamingAudioPlayer: Playback stopped")
    }
    
    // MARK: - Delay Management
    
    /// Set the playback delay in seconds
    /// - Parameter delay: Delay in seconds before audio playback starts
    func setPlaybackDelay(_ delay: TimeInterval) {
        delayBufferLock.lock()
        playbackDelay = max(0.0, delay)
        isDelayActive = playbackDelay > 0.0
        
        if isDelayActive {
            print("\(timestamp()) StreamingAudioPlayer: Playback delay set to \(playbackDelay) seconds")
        } else {
            print("\(timestamp()) StreamingAudioPlayer: No playback delay")
        }
        delayBufferLock.unlock()
    }
    
    /// Get the current playback delay
    var currentDelay: TimeInterval {
        return playbackDelay
    }
    
    /// Check if delay period has expired
    private func isDelayExpired() -> Bool {
        guard isDelayActive, let startTime = delayStartTime else { return true }
        return Date().timeIntervalSince(startTime) >= playbackDelay
    }
    
    /// Clean up delay state (no longer buffering - just timing delay)
    private func clearDelayState() {
        delayBufferLock.lock()
        delayBufferQueue.removeAll()
        delayStartTime = nil
        isDelayActive = false
        delayBufferLock.unlock()
    }
    
    // MARK: - Direct PCM Buffer Scheduling
    
    /// Schedule an audio buffer for playback
    /// During delay period, this method returns immediately without playing
    /// - Parameter buffer: The PCM audio buffer to play
    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isEngineRunning && isPlayerPlaying else {
            print("\(timestamp()) StreamingAudioPlayer: Cannot schedule buffer - engine not running")
            return
        }
        
        // Log buffer details (first few times)
        if debugLogCount < 3 {
            print("\(timestamp()) StreamingAudioPlayer: Scheduling PCM buffer #\(debugLogCount + 1)")
            print("\(timestamp())   Format: \(buffer.format)")
            print("\(timestamp())   Frame length: \(buffer.frameLength)")
            print("\(timestamp())   Frame capacity: \(buffer.frameCapacity)")
            debugLogCount += 1
        }
        
        // Check if format conversion is needed
        if let outputFormat = outputFormat, !buffer.format.isEqual(outputFormat) {
            // Convert buffer to output format
            if let convertedBuffer = convertBuffer(buffer, to: outputFormat) {
                scheduleConvertedBuffer(convertedBuffer)
            } else {
                print("\(timestamp()) StreamingAudioPlayer: Failed to convert buffer format")
            }
        } else {
            // Schedule buffer directly (optimal path)
            scheduleConvertedBuffer(buffer)
        }
    }
    
    private func scheduleConvertedBuffer(_ buffer: AVAudioPCMBuffer) {
        buffersScheduled += 1
        
        // Schedule the buffer for immediate playback
        playerNode.scheduleBuffer(buffer) { [weak self] in
            self?.bufferQueueLock.lock()
            self?.buffersPlayed += 1
            
            // Log performance metrics occasionally
            if let self = self, self.buffersPlayed % 50 == 0 {
                let latency = self.buffersScheduled - self.buffersPlayed
                print("\(self.timestamp()) StreamingAudioPlayer: Played \(self.buffersPlayed) buffers, queue latency: \(latency)")
            }
            
            self?.bufferQueueLock.unlock()
            
            // Schedule next buffer if available
            self?.processBufferQueue()
        }
    }
    
    private func processBufferQueue() {
        bufferQueueLock.lock()
        guard !bufferQueue.isEmpty else {
            bufferQueueLock.unlock()
            return
        }
        
        let nextBuffer = bufferQueue.removeFirst()
        bufferQueueLock.unlock()
        
        // Schedule next buffer
        scheduleConvertedBuffer(nextBuffer)
    }
    
    // MARK: - Format Conversion (If Needed)
    
    private func convertBuffer(_ inputBuffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Create converter
        guard let converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat) else {
            print("StreamingAudioPlayer: Failed to create audio converter")
            return nil
        }
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputBuffer.frameLength) else {
            print("StreamingAudioPlayer: Failed to create output buffer")
            return nil
        }
        
        // Convert audio
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("StreamingAudioPlayer: Conversion error: \(error)")
            return nil
        }
        
        if status == .haveData && outputBuffer.frameLength > 0 {
            return outputBuffer
        } else {
            print("StreamingAudioPlayer: Conversion failed - status: \(status)")
            return nil
        }
    }
    
    // MARK: - Buffer Queue Management
    
    private func addToBufferQueue(_ buffer: AVAudioPCMBuffer) {
        bufferQueueLock.lock()
        
        // Prevent buffer queue from growing too large (memory management)
        if bufferQueue.count >= maxQueueSize {
            // Remove oldest buffer
            bufferQueue.removeFirst()
            print("StreamingAudioPlayer: Buffer queue full, dropping oldest buffer")
        }
        
        bufferQueue.append(buffer)
        bufferQueueLock.unlock()
    }
    
    // MARK: - Volume Control
    
    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = max(0.0, min(1.0, newValue)) }
    }
    
    // MARK: - Status
    
    var isPlaybackActive: Bool {
        return isEngineRunning && isPlayerPlaying
    }
    
    // MARK: - Test Functions
    
    func playTestTone(duration: Double) throws {
        try startPlayback()
        
        guard let format = outputFormat else {
            throw NSError(domain: "StreamingAudioPlayer", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "No audio format available"])
        }
        
        let sampleRate = format.sampleRate
        let frequency: Float = 440.0 // A4 note
        let frameCount: AVAudioFrameCount = 1920 // 40ms at 48kHz
        
        print("StreamingAudioPlayer: Generating \(duration)s test tone at \(frequency)Hz")
        
        // Generate and schedule test tone buffers
        let totalFrames = AVAudioFrameCount(duration * sampleRate)
        var framesScheduled: AVAudioFrameCount = 0
        
        while framesScheduled < totalFrames {
            let framesToSchedule = min(frameCount, totalFrames - framesScheduled)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToSchedule) else {
                throw NSError(domain: "StreamingAudioPlayer", code: 2, 
                             userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
            }
            
            buffer.frameLength = framesToSchedule
            
            // Generate sine wave
            for channel in 0..<Int(format.channelCount) {
                guard let channelData = buffer.floatChannelData?[channel] else { continue }
                for frame in 0..<Int(framesToSchedule) {
                    let sampleIndex = framesScheduled + AVAudioFrameCount(frame)
                    let t = Float(sampleIndex) / Float(sampleRate)
                    channelData[frame] = sin(2.0 * .pi * frequency * t) * 0.3
                }
            }
            
            scheduleBuffer(buffer)
            framesScheduled += framesToSchedule
        }
        
        // Wait for completion
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + duration + 1.0) {
            semaphore.signal()
        }
        semaphore.wait()
        
        stopPlayback()
    }
    
    // MARK: - Status Information
    
    func getPlaybackStatus() -> [String: Any] {
        bufferQueueLock.lock()
        let queueCount = bufferQueue.count
        bufferQueueLock.unlock()
        
        delayBufferLock.lock()
        let remainingDelay: TimeInterval
        if isDelayActive, let startTime = delayStartTime {
            remainingDelay = max(0, playbackDelay - Date().timeIntervalSince(startTime))
        } else {
            remainingDelay = 0
        }
        delayBufferLock.unlock()
        
        return [
            "isEngineRunning": isEngineRunning,
            "isPlayerPlaying": isPlayerPlaying,
            "volume": volume,
            "buffersScheduled": buffersScheduled,
            "buffersPlayed": buffersPlayed,
            "queuedBuffers": queueCount,
            "outputFormat": outputFormat?.description ?? "nil",
            "playbackDelay": playbackDelay,
            "isDelayActive": isDelayActive,
            "remainingDelay": remainingDelay
        ]
    }
}

// MARK: - AudioStreamDelegate Implementation
@available(macOS 13.0, *)
extension StreamingAudioPlayer: AudioStreamDelegate {
    
    public func audioStreamer(_ streamer: StreamingAudioRecorder, didReceive buffer: AVAudioPCMBuffer) {
        // Handle delay - don't even start the engine until delay expires
        if isDelayActive {
            delayBufferLock.lock()
            
            // Start delay timer on first buffer
            if delayStartTime == nil {
                delayStartTime = Date()
                print("\(timestamp()) StreamingAudioPlayer: Starting \(playbackDelay)s delay timer - audio engine will start after delay...")
            }
            
            // Check if delay has expired
            if isDelayExpired() {
                print("\(timestamp()) StreamingAudioPlayer: Delay period expired - starting audio engine now!")
                isDelayActive = false
                delayBufferLock.unlock()
                
                // Start playback fresh after delay
                if !isEngineRunning {
                    do {
                        try startPlayback()
                        print("\(timestamp()) StreamingAudioPlayer: Audio engine started fresh after delay")
                    } catch {
                        print("\(timestamp()) StreamingAudioPlayer: Failed to start playback: \(error)")
                        return
                    }
                }
                
                // Schedule this buffer immediately
                scheduleBuffer(buffer)
            } else {
                // Log delay progress
                let elapsed = Date().timeIntervalSince(delayStartTime!)
                let remaining = playbackDelay - elapsed
                
                if Int(elapsed * 10) % 5 == 0 { // Every 0.5 seconds
                    print("\(timestamp()) StreamingAudioPlayer: Delay in progress (\(String(format: "%.1f", remaining))s remaining) - engine not started")
                }
                
                delayBufferLock.unlock()
                return // Drop this buffer
            }
        } else {
            // No delay or delay has expired - ensure engine is running
            if !isEngineRunning {
                print("\(timestamp()) StreamingAudioPlayer: Starting playback on first audio buffer")
                do {
                    try startPlayback()
                } catch {
                    print("\(timestamp()) StreamingAudioPlayer: Failed to start playback: \(error)")
                    return
                }
            }
            
            // Schedule buffer for immediate playback
            scheduleBuffer(buffer)
        }
    }
    
    public func audioStreamer(_ streamer: StreamingAudioRecorder, didEncounterError error: Error) {
        print("\(timestamp()) StreamingAudioPlayer: Audio streamer error: \(error)")
    }
    
    public func audioStreamerDidFinish(_ streamer: StreamingAudioRecorder) {
        print("\(timestamp()) StreamingAudioPlayer: Audio streamer finished")
        stopPlayback()
    }
}