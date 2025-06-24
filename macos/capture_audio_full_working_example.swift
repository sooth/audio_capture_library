import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreAudio

// Direct Audio Capture - Bypasses the AudioDevice API and uses AVAudioEngine directly
// Captures both system audio and Beats Fit Pro microphone

@main
struct DirectAudioCapture {
    static func main() async {
        print("Direct Audio Capture: System Output + Microphone")
        print("=================================================\n")
        
        // Check permissions first
        await checkPermissions()
        
        // Start capture
        await captureAudio()
    }
    
    static func checkPermissions() async {
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("✓ Microphone permission: Authorized")
        case .notDetermined:
            print("Requesting microphone permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            print(granted ? "✓ Microphone permission: Granted" : "❌ Microphone permission: Denied")
        case .denied, .restricted:
            print("❌ Microphone permission: Denied")
            print("   Please enable in System Settings > Privacy & Security > Microphone")
        @unknown default:
            break
        }
        
        print("")
    }
    
    static func captureAudio() async {
        do {
            // First, list all available audio devices
            print("Scanning for audio devices...")
            let inputDevices = getAllInputDevices()
            
            // Prompt user to select microphone
            print("\nAvailable Microphones:")
            print("======================")
            for (index, device) in inputDevices.enumerated() {
                print("  \(index + 1). \(device.name) [ID: \(device.id)]")
            }
            
            print("\nSelect microphone (enter number): ", terminator: "")
            guard let micChoice = readLine(), 
                  let micIndex = Int(micChoice),
                  micIndex > 0 && micIndex <= inputDevices.count else {
                print("❌ Invalid selection")
                return
            }
            
            let selectedMic = inputDevices[micIndex - 1]
            print("✓ Selected: \(selectedMic.name)")
            
            // Ask about system audio capture
            print("\nCapture system audio? (y/n): ", terminator: "")
            let captureSystemAudio = readLine()?.lowercased() == "y"
            
            // Create audio engine for microphone capture
            let audioEngine = AVAudioEngine()
            
            // Set the selected microphone BEFORE accessing inputNode
            print("\nSetting up microphone...")
            
            // Get the input node (this creates the audio unit)
            let inputNode = audioEngine.inputNode
            
            // Now set the device
            try setInputDevice(selectedMic.id, for: audioEngine)
            print("✓ Set \(selectedMic.name) as input device")
            
            // Setup system audio capture
            print("\nSetting up audio capture...")
            
            // System audio setup (only if user chose to capture it)
            var systemRecorder: StreamingAudioRecorder?
            var systemCollector: BufferCollector?
            
            if captureSystemAudio {
                systemRecorder = StreamingAudioRecorder()
                systemCollector = BufferCollector()
                systemRecorder!.addStreamDelegate(systemCollector!)
                print("✓ System audio capture configured")
            }
            
            // Get the actual hardware format of the input
            let hardwareFormat = inputNode.outputFormat(forBus: 0)
            print("\nMicrophone hardware format:")
            print("  Sample Rate: \(hardwareFormat.sampleRate) Hz")
            print("  Channels: \(hardwareFormat.channelCount)")
            print("  Interleaved: \(hardwareFormat.isInterleaved)")
            
            // Create a mic buffer collector that converts to 48kHz stereo
            let micCollector = ConvertingBufferCollector(
                inputFormat: hardwareFormat,
                outputSampleRate: 48000,
                outputChannels: 2
            )
            
            // Install tap with hardware format
            print("Installing tap on input node...")
            var tapCallCount = 0
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: nil  // Use hardware format
            ) { buffer, time in
                tapCallCount += 1
                if tapCallCount <= 3 {
                    print("  Mic tap called #\(tapCallCount): \(buffer.frameLength) frames @ \(buffer.format.sampleRate)Hz")
                }
                micCollector.addBuffer(buffer)
            }
            print("✓ Tap installed on input node")
            
            // Start captures
            print("\nStarting captures...")
            
            // Start microphone
            try audioEngine.start()
            print("✓ Microphone capture started")
            
            // Start system audio if selected
            if captureSystemAudio, let recorder = systemRecorder {
                try await recorder.startStreaming()
                print("✓ System audio capture started")
            }
            
            // Record for 10 seconds
            print("\nRecording for 10 seconds...")
            if captureSystemAudio {
                print("Make some noise to test both inputs!\n")
            } else {
                print("Recording microphone only...\n")
            }
            
            for i in 1...10 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                if captureSystemAudio, let collector = systemCollector {
                    print("  \(i)... (System: \(collector.buffers.count) buffers, Mic: \(micCollector.buffers.count) buffers)")
                } else {
                    print("  \(i)... (Mic: \(micCollector.buffers.count) buffers)")
                }
            }
            
