import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreAudio

// MARK: - Protocol Definitions

struct APIRequest: Codable {
    let id: String
    let command: String
    let params: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case id, command, params
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        command = try container.decode(String.self, forKey: .command)
        
        // Decode params as generic dictionary
        if container.contains(.params) {
            let paramsData = try container.decode([String: AnyCodable].self, forKey: .params)
            params = paramsData.mapValues { $0.value }
        } else {
            params = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(command, forKey: .command)
        if let params = params {
            let encodableParams = params.mapValues { AnyCodable($0) }
            try container.encode(encodableParams, forKey: .params)
        }
    }
}

struct APIResponse: Codable {
    let id: String
    let success: Bool
    let data: [String: AnyCodable]?
    let error: String?
}

// Helper for encoding/decoding Any types in JSON
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let uint as UInt:
            try container.encode(uint)
        case let uint32 as UInt32:
            try container.encode(Int(uint32))
        case let audioDeviceId as AudioDeviceID:
            try container.encode(Int(audioDeviceId))
        case let double as Double:
            try container.encode(double)
        case let float as Float:
            try container.encode(Double(float))
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            // Try to convert to string as last resort
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Audio Capture Server

@main
class AudioCaptureServer: NSObject {
    private var serverSocket: Int32 = -1
    private var port: UInt16 = 0  // Will be set to actual port
    private var clients: [Int32: ClientHandler] = [:]
    private let clientQueue = DispatchQueue(label: "audio.capture.clients", attributes: .concurrent)
    
    // Audio capture state
    private var isRecording = false
    private var recordingStartTime: Date?
    private var currentOutputPath: String?
    private var audioEngine: AVAudioEngine?
    private var systemRecorder: StreamingAudioRecorder?
    private var micCollector: ConvertingBufferCollector?
    private var systemCollector: BufferCollector?
    private let recordingQueue = DispatchQueue(label: "audio.capture.recording")
    
    static func main() {
        let server = AudioCaptureServer()
        server.start()
        
        // Keep the server running
        RunLoop.main.run()
    }
    
    func start() {
        // Ensure output is not buffered
        setbuf(stdout, nil)
        
        print("Audio Capture API Server")
        print("=======================")
        
        // Find and bind to a free port
        guard let foundPort = findAndBindToFreePort() else {
            print("❌ Failed to find available port")
            exit(1)
        }
        
        port = foundPort
        
        // Listen for connections
        guard listen(serverSocket, 5) >= 0 else {
            print("❌ Failed to listen on socket")
            close(serverSocket)
            exit(1)
        }
        
        print("✓ Server listening on port \(port)")
        print("✓ Ready to accept connections")
        print("✓ Python clients can connect using port \(port)\n")
        
        // Write port to file for Python clients
        writePortToFile()
        
        // Check permissions asynchronously
        Task {
            await checkPermissions()
        }
        
        // Accept connections in background
        DispatchQueue.global().async { [weak self] in
            self?.acceptConnections()
        }
    }
    
    private func findAndBindToFreePort() -> UInt16? {
        // Try ports starting from 9876
        let startPort: UInt16 = 9876
        let maxPort: UInt16 = 9976  // Try 100 ports
        
        for testPort in startPort...maxPort {
            // Create socket
            serverSocket = socket(AF_INET, SOCK_STREAM, 0)
            guard serverSocket >= 0 else {
                continue
            }
            
            // Allow socket reuse
            var yes: Int32 = 1
            setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            
            // Try to bind
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = testPort.bigEndian
            addr.sin_addr.s_addr = INADDR_ANY
            
            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            if bindResult >= 0 {
                print("✓ Found available port: \(testPort)")
                return testPort
            } else {
                close(serverSocket)
                serverSocket = -1
            }
        }
        
        return nil
    }
    
    private func writePortToFile() {
        let portFile = "server_port.txt"
        do {
            try "\(port)".write(toFile: portFile, atomically: true, encoding: .utf8)
            print("✓ Port number written to \(portFile)")
        } catch {
            print("⚠️  Failed to write port file: \(error)")
        }
    }
    
