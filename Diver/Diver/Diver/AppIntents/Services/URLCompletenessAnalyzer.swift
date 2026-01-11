//
//  URLCompletenessAnalyzer.swift
//  Diver
//
//  Created by Claude on 12/24/25.
//

import Foundation

/// Analyzes URLs to detect if they appear truncated or incomplete
struct URLCompletenessAnalyzer {

    enum CompletenessResult {
        case complete(confidence: Double)
        case likelyTruncated(reason: TruncationReason, confidence: Double)
        case partialDomain(missingPart: String)

        var isComplete: Bool {
            if case .complete = self { return true }
            return false
        }

        var confidence: Double {
            switch self {
            case .complete(let conf): return conf
            case .likelyTruncated(_, let conf): return conf
            case .partialDomain: return 0.0
            }
        }
    }

    enum TruncationReason: String {
        case endsAbruptly = "URL ends abruptly mid-word"
        case suspiciousPath = "Path seems incomplete"
        case missingTLD = "Top-level domain missing"
        case endsWithSlash = "Ends with trailing slash (might be incomplete path)"
        case uncommonEnding = "Ends with unusual character"
    }

    /// Analyze if a URL appears complete or truncated
    static func analyze(url: URL) -> CompletenessResult {
        let urlString = url.absoluteString

        // Check 1: Domain completeness
        if let domainIssue = checkDomainCompleteness(url: url) {
            return domainIssue
        }

        // Check 2: Path completeness
        if let pathIssue = checkPathCompleteness(url: url) {
            return pathIssue
        }

        // Check 3: Ends abruptly mid-word
        if endsAbruptlyMidWord(urlString) {
            return .likelyTruncated(reason: .endsAbruptly, confidence: 0.85)
        }

        // Check 4: Ends with unusual character
        if let lastChar = urlString.last, isUnusualEnding(lastChar) {
            return .likelyTruncated(reason: .uncommonEnding, confidence: 0.60)
        }

        // Passed all checks - likely complete
        return .complete(confidence: calculateCompleteness(url: url))
    }

    // MARK: - Domain Checks

    private static func checkDomainCompleteness(url: URL) -> CompletenessResult? {
        guard let host = url.host else {
            return .partialDomain(missingPart: "entire domain")
        }

        // Check for valid TLD
        let components = host.split(separator: ".")
        guard components.count >= 2 else {
            return .partialDomain(missingPart: "top-level domain")
        }

        let tld = String(components.last!)

        // Common TLDs that should be complete
        // Common TLDs that should be complete
        // let commonTLDs = ["com", "org", "net", "edu", "gov", "io", "co", "ai", "dev"]

        // If TLD is too short or not in common list, might be truncated
        if tld.count == 1 {
            return .likelyTruncated(reason: .missingTLD, confidence: 0.95)
        }

        // Check if TLD looks truncated (ends mid-common-TLD)
        let possibleTruncations = [
            "co": ["com"],
            "or": ["org"],
            "ne": ["net"],
            "ed": ["edu"],
            "go": ["gov"]
        ]

        if possibleTruncations[tld] != nil {
            return .likelyTruncated(
                reason: .missingTLD,
                confidence: 0.70
            )
        }

        return nil
    }

    // MARK: - Path Checks

    private static func checkPathCompleteness(url: URL) -> CompletenessResult? {
        let path = url.path

        // Empty path is fine
        if path.isEmpty || path == "/" {
            return nil
        }

        // Trailing slash might indicate incomplete path
        if path.hasSuffix("/") && path.count > 1 {
            // But trailing slashes are common, so low confidence
            return .likelyTruncated(reason: .endsWithSlash, confidence: 0.40)
        }

        // Check if path seems to end mid-word
        let pathComponents = path.split(separator: "/")
        if let lastComponent = pathComponents.last {
            // Common incomplete endings in paths
            let suspiciousEndings = ["arti", "docu", "prod", "serv", "acco"]

            for ending in suspiciousEndings {
                if String(lastComponent).hasSuffix(ending) {
                    return .likelyTruncated(reason: .suspiciousPath, confidence: 0.75)
                }
            }
        }

        return nil
    }

