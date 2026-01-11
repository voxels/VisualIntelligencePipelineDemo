//
//  ActionViewController.swift
//  ActionExtension
//
//  Refactored with Rich UI - 12/24/25
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import DiverShared
import DiverKit
import LinkPresentation

final class ActionViewController: UIViewController {

    private var queueStore: DiverQueueStore?
    private var keychainService: KeychainService?
    private var extractedURL: URL?

    /// Dependency injection initializer for testing
    init(queueStore: DiverQueueStore, keychainService: KeychainService? = nil) {
        self.queueStore = queueStore
        self.keychainService = keychainService
        super.init(nibName: nil, bundle: nil)
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setupQueueStore()
        setupKeychainService()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupQueueStore()
        setupKeychainService()
    }

    private func setupKeychainService() {
        self.keychainService = KeychainService(
            service: KeychainService.ServiceIdentifier.diver,
            accessGroup: AppGroupConfig.default.keychainAccessGroup
        )
    }

    private func setupQueueStore() {
        let groupIdentifier = "group.com.secretatomics.VisualIntelligence"
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)

        if containerURL == nil {
            print("❌ ERROR: Cannot access app group '\(groupIdentifier)'")
            return
        }

        do {
            if let queueDirectory = AppGroupContainer.queueDirectoryURL() {
                self.queueStore = try DiverQueueStore(directoryURL: queueDirectory)
                print("✅ Queue store initialized successfully")
            }
        } catch {
            print("❌ Error initializing queue store: \(error)")
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        resolveInputURL()
    }

    // MARK: - URL Extraction

