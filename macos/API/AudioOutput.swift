import Foundation
import AVFoundation

/// AudioOutput - Protocol for audio output destinations
///
/// Implement this protocol to create custom audio output destinations.
/// The protocol supports format configuration, buffer processing, error handling,
/// and lifecycle management.
public protocol AudioOutput: AnyObject {
    /// Unique identifier for this output
    var id: UUID { get }
    
    /// Configure the output with a specific audio format
    func configure(format: AudioFormat) async throws
    
    /// Process an audio buffer
    func process(_ buffer: AudioBuffer) async throws
    
    /// Handle errors during processing
    func handleError(_ error: Error) async
    
    /// Finish and cleanup the output
    func finish() async
}

// MARK: - File Output Implementation

/// FileOutput - Writes audio to a file
@available(macOS 13.0, *)
public class FileOutput: AudioOutput {
    
    // MARK: - Properties
    
    public let id = UUID()
    private let url: URL
    private var writer: WavFileWriter?
    private var isConfigured = false
    private let writeQueue = DispatchQueue(label: "com.audiocapture.fileoutput", qos: .utility)
    
    // MARK: - Initialization
    
    public init(url: URL) {
        self.url = url
    }
    
    // MARK: - AudioOutput Protocol
    
    public func configure(format: AudioFormat) async throws {
        guard !isConfigured else { return }
        
        // Create writer with format
        writer = try WavFileWriter(
            sampleRate: format.sampleRate,
            channels: format.channelCount
        )
        
        // Start writing
        let filename = url.deletingPathExtension().lastPathComponent
        try writer?.startWriting(to: filename)
        
        isConfigured = true
    }
    
    public func process(_ buffer: AudioBuffer) async throws {
        guard let writer = writer else {
            throw AudioCaptureError.outputNotConfigured
        }
        
        // Write buffer to file
        await withCheckedContinuation { continuation in
            writeQueue.async {
                writer.write(buffer.pcmBuffer)
                continuation.resume()
            }
        }
    }
    
    public func handleError(_ error: Error) async {
        print("FileOutput error: \(error)")
    }
    
    public func finish() async {
        writer?.stopWriting()
        writer = nil
        isConfigured = false
    }
}

// MARK: - Stream Output Implementation

/// StreamOutput - Provides audio buffers to external consumers
@available(macOS 13.0, *)
public class StreamOutput: AudioOutput {
    
    // MARK: - Properties
    
    public let id = UUID()
    private let bufferQueue: AudioBufferQueue
    private var format: AudioFormat?
    private var isConfigured = false
    
    /// Stream of audio buffers
    public var bufferStream: AsyncStream<AudioBuffer> {
        bufferQueue.stream
    }
    
    // MARK: - Initialization
    
    public init(queueSize: Int = 32) {
        self.bufferQueue = AudioBufferQueue(maxSize: queueSize)
    }
    
    // MARK: - AudioOutput Protocol
    
    public func configure(format: AudioFormat) async throws {
        self.format = format
        isConfigured = true
    }
    
    public func process(_ buffer: AudioBuffer) async throws {
        guard isConfigured else {
            throw AudioCaptureError.outputNotConfigured
        }
        
        // Add to queue
        await bufferQueue.enqueue(buffer)
    }
    
    public func handleError(_ error: Error) async {
        await bufferQueue.handleError(error)
    }
    
    public func finish() async {
        await bufferQueue.finish()
        isConfigured = false
    }
    
    // MARK: - Stream Control
    
    /// Get current queue depth
    public func getQueueDepth() async -> Int {
        return await bufferQueue.count
    }
    
    /// Clear the buffer queue
    public func clearQueue() async {
        await bufferQueue.clear()
    }
}

// MARK: - Callback Output Implementation

/// CallbackOutput - Delivers audio buffers via callback
@available(macOS 13.0, *)
public class CallbackOutput: AudioOutput {
    
    // MARK: - Properties
    
    public let id = UUID()
    private let handler: (AVAudioPCMBuffer) -> Void
    private let callbackQueue: DispatchQueue
    private var isConfigured = false
    
    // MARK: - Initialization
    
    public init(
        handler: @escaping (AVAudioPCMBuffer) -> Void,
        queue: DispatchQueue = .main
    ) {
        self.handler = handler
        self.callbackQueue = queue
    }
    
    // MARK: - AudioOutput Protocol
    
    public func configure(format: AudioFormat) async throws {
        isConfigured = true
    }
    
    public func process(_ buffer: AudioBuffer) async throws {
        guard isConfigured else {
            throw AudioCaptureError.outputNotConfigured
        }
        
        // Deliver buffer via callback
        callbackQueue.async { [weak self] in
            self?.handler(buffer.pcmBuffer)
        }
    }
    
    public func handleError(_ error: Error) async {
        print("CallbackOutput error: \(error)")
    }
    
    public func finish() async {
        isConfigured = false
    }
}

// MARK: - Playback Output Implementation

/// PlaybackOutput - Plays audio through speakers
@available(macOS 13.0, *)
public class PlaybackOutput: AudioOutput {
    
    // MARK: - Properties
    
    public let id = UUID()
    private let player: StreamingAudioPlayer
    private let device: AudioDevice?
    private var isConfigured = false
    
    // MARK: - Initialization
    
    public init(device: AudioDevice? = nil, delay: TimeInterval = 0) {
        self.device = device
        self.player = StreamingAudioPlayer(delay: delay)
    }
    
    // MARK: - AudioOutput Protocol
    
    public func configure(format: AudioFormat) async throws {
        // TODO: Configure player with specific device if provided
        try player.startPlayback()
        isConfigured = true
    }
    
