import Foundation
import AppIntents
import DiverKit
import DiverShared
import SwiftUI

/// Share a wrapped Diver link from the current page (share sheet context).
/// This intent wraps the URL, saves it to the library, and returns the wrapped link
/// for sharing via Shortcuts actions.
struct ShareLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Share Diver Link"
    static var description = IntentDescription("Wrap and share the current page as a Diver link.")

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Title", default: nil)
    var title: String?

    internal static var _testQueueStore: DiverQueueStore?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        // Validate URL
        guard Validation.isValidURL(url.absoluteString) else {
            return .result(
                value: "",
                dialog: "The provided URL is not valid."
            )
        }

        // Retrieve Diver link secret from keychain
        guard
            let keychainService = KeychainService(
                service: KeychainService.ServiceIdentifier.diver,
                accessGroup: AppGroupConfig.default.keychainAccessGroup
            ) as KeychainService?,
            let secretString = keychainService.retrieveString(key: KeychainService.Keys.diverLinkSecret),
            let secret = Data(base64Encoded: secretString)
        else {
            return .result(
                value: "",
                dialog: "Unable to access Diver keychain secret."
            )
        }

        // Wrap the URL
        let payload = DiverLinkPayload(url: url, title: title)
        guard let wrappedURL = try? DiverLinkWrapper.wrap(
            url: url,
            secret: secret,
            payload: payload,
            includePayload: true
        ) else {
            return .result(
                value: "",
                dialog: "Failed to create wrapped link."
            )
        }

        let wrappedString = wrappedURL.absoluteString

        // Save to library (queue for processing)
        // Note: wrappedLink is stored separately, not in the descriptor
        do {
            let descriptor = DiverItemDescriptor(
                id: DiverLinkWrapper.id(for: url),
                url: url.absoluteString,
                title: title ?? url.absoluteString,
                wrappedLink: wrappedString
            )

            let queueStore: DiverQueueStore
            if let testStore = Self._testQueueStore {
                queueStore = testStore
            } else {
                queueStore = try DiverQueueStore(directoryURL: AppGroupContainer.queueDirectoryURL()!)
            }
            let queueItem = DiverQueueItem(
                action: "save",
                descriptor: descriptor,
                source: url.host() ?? "AppIntent"
            )
            try queueStore.enqueue(queueItem)

            return .result(
                value: wrappedString,
                dialog: "Created Diver link for \"\(title ?? url.host ?? "link")\" and saved to library.",
                view: ShareLinkSnippet(
                    host: title ?? url.host ?? "Link",
                    wrappedLink: wrappedString
                )
            )
        } catch {
            // Still return the wrapped link even if queueing fails
            return .result(
                value: wrappedString,
                dialog: "Created Diver link for \"\(title ?? url.host ?? "link")\" but failed to save: \(error.localizedDescription)",
                view: ShareLinkSnippet(
                    host: title ?? url.host ?? "Link",
                    wrappedLink: wrappedString
                )
            )
        }
    }
}

extension ShareLinkIntent {
    var snippetView: some View {
        ShareLinkSnippet(
            host: title ?? url.host ?? "Link",
            wrappedLink: ""
        )
    }
}