    private func acceptConnections() {
        print("✓ Accept loop started")
        while true {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverSocket, $0, &clientAddrLen)
                }
            }
            
            guard clientSocket >= 0 else {
                print("❌ Failed to accept connection")
                continue
            }
            
            print("✓ New client connected: socket \(clientSocket)")
            
            let handler = ClientHandler(socket: clientSocket, server: self)
            clientQueue.async(flags: .barrier) {
                self.clients[clientSocket] = handler
            }
            
            handler.start()
        }
    }
    
    func removeClient(_ socket: Int32) {
        clientQueue.async(flags: .barrier) {
            self.clients.removeValue(forKey: socket)
        }
    }
    
    // MARK: - Permission Checking
    
    func checkPermissions() async {
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
    }
    
    // MARK: - Command Handlers
    
    func handleCommand(_ request: APIRequest) async -> APIResponse {
        switch request.command {
        case "LIST_DEVICES":
            return await listDevices(request)
        case "START_RECORDING":
            return await startRecording(request)
        case "STOP_RECORDING":
            return await stopRecording(request)
        case "GET_STATUS":
            return getStatus(request)
        case "GET_FILE":
            return await getFile(request)
        case "SHUTDOWN":
            return shutdown(request)
        default:
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "Unknown command: \(request.command)"
            )
        }
    }
    
    private func listDevices(_ request: APIRequest) async -> APIResponse {
        let devices = AudioDeviceEnumerator.getAllInputDevices()
        let deviceList = devices.map { device in
            // Create a simple dictionary instead of nested AnyCodable
            return [
                "id": Int(device.id),
                "name": device.name
            ] as [String: Any]
        }
        
        return APIResponse(
            id: request.id,
            success: true,
            data: ["devices": AnyCodable(deviceList)],
            error: nil
        )
    }
    
    private func startRecording(_ request: APIRequest) async -> APIResponse {
        guard !isRecording else {
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "Recording already in progress"
            )
        }
        
        // Extract parameters
        guard let params = request.params,
              let deviceIdAny = params["device_id"],
              let deviceId = (deviceIdAny as? Int).map({ AudioDeviceID($0) }) else {
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "Missing required parameter: device_id"
            )
        }
        
        let captureSystemAudio = (params["capture_system_audio"] as? Bool) ?? false
        let outputPath = (params["output_path"] as? String) ?? "api_recording_\(Date().timeIntervalSince1970).wav"
        
        // Check microphone permission
        let hasMicPermission = await checkMicrophonePermission()
        if !hasMicPermission {
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "Microphone permission denied. Please grant microphone access in System Preferences > Privacy & Security > Microphone"
            )
        }
        
        // Start recording
        do {
            try startRecordingInternal(
                deviceId: deviceId,
                captureSystemAudio: captureSystemAudio,
                outputPath: outputPath
            )
            
            return APIResponse(
                id: request.id,
                success: true,
                data: [
                    "output_path": AnyCodable(outputPath),
                    "started_at": AnyCodable(recordingStartTime!.timeIntervalSince1970)
                ],
                error: nil
            )
        } catch {
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "Failed to start recording: \(error.localizedDescription)"
            )
        }
    }
    
    private func checkMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    private func startRecordingInternal(deviceId: AudioDeviceID, captureSystemAudio: Bool, outputPath: String) throws {
        // Create audio engine
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine!.inputNode
        
        // Set the device
        try AudioDeviceConfigurator.setInputDevice(deviceId, for: audioEngine!)
        
        // Setup collectors
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        
        // Log the device format for debugging
        print("Device \(deviceId) format: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount)ch")
        
        // DYNAMICALLY adapt to the device's format
        // The ConvertingBufferCollector will handle ANY input format
        micCollector = ConvertingBufferCollector(
            inputFormat: hardwareFormat,
            outputSampleRate: 48000,
            outputChannels: 2
        )
        
        // Install tap - let AVAudioEngine decide the best format by passing nil
        // This allows the engine to negotiate the optimal format with the device
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: nil  // nil = let the engine choose the best format
        ) { [weak self] buffer, time in
            self?.micCollector?.addBuffer(buffer)
        }
        
        // Start microphone
        try audioEngine!.start()
        
        // Setup system audio if requested
        if captureSystemAudio {
            systemRecorder = StreamingAudioRecorder()
            systemCollector = BufferCollector()
            systemRecorder!.addStreamDelegate(systemCollector!)
            
            Task {
                try await self.systemRecorder!.startStreaming()
            }
        }
        
        isRecording = true
        recordingStartTime = Date()
        currentOutputPath = outputPath
        
        // Verify audio is being received after a short delay
        Task {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            if isRecording && micCollector?.buffers.count == 0 {
                print("WARNING: No audio buffers received from device ID \(deviceId). The device may not be compatible.")
            }
        }
    }
    
    private func stopRecording(_ request: APIRequest) async -> APIResponse {
        guard isRecording else {
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "No recording in progress"
            )
        }
        
        do {
            let (path, duration) = try await stopRecordingInternal()
            
            return APIResponse(
                id: request.id,
                success: true,
                data: [
                    "output_path": AnyCodable(path),
                    "duration": AnyCodable(duration),
                    "file_size": AnyCodable(getFileSize(path))
                ],
                error: nil
            )
        } catch {
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "Failed to stop recording: \(error.localizedDescription)"
            )
        }
    }
    
    private func stopRecordingInternal() async throws -> (String, Double) {
        guard let engine = audioEngine,
              let outputPath = currentOutputPath,
              let startTime = recordingStartTime else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid recording state"])
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Stop captures
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        
        if let recorder = systemRecorder {
            await recorder.stopStreaming()
        }
        
        // Export audio
        if let systemCol = systemCollector, !systemCol.buffers.isEmpty && !micCollector!.buffers.isEmpty {
            // Mix audio
            let mixed = try AudioMixer.mixAudioBuffers(
                systemBuffers: systemCol.buffers,
                micBuffers: micCollector!.buffers
            )
            try await AudioExporter.exportToWAV(buffers: mixed, outputPath: outputPath)
        } else if !micCollector!.buffers.isEmpty {
            // Mic only
            try await AudioExporter.exportToWAV(buffers: micCollector!.buffers, outputPath: outputPath)
        }
        
        // Cleanup
        isRecording = false
        audioEngine = nil
        systemRecorder = nil
        micCollector = nil
        systemCollector = nil
        recordingStartTime = nil
        currentOutputPath = nil
        
        return (outputPath, duration)
    }
    
    private func getStatus(_ request: APIRequest) -> APIResponse {
        var statusData: [String: AnyCodable] = [
            "is_recording": AnyCodable(isRecording)
        ]
        
        if isRecording, let startTime = recordingStartTime {
            statusData["duration"] = AnyCodable(Date().timeIntervalSince(startTime))
            statusData["started_at"] = AnyCodable(startTime.timeIntervalSince1970)
            
            if let micCol = micCollector {
                statusData["mic_buffers"] = AnyCodable(micCol.buffers.count)
            }
            
            if let sysCol = systemCollector {
                statusData["system_buffers"] = AnyCodable(sysCol.buffers.count)
            }
        }
        
        return APIResponse(
            id: request.id,
            success: true,
            data: statusData,
            error: nil
        )
    }
    
    private func getFile(_ request: APIRequest) async -> APIResponse {
        guard let params = request.params,
              let path = params["path"] as? String else {
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "Missing required parameter: path"
            )
        }
        
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "File not found: \(path)"
            )
        }
        
        do {
            let data = try Data(contentsOf: url)
            let base64 = data.base64EncodedString()
            
            return APIResponse(
                id: request.id,
                success: true,
                data: [
                    "path": AnyCodable(path),
                    "size": AnyCodable(data.count),
                    "data": AnyCodable(base64)
                ],
                error: nil
            )
        } catch {
            return APIResponse(
                id: request.id,
                success: false,
                data: nil,
                error: "Failed to read file: \(error.localizedDescription)"
            )
        }
    }
    
    private func shutdown(_ request: APIRequest) -> APIResponse {
        print("\n✓ Shutdown requested")
        
        // Stop any active recording
        if isRecording {
            Task {
                _ = try? await stopRecordingInternal()
            }
        }
        
        // Close all client connections
        clientQueue.sync {
            for (socket, _) in clients {
                close(socket)
            }
            clients.removeAll()
        }
        
        // Close server socket
        close(serverSocket)
        
        // Exit after sending response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
        
        return APIResponse(
            id: request.id,
            success: true,
            data: nil,
            error: nil
        )
    }
    
    private func getFileSize(_ path: String) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int else {
            return 0
        }
        return size
    }
}

