import Foundation
import AVFoundation
import ScreenCaptureKit

/// Session state enumeration
public enum SessionState: String, Codable {
    case idle = "idle"
    case starting = "starting"
    case active = "active"
    case paused = "paused"
    case stopping = "stopping"
    case stopped = "stopped"
    case error = "error"
}

/// Base class for audio sessions
@available(macOS 13.0, *)
public class BaseAudioSession {
    /// Unique session identifier
    public let id: UUID
    
    /// Session creation time
    public let createdAt: Date
    
    /// Current session state
    private(set) public var state: SessionState = .idle
    
    /// Session statistics
    private(set) public var statistics: SessionStatistics
    
    /// State change observers
    private var stateObservers: [UUID: (SessionState) -> Void] = [:]
    
    /// Error handler
    private var errorHandler: ((Error) -> Void)?
    
    init() {
        self.id = UUID()
        self.createdAt = Date()
        self.statistics = SessionStatistics(
            sessionId: id,
            state: .idle,
            bufferCount: 0,
            duration: 0,
            format: nil
        )
    }
    
    /// Update session state
    func updateState(_ newState: SessionState) {
        let oldState = state
        state = newState
        statistics = SessionStatistics(
            sessionId: id,
            state: newState,
            bufferCount: statistics.bufferCount,
            duration: statistics.duration,
            format: statistics.format
        )
        
        // Notify observers
        for observer in stateObservers.values {
            observer(newState)
        }
    }
    
    /// Add state observer
    public func addStateObserver(_ observer: @escaping (SessionState) -> Void) -> UUID {
        let observerId = UUID()
        stateObservers[observerId] = observer
        return observerId
    }
    
    /// Remove state observer
    public func removeStateObserver(_ observerId: UUID) {
        stateObservers.removeValue(forKey: observerId)
    }
    
    /// Set error handler
    public func setErrorHandler(_ handler: @escaping (Error) -> Void) {
        self.errorHandler = handler
    }
    
    /// Handle error
    func handleError(_ error: Error) {
        updateState(.error)
        errorHandler?(error)
    }
    
    /// Get session statistics
    public func getStatistics() -> SessionStatistics {
        return statistics
    }
}

/// AudioCaptureSession - Manages an audio capture session
@available(macOS 13.0, *)
public actor AudioCaptureSession {
    
    // MARK: - Properties
    
    /// Unique session identifier
    public let id: UUID
    
    /// Session creation time
    public let createdAt: Date
    
    /// Current session state
    private(set) public var state: SessionState = .idle
    
    /// Session statistics
    private(set) public var statistics: SessionStatistics
    
    /// State change observers
    private var stateObservers: [UUID: (SessionState) -> Void] = [:]
    
    /// Error handler
    private var errorHandler: ((Error) -> Void)?
    
    /// Session configuration
    private let configuration: CaptureConfiguration
    
    /// Audio recorder
    private var recorder: StreamingAudioRecorder?
    
    /// Active outputs
    private var outputs: [AudioOutput] = []
    
    /// Stream multiplexer
    private let multiplexer: AudioStreamMultiplexer
    
    /// Format for this session
    private var sessionFormat: AudioFormat?
    
    // MARK: - Initialization
    
    init(configuration: CaptureConfiguration) {
        self.id = UUID()
        self.createdAt = Date()
        self.statistics = SessionStatistics(
            sessionId: id,
            state: .idle,
            bufferCount: 0,
            duration: 0,
            format: nil
        )
        self.configuration = configuration
        self.multiplexer = AudioStreamMultiplexer()
    }
    
    // MARK: - Session Control
    
    /// Start capture session
    public func start() async throws {
        guard state == .idle || state == .stopped else {
            throw AudioCaptureError.invalidState("Session is already active")
        }
        
        await updateState(.starting)
        
        do {
            // Create recorder
            recorder = StreamingAudioRecorder()
            
            // Set up multiplexer as delegate
            recorder?.addStreamDelegate(multiplexer)
            
            // Start recording
            try await recorder?.startStreaming()
            
            // Update format
            sessionFormat = configuration.format ?? AudioFormat.defaultFormat
            
            await updateState(.active)
        } catch {
            await handleError(error)
            throw error
        }
    }
    
    /// Stop capture session
    public func stop() async throws {
        guard state == .active || state == .paused else {
            throw AudioCaptureError.invalidState("Session is not active")
        }
        
        await updateState(.stopping)
        
        // Stop recorder
        await recorder?.stopStreaming()
        
        // Notify outputs
        for output in outputs {
            await output.finish()
        }
        
        // Clear outputs
        outputs.removeAll()
        await multiplexer.removeAllOutputs()
        
        await updateState(.stopped)
    }
    
    /// Pause capture session
    public func pause() async throws {
        guard state == .active else {
            throw AudioCaptureError.invalidState("Session is not active")
        }
        
        await updateState(.paused)
        await multiplexer.setPaused(true)
    }
    
    /// Resume capture session
    public func resume() async throws {
        guard state == .paused else {
            throw AudioCaptureError.invalidState("Session is not paused")
        }
        
        await multiplexer.setPaused(false)
        await updateState(.active)
    }
    
    // MARK: - Output Management
    
    /// Add an output to the session
    public func addOutput(_ output: AudioOutput) async throws {
        guard state == .active || state == .paused else {
            throw AudioCaptureError.invalidState("Session must be active to add outputs")
        }
        
        // Configure output with session format
        if let format = sessionFormat {
            try await output.configure(format: format)
        }
        
        // Add to multiplexer
        await multiplexer.addOutput(output)
        
        // Track output
        outputs.append(output)
    }
    
    /// Remove an output from the session
    public func removeOutput(_ output: AudioOutput) async throws {
        await multiplexer.removeOutput(output)
        outputs.removeAll { $0.id == output.id }
        await output.finish()
    }
    
    /// Get all active outputs
    public func getOutputs() -> [AudioOutput] {
        return outputs
    }
    
    // MARK: - Configuration
    
    /// Get session configuration
    public func getConfiguration() -> CaptureConfiguration {
        return configuration
    }
    
    /// Get session format
    public func getFormat() -> AudioFormat? {
        return sessionFormat
    }
    
    // MARK: - Private Methods
    
    /// Update session state
    func updateState(_ newState: SessionState) {
        let oldState = state
        state = newState
        statistics = SessionStatistics(
            sessionId: id,
            state: newState,
            bufferCount: statistics.bufferCount,
            duration: statistics.duration,
            format: statistics.format
        )
        
        // Notify observers
        for observer in stateObservers.values {
            observer(newState)
        }
    }
    
    /// Handle error
    func handleError(_ error: Error) {
        updateState(.error)
        errorHandler?(error)
    }
    
    /// Get session statistics
    public func getStatistics() -> SessionStatistics {
        return statistics
    }
}

