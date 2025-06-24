import Foundation
import AVFoundation

/// WavFileWriter - High-Quality WAV File Recording
///
/// This class handles writing audio buffers to standard WAV files with proper
/// format conversion from the capture format (Float32 deinterleaved) to standard
/// WAV format (Int16 interleaved).
///
/// Key Features:
/// - Standard WAV file format: 16-bit PCM, 48kHz, stereo, interleaved
/// - Two-step format conversion for compatibility
/// - Thread-safe file writing on background queue
/// - Real-time progress monitoring
/// - Implements AudioStreamDelegate for seamless integration
///
/// Format Conversion Pipeline:
/// 1. Input: Float32, 48kHz, 2ch, deinterleaved (from ScreenCaptureKit)
/// 2. Step 1: Float32 deinterleaved → Float32 interleaved
/// 3. Step 2: Float32 interleaved → Int16 interleaved
/// 4. Output: Standard WAV file
///
/// Usage:
/// ```swift
/// let writer = try WavFileWriter(sampleRate: 48000.0, channels: 2)
/// try writer.startWriting(to: "recording.wav")
/// writer.write(audioBuffer)
/// writer.stopWriting()
/// ```

// MARK: - WAV File Writer
@available(macOS 13.0, *)
public class WavFileWriter: NSObject {
    
    // MARK: - Properties
    
    private var audioFile: AVAudioFile?
    private let writeQueue = DispatchQueue(label: "com.wavwriter.queue", qos: .utility)
    private var isWriting = false
    
    // Start time for precise timing
    private let startTime = Date()
    
    // Output format for WAV file (16-bit PCM is standard)
    private let outputFormat: AVAudioFormat
    
    // Format converter
    private var converter: AVAudioConverter?
    
    // Statistics
    private var buffersWritten = 0
    private var samplesWritten: Int64 = 0
    
    // MARK: - Utilities
    
    /// Get timestamp in milliseconds since writer initialization
    private func timestamp() -> String {
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        return String(format: "[%07.1fms]", elapsed)
    }
    
    // MARK: - Initialization
    
    init(sampleRate: Double = 48000.0, channels: UInt32 = 2) throws {
        // Create standard WAV format (16-bit PCM)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: sampleRate,
                                        channels: channels,
                                        interleaved: true) else {
            throw NSError(domain: "WavFileWriter", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create WAV format"])
        }
        
        self.outputFormat = format
        super.init()
        
        print("\(timestamp()) WavFileWriter: Initialized with format:")
        print("\(timestamp())   Sample Rate: \(sampleRate)Hz")
        print("\(timestamp())   Channels: \(channels)")
        print("\(timestamp())   Bit Depth: 16-bit")
        print("\(timestamp())   Format: PCM WAV")
    }
    
    // MARK: - File Management
    