// MARK: - Client Handler

class ClientHandler {
    private let socket: Int32
    private weak var server: AudioCaptureServer?
    private let queue = DispatchQueue(label: "client.handler")
    
    init(socket: Int32, server: AudioCaptureServer) {
        self.socket = socket
        self.server = server
    }
    
    func start() {
        queue.async { [weak self] in
            self?.handleClient()
        }
    }
    
    private func handleClient() {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer {
            buffer.deallocate()
            close(socket)
            server?.removeClient(socket)
            print("✓ Client disconnected: socket \(socket)")
        }
        
        var messageBuffer = Data()
        
        while true {
            let bytesRead = recv(socket, buffer, 4096, 0)
            
            if bytesRead <= 0 {
                break
            }
            
            messageBuffer.append(buffer, count: bytesRead)
            
            // Process complete messages (newline delimited)
            while let newlineIndex = messageBuffer.firstIndex(of: 0x0A) { // '\n'
                let messageData = messageBuffer[..<newlineIndex]
                messageBuffer.removeSubrange(...newlineIndex)
                
                do {
                    let request = try JSONDecoder().decode(APIRequest.self, from: messageData)
                    print("📥 Received request: \(request.command)")
                    
                    Task { [weak self] in
                        guard let self = self else { return }
                        let response = await self.server?.handleCommand(request) ?? APIResponse(
                            id: request.id,
                            success: false,
                            data: nil,
                            error: "Server error"
                        )
                        print("📤 Sending response for: \(request.command)")
                        self.sendResponse(response)
                    }
                } catch {
                    print("❌ Failed to decode request: \(error)")
                    print("   Raw data: \(String(data: messageData, encoding: .utf8) ?? "nil")")
                }
            }
        }
    }
    
