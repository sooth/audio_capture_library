import Foundation
import AVFoundation

/// AudioFormat - Represents an audio format configuration
///
/// This structure encapsulates all parameters needed to describe an audio format,
/// including sample rate, channel configuration, bit depth, and data layout.
public struct AudioFormat: Equatable, Hashable, Codable {
    /// Sample rate in Hz
    public let sampleRate: Double
    
    /// Number of channels
    public let channelCount: UInt32
    
    /// Bit depth (16, 24, 32)
    public let bitDepth: UInt32
    
    /// Whether samples are interleaved
    public let isInterleaved: Bool
    
    /// Whether format uses floating point
    public let isFloat: Bool
    
    /// Bytes per frame
    public var bytesPerFrame: UInt32 {
        return (bitDepth / 8) * (isInterleaved ? channelCount : 1)
    }
    
    /// Bytes per packet
    public var bytesPerPacket: UInt32 {
        return bytesPerFrame * (isInterleaved ? 1 : channelCount)
    }
    
    /// Common format type
    public var commonFormat: AVAudioCommonFormat {
        switch (bitDepth, isFloat) {
        case (16, false):
            return .pcmFormatInt16
        case (32, true):
            return .pcmFormatFloat32
        case (32, false):
            return .pcmFormatInt32
        case (24, false):
            return isInterleaved ? .pcmFormatInt24 : .pcmFormatInt32
        default:
            return .pcmFormatFloat32
        }
    }
    
    /// Default initializer
    public init(sampleRate: Double, channelCount: UInt32, bitDepth: UInt32, isInterleaved: Bool, isFloat: Bool = false) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.isInterleaved = isInterleaved
        self.isFloat = isFloat || bitDepth == 32 // Default to float for 32-bit
    }
    
    /// Create from AVAudioFormat
    public init?(from avFormat: AVAudioFormat) {
        self.sampleRate = avFormat.sampleRate
        self.channelCount = avFormat.channelCount
        self.isInterleaved = avFormat.isInterleaved
        
        switch avFormat.commonFormat {
        case .pcmFormatInt16:
            self.bitDepth = 16
            self.isFloat = false
        case .pcmFormatInt32:
            self.bitDepth = 32
            self.isFloat = false
        case .pcmFormatFloat32:
            self.bitDepth = 32
            self.isFloat = true
        case .pcmFormatFloat64:
            self.bitDepth = 64
            self.isFloat = true
        default:
            return nil
        }
    }
    
    /// Convert to AVAudioFormat
    public func toAVAudioFormat() -> AVAudioFormat? {
        return AVAudioFormat(
            commonFormat: commonFormat,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: isInterleaved
        )
    }
    
    /// Check if format is compatible with another format
    public func isCompatible(with other: AudioFormat) -> Bool {
        return self.sampleRate == other.sampleRate &&
               self.channelCount == other.channelCount &&
               self.bitDepth == other.bitDepth &&
               self.isInterleaved == other.isInterleaved &&
               self.isFloat == other.isFloat
    }
    
    /// Check if format requires conversion to another format
    public func requiresConversion(to other: AudioFormat) -> Bool {
        return !isCompatible(with: other)
    }
    
    /// Human-readable description
    public var description: String {
        let formatType = isFloat ? "Float" : "Int"
        let layout = isInterleaved ? "Interleaved" : "Non-interleaved"
        return "\(Int(sampleRate))Hz, \(channelCount)ch, \(bitDepth)-bit \(formatType), \(layout)"
    }
    
    // MARK: - Common Formats
    
    /// Default capture format (48kHz, 2ch, 32-bit float, non-interleaved)
    public static let defaultFormat = AudioFormat(
        sampleRate: 48000.0,
        channelCount: 2,
        bitDepth: 32,
        isInterleaved: false,
        isFloat: true
    )
    
    /// CD quality format (44.1kHz, 2ch, 16-bit int, interleaved)
    public static let cdQuality = AudioFormat(
        sampleRate: 44100.0,
        channelCount: 2,
        bitDepth: 16,
        isInterleaved: true,
        isFloat: false
    )
    
    /// Standard WAV format (48kHz, 2ch, 16-bit int, interleaved)
    public static let standardWAV = AudioFormat(
        sampleRate: 48000.0,
        channelCount: 2,
        bitDepth: 16,
        isInterleaved: true,
        isFloat: false
    )
    
    /// High quality format (96kHz, 2ch, 24-bit int, interleaved)
    public static let highQuality = AudioFormat(
        sampleRate: 96000.0,
        channelCount: 2,
        bitDepth: 24,
        isInterleaved: true,
        isFloat: false
    )
}

/// AudioFormatNegotiator - Handles format negotiation and conversion
public class AudioFormatNegotiator {
    
