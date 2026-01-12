import Foundation
import Vision
import CoreVideo

public enum IntelligenceResult {
    case qr(URL)
    case text(String, URL? = nil)
    case semantic(String, confidence: Float)
    case entertainment(title: String, type: EntertainmentType, assets: [URL] = [])
    case siftedSubject(VNInstanceMaskObservation, label: String?)
    case product(code: String, type: ProductCodeType, mediaAssets: [URL] = [])
    case document(VNRectangleObservation, text: String?, label: String?)
    case purpose(statements: [String])
    
    case richWeb(url: URL, data: EnrichmentData)
    
    public enum EntertainmentType {
        case movie, concert, book, podcast
    }
    
    public enum ProductCodeType: String {
        case upc, ean, unknown
    }

}

extension IntelligenceResult: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .qr(let url):
            hasher.combine(0)
            hasher.combine(url)
        case .text(let text, let url):
            hasher.combine(1)
            hasher.combine(text)
            hasher.combine(url)
        case .semantic(let label, let confidence):
            hasher.combine(2)
            hasher.combine(label)
            hasher.combine(confidence)
        case .entertainment(let title, let type, _):
            hasher.combine(3)
            hasher.combine(title)
            hasher.combine(type)
        case .siftedSubject(let obs, let label):
            hasher.combine(4)
            hasher.combine(obs)
            hasher.combine(label)
        case .product(let code, let type, _):
            hasher.combine(5)
            hasher.combine(code)
            hasher.combine(type)
        case .document(let obs, let text, let label):
            hasher.combine(6)
            hasher.combine(obs)
            hasher.combine(text)
            hasher.combine(label)
        case .purpose(let statements):
            hasher.combine(7)
            hasher.combine(statements)
        case .richWeb(let url, let data):
            hasher.combine(8)
            hasher.combine(url)
            hasher.combine(data.title)
        }
    }
    
    public static func == (lhs: IntelligenceResult, rhs: IntelligenceResult) -> Bool {
        switch (lhs, rhs) {
        case (.qr(let u1), .qr(let u2)): return u1 == u2
        case (.text(let t1, let u1), .text(let t2, let u2)): return t1 == t2 && u1 == u2
        case (.semantic(let l1, let c1), .semantic(let l2, let c2)): return l1 == l2 && c1 == c2
        case (.entertainment(let t1, let ty1, _), .entertainment(let t2, let ty2, _)): return t1 == t2 && ty1 == ty2
        case (.siftedSubject(let o1, let l1), .siftedSubject(let o2, let l2)): return o1 === o2 && l1 == l2
        case (.product(let c1, let t1, _), .product(let c2, let t2, _)): return c1 == c2 && t1 == t2
        case (.document(let o1, let t1, let l1), .document(let o2, let t2, let l2)): return o1 === o2 && t1 == t2 && l1 == l2
        case (.purpose(let s1), .purpose(let s2)): return s1 == s2
        case (.richWeb(let u1, let d1), .richWeb(let u2, let d2)): return u1 == u2 && d1.title == d2.title
        default: return false
        }
    }
}

// MARK: - Metadata Extensions
extension IntelligenceResult {
    public var title: String {
        switch self {
        case .qr: return "QR Code Found"
        case .richWeb(_, let data): return data.title ?? "Web Page"
        case .text(let text, _): return text.count > 30 ? String(text.prefix(30)) + "..." : text
        case .semantic(let label, _): return label.capitalized
        case .entertainment(let title, _, _): return title
        case .siftedSubject(_, let label): return label?.capitalized ?? "Subject Sifted"
        case .product: return "Product Detected"
        case .document(_, let text, let label): return text ?? label?.capitalized ?? "Document Scanned"
        case .purpose: return "Possible Intent"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .qr(let url): return url.absoluteString
        case .richWeb(_, let data): return data.descriptionText ?? data.title ?? "Tap to view"
        case .text(_, let url): return url?.absoluteString ?? "Scanned Text"
        case .semantic: return "Semantic Analysis"
        case .entertainment(_, let type, _):
            switch type {
            case .movie: return "Movie Poster"
            case .concert: return "Concert Flyer"
            case .book: return "Book Cover"
            case .podcast: return "Podcast Art"
            }
        case .siftedSubject(_, let label): return label != nil ? "Sifted Object" : "Ready to Peel"
        case .product(let code, let type, _): return "\(type.rawValue.uppercased()): \(code)"
        case .document(_, _, let label): return label?.capitalized ?? "Auto-segmented document"
        case .purpose(let statements): return statements.first ?? "Define your goal"
        }
    }
    