/// AudioPlaybackSession - Manages an audio playback session
@available(macOS 13.0, *)
public actor AudioPlaybackSession {
    
    // MARK: - Properties
    
    /// Unique session identifier
    public let id: UUID
    
    /// Session creation time
    public let createdAt: Date
    
    /// Current session state
    private(set) public var state: SessionState = .idle
    
    /// Session statistics
    private(set) public var statistics: SessionStatistics
    
    /// State change observers
    private var stateObservers: [UUID: (SessionState) -> Void] = [:]
    
    /// Error handler
    private var errorHandler: ((Error) -> Void)?
    
    /// Session configuration
    private let configuration: PlaybackConfiguration
    
    /// Audio player
    private var player: StreamingAudioPlayer?
    
    /// Input source
    private var inputSource: AudioInput?
    
    /// Format for this session
    private var sessionFormat: AudioFormat?
    
    // MARK: - Initialization
    
    init(configuration: PlaybackConfiguration) {
        self.id = UUID()
        self.createdAt = Date()
        self.statistics = SessionStatistics(
            sessionId: id,
            state: .idle,
            bufferCount: 0,
            duration: 0,
            format: nil
        )
        self.configuration = configuration
    }
    
    // MARK: - Session Control
    
    /// Start playback session
    public func start() async throws {
        guard state == .idle || state == .stopped else {
            throw AudioCaptureError.invalidState("Session is already active")
        }
        
        await updateState(.starting)
        
        do {
            // Create player with delay if specified
            player = StreamingAudioPlayer(delay: configuration.delay)
            
            // Set volume
            player?.volume = configuration.volume
            
            // Start playback
            try player?.startPlayback()
            
            // Update format
            sessionFormat = configuration.format ?? AudioFormat.defaultFormat
            
            await updateState(.active)
        } catch {
            await handleError(error)
            throw error
        }
    }
    
    /// Stop playback session
    public func stop() async throws {
        guard state == .active || state == .paused else {
            throw AudioCaptureError.invalidState("Session is not active")
        }
        
        await updateState(.stopping)
        
        // Stop player
        player?.stopPlayback()
        
        // Disconnect input
        if let input = inputSource {
            await input.disconnect()
        }
        
        await updateState(.stopped)
    }
    
    /// Pause playback session
    public func pause() async throws {
        guard state == .active else {
            throw AudioCaptureError.invalidState("Session is not active")
        }
        
        // TODO: Implement pause in StreamingAudioPlayer
        await updateState(.paused)
    }
    
    /// Resume playback session
    public func resume() async throws {
        guard state == .paused else {
            throw AudioCaptureError.invalidState("Session is not paused")
        }
        
        // TODO: Implement resume in StreamingAudioPlayer
        await updateState(.active)
    }
    
    // MARK: - Input Management
    
    /// Set input source for playback
    public func setInput(_ input: AudioInput) async throws {
        guard state == .active || state == .paused else {
            throw AudioCaptureError.invalidState("Session must be active to set input")
        }
        
        // Disconnect previous input
        if let currentInput = inputSource {
            await currentInput.disconnect()
        }
        
        // Connect new input
        self.inputSource = input
        
        if let player = player {
            try await input.connect(to: player)
        }
    }
    
    /// Get current input source
    public func getInput() -> AudioInput? {
        return inputSource
    }
    
    // MARK: - Playback Control
    
    /// Set playback volume (0.0 to 1.0)
    public func setVolume(_ volume: Float) {
        player?.volume = max(0.0, min(1.0, volume))
    }
    
    /// Get current volume
    public func getVolume() -> Float {
        return player?.volume ?? configuration.volume
    }
    
    // MARK: - Buffer Management
    
    /// Schedule a buffer for playback
    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        player?.scheduleBuffer(buffer)
    }
    
    // MARK: - Configuration
    
    /// Get session configuration
    public func getConfiguration() -> PlaybackConfiguration {
        return configuration
    }
    
    /// Get session format
    public func getFormat() -> AudioFormat? {
        return sessionFormat
    }
    
    // MARK: - Private Methods
    
    /// Update session state
    func updateState(_ newState: SessionState) {
        let oldState = state
        state = newState
        statistics = SessionStatistics(
            sessionId: id,
            state: newState,
            bufferCount: statistics.bufferCount,
            duration: statistics.duration,
            format: statistics.format
        )
        
        // Notify observers
        for observer in stateObservers.values {
            observer(newState)
        }
    }
    
    /// Handle error
    func handleError(_ error: Error) {
        updateState(.error)
        errorHandler?(error)
    }
    
    /// Get session statistics
    public func getStatistics() -> SessionStatistics {
        return statistics
    }
}

