import Foundation

/// AudioCaptureError - Comprehensive error types for the audio capture library
public enum AudioCaptureError: LocalizedError {
    
    // MARK: - Device Errors
    case deviceNotFound(String)
    case deviceEnumerationFailed
    case deviceSelectionFailed
    case devicePropertyReadFailed
    case invalidDevice(String)
    case deviceDisconnected(String)
    case deviceInUse(String)
    
    // MARK: - Permission Errors
    case permissionDenied
    case screenRecordingPermissionRequired
    case microphonePermissionRequired
    
    // MARK: - Session Errors
    case sessionNotFound(UUID)
    case invalidState(String)
    case sessionAlreadyActive
    case sessionNotActive
    case sessionStartFailed(String)
    
    // MARK: - Format Errors
    case unsupportedFormat(String)
    case formatConversionFailed(String)
    case formatMismatch(String)
    case formatNegotiationFailed
    
    // MARK: - Output Errors
    case outputNotConfigured
    case outputConfigurationFailed(String)
    case outputProcessingFailed(String)
    case fileWriteFailed(String)
    case streamingFailed(String)
    
    // MARK: - Buffer Errors
    case bufferAllocationFailed
    case bufferOverflow
    case bufferUnderrun
    case invalidBufferSize
    
    // MARK: - System Errors
    case systemResourcesExhausted
    case memoryAllocationFailed
    case audioEngineStartFailed(String)
    case unknownError(String)
    
    // MARK: - Network Errors (for future streaming)
    case networkConnectionFailed(String)
    case streamingProtocolError(String)
    
    // MARK: - LocalizedError Implementation
    
    public var errorDescription: String? {
        switch self {
        // Device Errors
        case .deviceNotFound(let name):
            return "Audio device '\(name)' not found"
        case .deviceEnumerationFailed:
            return "Failed to enumerate audio devices"
        case .deviceSelectionFailed:
            return "Failed to select audio device"
        case .devicePropertyReadFailed:
            return "Failed to read device properties"
        case .invalidDevice(let reason):
            return "Invalid device: \(reason)"
        case .deviceDisconnected(let name):
            return "Device '\(name)' was disconnected"
        case .deviceInUse(let name):
            return "Device '\(name)' is already in use"
            
        // Permission Errors
        case .permissionDenied:
            return "Permission denied"
        case .screenRecordingPermissionRequired:
            return "Screen Recording permission is required. Please grant permission in System Settings > Privacy & Security > Screen Recording"
        case .microphonePermissionRequired:
            return "Microphone permission is required. Please grant permission in System Settings > Privacy & Security > Microphone"
            
        // Session Errors
        case .sessionNotFound(let id):
            return "Session with ID \(id) not found"
        case .invalidState(let message):
            return "Invalid session state: \(message)"
        case .sessionAlreadyActive:
            return "Session is already active"
        case .sessionNotActive:
            return "Session is not active"
        case .sessionStartFailed(let reason):
            return "Failed to start session: \(reason)"
            
        // Format Errors
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format)"
        case .formatConversionFailed(let reason):
            return "Format conversion failed: \(reason)"
        case .formatMismatch(let details):
            return "Audio format mismatch: \(details)"
        case .formatNegotiationFailed:
            return "Failed to negotiate compatible audio format"
            
        // Output Errors
        case .outputNotConfigured:
            return "Output is not configured"
        case .outputConfigurationFailed(let reason):
            return "Output configuration failed: \(reason)"
        case .outputProcessingFailed(let reason):
            return "Output processing failed: \(reason)"
        case .fileWriteFailed(let reason):
            return "File write failed: \(reason)"
        case .streamingFailed(let reason):
            return "Streaming failed: \(reason)"
            
        // Buffer Errors
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .bufferOverflow:
            return "Audio buffer overflow"
        case .bufferUnderrun:
            return "Audio buffer underrun"
        case .invalidBufferSize:
            return "Invalid buffer size"
            
        // System Errors
        case .systemResourcesExhausted:
            return "System resources exhausted"
        case .memoryAllocationFailed:
            return "Memory allocation failed"
        case .audioEngineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
            
        // Network Errors
        case .networkConnectionFailed(let reason):
            return "Network connection failed: \(reason)"
        case .streamingProtocolError(let reason):
            return "Streaming protocol error: \(reason)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .screenRecordingPermissionRequired:
            return "The app needs access to system audio"
        case .microphonePermissionRequired:
            return "The app needs access to microphone input"
        case .systemResourcesExhausted:
            return "Not enough CPU or memory available"
        case .bufferOverflow:
            return "Audio processing can't keep up with input rate"
        case .bufferUnderrun:
            return "Audio input is not providing data fast enough"
        default:
            return nil
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .screenRecordingPermissionRequired:
            return "Open System Settings and grant Screen Recording permission to this app"
        case .microphonePermissionRequired:
            return "Open System Settings and grant Microphone permission to this app"
        case .deviceDisconnected:
            return "Reconnect the audio device or select a different device"
        case .systemResourcesExhausted:
            return "Close other applications to free up system resources"
        case .bufferOverflow:
            return "Try reducing the audio quality or closing other applications"
        case .formatMismatch:
            return "Check that all audio components are using compatible formats"
        default:
            return nil
        }
    }
    
    public var helpAnchor: String? {
        switch self {
        case .screenRecordingPermissionRequired, .microphonePermissionRequired:
            return "permissions"
        case .deviceNotFound, .deviceDisconnected, .deviceInUse:
            return "devices"
        case .unsupportedFormat, .formatConversionFailed, .formatMismatch:
            return "formats"
        case .bufferOverflow, .bufferUnderrun:
            return "performance"
        default:
            return nil
        }
    }
}

