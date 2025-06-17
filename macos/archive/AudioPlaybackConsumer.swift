import Foundation
import AVFoundation

@available(macOS 13.0, *)
class AudioPlaybackConsumer: NSObject {
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioConverter: AVAudioConverter?
    
    private var isEngineRunning = false
    private var audioFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    
    // Debug logging counter
    private var debugLogCount = 0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupAudioEngine()
    }
    
    deinit {
        stopPlayback()
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        // Set the output device to USB SPDIF Adapter before setting up the engine
        setOutputDevice()
        
        // Attach player node to engine
        audioEngine.attach(playerNode)
        
        // Get the engine's output format
        outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        
        print("AudioPlaybackConsumer: Engine output format: \(outputFormat!)")
        print("  Sample Rate: \(outputFormat!.sampleRate)Hz")
        print("  Channels: \(outputFormat!.channelCount)")
        print("  Format: \(outputFormat!.commonFormat.rawValue)")
        
        // Connect player directly to output
        audioEngine.connect(playerNode, to: audioEngine.outputNode, format: outputFormat)
        
        // Set initial volume
        playerNode.volume = 0.5
        
        print("AudioPlaybackConsumer: Audio engine configured")
    }
    
    private func setOutputDevice() {
        // Find USB SPDIF Adapter device ID
        guard let usbSpdifDeviceID = findAudioDevice(named: "USB SPDIF Adapter") else {
            print("AudioPlaybackConsumer: USB SPDIF Adapter not found, using default output")
            return
        }
        
        print("AudioPlaybackConsumer: Setting output device to USB SPDIF Adapter (ID: \(usbSpdifDeviceID))")
        
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
            print("AudioPlaybackConsumer: Successfully set USB SPDIF Adapter as output device")
        } else {
            print("AudioPlaybackConsumer: Failed to set USB SPDIF Adapter as output device (error: \(result))")
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
    
    private func startAudioEngine() throws {
        guard !isEngineRunning else { return }
        
        // Prepare and start the engine
        audioEngine.prepare()
        try audioEngine.start()
        isEngineRunning = true
        
        print("AudioPlaybackConsumer: Audio engine started")
    }
    
    // MARK: - Playback Control
    
    func startPlayback() throws {
        try startAudioEngine()
        
        if !playerNode.isPlaying {
            playerNode.play()
            print("AudioPlaybackConsumer: Player node started")
        }
    }
    
    func stopPlayback() {
        if playerNode.isPlaying {
            playerNode.stop()
        }
        
        if isEngineRunning {
            audioEngine.stop()
            isEngineRunning = false
        }
        
        print("AudioPlaybackConsumer: Playback stopped")
    }
    
    // MARK: - Volume Control
    
    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = max(0.0, min(1.0, newValue)) }
    }
    
    // MARK: - Status
    
    var isPlaybackActive: Bool {
        return isEngineRunning && playerNode.isPlaying
    }
    
    // MARK: - Test Functions
    
    func playTestTone(duration: Double) throws {
        try startPlayback()
        
        guard let format = outputFormat else {
            throw NSError(domain: "AudioPlaybackConsumer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio format available"])
        }
        
        let sampleRate = format.sampleRate
        let frequency: Float = 440.0 // A4 note
        let frameCount: AVAudioFrameCount = 1024
        
        print("AudioPlaybackConsumer: Generating \(duration)s test tone at \(frequency)Hz")
        
        // Generate and schedule test tone buffers
        let totalFrames = AVAudioFrameCount(duration * sampleRate)
        var framesScheduled: AVAudioFrameCount = 0
        
        while framesScheduled < totalFrames {
            let framesToSchedule = min(frameCount, totalFrames - framesScheduled)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToSchedule) else {
                throw NSError(domain: "AudioPlaybackConsumer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
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
            
            playerNode.scheduleBuffer(buffer)
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
    
    // MARK: - Audio Processing
    
    private func setupConverter(inputFormat: AVAudioFormat) {
        guard let outputFormat = outputFormat else { return }
        
        audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
        
        print("AudioPlaybackConsumer: Created converter")
        print("  Input: \(inputFormat)")
        print("  Output: \(outputFormat)")
    }
    
    private func convertAndPlayAudio(data: Data, inputFormat: AVAudioFormat) {
        // Set up converter if needed
        if audioConverter == nil {
            setupConverter(inputFormat: inputFormat)
        }
        
        guard let converter = audioConverter,
              let outputFormat = outputFormat else {
            print("AudioPlaybackConsumer: No converter available")
            return
        }
        
        // Calculate input frame count
        let bytesPerFrame = inputFormat.streamDescription.pointee.mBytesPerFrame
        let inputFrameCount = AVAudioFrameCount(data.count) / AVAudioFrameCount(bytesPerFrame)
        
        // Create input buffer
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCount) else {
            print("AudioPlaybackConsumer: Failed to create input buffer")
            return
        }
        
        inputBuffer.frameLength = inputFrameCount
        
        // Copy data to input buffer
        data.withUnsafeBytes { bytes in
            let audioBufferList = inputBuffer.mutableAudioBufferList
            var buffer = audioBufferList.pointee.mBuffers
            memcpy(buffer.mData, bytes.baseAddress, data.count)
            buffer.mDataByteSize = UInt32(data.count)
            audioBufferList.pointee.mBuffers = buffer
        }
        
        // Create output buffer (same size as input for simplicity)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputFrameCount) else {
            print("AudioPlaybackConsumer: Failed to create output buffer")
            return
        }
        
        // Convert audio
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("AudioPlaybackConsumer: Conversion error: \(error)")
            return
        }
        
        if status == .haveData && outputBuffer.frameLength > 0 {
            if debugLogCount < 5 {
                print("AudioPlaybackConsumer: Scheduling buffer with \(outputBuffer.frameLength) frames")
            }
            playerNode.scheduleBuffer(outputBuffer)
        } else {
            print("AudioPlaybackConsumer: Conversion failed - status: \(status), frames: \(outputBuffer.frameLength)")
        }
    }
}

