import Foundation
import AVFoundation
import Network

/// NetworkOutput - Streams audio over TCP/IP network
///
/// This output implementation creates a TCP server that streams audio buffers
/// to connected clients. It's designed for inter-process communication,
/// particularly with Python clients that want to receive real-time audio.
///
/// Protocol:
/// - Header: Format information (sent once per connection)
/// - Packets: Audio data with timestamps
@available(macOS 13.0, *)
public class NetworkOutput: AudioOutput {
    
    // MARK: - Properties
    
    public let id = UUID()
    private let port: UInt16
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.audiocapture.network", qos: .userInitiated)
    private var format: AudioFormat?
    private var isConfigured = false
    
    // Protocol constants
    private let protocolMagic = "AUDIO".data(using: .utf8)!
    private let protocolVersion: UInt8 = 1
    private let packetTypeAudio: UInt8 = 0x01
    private let packetTypeFormat: UInt8 = 0x02
    private let packetTypeEnd: UInt8 = 0xFF
    
    // Statistics
    private var packetsSent: UInt64 = 0
    private var bytesSent: UInt64 = 0
    private var startTime = Date()
    
    // MARK: - Initialization
    
    public init(port: UInt16 = 9876) {
        self.port = port
    }
    
    // MARK: - AudioOutput Protocol
    
    public func configure(format: AudioFormat) async throws {
        self.format = format
        
        // Start network listener
        try await startListener()
        
        isConfigured = true
        print("NetworkOutput: Started TCP server on port \(port)")
    }
    
    public func process(_ buffer: AudioBuffer) async throws {
        guard isConfigured else {
            throw AudioCaptureError.outputNotConfigured
        }
        
        // Create audio packet
        let packet = createAudioPacket(from: buffer)
        
        // Send to all connected clients
        await sendToAllClients(packet)
        
        packetsSent += 1
        bytesSent += UInt64(packet.count)
    }
    
    public func handleError(_ error: Error) async {
        print("NetworkOutput error: \(error)")
    }
    
    public func finish() async {
        // Send end packet to all clients
        let endPacket = createEndPacket()
        await sendToAllClients(endPacket)
        
        // Close all connections
        queue.sync {
            for connection in connections {
                connection.cancel()
            }
            connections.removeAll()
            
            listener?.cancel()
            listener = nil
        }
        
        isConfigured = false
        
        // Print statistics
        let duration = Date().timeIntervalSince(startTime)
        let mbSent = Double(bytesSent) / (1024 * 1024)
        print("NetworkOutput: Finished")
        print("  Packets sent: \(packetsSent)")
        print("  Data sent: \(String(format: "%.2f", mbSent)) MB")
        print("  Duration: \(String(format: "%.1f", duration))s")
        print("  Throughput: \(String(format: "%.2f", mbSent / duration)) MB/s")
    }
    
    // MARK: - Network Management
    
    private func startListener() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        guard let port = NWEndpoint.Port(rawValue: self.port) else {
            throw AudioCaptureError.networkConnectionFailed("Invalid port number")
        }
        