    public var icon: String {
        switch self {
        case .qr: return "qrcode"
        case .richWeb: return "safari"
        case .text: return "text.magnifyingglass"
        case .semantic: return "brain"
        case .entertainment(_, let type, _):
            switch type {
            case .movie: return "film"
            case .concert: return "music.mic"
            case .book: return "book"
            case .podcast: return "podcast.arrow.up.universal"
            }
        case .siftedSubject(_, let label):
            if let l = label?.lowercased() {
                if l.contains("dog") || l.contains("cat") { return "pawprint.fill" }
                if l.contains("coffee") || l.contains("mug") { return "cup.and.saucer.fill" }
                if l.contains("laptop") || l.contains("screen") { return "laptopcomputer" }
                if l.contains("plant") || l.contains("flower") { return "leaf.fill" }
            }
            return "hand.raised.fingers.spread"
        case .product: return "barcode.viewfinder"
        case .document: return "doc.text.viewfinder"
        case .purpose: return "sparkles.rectangle.stack"
        }
    }
    
    public var secondaryAction: (title: String, url: String)? {
        switch self {
        case .entertainment(let title, let type, _):
            let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            switch type {
            case .movie: return ("Watch Trailer", "https://www.youtube.com/results?search_query=\(query)+trailer")
            case .concert: return ("Book Tickets", "https://www.ticketmaster.com/search?q=\(query)")
            case .book: return ("Read Preview", "https://www.google.com/search?tbm=bks&q=\(query)")
            case .podcast: return ("Listen Now", "https://podcasts.apple.com/search?term=\(query)")
            }
        case .product(let code, _, _):
            return ("Compare Prices", "https://www.google.com/search?q=price+of+\(code)")
        default: return nil
        }
    }
    
    public var primaryURL: URL? {
        switch self {
        case .qr(let url): return url
        case .richWeb(let url, _): return url
        case .text(_, let url): return url
        case .product(let code, _, _):
            return URL(string: "https://www.google.com/search?q=\(code)")
        default: return nil
        }
    }
    
    public var assets: [URL] {
        switch self {
        case .entertainment(_, _, let assets): return assets
        case .product(_, _, let assets): return assets
        case .richWeb(_, let data):
            if let imageURLString = data.image, let url = URL(string: imageURLString) {
                return [url]
            }
            return []
        default: return []
        }
    }
    
    public var sortPriority: Int {
        switch self {
        case .product, .entertainment: return 0
        case .qr: return 1
        case .richWeb: return 1 // Same priority as QR/Web
        case .text(_, let url): return url != nil ? 1 : 3
        case .document: return 2
        case .purpose: return 7 // Questions appear last
        case .semantic: return 4
        case .siftedSubject: return 5
        }
    }
}

/// Agent [VISION/AI] - Responsible for OCR, QR, Semantic, Subject, and Product Analysis
public final class IntelligenceProcessor: Sendable {
    public init() {}
    
    public enum AnalysisMode: Sendable {
        case liveSifting
        case fullAnalysis
    }
    
    public func process(frame: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up, mode: AnalysisMode = .liveSifting) async throws -> [IntelligenceResult] {
        return try await performRequests(cvPixelBuffer: frame, orientation: orientation, mode: mode)
    }
    
    public func process(image: CGImage, orientation: CGImagePropertyOrientation = .up, mode: AnalysisMode = .liveSifting) async throws -> [IntelligenceResult] {
        return try await performRequests(cgImage: image, orientation: orientation, mode: mode)
    }
    
    private func performRequests(cvPixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, mode: AnalysisMode) async throws -> [IntelligenceResult] {
        return try await executePipeline(mode: mode) {
            VNImageRequestHandler(cvPixelBuffer: cvPixelBuffer, orientation: orientation, options: [:])
        }
    }
    
    private func performRequests(cgImage: CGImage, orientation: CGImagePropertyOrientation, mode: AnalysisMode) async throws -> [IntelligenceResult] {
        return try await executePipeline(mode: mode) {
            VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        }
    }
    