// MARK: - AudioDataDelegate Implementation

@available(macOS 13.0, *)
extension AudioPlaybackConsumer: AudioDataDelegate {
    
    func audioRecorder(_ recorder: AudioRecorder, didReceiveAudioData data: Data, format: AVAudioFormat) {
        // Log incoming audio data details (only first few times to avoid spam)
        if debugLogCount < 3 {
            print("AudioPlaybackConsumer: Received audio data #\(debugLogCount + 1)")
            print("  Incoming format: \(format)")
            print("  Data size: \(data.count) bytes")
            debugLogCount += 1
        }
        
        // Start playback on first callback if not already started
        if !isEngineRunning {
            print("AudioPlaybackConsumer: Starting playback on first audio data")
            do {
                try startPlayback()
            } catch {
                print("AudioPlaybackConsumer: Failed to start playback: \(error)")
                return
            }
        }
        
        guard data.count > 0 else {
            print("AudioPlaybackConsumer: Empty audio data received")
            return
        }
        
        // Convert and play audio using AVAudioConverter
        convertAndPlayAudio(data: data, inputFormat: format)
    }
}

// MARK: - Convenience Extensions

@available(macOS 13.0, *)
extension AudioPlaybackConsumer {
    
    /// Get current playback status information
    func getPlaybackStatus() -> [String: Any] {
        return [
            "isEngineRunning": isEngineRunning,
            "isPlayerPlaying": playerNode.isPlaying,
            "volume": volume,
            "audioFormat": audioFormat?.description ?? "nil"
        ]
    }
    
    /// Reset the audio consumer (useful for format changes)
    func reset() {
        stopPlayback()
        audioConverter = nil
        audioFormat = nil
        print("AudioPlaybackConsumer: Reset completed")
    }
}