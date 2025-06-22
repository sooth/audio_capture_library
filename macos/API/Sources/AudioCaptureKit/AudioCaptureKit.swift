import Foundation
import AVFoundation
import ScreenCaptureKit

/// AudioCaptureKit - Main API Entry Point
///
/// This is the primary interface for the audio capture library, providing a clean
/// and intuitive API for audio capture, playback, and streaming operations.
///
/// Key Features:
/// - Device enumeration and management
/// - Session-based recording and playback
/// - Multiple output support (file, stream, playback)
/// - Format negotiation and conversion
/// - Comprehensive error handling
///
/// Usage:
/// ```swift
/// let audioCaptureKit = AudioCaptureKit()
///
/// // Start recording to file
/// let session = try await audioCaptureKit.startCapture()
/// let fileOutput = FileOutput(url: URL(fileURLWithPath: "recording.wav"))
/// try await session.addOutput(fileOutput)
/// ```
@available(macOS 13.0, *)
public actor AudioCaptureKit {
    
    // MARK: - Properties
    
    /// Singleton instance for convenient access
    public static let shared = AudioCaptureKit()
    
    /// Device manager for audio device operations
    private let deviceManager: AudioDeviceManager
    
    /// Active capture sessions
    private var captureSessions: [UUID: AudioCaptureSession] = [:]
    
    /// Active playback sessions
    private var playbackSessions: [UUID: AudioPlaybackSession] = [:]
    
    /// Global configuration
    private var configuration: AudioCaptureConfiguration
    
    // MARK: - Initialization
    
    public init() {
        self.deviceManager = AudioDeviceManager()
        self.configuration = AudioCaptureConfiguration()
    }
    
    // MARK: - Device Management
    
    /// Get available playback devices
    public func getPlaybackDevices() async throws -> [AudioDevice] {
        return try await deviceManager.getPlaybackDevices()
    }
    
    /// Get available recording devices
    public func getRecordingDevices() async throws -> [AudioDevice] {
        return try await deviceManager.getRecordingDevices()
    }
    
    /// Set the default playback device
    public func setPlaybackDevice(_ device: AudioDevice) async throws {
        try await deviceManager.setPlaybackDevice(device)
    }
    
    /// Set the default recording device
    public func setRecordingDevice(_ device: AudioDevice) async throws {
        try await deviceManager.setRecordingDevice(device)
    }
    
    /// Get current playback device
    public func getCurrentPlaybackDevice() async throws -> AudioDevice? {
        return try await deviceManager.getCurrentPlaybackDevice()
    }
    
    /// Get current recording device
    public func getCurrentRecordingDevice() async throws -> AudioDevice? {
        return try await deviceManager.getCurrentRecordingDevice()
    }
    
    // MARK: - Capture Operations
    
    /// Start audio capture with configuration
    public func startCapture(configuration: CaptureConfiguration? = nil) async throws -> AudioCaptureSession {
        let config = configuration ?? CaptureConfiguration()
        let session = AudioCaptureSession(configuration: config)
        
        // Get session ID
        let sessionId = await session.id
        
        // Store session
        captureSessions[sessionId] = session
        
        // Start capture
        try await session.start()
        
        return session
    }
    
    /// Stop audio capture for session
    public func stopCapture(session: AudioCaptureSession) async throws {
        try await session.stop()
        let sessionId = await session.id
        captureSessions.removeValue(forKey: sessionId)
    }
    
    /// Get all active capture sessions
    public func getActiveCaptureSession() async -> [AudioCaptureSession] {
        return Array(captureSessions.values)
    }
    
    // MARK: - Playback Operations
    
    /// Start audio playback with configuration
    public func startPlayback(configuration: PlaybackConfiguration? = nil) async throws -> AudioPlaybackSession {
        let config = configuration ?? PlaybackConfiguration()
        let session = AudioPlaybackSession(configuration: config)
        
        // Get session ID
        let sessionId = await session.id
        
        // Store session
        playbackSessions[sessionId] = session
        
        // Start playback
        try await session.start()
        
        return session
    }
    
    /// Stop audio playback for session
    public func stopPlayback(session: AudioPlaybackSession) async throws {
        try await session.stop()
        let sessionId = await session.id
        playbackSessions.removeValue(forKey: sessionId)
    }
    
    /// Get all active playback sessions
    public func getActivePlaybackSessions() async -> [AudioPlaybackSession] {
        return Array(playbackSessions.values)
    }
    
    // MARK: - Quick Operations
    
    /// Record to file with default settings
    public func recordToFile(url: URL, duration: TimeInterval? = nil) async throws {
        let session = try await startCapture()
        let fileOutput = FileOutput(url: url)
        try await session.addOutput(fileOutput)
        
        if let duration = duration {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            try await stopCapture(session: session)
        }
    }
    
    /// Stream system audio with callback
    public func streamAudio(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) async throws -> AudioCaptureSession {
        let session = try await startCapture()
        let streamOutput = CallbackOutput(handler: bufferHandler)
        try await session.addOutput(streamOutput)
        return session
    }
    
    /// Play system audio through speakers
    public func playSystemAudio(device: AudioDevice? = nil) async throws -> AudioCaptureSession {
        let session = try await startCapture()
        let playbackOutput = PlaybackOutput(device: device)
        try await session.addOutput(playbackOutput)
        return session
    }
    
    // MARK: - Configuration
    
    /// Set global configuration
    public func setConfiguration(_ configuration: AudioCaptureConfiguration) {
        self.configuration = configuration
    }
    
    /// Get current configuration
    public func getConfiguration() -> AudioCaptureConfiguration {
        return configuration
    }
    
    // MARK: - Monitoring
    
    /// Get library statistics
    public func getStatistics() async -> AudioCaptureStatistics {
        let captureStats = await withTaskGroup(of: SessionStatistics?.self) { group in
            for session in captureSessions.values {
                group.addTask {
                    return await session.getStatistics()
                }
            }
            
            var stats: [SessionStatistics] = []
            for await stat in group {
                if let stat = stat {
                    stats.append(stat)
                }
            }
            return stats
        }
        
        let playbackStats = await withTaskGroup(of: SessionStatistics?.self) { group in
            for session in playbackSessions.values {
                group.addTask {
                    return await session.getStatistics()
                }
            }
            
            var stats: [SessionStatistics] = []
            for await stat in group {
                if let stat = stat {
                    stats.append(stat)
                }
            }
            return stats
        }
        
        return AudioCaptureStatistics(
            captureSessionCount: captureSessions.count,
            playbackSessionCount: playbackSessions.count,
            captureStatistics: captureStats,
            playbackStatistics: playbackStats
        )
    }
    
    // MARK: - Cleanup
    
    /// Stop all sessions and cleanup resources
    public func cleanup() async {
        // Stop all capture sessions
        for session in captureSessions.values {
            try? await session.stop()
        }
        captureSessions.removeAll()
        
        // Stop all playback sessions
        for session in playbackSessions.values {
            try? await session.stop()
        }
        playbackSessions.removeAll()
    }
}