    /// Find best common format between source and destination
    public static func negotiate(source: AudioFormat, destination: AudioFormat, preferences: FormatPreferences = .default) -> AudioFormat {
        // If formats match, no negotiation needed
        if source.isCompatible(with: destination) {
            return source
        }
        
        // Apply preferences
        switch preferences.priority {
        case .quality:
            // Prefer higher sample rate and bit depth
            return AudioFormat(
                sampleRate: max(source.sampleRate, destination.sampleRate),
                channelCount: max(source.channelCount, destination.channelCount),
                bitDepth: max(source.bitDepth, destination.bitDepth),
                isInterleaved: destination.isInterleaved,
                isFloat: source.isFloat || destination.isFloat
            )
            
        case .compatibility:
            // Prefer destination format for maximum compatibility
            return destination
            
        case .performance:
            // Prefer source format to minimize conversion
            return source
            
        case .balanced:
            // Find middle ground
            return AudioFormat(
                sampleRate: destination.sampleRate, // Use destination sample rate
                channelCount: min(source.channelCount, destination.channelCount),
                bitDepth: destination.bitDepth,
                isInterleaved: destination.isInterleaved,
                isFloat: destination.isFloat
            )
        }
    }
    
    /// Check if direct conversion is possible
    public static func canConvert(from source: AudioFormat, to destination: AudioFormat) -> Bool {
        // Check for supported conversions
        if source.sampleRate != destination.sampleRate {
            // Sample rate conversion is supported
            return true
        }
        
        if source.channelCount != destination.channelCount {
            // Channel count mismatch - check if downmix/upmix is possible
            if source.channelCount > 2 && destination.channelCount == 2 {
                return true // Can downmix to stereo
            }
            if source.channelCount == 1 && destination.channelCount == 2 {
                return true // Can upmix mono to stereo
            }
        }
        
        // Format conversion is generally possible
        return true
    }
    
    /// Get conversion complexity score (0.0 = simple, 1.0 = complex)
    public static func conversionComplexity(from source: AudioFormat, to destination: AudioFormat) -> Float {
        var complexity: Float = 0.0
        
        // Sample rate conversion
        if source.sampleRate != destination.sampleRate {
            complexity += 0.3
        }
        
        // Channel conversion
        if source.channelCount != destination.channelCount {
            complexity += 0.2
        }
        
        // Bit depth conversion
        if source.bitDepth != destination.bitDepth {
            complexity += 0.2
        }
        
        // Float/Int conversion
        if source.isFloat != destination.isFloat {
            complexity += 0.2
        }
        
        // Interleaving conversion
        if source.isInterleaved != destination.isInterleaved {
            complexity += 0.1
        }
        
        return min(complexity, 1.0)
    }
}

/// Format negotiation preferences
public struct FormatPreferences {
    /// Negotiation priority
    public enum Priority {
        case quality        // Prefer highest quality
        case compatibility  // Prefer most compatible format
        case performance    // Prefer least conversion
        case balanced       // Balance all factors
    }
    
    /// Priority for negotiation
    public let priority: Priority
    
    /// Maximum sample rate to consider
    public let maxSampleRate: Double?
    
    /// Maximum bit depth to consider
    public let maxBitDepth: UInt32?
    
    /// Prefer interleaved formats
    public let preferInterleaved: Bool
    
    /// Prefer floating point formats
    public let preferFloat: Bool
    
    /// Default preferences
    public static let `default` = FormatPreferences(
        priority: .balanced,
        maxSampleRate: nil,
        maxBitDepth: nil,
        preferInterleaved: true,
        preferFloat: false
    )
    
    /// High quality preferences
    public static let highQuality = FormatPreferences(
        priority: .quality,
        maxSampleRate: 192000.0,
        maxBitDepth: 32,
        preferInterleaved: false,
        preferFloat: true
    )
    
    /// Performance preferences
    public static let performance = FormatPreferences(
        priority: .performance,
        maxSampleRate: 48000.0,
        maxBitDepth: 16,
        preferInterleaved: true,
        preferFloat: false
    )
}

/// Audio buffer wrapper for format-aware operations
public struct AudioBuffer {
    /// The underlying PCM buffer
    public let pcmBuffer: AVAudioPCMBuffer
    
    /// The audio format
    public let format: AudioFormat
    
    /// Timestamp of buffer capture
    public let timestamp: Date
    
    /// Duration in seconds
    public var duration: TimeInterval {
        return Double(pcmBuffer.frameLength) / format.sampleRate
    }
    
    /// Create from PCM buffer
    public init(pcmBuffer: AVAudioPCMBuffer, timestamp: Date = Date()) {
        self.pcmBuffer = pcmBuffer
        self.format = AudioFormat(from: pcmBuffer.format) ?? AudioFormat.defaultFormat
        self.timestamp = timestamp
    }
    
    /// Create with format and frame capacity
    public init?(format: AudioFormat, frameCapacity: AVAudioFrameCount) {
        guard let avFormat = format.toAVAudioFormat(),
              let buffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: frameCapacity) else {
            return nil
        }
        self.pcmBuffer = buffer
        self.format = format
        self.timestamp = Date()
    }
}