import Foundation
import AVFoundation

/// AudioBufferQueue - Thread-safe queue for audio buffers with async stream support
///
/// This actor provides a thread-safe queue for audio buffers with support for
/// async/await patterns. It includes backpressure handling, overflow protection,
/// and seamless integration with Swift's AsyncStream.
@available(macOS 13.0, *)
public actor AudioBufferQueue {
    
    // MARK: - Properties
    
    /// Maximum queue size
    private let maxSize: Int
    
    /// Internal buffer storage
    private var buffers: [AudioBuffer] = []
    
    /// Continuation for async stream
    private var continuation: AsyncStream<AudioBuffer>.Continuation?
    
    /// Stream state
    private var isFinished = false
    
    /// Error state
    private var lastError: Error?
    
    /// Statistics
    private var statistics = QueueStatistics()
    
    /// Async stream of audio buffers
    public let stream: AsyncStream<AudioBuffer>
    
    // MARK: - Initialization
    
    public init(maxSize: Int = 32) {
        self.maxSize = maxSize
        
        // Create async stream
        var localContinuation: AsyncStream<AudioBuffer>.Continuation?
        self.stream = AsyncStream<AudioBuffer> { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
    }
    
    // MARK: - Queue Operations
    
    /// Enqueue a buffer
    public func enqueue(_ buffer: AudioBuffer) async {
        guard !isFinished else { return }
        
        statistics.totalEnqueued += 1
        
        // Check for overflow
        if buffers.count >= maxSize {
            statistics.droppedBuffers += 1
            
            // Drop oldest buffer (FIFO)
            if !buffers.isEmpty {
                buffers.removeFirst()
            }
        }
        
        // Add to queue
        buffers.append(buffer)
        statistics.currentSize = buffers.count
        statistics.peakSize = max(statistics.peakSize, buffers.count)
        
        // Send to stream
        continuation?.yield(buffer)
    }
    
    /// Dequeue a buffer (for pull-based consumers)
    public func dequeue() async -> AudioBuffer? {
        guard !buffers.isEmpty else { return nil }
        
        let buffer = buffers.removeFirst()
        statistics.totalDequeued += 1
        statistics.currentSize = buffers.count
        
        return buffer
    }
    
    /// Peek at next buffer without removing
    public func peek() -> AudioBuffer? {
        return buffers.first
    }
    
    /// Clear all buffers
    public func clear() {
        let dropped = buffers.count
        buffers.removeAll()
        statistics.droppedBuffers += dropped
        statistics.currentSize = 0
    }
    
    /// Get current queue count
    public var count: Int {
        return buffers.count
    }
    
    /// Check if queue is empty
    public var isEmpty: Bool {
        return buffers.isEmpty
    }
    
    /// Check if queue is full
    public var isFull: Bool {
        return buffers.count >= maxSize
    }
    
    // MARK: - Stream Control
    
    /// Handle error
    public func handleError(_ error: Error) {
        lastError = error
        statistics.errorCount += 1
    }
    
    /// Finish the stream
    public func finish() {
        isFinished = true
        continuation?.finish()
        continuation = nil
        buffers.removeAll()
    }
    
    /// Get last error
    public func getLastError() -> Error? {
        return lastError
    }
    
    // MARK: - Statistics
    
    /// Get queue statistics
    public func getStatistics() -> QueueStatistics {
        return statistics
    }
    
    /// Reset statistics
    public func resetStatistics() {
        statistics = QueueStatistics()
        statistics.currentSize = buffers.count
    }
}

/// Queue statistics
public struct QueueStatistics {
    public var currentSize: Int = 0
    public var peakSize: Int = 0
    public var totalEnqueued: Int = 0
    public var totalDequeued: Int = 0
    public var droppedBuffers: Int = 0
    public var errorCount: Int = 0
    
    /// Buffer drop rate (0.0 to 1.0)
    public var dropRate: Double {
        guard totalEnqueued > 0 else { return 0.0 }
        return Double(droppedBuffers) / Double(totalEnqueued)
    }
    
    /// Average queue utilization (0.0 to 1.0)
    public var utilization: Double {
        guard peakSize > 0 else { return 0.0 }
        return Double(currentSize) / Double(peakSize)
    }
}

/// Priority buffer queue with multiple priority levels
@available(macOS 13.0, *)
public actor PriorityAudioBufferQueue {
    
    // MARK: - Types
    
    public enum Priority: Int, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3
        
        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    private struct PriorityBuffer {
        let buffer: AudioBuffer
        let priority: Priority
        let timestamp: Date
    }
    
    // MARK: - Properties
    
    private let maxSize: Int
    private var buffers: [PriorityBuffer] = []
    private var continuation: AsyncStream<AudioBuffer>.Continuation?
    private var isFinished = false
    
    public let stream: AsyncStream<AudioBuffer>
    
    // MARK: - Initialization
    
    public init(maxSize: Int = 32) {
        self.maxSize = maxSize
        
        var localContinuation: AsyncStream<AudioBuffer>.Continuation?
        self.stream = AsyncStream<AudioBuffer> { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
    }
    
    // MARK: - Queue Operations
    
    /// Enqueue buffer with priority
    public func enqueue(_ buffer: AudioBuffer, priority: Priority = .normal) async {
        guard !isFinished else { return }
        
        let priorityBuffer = PriorityBuffer(
            buffer: buffer,
            priority: priority,
            timestamp: Date()
        )
        
        // Check for overflow
        if buffers.count >= maxSize {
            // Remove lowest priority buffer
            if let lowestIndex = findLowestPriorityIndex() {
                buffers.remove(at: lowestIndex)
            }
        }
        
        // Insert in priority order
        let insertIndex = findInsertIndex(for: priority)
        buffers.insert(priorityBuffer, at: insertIndex)
        
        // Send highest priority buffer to stream
        if let highest = buffers.first {
            buffers.removeFirst()
            continuation?.yield(highest.buffer)
        }
    }
    
    /// Find index to insert buffer with given priority
    private func findInsertIndex(for priority: Priority) -> Int {
        // Binary search for insertion point
        var low = 0
        var high = buffers.count
        
        while low < high {
            let mid = (low + high) / 2
            if buffers[mid].priority >= priority {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        return low
    }
    
    /// Find index of lowest priority buffer
    private func findLowestPriorityIndex() -> Int? {
        guard !buffers.isEmpty else { return nil }
        
        var lowestIndex = 0
        var lowestPriority = buffers[0].priority
        
        for (index, buffer) in buffers.enumerated() {
            if buffer.priority < lowestPriority {
                lowestPriority = buffer.priority
                lowestIndex = index
            }
        }
        
        return lowestIndex
    }
    
    /// Finish the queue
    public func finish() {
        isFinished = true
        
        // Send remaining buffers in priority order
        for priorityBuffer in buffers {
            continuation?.yield(priorityBuffer.buffer)
        }
        
        continuation?.finish()
        continuation = nil
        buffers.removeAll()
    }
}

/// Circular buffer queue for lock-free operations
@available(macOS 13.0, *)
public class CircularAudioBufferQueue {
    
    // MARK: - Properties
    
    private let capacity: Int
    private var buffers: [AudioBuffer?]
    private var head: Int = 0
    private var tail: Int = 0
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(capacity: Int = 32) {
        self.capacity = capacity
        self.buffers = Array(repeating: nil, count: capacity)
    }
    
    // MARK: - Queue Operations
    
    /// Try to enqueue a buffer
    public func tryEnqueue(_ buffer: AudioBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let nextTail = (tail + 1) % capacity
        
        // Check if full
        if nextTail == head {
            return false
        }
        
        buffers[tail] = buffer
        tail = nextTail
        
        return true
    }
    
    /// Try to dequeue a buffer
    public func tryDequeue() -> AudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        
        // Check if empty
        if head == tail {
            return nil
        }
        
        let buffer = buffers[head]
        buffers[head] = nil
        head = (head + 1) % capacity
        
        return buffer
    }
    
    /// Get current count
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        
        if tail >= head {
            return tail - head
        } else {
            return capacity - head + tail
        }
    }
    
    /// Check if empty
    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return head == tail
    }
    
    /// Check if full
    public var isFull: Bool {
        lock.lock()
        defer { lock.unlock() }
        return (tail + 1) % capacity == head
    }
    
    /// Clear all buffers
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        head = 0
        tail = 0
        buffers = Array(repeating: nil, count: capacity)
    }
}