//
//  ScreenshotProcessor.swift
//  VisualIntelligencePipeline
//
//  Created by Claude on 12/24/25.
//

import Foundation
import Vision
import CoreImage
import UniformTypeIdentifiers
import DiverShared
import DiverKit

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// Service that processes screenshots using Vision framework to extract URLs
actor ScreenshotProcessor {

    enum ProcessingError: LocalizedError {
        case invalidImage
        case noURLsFound
        case visionProcessingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "The provided image could not be processed"
            case .noURLsFound:
                return "No URLs were found in the screenshot"
            case .visionProcessingFailed(let error):
                return "Vision processing failed: \(error.localizedDescription)"
            }
        }
    }

    struct ExtractedURL {
        let url: URL
        let completeness: URLCompletenessAnalyzer.CompletenessResult
        let suggestedCompletions: [String]

        var isLikelyComplete: Bool {
            completeness.isComplete || completeness.confidence > 0.75
        }

        var warningMessage: String? {
            if case .likelyTruncated(let reason, let confidence) = completeness {
                return "\(reason.rawValue) (confidence: \(Int(confidence * 100))%)"
            }
            if case .partialDomain(let missing) = completeness {
                return "Missing \(missing)"
            }
            return nil
        }
    }

    /// Process a screenshot and extract all URLs found via OCR with completeness analysis
    func extractURLsWithAnalysis(from imageData: Data) async throws -> [ExtractedURL] {
        // Convert data to CGImage
        guard let cgImage = createCGImage(from: imageData) else {
            throw ProcessingError.invalidImage
        }

        // Perform OCR using Vision
        let recognizedText = try await performOCR(on: cgImage)

        // Extract URLs from recognized text
        let urls = extractURLs(from: recognizedText)

        guard !urls.isEmpty else {
            throw ProcessingError.noURLsFound
        }

        // Analyze each URL for completeness
        var extractedURLs: [ExtractedURL] = []

        for url in urls {
            let completeness = URLCompletenessAnalyzer.analyze(url: url)

            var suggestions: [String] = []
            if case .likelyTruncated(let reason, _) = completeness {
                suggestions = URLCompletenessAnalyzer.suggestCompletions(
                    for: url,
                    truncationReason: reason
                )
            }

            extractedURLs.append(ExtractedURL(
                url: url,
                completeness: completeness,
                suggestedCompletions: suggestions
            ))
        }

        // Sort by completeness confidence (most complete first)
        extractedURLs.sort { $0.completeness.confidence > $1.completeness.confidence }

        return extractedURLs
    }

    /// Process a screenshot and extract all URLs found via OCR (simple version)
    func extractURLs(from imageData: Data) async throws -> [URL] {
        let extractedURLs = try await extractURLsWithAnalysis(from: imageData)
        return extractedURLs.map { $0.url }
    }

    // MARK: - Image Conversion

    private func createCGImage(from data: Data) -> CGImage? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return uiImage.cgImage
        #else
        guard let nsImage = NSImage(data: data) else { return nil }
        var rect = CGRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    // MARK: - Vision OCR

    private func performOCR(on cgImage: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        // Enable automatic language detection
        if #available(iOS 16.0, macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw ProcessingError.visionProcessingFailed(error as! Error)
        }

        guard let observations = request.results else {
            return ""
        }

        // Combine all recognized text
        let recognizedStrings = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }

        return recognizedStrings.joined(separator: " ")
    }

    // MARK: - URL Extraction

    private func extractURLs(from text: String) -> [URL] {
        var urls: [URL] = []

        // Use NSDataDetector to find URLs
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        for match in matches {
            if let url = match.url {
                urls.append(url)
            }
        }

        // Also try to find URLs that might have been broken by OCR (spaces, line breaks)
        urls.append(contentsOf: extractBrokenURLs(from: text))

        // Deduplicate
        return Array(Set(urls))
    }

    /// Extract URLs that may have been split across lines or have spaces
    private func extractBrokenURLs(from text: String) -> [URL] {
        var urls: [URL] = []

        // Common URL patterns that might be split
        let patterns = [
            // http://example.com or https://example.com
            #"https?://\s*[\w\-\.]+\s*\.\s*[a-zA-Z]{2,}(?:\s*/\s*[\w\-\./?%&=]*)?"#,
            // www.example.com
            #"www\s*\.\s*[\w\-\.]+\s*\.\s*[a-zA-Z]{2,}(?:\s*/\s*[\w\-\./?%&=]*)?"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

            for match in matches {
                if let range = Range(match.range, in: text) {
                    var urlString = String(text[range])

                    // Remove whitespace
                    urlString = urlString.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

                    // Add https:// if missing
                    if urlString.starts(with: "www.") {
                        urlString = "https://" + urlString
                    }

                    if let url = URL(string: urlString), Validation.isValidURL(urlString) {
                        urls.append(url)
                    }
                }
            }
        }

        return urls
    }

    // MARK: - QR Code Detection (Bonus)

    /// Detect QR codes in screenshot (useful for capturing QR codes on screen)
    func extractQRCodes(from imageData: Data) async throws -> [URL] {
        guard let cgImage = createCGImage(from: imageData) else {
            throw ProcessingError.invalidImage
        }

        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw ProcessingError.visionProcessingFailed(error as! Error)
        }

        guard let observations = request.results else {
            return []
        }

        var urls: [URL] = []

        for observation in observations {
            if let payload = observation.payloadStringValue,
               let url = URL(string: payload),
               Validation.isValidURL(payload) {
                urls.append(url)
            }
        }

        return urls
    }
}
