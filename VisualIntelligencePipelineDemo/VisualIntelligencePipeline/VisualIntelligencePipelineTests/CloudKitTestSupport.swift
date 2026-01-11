import Security

func hasCloudKitEntitlement() -> Bool {
    #if os(macOS)
    guard let task = SecTaskCreateFromSelf(nil) else {
        return false
    }
    guard let rawValue = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.icloud-services" as CFString,
        nil
    ) else {
        return false
    }
    let services = rawValue as? [String] ?? []
    return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
    #else
    return true
    #endif
}
