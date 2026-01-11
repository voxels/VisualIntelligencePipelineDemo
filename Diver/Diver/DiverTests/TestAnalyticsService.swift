import knowmaps

struct TestAnalyticsService: AnalyticsService, Sendable {
    func track(event: String, properties: [String: Any]?) {}
    func trackError(error: Error, additionalInfo: [String: Any]?) {}
    func trackCacheRefresh(cacheType: String, success: Bool, additionalInfo: [String: Any]?) {}
    func identify(userID: String) {}
}
