import Foundation
import AVFoundation
import CoreAudio

/// AudioDevice - Represents an audio input or output device
///
/// This structure encapsulates all relevant information about an audio device,
/// including its capabilities, supported formats, and current status.
public struct AudioDevice: Identifiable, Hashable, Codable {
    /// Unique device identifier
    public let id: String
    
    /// Human-readable device name
    public let name: String
    
    /// Device manufacturer
    public let manufacturer: String?
    
    /// Device type
    public let type: DeviceType
    
    /// Core Audio device ID
    public let audioDeviceID: AudioDeviceID
    
    /// Supported audio formats
    public let supportedFormats: [AudioFormat]
    
    /// Is this the default device for its type
    public let isDefault: Bool
    
    /// Current device status
    public var status: DeviceStatus
    
    /// Device capabilities
    public let capabilities: DeviceCapabilities
    
    /// Device type enumeration
    public enum DeviceType: String, Codable {
        case input = "input"
        case output = "output"
        case system = "system"  // System audio capture
    }
    
    /// Device status
    public enum DeviceStatus: String, Codable {
        case connected = "connected"
        case disconnected = "disconnected"
        case unavailable = "unavailable"
    }
}

/// Device capabilities
public struct DeviceCapabilities: Codable, Hashable {
    /// Supports hardware monitoring
    public let hardwareMonitoring: Bool
    
    /// Supports exclusive mode
    public let exclusiveMode: Bool
    
    /// Minimum latency in seconds
    public let minLatency: TimeInterval
    
    /// Maximum channel count
    public let maxChannels: Int
    
    /// Supported sample rates
    public let sampleRates: [Double]
}