    private func executePipeline(mode: AnalysisMode, handlerFactory: () -> VNImageRequestHandler) async throws -> [IntelligenceResult] {
         print("🧠 IntelligenceProcessor: Starting Pipeline (Mode: \(mode))")
         var finalResults: [IntelligenceResult] = []
         
         // 1. Sifting (First Pass)
         // We always run sifting if included in mode or if implicit in Full Analysis
         let siftingRequest = VNGenerateForegroundInstanceMaskRequest()
         
         // Run Sift Pass
         let siftHandler = handlerFactory()
         try siftHandler.perform([siftingRequest])
         
         var subjectBounds: CGRect?
         if let observation = siftingRequest.results?.first {
             finalResults.append(.siftedSubject(observation, label: nil))
             if mode == .fullAnalysis {
                 subjectBounds = calculateBounds(from: observation)
             }
         }
         
         // 2. Return early if Live Mode
         if mode == .liveSifting {
             return finalResults
         }
         
         // 3. Full Analysis Configuration (Second Pass)
         print("🧠 IntelligenceProcessor: Starting Full Analysis Pass")
         
         let barcodeRequest = VNDetectBarcodesRequest()
         barcodeRequest.symbologies = [.qr, .upce, .ean13, .ean8, .code128]
         
         let textRequest = VNRecognizeTextRequest()
         textRequest.recognitionLevel = .accurate
         
         let classificationRequest = VNClassifyImageRequest()
         let documentRequest = VNDetectDocumentSegmentationRequest()
         
         // Apply ROI if Subject Found
         if let roi = subjectBounds {
             if roi.width > 0.05 && roi.height > 0.05 {
                 print("🎯 Focusing Intelligence on Subject ROI: \(roi)")
                 // Expand slightly to ensure we capture edges
                 let paddedRoi = roi.insetBy(dx: -0.05, dy: -0.05).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                 
                 // barcodeRequest.regionOfInterest = paddedRoi // Fix: Allow barcode scanning on full frame
                 textRequest.regionOfInterest = paddedRoi
                 classificationRequest.regionOfInterest = paddedRoi // Focus classification on subject
                 documentRequest.regionOfInterest = paddedRoi
             }
         } else {
             print("🌍 No Subject Sifted - Analyzing Full Scene")
         }
         
         // 4. Run Metadata Requests on FRESH Handler
         let metadataHandler = handlerFactory()
         try metadataHandler.perform([barcodeRequest, textRequest, classificationRequest, documentRequest])
         
         // 5. Process Metadata Results
        if let observations = barcodeRequest.results {
             // 1. Handle QR Codes: Respect Layout Direction
             let qrObservations = observations.filter { $0.symbology == .qr }
             
             // Determine Layout Direction
             let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
             let direction = Locale.characterDirection(forLanguage: languageCode)
             let isRTL = direction == .rightToLeft
             
             let sortedQRs: [VNBarcodeObservation]
             if isRTL {
                 // RTL: Start from Right -> Pick largest X
                 sortedQRs = qrObservations.sorted { $0.boundingBox.origin.x > $1.boundingBox.origin.x }
             } else {
                 // LTR: Start from Left -> Pick smallest X
                 sortedQRs = qrObservations.sorted { $0.boundingBox.origin.x < $1.boundingBox.origin.x }
             }
             
             for qr in sortedQRs {
                 if let payload = qr.payloadStringValue, let url = URL(string: payload) {
                     finalResults.append(.qr(url))
                 }
             }
             
             // 2. Handle Product Codes
             for observation in observations where observation.symbology != .qr {
                 let type: IntelligenceResult.ProductCodeType = {
                     switch observation.symbology {
                     case .upce, .code128: return .upc
                     case .ean13, .ean8: return .ean
                     default: return .unknown
                     }
                 }()
                 
                 let code = observation.payloadStringValue ?? ""
                 let assets: [URL] = [] // Removed mock Picsum assets
                 
                 finalResults.append(.product(code: code, type: type, mediaAssets: assets))
             }
         }
          // Collect all OCR text
          var ocrTextLines: [String] = []
          if let observations = textRequest.results {
              for observation in observations {
                  if let topCandidate = observation.topCandidates(1).first {
                      ocrTextLines.append(topCandidate.string)
                  }
              }
          }
          
          // Document results handled above with text aggregation
          // MOVED SEMANTIC ANALYSIS to before document creation to provide labels
          
         var semanticLabels: [String] = []
         if let observations = classificationRequest.results {
             let topObservations = observations.prefix(5).filter { $0.confidence > 0.4 }
             semanticLabels = topObservations.map { $0.identifier.lowercased() }
             
             for observation in topObservations where observation.confidence > 0.7 {
                 finalResults.append(.semantic(observation.identifier, confidence: observation.confidence))
              }
              
              // Backfill the Sifted Subject Label
              if let bestLabel = topObservations.first?.identifier,
                 let index = finalResults.firstIndex(where: { if case .siftedSubject = $0 { return true } else { return false } }),
                 case .siftedSubject(let obs, _) = finalResults[index] {
                  // Replace with labeled version
                  finalResults[index] = .siftedSubject(obs, label: bestLabel)
                  print("🏷️ Assigned Label '\(bestLabel)' to Sifted Subject")
              }
          }
          
          if let results = documentRequest.results, !results.isEmpty {
               // Aggregation: Add document results WITH text label AND semantic label
               let bestLabel = ocrTextLines.sorted { $0.count > $1.count }.first
               // Pick most relevant semantic label for document (e.g. menu, receipt) - naïve approach: first one
               let docType = semanticLabels.first
               
               for observation in results {
                   finalResults.append(.document(observation, text: bestLabel, label: docType))
               }
          } else {
              // No document detected, check for loose text
              for line in ocrTextLines {
                  let url = extractURL(from: line)
                  // Only show loose text if it's a URL or we have nothing else
                  if url != nil || (line.count > 5 && finalResults.isEmpty) {
                      finalResults.append(.text(line, url))
                  }
              }
          }
          
          // Document results handled above with text aggregation
          
         if !ocrTextLines.isEmpty {
            let labels = semanticLabels.joined(separator: " ")
            let isEntertainment = labels.contains("movie") || labels.contains("poster") || labels.contains("book") || labels.contains("concert") || labels.contains("entertainment")
            
            if isEntertainment {
                let sortedLines = ocrTextLines.sorted { $0.count > $1.count }
                if let title = sortedLines.first, title.count > 3 {
                     let type: IntelligenceResult.EntertainmentType = {
                        if labels.contains("movie") { return .movie }
                        if labels.contains("concert") || labels.contains("music") { return .concert }
                        if labels.contains("book") { return .book }
                        return .movie
                     }()
                     
                     // Removed mock assets
                     let mockAssets: [URL] = []
                     
                     finalResults.insert(.entertainment(title: title, type: type, assets: mockAssets), at: 0)
                }
            }
        }
         
         print("✅ IntelligenceProcessor: Finished with \(finalResults.count) results")
         return finalResults
    }
    
