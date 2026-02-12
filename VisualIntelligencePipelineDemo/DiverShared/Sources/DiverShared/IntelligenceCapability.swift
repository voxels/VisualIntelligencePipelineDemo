import Foundation
#if os(iOS)
import UIKit
#endif
import Darwin

public struct IntelligenceCapability {
    /// Returns true if the device supports Apple Intelligence features.
    /// This is a proxy for iOS 18.0+ and potentially device capabilities.
    public static var isAvailable: Bool {
        // 1. OS Check (iOS 18+)
        guard #available(iOS 18.0, macOS 15.0, *) else { return false }
        
        // 2. Device Model Check (iPhone 16+ or M-series iPad/Mac)
        #if os(iOS)
        return isIPhone16OrNewer() || isIPadWithMSeries()
        #else
        return true // Mac (Apple Silicon) assumed for macOS 15+ usually, or we can check
        #endif
    }
    
    private static func isIPhone16OrNewer() -> Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // Handle Simulator
        if identifier == "i386" || identifier == "x86_64" || identifier == "arm64" {
            if let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                return checkModelID(simModel)
            }
            return false // Fallback for simulator if env var missing
        }
        
        return checkModelID(identifier)
    }
    
    private static func checkModelID(_ identifier: String) -> Bool {
        // iPhone 16 series is iPhone17,x
        // iPhone 15 Pro is iPhone16,1 / iPhone16,2 (Supported by Apple Intelligence but User restricted to 16+)
        
        if identifier.hasPrefix("iPhone") {
            let modelVersionString = identifier.dropFirst(6).split(separator: ",").first
            if let modelVersionString = modelVersionString, let majorVersion = Int(modelVersionString) {
                // iPhone 16 is "iPhone17,x" -> Major Version 17
                return majorVersion >= 17
            }
        }
        return false // Not an iPhone (or parsing failed)
    }
    
    private static func isIPadWithMSeries() -> Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
             guard let value = element.value as? Int8, value != 0 else { return identifier }
             return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.lowercased().contains("ipad")
    }
}