    private func sendResponse(_ response: APIResponse) {
        do {
            let data = try JSONEncoder().encode(response)
            var message = data
            message.append(0x0A) // '\n'
            
            print("📤 Sending \(message.count) bytes to socket \(socket)")
            
            let result = message.withUnsafeBytes { bytes in
                send(socket, bytes.baseAddress, message.count, 0)
            }
            
            if result < 0 {
                print("❌ Send failed: \(errno)")
            } else {
                print("✅ Sent \(result) bytes")
            }
        } catch {
            print("❌ Failed to encode response: \(error)")
        }
    }
}

// MARK: - Helper Classes

struct AudioDeviceInfo {
    let id: AudioDeviceID
    let name: String
}

class AudioDeviceEnumerator {
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
}

class AudioDeviceConfigurator {
    static func setInputDevice(_ deviceID: AudioDeviceID, for engine: AVAudioEngine) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio unit on input node"])
        }
        
        // Enable IO for input
        var enableIO: UInt32 = 1
        var result = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        if result != noErr {
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
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
    }
}

class AudioMixer {
    static func mixAudioBuffers(systemBuffers: [AVAudioPCMBuffer], micBuffers: [AVAudioPCMBuffer]) throws -> [AVAudioPCMBuffer] {
        guard !systemBuffers.isEmpty && !micBuffers.isEmpty else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No buffers to mix"])
        }
        
