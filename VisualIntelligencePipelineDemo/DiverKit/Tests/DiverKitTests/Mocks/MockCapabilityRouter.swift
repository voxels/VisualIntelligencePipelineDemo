//
//  MockCapabilityRouter.swift
//  DiverKit
//
//  Mock implementation or helper for CapabilityRouter.
//

import Foundation
@testable import DiverKit

/// This mock provides a controlled way to simulate hardware capabilities for testing.
/// Note: Since CapabilityRouter is a final class, this mock can be used directly if
/// CapabilityRouter is refactored behind a protocol, or it can be used to construct
/// artificial HardwareCapability instances for edge tests.
public final class MockCapabilityRouter {
    
    public let currentCapability: HardwareCapability
    
    public init(chipFamily: String, tops: Float, ram: UInt64) {
        self.currentCapability = HardwareCapability(
            chipFamily: chipFamily,
            neuralEngineTOPS: tops,
            physicalMemoryGB: ram
        )
    }
    
    public var canRunHeavyVLM: Bool {
        return currentCapability.physicalMemoryGB >= 16
    }
    
    public var canRunLightVLM: Bool {
        return currentCapability.physicalMemoryGB >= 8
    }
    
    public var canRunHeavyVision: Bool {
        return currentCapability.neuralEngineTOPS >= 30.0
    }
    
    // Quick helpers
    public static var genericM3Max: MockCapabilityRouter {
        return MockCapabilityRouter(chipFamily: "M3 Max", tops: 60.0, ram: 128)
    }
    
    public static var genericIphone15: MockCapabilityRouter {
        return MockCapabilityRouter(chipFamily: "A16", tops: 17.0, ram: 6)
    }
}