            // Stop captures
            print("\nStopping captures...")
            
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            
            if captureSystemAudio, let recorder = systemRecorder {
                await recorder.stopStreaming()
            }
            
            // Export audio
            if captureSystemAudio, let collector = systemCollector, !collector.buffers.isEmpty && !micCollector.buffers.isEmpty {
                // Mix system and mic audio
                let mixed = try mixAudioBuffers(
                    systemBuffers: collector.buffers,
                    micBuffers: micCollector.buffers
                )
                
                let outputPath = "mixed_direct_output.wav"
                try await exportToWAV(buffers: mixed, outputPath: outputPath)
                
                print("\n✓ Mixed audio exported to: \(outputPath)")
                print("  System buffers: \(collector.buffers.count)")
                print("  Mic buffers: \(micCollector.buffers.count)")
            } else if !micCollector.buffers.isEmpty {
                // Export mic only
                let outputPath = captureSystemAudio ? "mic_only_output.wav" : "microphone_recording.wav"
                try await exportToWAV(buffers: micCollector.buffers, outputPath: outputPath)
                print("\n✓ Microphone audio exported to: \(outputPath)")
                print("  Mic buffers: \(micCollector.buffers.count)")
                
                if captureSystemAudio, let collector = systemCollector {
                    if collector.buffers.isEmpty {
                        print("  Note: System audio capture was enabled but no buffers were received")
                    }
                }
            } else {
                print("\n❌ No audio was captured")
            }
            
        } catch {
            print("\n❌ Error: \(error)")
        }
    }
    
    // Simple device info struct
    struct AudioDeviceInfo {
        let id: AudioDeviceID
        let name: String
    }
    
    // Get all input devices
    static func getAllInputDevices() -> [AudioDeviceInfo] {
        var devices: [AudioDeviceInfo] = []
        
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Get size
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        ) == noErr else { return devices }
        
        // Get devices
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &audioDevices
        ) == noErr else { return devices }
        
        for deviceID in audioDevices {
            // Check if it's an input device
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            
            if AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr && inputSize > 0 {
                // Get device name
                var nameSize: UInt32 = 0
                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceNameCFString,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                
                guard AudioObjectGetPropertyDataSize(
                    deviceID,
                    &nameAddress,
                    0,
                    nil,
                    &nameSize
                ) == noErr else { continue }
                
                var deviceName: CFString = "" as CFString
                guard AudioObjectGetPropertyData(
                    deviceID,
                    &nameAddress,
                    0,
                    nil,
                    &nameSize,
                    &deviceName
                ) == noErr else { continue }
                
                let name = deviceName as String
                devices.append(AudioDeviceInfo(id: deviceID, name: name))
            }
        }
        
        return devices
    }
    
    // List all audio devices
    static func listAllAudioDevices() {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Get size
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        ) == noErr else { 
            print("Failed to get device list size")
            return 
        }
        
        // Get devices
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &audioDevices
        ) == noErr else { 
            print("Failed to get device list")
            return 
        }
        
        print("\nAvailable Audio Devices:")
        print("========================")
        
        for deviceID in audioDevices {
            // Get device name
            var nameSize: UInt32 = 0
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            guard AudioObjectGetPropertyDataSize(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize
            ) == noErr else { continue }
            
            var deviceName: CFString = "" as CFString
            guard AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                &deviceName
            ) == noErr else { continue }
            
            let deviceNameString = deviceName as String
            
            // Check if input or output
            var hasInput = false
            var hasOutput = false
            
            // Check input
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr && inputSize > 0 {
                hasInput = true
            }
            
            // Check output
            var outputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var outputSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(deviceID, &outputAddress, 0, nil, &outputSize) == noErr && outputSize > 0 {
                hasOutput = true
            }
            
            let type = hasInput ? (hasOutput ? "Input/Output" : "Input") : "Output"
            print("  ID \(deviceID): \(deviceNameString) [\(type)]")
        }
        print("")
    }
    
    // Find audio device by name
    static func findAudioDevice(named name: String, isInput: Bool) -> AudioDeviceID? {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Get size
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        ) == noErr else { return nil }
        
        // Get devices
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &audioDevices
        ) == noErr else { return nil }
        
        // Find device by name
        for deviceID in audioDevices {
            // Get device name
            var nameSize: UInt32 = 0
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            guard AudioObjectGetPropertyDataSize(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize
            ) == noErr else { continue }
            
            var deviceName: CFString = "" as CFString
            guard AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                &deviceName
            ) == noErr else { continue }
            
            let deviceNameString = deviceName as String
            
            // Check if this is the device we want and has correct type
            if deviceNameString.contains(name) {
                // Check if it has the correct scope (input/output)
                let scope = isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
                var streamAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreams,
                    mScope: scope,
                    mElement: kAudioObjectPropertyElementMain
                )
                var streamSize: UInt32 = 0
                
                if AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) == noErr && streamSize > 0 {
                    return deviceID
                }
            }
        }
        
        return nil
    }
    
    // Set input device for audio engine
    static func setInputDevice(_ deviceID: AudioDeviceID, for engine: AVAudioEngine) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio unit on input node"])
        }
        
        // First, enable IO for input
        var enableIO: UInt32 = 1
        var result = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,  // input element
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        if result != noErr {
            print("Failed to enable input IO: \(result)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
        
        // Set the input device
        var deviceIDVar = deviceID
        result = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDVar,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        if result != noErr {
            print("Failed to set device: \(result)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
        
        print("✓ Audio unit configured for device ID: \(deviceID)")
    }
    
    // Mix audio buffers
    static func mixAudioBuffers(systemBuffers: [AVAudioPCMBuffer], micBuffers: [AVAudioPCMBuffer]) throws -> [AVAudioPCMBuffer] {
        guard !systemBuffers.isEmpty && !micBuffers.isEmpty else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No buffers to mix"])
        }
        
        // Use the format from system buffers
        guard let format = systemBuffers.first?.format else {
            throw NSError(domain: "AudioCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "No format available"])
        }
        
        print("\nMixing audio streams...")
        print("  Format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        print("  System buffers: \(systemBuffers.count)")
        print("  Mic buffers: \(micBuffers.count)")
        
        // Calculate total frames
        let systemFrames = systemBuffers.reduce(0) { $0 + Int($1.frameLength) }
        let micFrames = micBuffers.reduce(0) { $0 + Int($1.frameLength) }
        print("  System total frames: \(systemFrames) (\(Double(systemFrames) / format.sampleRate) seconds)")
        print("  Mic total frames: \(micFrames) (\(Double(micFrames) / format.sampleRate) seconds)")
        
        // First, combine all mic buffers into one continuous buffer to avoid popping
        let totalMicFrames = micBuffers.reduce(0) { $0 + Int($1.frameLength) }
        guard let combinedMicBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalMicFrames)) else {
            throw NSError(domain: "AudioCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create combined buffer"])
        }
        
        combinedMicBuffer.frameLength = 0
        
        // Copy all mic buffers into the combined buffer
        if let combinedData = combinedMicBuffer.floatChannelData {
            for micBuffer in micBuffers {
                if let micData = micBuffer.floatChannelData {
                    let startFrame = Int(combinedMicBuffer.frameLength)
                    for channel in 0..<Int(format.channelCount) {
                        for frame in 0..<Int(micBuffer.frameLength) {
                            combinedData[channel][startFrame + frame] = micData[channel][frame]
                        }
                    }
                    combinedMicBuffer.frameLength += micBuffer.frameLength
                }
            }
        }
        
        // Now mix with system buffers
        var mixed: [AVAudioPCMBuffer] = []
        var micFrameOffset = 0
        
        for systemBuffer in systemBuffers {
            // Create mixed buffer
            guard let mixedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: systemBuffer.frameLength) else {
                continue
            }
            
            mixedBuffer.frameLength = systemBuffer.frameLength
            
            // Mix the audio data
            if let systemData = systemBuffer.floatChannelData,
               let micData = combinedMicBuffer.floatChannelData,
               let mixedData = mixedBuffer.floatChannelData {
                
                for frame in 0..<Int(systemBuffer.frameLength) {
                    // Mix samples
                    for channel in 0..<Int(format.channelCount) {
                        let systemSample = systemData[channel][frame]
                        
                        // Get mic sample with wraparound if needed
                        let micSample: Float
                        if micFrameOffset < Int(combinedMicBuffer.frameLength) {
                            micSample = micData[channel][micFrameOffset]
                        } else {
                            // If we run out of mic data, use silence
                            micSample = 0.0
                        }
                        
                        mixedData[channel][frame] = systemSample * 0.5 + micSample * 0.5
                    }
                    
                    micFrameOffset += 1
                }
            }
            
            mixed.append(mixedBuffer)
        }
        
        print("  Mixed \(mixed.count) buffers")
        
        return mixed
    }
    
    // Export to WAV
    static func exportToWAV(buffers: [AVAudioPCMBuffer], outputPath: String) async throws {
        guard let firstBuffer = buffers.first else {
            throw NSError(domain: "AudioCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "No buffers to export"])
        }
        
        let format = firstBuffer.format
        let url = URL(fileURLWithPath: outputPath)
        
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        
        for buffer in buffers {
            try file.write(from: buffer)
        }
    }
}