    public func startWriting(to filename: String) throws {
        guard !isWriting else {
            throw NSError(domain: "WavFileWriter", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Already writing to a file"])
        }
        
        // Ensure .wav extension
        let wavFilename = filename.hasSuffix(".wav") ? filename : "\(filename).wav"
        let url = URL(fileURLWithPath: wavFilename)
        
        // Create the audio file for writing
        audioFile = try AVAudioFile(forWriting: url,
                                   settings: outputFormat.settings,
                                   commonFormat: outputFormat.commonFormat,
                                   interleaved: outputFormat.isInterleaved)
        
        isWriting = true
        buffersWritten = 0
        samplesWritten = 0
        
        print("\(timestamp()) WavFileWriter: Started writing to \(wavFilename)")
        print("\(timestamp())   Format: \(outputFormat)")
    }
    
    public func stopWriting() {
        guard isWriting else { return }
        
        writeQueue.sync {
            isWriting = false
            audioFile = nil
            converter = nil
        }
        
        let duration = Double(samplesWritten) / outputFormat.sampleRate
        print("\(timestamp()) WavFileWriter: Stopped writing")
        print("\(timestamp())   Total buffers written: \(buffersWritten)")
        print("\(timestamp())   Total samples written: \(samplesWritten)")
        print("\(timestamp())   Total frames written: \(samplesWritten)")
        print("\(timestamp())   Duration: \(String(format: "%.2f", duration)) seconds")
        print("\(timestamp())   Expected duration: ~\(Double(buffersWritten * 960) / outputFormat.sampleRate) seconds")
    }
    
    // MARK: - Buffer Writing
    
    public func write(_ buffer: AVAudioPCMBuffer) {
        guard isWriting else { return }
        
        writeQueue.async { [weak self] in
            guard let self = self, self.isWriting else { return }
            
            do {
                // Check if we need format conversion
                if buffer.format.isEqual(self.outputFormat) {
                    // Direct write - no conversion needed
                    try self.audioFile?.write(from: buffer)
                    self.samplesWritten += Int64(buffer.frameLength)
                } else {
                    // Need to convert format
                    if let convertedBuffer = self.convertBuffer(buffer) {
                        try self.audioFile?.write(from: convertedBuffer)
                        self.samplesWritten += Int64(convertedBuffer.frameLength)
                        
                        // Debug logging for first few buffers
                        if self.buffersWritten < 3 {
                            print("\(self.timestamp()) WavFileWriter: Converted buffer frameLength: \(convertedBuffer.frameLength)")
                        }
                    } else {
                        print("\(self.timestamp()) WavFileWriter: Failed to convert buffer")
                        return
                    }
                }
                
                self.buffersWritten += 1
                
                // Log progress periodically
                if self.buffersWritten % 100 == 0 {
                    let duration = Double(self.samplesWritten) / self.outputFormat.sampleRate
                    print("\(self.timestamp()) WavFileWriter: Written \(self.buffersWritten) buffers (\(String(format: "%.1f", duration))s)")
                }
                
                // Debug logging for first few buffers
                if self.buffersWritten <= 3 {
                    print("\(self.timestamp()) WavFileWriter: Buffer #\(self.buffersWritten) - input frameLength: \(buffer.frameLength)")
                }
                
            } catch {
                print("\(self.timestamp()) WavFileWriter: Error writing buffer: \(error)")
            }
        }
    }
    
    // MARK: - Format Conversion
    
    /// Convert audio buffer from capture format to WAV format
    /// Handles the two-step conversion: deinterleaved Float32 → interleaved Int16
    /// - Parameter inputBuffer: The input buffer in Float32 deinterleaved format
    /// - Returns: Converted buffer in Int16 interleaved format, or nil if conversion fails
    private func convertBuffer(_ inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // Handle common case: Float32 deinterleaved to Int16 interleaved
        let inputFormat = inputBuffer.format
        
        // Debug logging for first few conversions
        if buffersWritten < 3 {
            print("\(timestamp()) WavFileWriter: Converting buffer - Input format: \(inputFormat)")
            print("\(timestamp())   Input frames: \(inputBuffer.frameLength)")
        }
        
        // Create intermediate format if needed (Float32 interleaved)
        let needsInterleaving = !inputFormat.isInterleaved && outputFormat.isInterleaved
        let needsFloatToInt = inputFormat.commonFormat == .pcmFormatFloat32 && outputFormat.commonFormat == .pcmFormatInt16
        
        if needsInterleaving && needsFloatToInt {
            // Two-step conversion: deinterleaved Float32 -> interleaved Float32 -> interleaved Int16
            
            // Step 1: Create interleaved Float32 format
            guard let intermediateFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                        sampleRate: inputFormat.sampleRate,
                                                        channels: inputFormat.channelCount,
                                                        interleaved: true) else {
                print("\(timestamp()) WavFileWriter: Failed to create intermediate format")
                return nil
            }
            
            // Convert to interleaved Float32
            guard let interleavedBuffer = manuallyInterleaveBuffer(inputBuffer, to: intermediateFormat) else {
                print("\(timestamp()) WavFileWriter: Failed to interleave buffer")
                return nil
            }
            
            // Step 2: Convert Float32 to Int16
            let result = convertFloatToInt16(interleavedBuffer)
            
            if buffersWritten < 3 && result != nil {
                print("\(timestamp())   Output frames: \(result!.frameLength)")
            }
            
            return result
            
        } else if needsFloatToInt {
            // Simple Float32 to Int16 conversion
            return convertFloatToInt16(inputBuffer)
        } else {
            // Use standard converter for other cases
            return standardConvert(inputBuffer)
        }
    }
    
