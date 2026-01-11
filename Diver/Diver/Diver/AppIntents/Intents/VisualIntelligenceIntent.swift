//
//  VisualIntelligenceIntent.swift
//  Diver
//
//

import Foundation
import AppIntents
import SwiftUI
import DiverShared
import DiverKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import WidgetKit

/// Captures what's on screen using Visual Intelligence (OCR) and creates a Diver link
struct VisualIntelligenceIntent: AppIntent {
    static var title: LocalizedStringResource = "Intelligence Scan (Camera or Library)"
    static var description = IntentDescription("Scan the screen or pick from your Photos library to extract URLs, QR codes, and metadata.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Screenshot", description: "Screenshot or image to analyze")
    var screenshot: IntentFile

    @Parameter(title: "Include QR Codes", description: "Also scan for QR codes", default: true)
    var includeQRCodes: Bool

    @Parameter(title: "Auto-Share", description: "Automatically open Messages after creating link", default: false)
    var autoShare: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Scan \(\.$screenshot) for URLs") {
            \.$includeQRCodes
            \.$autoShare
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        // Load screenshot data
        guard let fileURL = screenshot.fileURL, let imageData = try? Data(contentsOf:fileURL) else {
            return .result(
                value: "",
                dialog: "Could not read the screenshot image"
            )
        }

        // Process screenshot to extract URLs with completeness analysis
        let processor = ScreenshotProcessor()
        var extractedURLs: [ScreenshotProcessor.ExtractedURL] = []

        // Extract URLs via OCR with analysis
        do {
            let ocrResults = try await processor.extractURLsWithAnalysis(from: imageData)
            extractedURLs.append(contentsOf: ocrResults)
        } catch {
            print("OCR extraction failed: \(error)")
        }

        // Extract QR codes if enabled (QR codes are usually complete)
        if includeQRCodes {
            do {
                let qrURLs = try await processor.extractQRCodes(from: imageData)
                // QR codes are considered complete
                for qrURL in qrURLs {
                    let completeness = URLCompletenessAnalyzer.CompletenessResult.complete(confidence: 1.0)
                    extractedURLs.append(ScreenshotProcessor.ExtractedURL(
                        url: qrURL,
                        completeness: completeness,
                        suggestedCompletions: []
                    ))
                }
            } catch {
                print("QR code extraction failed: \(error)")
            }
        }

        guard !extractedURLs.isEmpty else {
            return .result(
                value: "",
                dialog: "No URLs found in the screenshot.\n\n💡 Tip: Make sure the URL is fully visible on screen before taking the screenshot."
            )
        }

        // URLs are already sorted by completeness confidence (most complete first)
        let selectedExtraction = extractedURLs[0]
        let selectedURL = selectedExtraction.url

        // Check if URL appears truncated
        var warningMessage = ""
        if !selectedExtraction.isLikelyComplete {
            if let warning = selectedExtraction.warningMessage {
                warningMessage = "\n\n⚠️ Warning: \(warning)\n\nThe URL may be cut off. Try scrolling to show the full URL before capturing."
            }
        }

        // Get keychain secret
        let keychainService = KeychainService(
            service: KeychainService.ServiceIdentifier.diver,
            accessGroup: AppGroupConfig.default.keychainAccessGroup
        )

        guard let secretString = keychainService.retrieveString(key: KeychainService.Keys.diverLinkSecret),
              let secret = Data(base64Encoded: secretString) else {
            return .result(
                value: "",
                dialog: "DiverLink secret not found. Please set up the app first."
            )
        }

        // Wrap URL into Diver link
        let payload = DiverLinkPayload(url: selectedURL, title: nil)
        let wrappedURL = try DiverLinkWrapper.wrap(
            url: selectedURL,
            secret: secret,
            payload: payload,
            includePayload: true
        )

        let wrappedString = wrappedURL.absoluteString

        // Save to queue
        guard let queueDirectory = AppGroupContainer.queueDirectoryURL() else {
            return .result(
                value: wrappedString,
                dialog: "Created Diver link but could not save to library: \(wrappedString)"
            )
        }

        do {
            let queueStore = try DiverQueueStore(directoryURL: queueDirectory)
            let descriptor = DiverItemDescriptor(
                id: DiverLinkWrapper.id(for: selectedURL),
                url: selectedURL.absoluteString,
                title: selectedURL.host ?? selectedURL.absoluteString,
                categories: ["visual-intelligence", "screenshot"]
            )

            let queueItem = DiverQueueItem(
                action: "save",
                descriptor: descriptor,
                source: "visual-intelligence"
            )

            try queueStore.enqueue(queueItem)
            
            // Refresh widgets to show the new item
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Failed to enqueue: \(error)")
        }

        // Copy to clipboard
        #if canImport(UIKit)
        UIPasteboard.general.string = wrappedString
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(wrappedString, forType: .string)
        #endif

        // Build response message
        let baseMessage: String
        if extractedURLs.count > 1 {
            baseMessage = "Found \(extractedURLs.count) URLs. Created Diver link for: \(selectedURL.host ?? "link")\n\nLink copied to clipboard!"
        } else {
            baseMessage = "Created Diver link for: \(selectedURL.host ?? "link")\n\nLink copied to clipboard!"
        }

        let message = baseMessage + warningMessage

        return .result(
            value: wrappedString,
            dialog: IntentDialog(stringLiteral: message),
            view: VisualIntelligenceSnippet(
                url: selectedURL,
                foundCount: extractedURLs.count,
                isWarning: !selectedExtraction.isLikelyComplete
            )
        )
    }
}

/// Snippet view for VisualIntelligenceIntent shown in Siri/Shortcuts UI.
struct VisualIntelligenceSnippet: View {
    let url: URL
    let foundCount: Int
    let isWarning: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles.tv")
                    .foregroundColor(.cyan)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(foundCount > 1 ? "Diver Found \(foundCount) Links" : "Diver Scan Success")
                        .font(.headline)
                    
                    Text(url.host ?? url.absoluteString)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            
            if isWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("URL may be truncated from screenshot")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            HStack {
                Label("Copied to Clipboard", systemImage: "doc.on.clipboard.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.cyan.opacity(0.8))
                Spacer()
                Text("Saved to Library")
                    .font(.caption2.bold())
                    .foregroundStyle(.blue.opacity(0.8))
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    VisualIntelligenceSnippet(
        url: URL(string: "https://apple.com/iphone-17-pro")!,
        foundCount: 3,
        isWarning: true
    )
    .padding()
}