    public func process(_ buffer: AudioBuffer) async throws {
        guard isConfigured else {
            throw AudioCaptureError.outputNotConfigured
        }
        
        player.scheduleBuffer(buffer.pcmBuffer)
    }
    
    public func handleError(_ error: Error) async {
        print("PlaybackOutput error: \(error)")
    }
    
    public func finish() async {
        player.stopPlayback()
        isConfigured = false
    }
    
    // MARK: - Playback Control
    
    /// Set playback volume (0.0 to 1.0)
    public func setVolume(_ volume: Float) {
        player.volume = volume
    }
    
    /// Get current volume
    public func getVolume() -> Float {
        return player.volume
    }
}

// MARK: - Ring Buffer Output Implementation

/// RingBufferOutput - Provides lock-free ring buffer access
@available(macOS 13.0, *)
public class RingBufferOutput: AudioOutput {
    
    // MARK: - Properties
    
    public let id = UUID()
    private var ringBuffer: TPCircularBuffer
    private var format: AudioFormat?
    private let bufferDuration: TimeInterval
    private var isConfigured = false
    
    // MARK: - Initialization
    
    public init(bufferDuration: TimeInterval = 1.0) {
        self.bufferDuration = bufferDuration
        self.ringBuffer = TPCircularBuffer()
    }
    
    deinit {
        TPCircularBufferCleanup(&ringBuffer)
    }
    
    // MARK: - AudioOutput Protocol
    
    public func configure(format: AudioFormat) async throws {
        self.format = format
        
        // Calculate buffer size
        let bytesPerSecond = Int32(format.sampleRate * Double(format.bytesPerPacket))
        let bufferSize = Int32(Double(bytesPerSecond) * bufferDuration)
        
        // Initialize ring buffer
        if !TPCircularBufferInit(&ringBuffer, bufferSize) {
            throw AudioCaptureError.bufferAllocationFailed
        }
        
        isConfigured = true
    }
    
    public func process(_ buffer: AudioBuffer) async throws {
        guard isConfigured else {
            throw AudioCaptureError.outputNotConfigured
        }
        
        // Get audio data
        let audioBuffer = buffer.pcmBuffer.audioBufferList.pointee.mBuffers
        guard let data = audioBuffer.mData else { return }
        
        let byteCount = Int(audioBuffer.mDataByteSize)
        
        // Write to ring buffer
        let availableSpace = TPCircularBufferGetAvailableSpace(&ringBuffer, &(ringBuffer.tail))
        if availableSpace >= byteCount {
            TPCircularBufferProduceBytes(&ringBuffer, data, Int32(byteCount))
        } else {
            // Buffer overflow - drop oldest data
            TPCircularBufferConsume(&ringBuffer, Int32(byteCount - availableSpace))
            TPCircularBufferProduceBytes(&ringBuffer, data, Int32(byteCount))
        }
    }
    
    public func handleError(_ error: Error) async {
        print("RingBufferOutput error: \(error)")
    }
    
    public func finish() async {
        TPCircularBufferClear(&ringBuffer)
        isConfigured = false
    }
    
    // MARK: - Ring Buffer Access
    
    /// Read data from ring buffer
    public func read(into buffer: UnsafeMutableRawPointer, maxBytes: Int) -> Int {
        var availableBytes: Int32 = 0
        let data = TPCircularBufferTail(&ringBuffer, &availableBytes)
        
        let bytesToRead = min(Int(availableBytes), maxBytes)
        if bytesToRead > 0, let data = data {
            memcpy(buffer, data, bytesToRead)
            TPCircularBufferConsume(&ringBuffer, Int32(bytesToRead))
        }
        
        return bytesToRead
    }
    
    /// Get available bytes in buffer
    public func availableBytes() -> Int {
        var bytes: Int32 = 0
        _ = TPCircularBufferTail(&ringBuffer, &bytes)
        return Int(bytes)
    }
}

// MARK: - TPCircularBuffer Definition (Simplified)

/// Simple circular buffer structure
struct TPCircularBuffer {
    var buffer: UnsafeMutablePointer<UInt8>?
    var length: Int32 = 0
    var tail: Int32 = 0
    var head: Int32 = 0
}

func TPCircularBufferInit(_ buffer: inout TPCircularBuffer, _ length: Int32) -> Bool {
    buffer.length = length
    buffer.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(length))
    buffer.tail = 0
    buffer.head = 0
    return true
}

func TPCircularBufferCleanup(_ buffer: inout TPCircularBuffer) {
    buffer.buffer?.deallocate()
    buffer.buffer = nil
}

func TPCircularBufferClear(_ buffer: inout TPCircularBuffer) {
    buffer.head = 0
    buffer.tail = 0
}

func TPCircularBufferGetAvailableSpace(_ buffer: inout TPCircularBuffer, _ tail: inout Int32) -> Int {
    tail = buffer.tail
    let space = buffer.length - (buffer.head - buffer.tail)
    return Int(space)
}

func TPCircularBufferProduceBytes(_ buffer: inout TPCircularBuffer, _ data: UnsafeRawPointer, _ length: Int32) {
    guard let dest = buffer.buffer else { return }
    let head = Int(buffer.head % buffer.length)
    memcpy(dest.advanced(by: head), data, Int(length))
    buffer.head += length
}

func TPCircularBufferTail(_ buffer: inout TPCircularBuffer, _ availableBytes: inout Int32) -> UnsafeMutableRawPointer? {
    availableBytes = buffer.head - buffer.tail
    guard availableBytes > 0, let src = buffer.buffer else { return nil }
    let tail = Int(buffer.tail % buffer.length)
    return UnsafeMutableRawPointer(src.advanced(by: tail))
}

func TPCircularBufferConsume(_ buffer: inout TPCircularBuffer, _ length: Int32) {
    buffer.tail += length
}