    private func manuallyInterleaveBuffer(_ inputBuffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: inputBuffer.frameLength) else {
            return nil
        }
        
        outputBuffer.frameLength = inputBuffer.frameLength
        
        let channelCount = Int(inputBuffer.format.channelCount)
        let frameCount = Int(inputBuffer.frameLength)
        
        if let inputFloatData = inputBuffer.floatChannelData,
           let outputFloatData = outputBuffer.floatChannelData {
            
            // Interleave the data
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    let inputSample = inputFloatData[channel][frame]
                    outputFloatData[0][frame * channelCount + channel] = inputSample
                }
            }
        }
        
        return outputBuffer
    }
    
    private func convertFloatToInt16(_ floatBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: floatBuffer.frameLength) else {
            return nil
        }
        
        outputBuffer.frameLength = floatBuffer.frameLength
        
        let frameCount = Int(floatBuffer.frameLength)
        let channelCount = Int(floatBuffer.format.channelCount)
        
        if floatBuffer.format.isInterleaved {
            // Interleaved Float32 to Int16
            if let floatData = floatBuffer.floatChannelData?[0],
               let int16Data = outputBuffer.int16ChannelData?[0] {
                
                for i in 0..<(frameCount * channelCount) {
                    // Convert Float32 [-1.0, 1.0] to Int16 [-32768, 32767]
                    let sample = max(-1.0, min(1.0, floatData[i]))
                    int16Data[i] = Int16(sample * 32767.0)
                }
            }
        } else {
            // Deinterleaved - shouldn't happen with our logic but handle it
            print("\(timestamp()) WavFileWriter: Unexpected deinterleaved buffer in convertFloatToInt16")
            return nil
        }
        
        return outputBuffer
    }
    
    private func standardConvert(_ inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // Fallback to standard converter
        if converter == nil {
            converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat)
        }
        
        guard let converter = converter else {
            print("\(timestamp()) WavFileWriter: Failed to create standard converter")
            return nil
        }
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                 frameCapacity: inputBuffer.frameLength) else {
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("\(timestamp()) WavFileWriter: Standard conversion error: \(error)")
            return nil
        }
        
        return status == .haveData ? outputBuffer : nil
    }
    
    // MARK: - File Information
    
    func getFileInfo() -> [String: Any] {
        return [
            "isWriting": isWriting,
            "buffersWritten": buffersWritten,
            "samplesWritten": samplesWritten,
            "duration": Double(samplesWritten) / outputFormat.sampleRate,
            "format": outputFormat.description
        ]
    }
}

// MARK: - AudioStreamDelegate Extension
@available(macOS 13.0, *)
extension WavFileWriter: AudioStreamDelegate {
    
    public func audioStreamer(_ streamer: StreamingAudioRecorder, didReceive buffer: AVAudioPCMBuffer) {
        // Write buffer to file
        write(buffer)
    }
    
    public func audioStreamer(_ streamer: StreamingAudioRecorder, didEncounterError error: Error) {
        print("\(timestamp()) WavFileWriter: Audio streamer error: \(error)")
    }
    
    public func audioStreamerDidFinish(_ streamer: StreamingAudioRecorder) {
        print("\(timestamp()) WavFileWriter: Audio streamer finished")
        stopWriting()
    }
}