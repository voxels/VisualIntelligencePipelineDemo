import SwiftUI
import AppIntents

/// Agent [CORE] - Action Button Intent to launch Visual Intelligence Mode
public struct OpenVisualIntelligenceIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open Visual Intelligence"
    public static var openAppWhenRun: Bool = true
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult {
        // Broadcast deep link or set global state to activate Camera
        NotificationCenter.default.post(name: .openVisualIntelligence, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let openVisualIntelligence = Notification.Name("openVisualIntelligence")
}