    // MARK: - Character Analysis

    private static func endsAbruptlyMidWord(_ urlString: String) -> Bool {
        guard let lastChar = urlString.last else { return false }

        // If ends with alphanumeric but the substring before it suggests truncation
        if lastChar.isLetter || lastChar.isNumber {
            // Extract last segment (after last slash)
            if let lastSlashIndex = urlString.lastIndex(of: "/") {
                let lastSegment = String(urlString[urlString.index(after: lastSlashIndex)...])

                // Check if last segment looks truncated
                // e.g., ends with common prefixes: "artic", "documen", "catego"
                let truncatedPrefixes = [
                    "arti", "artic", "articl",  // article
                    "docu", "docum", "docume", "documen",  // document
                    "cate", "categ", "catego", "categor",  // category
                    "prod", "produ", "produc",  // product
                    "serv", "servi", "servic",  // service
                    "acco", "accou", "accoun",  // account
                    "profi", "profil"  // profile
                ]

                for prefix in truncatedPrefixes {
                    if lastSegment.lowercased().hasSuffix(prefix) {
                        return true
                    }
                }
            }
        }

        return false
    }

    private static func isUnusualEnding(_ char: Character) -> Bool {
        // Characters that rarely end a URL naturally
        let unusualEndings: Set<Character> = ["-", "_", "%", "&", "=", "?"]
        return unusualEndings.contains(char)
    }

    // MARK: - Confidence Calculation

    private static func calculateCompleteness(url: URL) -> Double {
        var confidence = 1.0

        // Reduce confidence if no query parameters (many URLs have them)
        if url.query == nil && url.path.count > 10 {
            confidence -= 0.1
        }

        // Increase confidence if has complete-looking structure
        if url.scheme != nil && url.host != nil {
            confidence = min(confidence + 0.1, 1.0)
        }

        // Check if URL matches common patterns
        if matchesCommonPattern(url: url) {
            confidence = min(confidence + 0.15, 1.0)
        }

        return max(0.0, min(1.0, confidence))
    }

    private static func matchesCommonPattern(url: URL) -> Bool {
        let urlString = url.absoluteString

        // Common complete URL patterns
        let completePatterns = [
            #"^https?://[\w\-\.]+\.(com|org|net|edu)/[\w\-/]+$"#,  // Clean path
            #"^https?://[\w\-\.]+\.(com|org|net|edu)/[\w\-/]+\.html?$"#,  // HTML file
            #"^https?://[\w\-\.]+\.(com|org|net|edu)/[\w\-/]+\?[\w=&\-]+$"#,  // With query
        ]

        for pattern in completePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - Suggested Completions

    /// Suggest possible completions for truncated URLs
    static func suggestCompletions(for url: URL, truncationReason: TruncationReason) -> [String] {
        var suggestions: [String] = []

        switch truncationReason {
        case .missingTLD:
            // Suggest completing the TLD
            if let host = url.host {
                let components = host.split(separator: ".")
                if let tld = components.last {
                    let tldString = String(tld)
                    // Common TLD completions
                    let completions: [String: [String]] = [
                        "co": ["com"],
                        "or": ["org"],
                        "ne": ["net"],
                        "ed": ["edu"]
                    ]

                    if let possibleCompletions = completions[tldString] {
                        for completion in possibleCompletions {
                            var newComponents = components.dropLast()
                            newComponents.append(Substring(completion))
                            let newHost = newComponents.joined(separator: ".")


                            if let completed = URL(string: url.absoluteString.replacingOccurrences(of: host, with: newHost)) {
                                suggestions.append(completed.absoluteString)
                            }
                        }
                    }
                }
            }

        case .endsAbruptly, .suspiciousPath:
            // Can't reliably suggest completions for truncated paths
            // User must scroll to show full URL
            break

        case .endsWithSlash:
            // Might be complete, no suggestions needed
            break

        case .uncommonEnding:
            // Remove trailing unusual character
            let cleaned = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "-_&=?%"))
            if cleaned != url.absoluteString {
                suggestions.append(cleaned)
            }
        }

        return suggestions
    }
}