    private func resolveInputURL() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("No input items were provided.")
            return
        }

        let providers = extensionItems
            .compactMap { $0.attachments }
            .flatMap { $0 }

        let urlTypeIdentifier = UTType.url.identifier
        let textTypeIdentifier = UTType.plainText.identifier

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlTypeIdentifier) }) {
            loadItem(from: provider, typeIdentifier: urlTypeIdentifier)
            return
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textTypeIdentifier) }) {
            loadItem(from: provider, typeIdentifier: textTypeIdentifier)
            return
        }

        showError("No URL was found in the share item.")
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.showError("Unable to load the shared item: \(error.localizedDescription)")
                }
                return
            }

            guard let url = self.extractURL(from: item) else {
                DispatchQueue.main.async {
                    self.showError("The shared content does not include a valid URL.")
                }
                return
            }

            guard Validation.isValidURL(url.absoluteString) else {
                DispatchQueue.main.async {
                    self.showError("The provided URL is not valid.")
                }
                return
            }

            DispatchQueue.main.async {
                self.extractedURL = url
                self.showLinkPreview(url: url)
            }
        }
    }

    private func extractURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let url = item as? NSURL {
            return url as URL
        }

        if let text = item as? String {
            return extractURL(from: text)
        }

        if let text = item as? NSString {
            return extractURL(from: text as String)
        }

        if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
            return extractURL(from: text)
        }

        return nil
    }

    private func extractURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let match = detector.firstMatch(in: trimmed, options: [], range: range),
               let url = match.url {
                return url
            }
        }

        if trimmed.contains(" ") == false {
            return URL(string: "https://\(trimmed)")
        }

        return nil
    }

    // MARK: - Rich UI Presentation

    private func showLinkPreview(url: URL) {
        // Start with placeholder
        let initialMetadata = LinkMetadata.placeholder(for: url)
        
        // Create view model
        let viewModel = MetadataViewModel(metadata: initialMetadata)

        // Generate smart tags
        let suggestedTags = SmartTagGenerator.generateTags(for: url)

        // Create SwiftUI view with view model
        let previewView = LinkPreviewView(
            url: url,
            viewModel: viewModel,
            suggestedTags: suggestedTags,
            onSave: { [weak self] tags in
                await self?.performSave(url: url, tags: tags)
            },
            onSaveAndShare: { [weak self] tags in
                await self?.performSaveAndShare(url: url, tags: tags)
            },
            onDismiss: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        )
        
        // Present SwiftUI view in UIHostingController
        let hostingController = UIHostingController(rootView: previewView)
        hostingController.modalPresentationStyle = .formSheet
        present(hostingController, animated: true)
        
        // Fetch rich metadata in background
        fetchRichMetadata(for: url) { [weak viewModel] richMetadata in
            DispatchQueue.main.async {
                viewModel?.metadata = richMetadata
            }
        }
    }
    
    // MARK: - Metadata Fetching
    
    private func fetchRichMetadata(for url: URL, completion: @escaping (LinkMetadata) -> Void) {
        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { metadata, error in
            if let metadata = metadata {
                // let _ = metadata.imageProvider // Silence unused warning if we ever wanted to check it
                
                let newMetadata = LinkMetadata(
                    url: url,
                    title: metadata.title,
                    description: metadata.value(forKey: "summary") as? String, // Private key fallback or just rely on title
                    imageURL: metadata.url // Temporary fallback
                )
                completion(newMetadata)
            } else {
                // Fallback or error, keep placeholder
                print("❌ Failed to fetch LPLinkMetadata: \(String(describing: error))")
            }
        }
    }

    // MARK: - Intent Execution

    @MainActor
    private func performSave(url: URL, tags: [String]) async {
        do {
            guard let queueStore = queueStore else {
                showError("Extension not properly initialized.")
                return
            }

            // Create descriptor with tags
            let descriptor = DiverItemDescriptor(
                id: DiverLinkWrapper.id(for: url),
                url: url.absoluteString,
                title: url.host ?? url.absoluteString,
                categories: tags
            )

            let queueItem = DiverQueueItem(
                action: "save",
                descriptor: descriptor,
                source: "action-extension"
            )

            try queueStore.enqueue(queueItem)

            showSuccess(message: "Saved to Diver ✅")
        } catch {
            showError("Failed to save: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func performSaveAndShare(url: URL, tags: [String]) async {
        do {
            guard let queueStore = queueStore else {
                showError("Extension not properly initialized.")
                return
            }

            guard let keychainService = keychainService else {
                showError("Keychain service not available.")
                return
            }

            guard let secretString = keychainService.retrieveString(key: KeychainService.Keys.diverLinkSecret),
                  let secret = Data(base64Encoded: secretString) else {
                showError("DiverLink secret not found in Keychain.")
                return
            }

            // Step 1: Save to queue
            let descriptor = DiverItemDescriptor(
                id: DiverLinkWrapper.id(for: url),
                url: url.absoluteString,
                title: url.host ?? url.absoluteString,
                categories: tags
            )

            let queueItem = DiverQueueItem(
                action: "save",
                descriptor: descriptor,
                source: "action-extension"
            )

            try queueStore.enqueue(queueItem)

            // Step 2: Wrap URL
            let payload = DiverLinkPayload(url: url, title: nil)
            let wrappedURL = try DiverLinkWrapper.wrap(
                url: url,
                secret: secret,
                payload: payload,
                includePayload: true
            )

            let wrappedString = wrappedURL.absoluteString

            // Step 3: Copy to clipboard
            UIPasteboard.general.string = wrappedString

            // Step 4: Open Messages
            openMessages(with: wrappedString)
        } catch {
            showError("Failed to save and share: \(error.localizedDescription)")
        }
    }

    // MARK: - Messages Integration

    private func openMessages(with link: String) {
        MessagesLaunchStore.save(body: link)
        let candidates = ["sms:", "sms://"].compactMap(URL.init(string:))
        attemptOpenMessages(with: candidates)
    }

    private func attemptOpenMessages(with candidates: [URL]) {
        guard let url = candidates.first else {
            showSuccess(message: "Link copied! Open Messages to share.")
            return
        }

        extensionContext?.open(url, completionHandler: { [weak self] success in
            guard let self = self else { return }
            if success {
                return
            }
            let remaining = Array(candidates.dropFirst())
            self.attemptOpenMessages(with: remaining)
        })
    }

    // MARK: - Simple Status Views (Fallback)

    private func showSuccess(message: String) {
        dismiss(animated: true) { [weak self] in
            self?.showSimpleAlert(title: "Success", message: message)
        }
    }

    private func showError(_ message: String) {
        dismiss(animated: true) { [weak self] in
            self?.showSimpleAlert(title: "Error", message: message)
        }
    }

    private func showSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
        present(alert, animated: true)
    }
}