/// Error recovery strategies
public enum ErrorRecoveryStrategy {
    case retry(maxAttempts: Int, delay: TimeInterval)
    case fallback(action: () async throws -> Void)
    case ignore
    case fail
}

/// Error handler with recovery strategies
public struct ErrorHandler {
    
    /// Handle error with recovery strategy
    public static func handle(
        _ error: Error,
        strategy: ErrorRecoveryStrategy = .fail
    ) async throws {
        print("Error occurred: \(error.localizedDescription)")
        
        switch strategy {
        case .retry(let maxAttempts, let delay):
            // Retry logic would be implemented by caller
            throw error
            
        case .fallback(let action):
            try await action()
            
        case .ignore:
            // Log and continue
            print("Ignoring error: \(error)")
            
        case .fail:
            throw error
        }
    }
    
    /// Get suggested recovery strategy for error
    public static func suggestedStrategy(for error: Error) -> ErrorRecoveryStrategy {
        if let captureError = error as? AudioCaptureError {
            switch captureError {
            case .deviceDisconnected:
                return .retry(maxAttempts: 3, delay: 1.0)
            case .bufferOverflow, .bufferUnderrun:
                return .ignore
            case .sessionStartFailed:
                return .retry(maxAttempts: 2, delay: 0.5)
            default:
                return .fail
            }
        }
        
        return .fail
    }
}

/// Error context for detailed debugging
public struct ErrorContext {
    public let error: Error
    public let timestamp: Date
    public let sessionId: UUID?
    public let operation: String
    public let additionalInfo: [String: Any]
    
    public init(
        error: Error,
        sessionId: UUID? = nil,
        operation: String,
        additionalInfo: [String: Any] = [:]
    ) {
        self.error = error
        self.timestamp = Date()
        self.sessionId = sessionId
        self.operation = operation
        self.additionalInfo = additionalInfo
    }
    
    /// Create detailed error report
    public func report() -> String {
        var report = """
        Audio Capture Error Report
        ========================
        Timestamp: \(timestamp)
        Operation: \(operation)
        Error: \(error.localizedDescription)
        """
        
        if let sessionId = sessionId {
            report += "\nSession ID: \(sessionId)"
        }
        
        if !additionalInfo.isEmpty {
            report += "\n\nAdditional Information:"
            for (key, value) in additionalInfo {
                report += "\n  \(key): \(value)"
            }
        }
        
        if let captureError = error as? AudioCaptureError,
           let suggestion = captureError.recoverySuggestion {
            report += "\n\nRecovery Suggestion: \(suggestion)"
        }
        
        return report
    }
}