/// AudioDeviceManager - Manages audio device enumeration and selection
@available(macOS 13.0, *)
public actor AudioDeviceManager {
    
    // MARK: - Properties
    
    /// Device change notification handler
    private var deviceChangeHandler: ((DeviceChangeEvent) -> Void)?
    
    /// Cached device list
    private var cachedDevices: [AudioDevice] = []
    
    /// Last device scan time
    private var lastScanTime: Date?
    
    /// Device scan interval (to avoid excessive scanning)
    private let scanInterval: TimeInterval = 1.0
    
    // MARK: - Initialization
    
    public init() {
        Task {
            await setupDeviceChangeNotifications()
        }
    }
    
    // MARK: - Device Enumeration
    
    /// Get all available playback devices
    public func getPlaybackDevices() throws -> [AudioDevice] {
        if shouldRefreshDeviceList() {
            try refreshDeviceList()
        }
        return cachedDevices.filter { $0.type == .output }
    }
    
    /// Get all available recording devices
    public func getRecordingDevices() throws -> [AudioDevice] {
        if shouldRefreshDeviceList() {
            try refreshDeviceList()
        }
        
        var devices = cachedDevices.filter { $0.type == .input }
        
        // Add system audio capture as a special device
        let systemDevice = AudioDevice(
            id: "system-audio-capture",
            name: "System Audio",
            manufacturer: "Apple",
            type: .system,
            audioDeviceID: 0,
            supportedFormats: [AudioFormat.defaultFormat],
            isDefault: false,
            status: .connected,
            capabilities: DeviceCapabilities(
                hardwareMonitoring: false,
                exclusiveMode: false,
                minLatency: 0.020,
                maxChannels: 2,
                sampleRates: [44100.0, 48000.0]
            )
        )
        devices.append(systemDevice)
        
        return devices
    }
    
    /// Get device by ID
    public func getDevice(byId id: String) throws -> AudioDevice? {
        if shouldRefreshDeviceList() {
            try refreshDeviceList()
        }
        return cachedDevices.first { $0.id == id }
    }
    
    // MARK: - Device Selection
    
    /// Set the default playback device
    public func setPlaybackDevice(_ device: AudioDevice) throws {
        guard device.type == .output else {
            throw AudioCaptureError.invalidDevice("Device is not an output device")
        }
        
        try setDefaultDevice(device.audioDeviceID, scope: kAudioHardwarePropertyDefaultOutputDevice)
    }
    
    /// Set the default recording device
    public func setRecordingDevice(_ device: AudioDevice) throws {
        guard device.type == .input || device.type == .system else {
            throw AudioCaptureError.invalidDevice("Device is not an input device")
        }
        
        if device.type == .system {
            // System audio capture doesn't change hardware device
            return
        }
        
        try setDefaultDevice(device.audioDeviceID, scope: kAudioHardwarePropertyDefaultInputDevice)
    }
    
    /// Get current playback device
    public func getCurrentPlaybackDevice() throws -> AudioDevice? {
        let deviceID = try getDefaultDevice(scope: kAudioHardwarePropertyDefaultOutputDevice)
        return try getDevice(byAudioDeviceID: deviceID)
    }
    
    /// Get current recording device
    public func getCurrentRecordingDevice() throws -> AudioDevice? {
        let deviceID = try getDefaultDevice(scope: kAudioHardwarePropertyDefaultInputDevice)
        return try getDevice(byAudioDeviceID: deviceID)
    }
    
    // MARK: - Device Monitoring
    
    /// Set device change handler
    public func setDeviceChangeHandler(_ handler: @escaping (DeviceChangeEvent) -> Void) {
        self.deviceChangeHandler = handler
    }
    
    /// Remove device change handler
    public func removeDeviceChangeHandler() {
        self.deviceChangeHandler = nil
    }
    
    // MARK: - Private Methods
    
    private func shouldRefreshDeviceList() -> Bool {
        guard let lastScan = lastScanTime else { return true }
        return Date().timeIntervalSince(lastScan) > scanInterval
    }
    
    private func refreshDeviceList() throws {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Get size
        let sizeResult = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard sizeResult == noErr else {
            throw AudioCaptureError.deviceEnumerationFailed
        }
        
        // Get devices
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        let devicesResult = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &audioDevices
        )
        
        guard devicesResult == noErr else {
            throw AudioCaptureError.deviceEnumerationFailed
        }
        
        // Convert to AudioDevice objects
        cachedDevices = audioDevices.compactMap { deviceID in
            do {
                return try createAudioDevice(from: deviceID)
            } catch {
                print("Failed to create AudioDevice from ID \(deviceID): \(error)")
                return nil
            }
        }
        
        lastScanTime = Date()
    }
    
    private func createAudioDevice(from deviceID: AudioDeviceID) throws -> AudioDevice {
        // Get device name
        let name = try getDeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString) as String
        
        // Get manufacturer
        let manufacturer = try? getDeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceManufacturerCFString) as String
        
        // Get UID for unique ID
        let uid = try getDeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) as String
        
        // Determine device type
        let hasOutput = try deviceHasScope(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
        let hasInput = try deviceHasScope(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
        
        let deviceType: AudioDevice.DeviceType
        if hasOutput && !hasInput {
            deviceType = .output
        } else if hasInput && !hasOutput {
            deviceType = .input
        } else {
            // Skip devices that are both input and output for now
            throw AudioCaptureError.invalidDevice("Unsupported device type")
        }
        
        // Get supported formats
        let formats = try getSupportedFormats(deviceID: deviceID, scope: deviceType == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput)
        
        // Check if default
        let isDefault = try isDefaultDevice(deviceID: deviceID, type: deviceType)
        
        // Get capabilities
        let capabilities = try getDeviceCapabilities(deviceID: deviceID, type: deviceType)
        
        return AudioDevice(
            id: uid,
            name: name,
            manufacturer: manufacturer,
            type: deviceType,
            audioDeviceID: deviceID,
            supportedFormats: formats,
            isDefault: isDefault,
            status: .connected,
            capabilities: capabilities
        )
    }
    
    private func getDeviceProperty<T>(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws -> T {
        var propertySize = UInt32(MemoryLayout<T>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var value: T?
        let result = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &propertySize,
                ptr
            )
        }
        
        guard result == noErr, let value = value else {
            throw AudioCaptureError.devicePropertyReadFailed
        }
        
        return value
    }
    
    private func deviceHasScope(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        let result = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        return result == noErr && propertySize > 0
    }
    
    private func getSupportedFormats(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> [AudioFormat] {
        // For now, return common formats
        // TODO: Query actual device formats
        return [
            AudioFormat(sampleRate: 44100.0, channelCount: 2, bitDepth: 16, isInterleaved: true),
            AudioFormat(sampleRate: 48000.0, channelCount: 2, bitDepth: 16, isInterleaved: true),
            AudioFormat(sampleRate: 48000.0, channelCount: 2, bitDepth: 24, isInterleaved: true),
            AudioFormat(sampleRate: 48000.0, channelCount: 2, bitDepth: 32, isInterleaved: false)
        ]
    }
    
    private func isDefaultDevice(deviceID: AudioDeviceID, type: AudioDevice.DeviceType) throws -> Bool {
        let selector = type == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
        let defaultID = try getDefaultDevice(scope: selector)
        return deviceID == defaultID
    }
    
    private func getDeviceCapabilities(deviceID: AudioDeviceID, type: AudioDevice.DeviceType) throws -> DeviceCapabilities {
        // TODO: Query actual device capabilities
        return DeviceCapabilities(
            hardwareMonitoring: false,
            exclusiveMode: false,
            minLatency: 0.010,
            maxChannels: type == .output ? 8 : 2,
            sampleRates: [44100.0, 48000.0, 96000.0]
        )
    }
    
    private func setDefaultDevice(_ deviceID: AudioDeviceID, scope: AudioObjectPropertySelector) throws {
        var mutableDeviceID = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: scope,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
        
        guard result == noErr else {
            throw AudioCaptureError.deviceSelectionFailed
        }
    }
    
    private func getDefaultDevice(scope: AudioObjectPropertySelector) throws -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: scope,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        guard result == noErr else {
            throw AudioCaptureError.devicePropertyReadFailed
        }
        
        return deviceID
    }
    
    private func getDevice(byAudioDeviceID audioDeviceID: AudioDeviceID) throws -> AudioDevice? {
        if shouldRefreshDeviceList() {
            try refreshDeviceList()
        }
        return cachedDevices.first { $0.audioDeviceID == audioDeviceID }
    }
    
    private func setupDeviceChangeNotifications() {
        // TODO: Implement Core Audio device change notifications
    }
}

/// Device change event
public enum DeviceChangeEvent {
    case deviceAdded(AudioDevice)
    case deviceRemoved(AudioDevice)
    case defaultChanged(AudioDevice.DeviceType, AudioDevice?)
}