        guard let format = systemBuffers.first?.format else {
            throw NSError(domain: "AudioCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "No format available"])
        }
        
        // Combine all mic buffers into one continuous buffer
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
            guard let mixedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: systemBuffer.frameLength) else {
                continue
            }
            
            mixedBuffer.frameLength = systemBuffer.frameLength
            
            if let systemData = systemBuffer.floatChannelData,
               let micData = combinedMicBuffer.floatChannelData,
               let mixedData = mixedBuffer.floatChannelData {
                
                for frame in 0..<Int(systemBuffer.frameLength) {
                    for channel in 0..<Int(format.channelCount) {
                        let systemSample = systemData[channel][frame]
                        
                        let micSample: Float
                        if micFrameOffset < Int(combinedMicBuffer.frameLength) {
                            micSample = micData[channel][micFrameOffset]
                        } else {
                            micSample = 0.0
                        }
                        
                        mixedData[channel][frame] = systemSample * 0.5 + micSample * 0.5
                    }
                    
                    micFrameOffset += 1
                }
            }
            
            mixed.append(mixedBuffer)
        }
        
        return mixed
    }
}

class AudioExporter {
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

// Buffer collector classes (from original implementation)
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
        // Log input format for debugging
        print("ConvertingBufferCollector init:")
        print("  Input: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch, format: \(inputFormat.commonFormat.rawValue)")
        print("  Output: \(outputSampleRate)Hz, \(outputChannels)ch")
        
        self.needsStereoConversion = inputFormat.channelCount == 1 && outputChannels == 2
        
        // Handle any input format by always converting to standard PCM float
        if needsStereoConversion {
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
            
            // Create converter - handle potential failure
            if let conv = AVAudioConverter(from: inputFormat, to: intermediateFormat) {
                self.converter = conv
            } else {
                print("⚠️  Failed to create converter, trying with standard format")
                // If direct conversion fails, try converting to a standard format first
                let standardFormat = AVAudioFormat(
                    standardFormatWithSampleRate: inputFormat.sampleRate,
                    channels: inputFormat.channelCount
                )!
                self.converter = AVAudioConverter(from: standardFormat, to: intermediateFormat)!
            }
        } else {
            self.intermediateFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputSampleRate,
                channels: min(inputFormat.channelCount, outputChannels), // Don't increase channels
                interleaved: false
            )!
            self.outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputSampleRate,
                channels: outputChannels,
                interleaved: false
            )!
            
            // Create converter - handle potential failure
            if let conv = AVAudioConverter(from: inputFormat, to: intermediateFormat) {
                self.converter = conv
            } else {
                print("⚠️  Failed to create converter, trying with standard format")
                let standardFormat = AVAudioFormat(
                    standardFormatWithSampleRate: inputFormat.sampleRate,
                    channels: inputFormat.channelCount
                )!
                self.converter = AVAudioConverter(from: standardFormat, to: intermediateFormat)!
            }
        }
        
        converter.sampleRateConverterQuality = .max
        
        super.init()
    }
    
    override func addBuffer(_ buffer: AVAudioPCMBuffer) {
        queue.sync {
            let sampleRateRatio = intermediateFormat.sampleRate / buffer.format.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio + 2)
            
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: intermediateFormat, frameCapacity: outputFrameCapacity) else {
                return
            }
            
            var error: NSError?
            var bufferSubmitted = false
            
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
            
            if needsStereoConversion {
                guard let stereoBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: convertedBuffer.frameLength) else {
                    return
                }
                stereoBuffer.frameLength = convertedBuffer.frameLength
                
                if let monoData = convertedBuffer.floatChannelData?[0],
                   let stereoData = stereoBuffer.floatChannelData {
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