/// AudioStreamMultiplexer - Distributes audio to multiple outputs
@available(macOS 13.0, *)
actor AudioStreamMultiplexer: AudioStreamDelegate {
    
    // MARK: - Properties
    
    /// Active outputs
    private var outputs: [AudioOutput] = []
    
    /// Processing queue
    private let processingQueue = DispatchQueue(label: "com.audiocapture.multiplexer", qos: .userInitiated)
    
    /// Paused state
    private var isPaused = false
    
    /// Buffer count for statistics
    private var bufferCount = 0
    
    // MARK: - Output Management
    
    func addOutput(_ output: AudioOutput) {
        outputs.append(output)
    }
    
    func removeOutput(_ output: AudioOutput) {
        outputs.removeAll { $0.id == output.id }
    }
    
    func removeAllOutputs() {
        outputs.removeAll()
    }
    
    func setPaused(_ paused: Bool) {
        isPaused = paused
    }
    
    // MARK: - AudioStreamDelegate
    
    nonisolated func audioStreamer(_ streamer: StreamingAudioRecorder, didReceive buffer: AVAudioPCMBuffer) {
        Task {
            await processBuffer(buffer)
        }
    }
    
    nonisolated func audioStreamer(_ streamer: StreamingAudioRecorder, didEncounterError error: Error) {
        Task {
            await handleError(error)
        }
    }
    
    nonisolated func audioStreamerDidFinish(_ streamer: StreamingAudioRecorder) {
        Task {
            await finish()
        }
    }
    
    // MARK: - Private Methods
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard !isPaused else { return }
        
        bufferCount += 1
        
        // Create audio buffer wrapper
        let audioBuffer = AudioBuffer(pcmBuffer: buffer)
        
        // Distribute to all outputs
        await withTaskGroup(of: Void.self) { group in
            for output in outputs {
                group.addTask {
                    do {
                        try await output.process(audioBuffer)
                    } catch {
                        print("Output \(output.id) failed to process buffer: \(error)")
                    }
                }
            }
        }
    }
    
    private func handleError(_ error: Error) async {
        // Notify all outputs of error
        for output in outputs {
            await output.handleError(error)
        }
    }
    
    private func finish() async {
        // Notify all outputs of finish
        for output in outputs {
            await output.finish()
        }
    }
}

/// AudioInput protocol for playback sources
public protocol AudioInput {
    /// Unique identifier
    var id: UUID { get }
    
    /// Connect to a player
    func connect(to player: StreamingAudioPlayer) async throws
    
    /// Disconnect from player
    func disconnect() async
}

/// Capture session as audio input
@available(macOS 13.0, *)
extension AudioCaptureSession: AudioInput {
    public func connect(to player: StreamingAudioPlayer) async throws {
        // Create bridge output that forwards to player
        let bridgeOutput = BridgeOutput(player: player)
        try await addOutput(bridgeOutput)
    }
    
    public func disconnect() async {
        // Remove bridge outputs
        let bridgeOutputs = outputs.filter { $0 is BridgeOutput }
        for output in bridgeOutputs {
            try? await removeOutput(output)
        }
    }
}

/// Bridge output for connecting capture to playback
@available(macOS 13.0, *)
class BridgeOutput: AudioOutput {
    let id = UUID()
    private let player: StreamingAudioPlayer
    
    init(player: StreamingAudioPlayer) {
        self.player = player
    }
    
    func configure(format: AudioFormat) async throws {
        // Player handles format internally
    }
    
    func process(_ buffer: AudioBuffer) async throws {
        player.scheduleBuffer(buffer.pcmBuffer)
    }
    
    func handleError(_ error: Error) async {
        print("Bridge output error: \(error)")
    }
    
    func finish() async {
        // Nothing to cleanup
    }
}