// Buffer collector that works as both a delegate and direct collector
class BufferCollector: NSObject, AudioStreamDelegate {
    var buffers: [AVAudioPCMBuffer] = []
    let queue = DispatchQueue(label: "buffer.collector")
    
    func addBuffer(_ buffer: AVAudioPCMBuffer) {
        queue.sync {
            buffers.append(buffer)
        }
    }
    
    // AudioStreamDelegate methods
    func audioStreamer(_ streamer: StreamingAudioRecorder, didReceive buffer: AVAudioPCMBuffer) {
        addBuffer(buffer)
    }
    
    func audioStreamer(_ streamer: StreamingAudioRecorder, didEncounterError error: Error) {
        print("Stream error: \(error)")
    }
    
    func audioStreamerDidFinish(_ streamer: StreamingAudioRecorder) {
        // Nothing to do
    }
}

// Converting buffer collector that resamples and changes channel count
class ConvertingBufferCollector: BufferCollector {
    private let converter: AVAudioConverter
    private let intermediateFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let needsStereoConversion: Bool
    
    init(inputFormat: AVAudioFormat, outputSampleRate: Double, outputChannels: AVAudioChannelCount) {
        // If converting from mono to stereo, first convert sample rate with mono
        // then duplicate channels (AVAudioConverter can't do both at once reliably)
        self.needsStereoConversion = inputFormat.channelCount == 1 && outputChannels == 2
        
        if needsStereoConversion {
            // First convert to target sample rate in mono
            self.intermediateFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputSampleRate,
                channels: 1,
                interleaved: false
            )!
            self.outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputSampleRate,
                channels: outputChannels,
                interleaved: false
            )!
            self.converter = AVAudioConverter(from: inputFormat, to: intermediateFormat)!
        } else {
            // Direct conversion
            self.intermediateFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputSampleRate,
                channels: outputChannels,
                interleaved: false
            )!
            self.outputFormat = intermediateFormat
            self.converter = AVAudioConverter(from: inputFormat, to: outputFormat)!
        }
        
        // Set converter to highest quality
        converter.sampleRateConverterQuality = .max
        
        super.init()
        
        print("Created audio converter:")
        print("  From: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")
        print("  To: \(outputFormat.sampleRate)Hz, \(outputFormat.channelCount)ch")
        print("  Two-stage conversion: \(needsStereoConversion)")
    }
    
    override func addBuffer(_ buffer: AVAudioPCMBuffer) {
        queue.sync {
            // Calculate output frame capacity
            let sampleRateRatio = intermediateFormat.sampleRate / buffer.format.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio + 2)
            
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: intermediateFormat, frameCapacity: outputFrameCapacity) else {
                return
            }
            
            var error: NSError?
            var bufferSubmitted = false
            
            // Use the proper input block method for sample rate conversion
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                if bufferSubmitted {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                bufferSubmitted = true
                outStatus.pointee = .haveData
                return buffer
            }
            
            let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if status == .error {
                print("Conversion error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            
            // Debug: Print conversion info periodically
            if buffers.count % 10 == 0 {
                print("Converted buffer \(buffers.count): \(buffer.frameLength) frames @ \(buffer.format.sampleRate)Hz -> \(convertedBuffer.frameLength) frames @ \(intermediateFormat.sampleRate)Hz")
            }
            
            // If we need stereo conversion, do it now
            if needsStereoConversion {
                guard let stereoBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: convertedBuffer.frameLength) else {
                    return
                }
                stereoBuffer.frameLength = convertedBuffer.frameLength
                
                if let monoData = convertedBuffer.floatChannelData?[0],
                   let stereoData = stereoBuffer.floatChannelData {
                    // Copy mono channel to both stereo channels
                    for frame in 0..<Int(convertedBuffer.frameLength) {
                        stereoData[0][frame] = monoData[frame]
                        stereoData[1][frame] = monoData[frame]
                    }
                }
                
                buffers.append(stereoBuffer)
            } else {
                buffers.append(convertedBuffer)
            }
        }
    }
}