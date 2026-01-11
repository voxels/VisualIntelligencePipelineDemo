import AppIntents

struct OpenLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Link"
    
    // Set to false because OpenURLIntent handles the app transition
    static var openAppWhenRun = false

    @Parameter(title: "Link")
    var link: LinkEntity

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = link.url else {
            // If the URL is missing, we throw an error to provide feedback to the user
            throw OpenLinkError.invalidURL
        }

        // The system handles opening this URL in the default browser/app
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// Custom error to handle the missing URL case cleanly
enum OpenLinkError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case invalidURL
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidURL: return "This link does not have a valid URL."
        }
    }
}
