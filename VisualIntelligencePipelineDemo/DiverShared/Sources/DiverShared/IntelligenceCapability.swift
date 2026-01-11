import Foundation

public struct IntelligenceCapability {
    /// Returns true if the device supports Apple Intelligence features.
    /// This is a proxy for iOS 18.0+ and potentially device capabilities.
    public static var isAvailable: Bool {
        if #available(iOS 18.0, macOS 15.0, *) {
             // Example: We could add logic here to check for specific hardware or user settings.
             // For now, we assume newer OS versions support the "Intelligence" flow.
             return true
        }
        return false
    }
}
