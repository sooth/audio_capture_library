import XCTest
@testable import AudioCaptureKit

final class AudioCaptureKitTests: XCTestCase {
    
    func testDeviceEnumeration() async throws {
        // Test that we can enumerate audio devices
        let devices = await AudioDeviceManager.shared.getAllInputDevices()
        XCTAssertFalse(devices.isEmpty, "Should find at least one audio input device")
        
        // Verify device properties
        for device in devices {
            XCTAssertFalse(device.name.isEmpty, "Device should have a name")
            XCTAssertGreaterThan(device.id, 0, "Device should have valid ID")
        }
    }
    
    func testAudioFormatCreation() throws {
        // Test standard formats
        let cdQuality = AudioFormat.cdQuality
        XCTAssertEqual(cdQuality.sampleRate, 44100)
        XCTAssertEqual(cdQuality.channelCount, 2)
        XCTAssertEqual(cdQuality.bitDepth, 16)
        
        let highQuality = AudioFormat.highQuality
        XCTAssertEqual(highQuality.sampleRate, 48000)
        XCTAssertEqual(highQuality.channelCount, 2)
        XCTAssertEqual(highQuality.bitDepth, 24)
    }
    
    func testAudioCaptureKitSingleton() async throws {
        // Test that we can access the shared instance
        let kit = AudioCaptureKit.shared
        
        // Test device listing
        let devices = await kit.listAudioDevices()
        XCTAssertFalse(devices.isEmpty, "Should have audio devices")
        
        // Test default device
        if let defaultDevice = await kit.getDefaultInputDevice() {
            XCTAssertFalse(defaultDevice.name.isEmpty)
        }
    }
    
    func testErrorTypes() {
        // Test error creation and properties
        let error = AudioCaptureError.deviceNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.failureReason)
        XCTAssertNotNil(error.recoverySuggestion)
    }
    
    func testBufferQueue() async throws {
        // Test buffer queue functionality
        let queue = AudioBufferQueue(maxBuffers: 10)
        
        // Create a test buffer
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        
        // Test enqueue
        let enqueued = await queue.enqueue(buffer)
        XCTAssertTrue(enqueued, "Should successfully enqueue buffer")
        
        // Test statistics
        let stats = await queue.statistics
        XCTAssertEqual(stats.currentCount, 1)
        XCTAssertEqual(stats.totalEnqueued, 1)
    }
}