// MARK: - Configuration Types

/// Global audio capture configuration
public struct AudioCaptureConfiguration {
    /// Default sample rate for capture
    public var sampleRate: Double = 48000.0
    
    /// Default channel count
    public var channelCount: UInt32 = 2
    
    /// Default buffer size in frames
    public var bufferSize: UInt32 = 960
    
    /// Enable performance monitoring
    public var enableMonitoring: Bool = true
    
    /// Maximum memory usage in MB
    public var maxMemoryUsage: Int = 100
    
    /// Processing priority
    public var processingPriority: ProcessingPriority = .balanced
    
    public init() {}
}

/// Capture session configuration
public struct CaptureConfiguration {
    /// Audio format for capture
    public var format: AudioFormat?
    
    /// Capture device (nil for system default)
    public var device: AudioDevice?
    
    /// Exclude current process audio
    public var excludeCurrentProcess: Bool = true
    
    /// Buffer queue size
    public var bufferQueueSize: Int = 8
    
    public init() {}
}

/// Playback session configuration
public struct PlaybackConfiguration {
    /// Audio format for playback
    public var format: AudioFormat?
    
    /// Playback device (nil for system default)
    public var device: AudioDevice?
    
    /// Initial volume (0.0 to 1.0)
    public var volume: Float = 0.5
    
    /// Playback delay in seconds
    public var delay: TimeInterval = 0.0
    
    public init() {}
}

/// Processing priority modes
public enum ProcessingPriority {
    case realtime       // Lowest latency, highest CPU
    case balanced       // Balanced performance
    case efficiency     // Lower CPU, higher latency
}

/// Library statistics
public struct AudioCaptureStatistics {
    public let captureSessionCount: Int
    public let playbackSessionCount: Int
    public let captureStatistics: [SessionStatistics]
    public let playbackStatistics: [SessionStatistics]
}

/// Session statistics
public struct SessionStatistics {
    public let sessionId: UUID
    public let state: SessionState
    public let bufferCount: Int
    public let duration: TimeInterval
    public let format: AudioFormat?
}