    // Internal Helper for ROI calculation
    public func calculateBounds(from observation: VNInstanceMaskObservation) -> CGRect {
        let maskBuffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else { return .zero }
        
        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var found = false
        
        // Fast scan
        for y in 0..<height {
            let row = buffer + (y * bytesPerRow)
            for x in 0..<width {
                if row[x] != 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    found = true
                }
            }
        }
        
        if !found { return .zero }
        
        let normalizedMinX = CGFloat(minX) / CGFloat(width)
        let normalizedMaxX = CGFloat(maxX) / CGFloat(width)
        // Vision Origin is Bottom-Left, Buffer is Top-Left. 
        // VNRecognizeTextRequest Y is Bottom-Left.
        // We need Standard Normalized Coordinates (0,0 is Bottom Left).
        // Buffer Y=0 is Top.
        // NormalizedY = 1 - (y / height).
        // MaxY in buffer (bottom of object) -> MinY in Vision.
        // MinY in buffer (top of object) -> MaxY in Vision.
        
        let normalizedMinY = 1.0 - (CGFloat(maxY) / CGFloat(height)) // Bottom of object
        let normalizedMaxY = 1.0 - (CGFloat(minY) / CGFloat(height)) // Top of object
        
        return CGRect(
            x: normalizedMinX,
            y: normalizedMinY,
            width: normalizedMaxX - normalizedMinX,
            height: normalizedMaxY - normalizedMinY
        )
    }
    
    private func extractURL(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.url
    }
    public func verify(initialResults: [IntelligenceResult], image: CGImage) -> AsyncStream<IntelligenceResult> {
        return AsyncStream { continuation in
            Task {
                print("🧠 IntelligenceProcessor: Starting Verification Round")
                
                // 1. Verify Semantics - Check for alternatives
                let semanticResults = initialResults.compactMap { res -> (String, Float)? in
                    if case .semantic(let label, let conf) = res { return (label, conf) }
                    return nil
                }
                
                if !semanticResults.isEmpty {
                    // Simulate checking "Next Best" options or related concepts
                    // In a real implementation, we might run a secondary classifier or query knowledge graph
                    try? await Task.sleep(nanoseconds: 500_000_000) // Simulate work
                    
                    for (label, _) in semanticResults {
                        // Mock: Add specific alternatives for demo purposes
                        if label.contains("coffee") {
                            continuation.yield(.semantic("espresso", confidence: 0.6))
                            continuation.yield(.semantic("latte art", confidence: 0.55))
                        }
                        if label.contains("computer") || label.contains("laptop") {
                            continuation.yield(.purpose(statements: ["Coding Session", "Remote Work"]))
                        }
                    }
                }
                
                // 2. Text Deep Dive
                let textResults = initialResults.compactMap { res -> String? in
                    if case .text(let text, _) = res { return text }
                    return nil
                }
                
                for text in textResults {
                    // Detect potential dates or emails (simple regex mock)
                    if text.contains("@") {
                         continuation.yield(.semantic("contact info", confidence: 0.8))
                    }
                }
                
                print("✅ IntelligenceProcessor: Verification Complete")
                continuation.finish()
            }
        }
    }
}