        listener = try NWListener(using: parameters, on: port)
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: queue)
        
        // Wait for listener to be ready
        try await withCheckedThrowingContinuation { continuation in
            queue.asyncAfter(deadline: .now() + 0.1) {
                if self.listener?.state == .ready {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AudioCaptureError.networkConnectionFailed("Failed to start listener"))
                }
            }
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("NetworkOutput: New client connected from \(connection.endpoint)")
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.handleConnectionReady(connection)
            case .failed(let error):
                print("NetworkOutput: Connection failed: \(error)")
                self?.removeConnection(connection)
            case .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        
        queue.sync {
            connections.append(connection)
        }
    }
    
    private func handleConnectionReady(_ connection: NWConnection) {
        // Send format header to new client
        if let format = self.format {
            let header = createFormatHeader(format: format)
            connection.send(content: header, completion: .contentProcessed { error in
                if let error = error {
                    print("NetworkOutput: Failed to send header: \(error)")
                } else {
                    print("NetworkOutput: Sent format header to client")
                }
            })
        }
    }
    
    private func removeConnection(_ connection: NWConnection) {
        queue.sync {
            connections.removeAll { $0 === connection }
        }
        print("NetworkOutput: Client disconnected. Active connections: \(connections.count)")
    }
    
    // MARK: - Packet Creation
    
    private func createFormatHeader(format: AudioFormat) -> Data {
        var data = Data()
        
        // Magic bytes
        data.append(protocolMagic)
        
        // Version
        data.append(protocolVersion)
        
        // Sample rate (4 bytes, little-endian)
        var sampleRate = UInt32(format.sampleRate).littleEndian
        data.append(Data(bytes: &sampleRate, count: 4))
        
        // Channels (2 bytes, little-endian)
        var channels = UInt16(format.channelCount).littleEndian
        data.append(Data(bytes: &channels, count: 2))
        
        // Bit depth (2 bytes, little-endian)
        var bitDepth = UInt16(format.bitDepth).littleEndian
        data.append(Data(bytes: &bitDepth, count: 2))
        
        // Format flags (4 bytes, little-endian)
        var flags: UInt32 = 0
        if format.isFloat { flags |= 0x01 }
        if format.isInterleaved { flags |= 0x02 }
        flags = flags.littleEndian
        data.append(Data(bytes: &flags, count: 4))
        
        return data
    }
    
    private func createAudioPacket(from buffer: AudioBuffer) -> Data {
        var packet = Data()
        
        // Packet type
        packet.append(packetTypeAudio)
        
        // Timestamp (8 bytes, microseconds since start)
        let timestamp = UInt64(buffer.timestamp.timeIntervalSince(startTime) * 1_000_000)
        var timestampLE = timestamp.littleEndian
        packet.append(Data(bytes: &timestampLE, count: 8))
        
        // Frame count (4 bytes)
        var frameCount = UInt32(buffer.pcmBuffer.frameLength).littleEndian
        packet.append(Data(bytes: &frameCount, count: 4))
        
        // Audio data
        let audioData = extractAudioData(from: buffer.pcmBuffer)
        packet.append(audioData)
        
        return packet
    }
    
    private func createEndPacket() -> Data {
        var packet = Data()
        packet.append(packetTypeEnd)
        
        // Final timestamp
        let timestamp = UInt64(Date().timeIntervalSince(startTime) * 1_000_000)
        var timestampLE = timestamp.littleEndian
        packet.append(Data(bytes: &timestampLE, count: 8))
        
        return packet
    }
    
    private func extractAudioData(from buffer: AVAudioPCMBuffer) -> Data {
        let format = buffer.format
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        
        var audioData = Data()
        
        if format.commonFormat == .pcmFormatFloat32 {
            // Float32 format
            if let channelData = buffer.floatChannelData {
                if format.isInterleaved {
                    // Interleaved - single buffer
                    let totalSamples = frameCount * channelCount
                    audioData.append(Data(bytes: channelData[0], count: totalSamples * 4))
                } else {
                    // Non-interleaved - need to interleave for network transport
                    for frame in 0..<frameCount {
                        for channel in 0..<channelCount {
                            let sample = channelData[channel][frame]
                            var sampleLE = sample.bitPattern.littleEndian
                            audioData.append(Data(bytes: &sampleLE, count: 4))
                        }
                    }
                }
            }
        } else if format.commonFormat == .pcmFormatInt16 {
            // Int16 format
            if let channelData = buffer.int16ChannelData {
                if format.isInterleaved {
                    // Interleaved - single buffer
                    let totalSamples = frameCount * channelCount
                    audioData.append(Data(bytes: channelData[0], count: totalSamples * 2))
                } else {
                    // Non-interleaved - need to interleave
                    for frame in 0..<frameCount {
                        for channel in 0..<channelCount {
                            var sample = channelData[channel][frame].littleEndian
                            audioData.append(Data(bytes: &sample, count: 2))
                        }
                    }
                }
            }
        }
        
        return audioData
    }
    
    // MARK: - Data Transmission
    
    private func sendToAllClients(_ data: Data) async {
        await withTaskGroup(of: Void.self) { group in
            for connection in connections {
                group.addTask {
                    await self.sendData(data, to: connection)
                }
            }
        }
    }
    
    private func sendData(_ data: Data, to connection: NWConnection) async {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("NetworkOutput: Send error: \(error)")
                    self.removeConnection(connection)
                }
                continuation.resume()
            })
        }
    }
    
    // MARK: - Public Methods
    
    /// Get current connection count
    public func getConnectionCount() -> Int {
        return queue.sync { connections.count }
    }
    
    /// Get network statistics
    public func getStatistics() -> NetworkStatistics {
        let duration = Date().timeIntervalSince(startTime)
        return NetworkStatistics(
            connectionCount: getConnectionCount(),
            packetsSent: packetsSent,
            bytesSent: bytesSent,
            duration: duration,
            throughputMBps: Double(bytesSent) / (1024 * 1024) / duration
        )
    }
}

/// Network statistics
public struct NetworkStatistics {
    public let connectionCount: Int
    public let packetsSent: UInt64
    public let bytesSent: UInt64
    public let duration: TimeInterval
    public let throughputMBps: Double
}