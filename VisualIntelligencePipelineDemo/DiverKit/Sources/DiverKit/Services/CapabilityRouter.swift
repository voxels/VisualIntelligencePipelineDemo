//
//  CapabilityRouter.swift
//  DiverKit
//
//  Abstracts hardware capabilities (RAM, Neural Engine TOPS) to determine
//  whether ML inference tasks should execute locally or be offloaded to an edge node.
//

import Foundation
#if os(macOS)
import Darwin
#endif

/// Defines the underlying hardware capabilities of the current device.
public struct HardwareCapability: Sendable {
    public let chipFamily: String
    public let neuralEngineTOPS: Float
    public let physicalMemoryGB: UInt64
    
    public init(chipFamily: String, neuralEngineTOPS: Float, physicalMemoryGB: UInt64) {
        self.chipFamily = chipFamily
        self.neuralEngineTOPS = neuralEngineTOPS
        self.physicalMemoryGB = physicalMemoryGB
    }
}

/// Router to determine local vs remote ML capabilities.
public final class CapabilityRouter: Sendable {
    
    public static let shared = CapabilityRouter()
    
    /// The physical capabilities of the current device.
    public let currentCapability: HardwareCapability
    
    public init() {
        self.currentCapability = Self.detectHardware()
    }
    
    // MARK: - Local ML Capabilities
    
    /// Minimum recommended RAM to run large FastVLM (7B+) models locally in MLX Swift.
    /// Requires 16GB+ RAM — M4 Pro Mac, M4 iPad Pro (16GB config), etc.
    public var canRunHeavyVLM: Bool {
        return currentCapability.physicalMemoryGB >= 16
    }
    
    /// M-series device with enough RAM for the 1.5B model (the sweet spot for M2/M3 iPads).
    /// 7GB+ RAM on M-series silicon — excludes A-series iPhones.
    public var canRunMediumVLM: Bool {
        let chip = currentCapability.chipFamily
        let isMSeries = chip.hasPrefix("M")
        return isMSeries && currentCapability.physicalMemoryGB >= 7
    }
    
    /// Minimum recommended RAM to run the FastVLM 0.5B or CLaRa 7B model.
    /// Any device with 7GB+ RAM (including M2 MacBook Air, A18 iPhones).
    public var canRunLightVLM: Bool {
        return currentCapability.physicalMemoryGB >= 7
    }
    
    /// Minimum recommended Neural Engine TOPS to run heavy CoreML workloads like SAM 2.1 comfortably.
    public var canRunHeavyVision: Bool {
        return currentCapability.neuralEngineTOPS >= 30.0
    }
    
    // MARK: - Hardware Detection
    
    private static func detectHardware() -> HardwareCapability {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = physicalMemory / (1024 * 1024 * 1024)
        
        let chip = chipFamily()
        let tops = neuralEngineTOPS(for: chip)
        
        return HardwareCapability(
            chipFamily: chip,
            neuralEngineTOPS: tops,
            physicalMemoryGB: memoryGB
        )
    }
    
    private static func chipFamily() -> String {
        // Retrieve hardware machine string like "Mac14,5" or "iPhone16,1"
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)
        
        #if os(macOS)
        // On macOS, we can get a friendlier brand string
        var brandSize: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &brandSize, nil, 0)
        var brand = [CChar](repeating: 0, count: brandSize)
        sysctlbyname("machdep.cpu.brand_string", &brand, &brandSize, nil, 0)
        let brandString = String(cString: brand)
        
        if brandString.contains("M5") { return "M5" }
        if brandString.contains("M4") { return "M4" }
        if brandString.contains("M3") { return "M3" }
        if brandString.contains("M2") { return "M2" }
        if brandString.contains("M1") { return "M1" }
        return "Apple Silicon"
        #else
        if identifier.hasPrefix("iPhone") {
            let modelVersionString = identifier.dropFirst(6).split(separator: ",").first
            if let versionString = modelVersionString, let major = Int(versionString) {
                if major >= 17 { return "A18" }
                if major == 16 { return "A17" }
                if major == 15 { return "A16" }
                if major == 14 { return "A15" }
                return "A-Series"
            }
        } else if identifier.hasPrefix("iPad") {
            // M-series iPads started around iPad13,x/14,x
            let modelVersionString = identifier.dropFirst(4).split(separator: ",").first
            if let versionString = modelVersionString, let major = Int(versionString) {
                if major >= 18 { return "M5" }
                if major >= 16 { return "M4" }  // Approximation
                if major >= 14 { return "M2" }
                if major >= 13 { return "M1" }
                return "A-Series iPad"
            }
        }
        return "Apple Silicon"
        #endif
    }
    
    private static func neuralEngineTOPS(for chip: String) -> Float {
        switch chip {
        case "M5": return 45.0 // Est.
        case "M4": return 38.0
        case "A18", "A18 Pro", "A17", "A17 Pro", "A18e": return 35.0
        case "M3": return 18.0
        case "A16": return 17.0
        case "M2", "A15": return 15.8
        case "M1", "A14": return 11.0
        default: return 11.0
        }
    }
}
