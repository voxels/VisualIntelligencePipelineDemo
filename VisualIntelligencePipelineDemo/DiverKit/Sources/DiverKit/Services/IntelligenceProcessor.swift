import Foundation
import Vision
import CoreVideo
import CoreImage
import CoreImage.CIFilterBuiltins
import VideoToolbox

public enum IntelligenceResult {
    case qr(URL)
    case text(String, URL? = nil)
    case semantic(String, confidence: Float)
    case entertainment(title: String, type: EntertainmentType, assets: [URL] = [])
    case siftedSubject(VNInstanceMaskObservation, label: String?)
    case product(code: String, type: ProductCodeType, mediaAssets: [URL] = [])
    case document(VNRectangleObservation, text: String?, label: String?, rectifiedImage: Data? = nil)
    case purpose(statements: [String])
    case aesthetics(score: Float)
    case saliency(SaliencyResult)
    
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
        case .document(let obs, let text, let label, let rectifiedImage):
            hasher.combine(6)
            hasher.combine(obs)
            hasher.combine(text)
            hasher.combine(label)
            hasher.combine(rectifiedImage)
        case .purpose(let statements):
            hasher.combine(7)
            hasher.combine(statements)
        case .aesthetics(let score):
            hasher.combine(8)
            hasher.combine(score)
        case .saliency(let result):
            hasher.combine(10)
            hasher.combine(result.width)
            hasher.combine(result.height)
        case .richWeb(let url, let data):
            hasher.combine(9)
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
        case (.document(let o1, let t1, let l1, let r1), .document(let o2, let t2, let l2, let r2)): return o1 === o2 && t1 == t2 && l1 == l2 && r1 == r2
        case (.purpose(let s1), .purpose(let s2)): return s1 == s2
        case (.aesthetics(let s1), .aesthetics(let s2)): return s1 == s2
        case (.saliency(let r1), .saliency(let r2)): return r1.width == r2.width && r1.height == r2.height
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
        case .product: return "Product" // Simplification
        case .document(_, let text, let label, _): 
            let prefix = "Doc: "
            if let text = text {
                return prefix + (text.count > 25 ? String(text.prefix(25)) + "..." : text)
            }
            return prefix + (label?.capitalized ?? "Scanned")
        case .purpose(let statements): return statements.first ?? "Purpose"
        case .aesthetics: return "Quality Score"
        case .saliency: return "Saliency Map"
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
        case .document(_, _, let label, _): return label?.capitalized ?? "Auto-segmented document"
        case .purpose(let statements): 
            if statements.count > 1 {
                return "+\(statements.count - 1) more"
            }
            return "Suggested Purpose"
        case .aesthetics(let score): return String(format: "%.0f%%", score * 100)
        case .saliency(let result): return "\(result.salientRegions.count) region(s)"
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
        case .document: return "doc.text.below.ecg.fill" // More distinct document icon
        case .purpose: return "sparkles.rectangle.stack"
        case .aesthetics: return "sparkle.magnifyingglass"
        case .saliency: return "eye.trianglebadge.exclamationmark"
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
        case .aesthetics: return 6
        case .saliency: return 6  // Same priority as aesthetics
        }
    }
}

/// Agent [VISION/AI] - Responsible for OCR, QR, Semantic, Subject, and Product Analysis
public final class IntelligenceProcessor: IntelligenceProcessing, Sendable {
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
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(cvPixelBuffer, options: nil, imageOut: &cgImage)
        
        return try await executePipeline(mode: mode, sourceImage: cgImage, orientation: orientation) {
            VNImageRequestHandler(cvPixelBuffer: cvPixelBuffer, orientation: orientation, options: [:])
        }
    }
    
    private func performRequests(cgImage: CGImage, orientation: CGImagePropertyOrientation, mode: AnalysisMode) async throws -> [IntelligenceResult] {
        return try await executePipeline(mode: mode, sourceImage: cgImage, orientation: orientation) {
            VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        }
    }
    
    private func executePipeline(mode: AnalysisMode, sourceImage: CGImage? = nil, orientation: CGImagePropertyOrientation = .up, handlerFactory: () -> VNImageRequestHandler) async throws -> [IntelligenceResult] {
         if mode != .liveSifting {
            print("🧠 IntelligenceProcessor: Starting Pipeline (Mode: \(mode))")
         }
         var finalResults: [IntelligenceResult] = []
         
         // Build the request list based on mode
         let siftingRequest = VNGenerateForegroundInstanceMaskRequest()
         let barcodeRequest = VNDetectBarcodesRequest()
         let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
         
         var allRequests: [VNRequest] = [siftingRequest, barcodeRequest, aestheticsRequest]
         
         // For full analysis, add all requests upfront so they run in ONE parallel perform() call.
         // We dropped the ROI optimization (where classification focused on the sifted subject region)
         // in exchange for running all requests concurrently — net faster.
         var textRequest: VNRecognizeTextRequest?
         var classificationRequest: VNClassifyImageRequest?
         var documentRequest: VNDetectDocumentSegmentationRequest?
         var saliencyRequest: VNGenerateAttentionBasedSaliencyImageRequest?
         
         if mode == .fullAnalysis {
             print("🧠 IntelligenceProcessor: Starting Full Analysis (Single Pass)")
             let tr = VNRecognizeTextRequest()
             tr.recognitionLevel = .accurate
             textRequest = tr
             
             let cr = VNClassifyImageRequest()
             classificationRequest = cr
             
             let dr = VNDetectDocumentSegmentationRequest()
             documentRequest = dr
             
             let sr = VNGenerateAttentionBasedSaliencyImageRequest()
             saliencyRequest = sr
             
             allRequests.append(contentsOf: [tr, cr, dr, sr])
         }
         
         // Run ALL requests in a single perform() call — Vision parallelizes internally
         let handler = handlerFactory()
         try handler.perform(allRequests)
         
         // --- Process Aesthetics Score ---
         if let aestheticResult = aestheticsRequest.results?.first {
             finalResults.append(.aesthetics(score: aestheticResult.overallScore))
         }
         
         // --- Process Sifting Results ---
         if let observation = siftingRequest.results?.first {
             finalResults.append(.siftedSubject(observation, label: nil))
         }
         
         // --- Process Barcode Results ---
         if let observations = barcodeRequest.results, !observations.isEmpty {
             print("🔍 IntelligenceProcessor: Found \(observations.count) barcodes")
             
             // Handle QR Codes: Respect Layout Direction
             let qrObservations = observations.filter { $0.symbology == .qr }
             
             let direction = Locale.current.language.characterDirection
             let isRTL = direction == .rightToLeft
             
             let sortedQRs: [VNBarcodeObservation]
             if isRTL {
                 sortedQRs = qrObservations.sorted { $0.boundingBox.origin.x > $1.boundingBox.origin.x }
             } else {
                 sortedQRs = qrObservations.sorted { $0.boundingBox.origin.x < $1.boundingBox.origin.x }
             }
             
             for qr in sortedQRs {
                 if let payload = qr.payloadStringValue {
                    print("   - QR Found: \(payload)")
                    if let url = URL(string: payload), payload.contains("://") || payload.lowercased().hasPrefix("http") {
                        finalResults.append(.qr(url))
                    } else if !payload.isEmpty {
                        finalResults.append(.text(payload, nil))
                    }
                 }
             }
             
             // Handle Product Codes
             for observation in observations where observation.symbology != .qr {
                 guard let code = observation.payloadStringValue,
                       !code.isEmpty,
                       code.count >= 6,
                       observation.confidence > 0.5 else {
                     print("   - Skipping low-confidence or invalid barcode: \(observation.payloadStringValue ?? "nil") (confidence: \(observation.confidence))")
                     continue
                 }
                 
                 let type: IntelligenceResult.ProductCodeType = {
                     switch observation.symbology {
                     case .upce, .code128, .code39, .code93: return .upc
                     case .ean13, .ean8, .itf14: return .ean
                     default: return .unknown
                     }
                 }()
                 
                 print("   - Barcode Found: \(code) (\(observation.symbology.rawValue), confidence: \(observation.confidence))")
                 finalResults.append(.product(code: code, type: type, mediaAssets: []))
             }
         }
         
         // Return early if Live Mode
         if mode == .liveSifting {
             return finalResults
         }
         
         // --- Process Saliency Results ---
         if let observation = saliencyRequest?.results?.first {
             let pixelBuffer = observation.pixelBuffer
             CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
             defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
             
             let width = CVPixelBufferGetWidth(pixelBuffer)
             let height = CVPixelBufferGetHeight(pixelBuffer)
             let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
             
             if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                 let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
                 var heatmap: [Float] = []
                 heatmap.reserveCapacity(width * height)
                 
                 for y in 0..<height {
                     let rowStart = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                     for x in 0..<width {
                         heatmap.append(rowStart[x])
                     }
                 }
                 
                 // Extract salient region bounding boxes
                 let salientRegions: [NormalizedRect] = observation.salientObjects?.map { obj in
                     let box = obj.boundingBox
                     return NormalizedRect(
                         x: Float(box.origin.x),
                         y: Float(box.origin.y),
                         width: Float(box.width),
                         height: Float(box.height)
                     )
                 } ?? []
                 
                 let result = SaliencyResult(
                     width: width,
                     height: height,
                     heatmap: heatmap,
                     salientRegions: salientRegions
                 )
                 finalResults.append(.saliency(result))
                 print("👁️ Saliency: \(width)x\(height) heatmap, \(salientRegions.count) salient region(s)")
             }
         }
         
         // --- Process Full Analysis Results ---
         
         // Collect OCR text
         var ocrTextLines: [String] = []
         if let observations = textRequest?.results {
             for observation in observations {
                 if let topCandidate = observation.topCandidates(1).first {
                     ocrTextLines.append(topCandidate.string)
                 }
             }
         }
         
         // Semantic classification
         var semanticLabels: [String] = []
         if let observations = classificationRequest?.results {
             let topObservations = observations.prefix(5).filter { $0.confidence > 0.4 }
             semanticLabels = topObservations.map { $0.identifier.lowercased() }
             
             for observation in topObservations where observation.confidence > 0.7 {
                 finalResults.append(.semantic(observation.identifier, confidence: observation.confidence))
              }
              
              // Backfill the Sifted Subject Label
              if let bestLabel = topObservations.first?.identifier,
                 let index = finalResults.firstIndex(where: { if case .siftedSubject = $0 { return true } else { return false } }),
                 case .siftedSubject(let obs, _) = finalResults[index] {
                  finalResults[index] = .siftedSubject(obs, label: bestLabel)
                  print("🏷️ Assigned Label '\(bestLabel)' to Sifted Subject")
              }
          }
          
          // Document detection
          if let results = documentRequest?.results, !results.isEmpty {
               let bestLabel = ocrTextLines.sorted { $0.count > $1.count }.first
               let docType = semanticLabels.first
               
               for observation in results {
                   var rectifiedData: Data? = nil
                   if let source = sourceImage {
                       let docManager = DocumentManager()
                       rectifiedData = docManager.rectifyImage(source, using: observation, orientation: orientation)
                   }
                   
                   finalResults.append(.document(observation, text: bestLabel, label: docType, rectifiedImage: rectifiedData))
               }
               
               for line in ocrTextLines where line.count > 10 {
                   let url = extractURL(from: line)
                   finalResults.append(.text(line, url))
               }
          } else {
              for line in ocrTextLines {
                  let url = extractURL(from: line)
                  if url != nil || line.count > 3 {
                      finalResults.append(.text(line, url))
                  }
              }
          }
          
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
                     
                     finalResults.insert(.entertainment(title: title, type: type, assets: []), at: 0)
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
                
                // 1. Build comprehensive context from ALL results for purpose suggestion
                var contextParts: [String] = []
                
                for result in initialResults {
                    switch result {
                    case .semantic(let label, let conf):
                        contextParts.append("Object: \(label) (confidence: \(String(format: "%.0f%%", conf * 100)))")
                    case .text(let text, let url):
                        let preview = String(text.prefix(200))
                        contextParts.append("Captured Text: \(preview)")
                        if let url { contextParts.append("Text Source URL: \(url.absoluteString)") }
                    case .document(_, let text, let label, _):
                        if let label { contextParts.append("Document Type: \(label)") }
                        if let text {
                            let preview = String(text.prefix(300))
                            contextParts.append("Document Content: \(preview)")
                        }
                    case .richWeb(let url, let data):
                        contextParts.append("Web Link: \(url.absoluteString)")
                        if let title = data.title { contextParts.append("Page Title: \(title)") }
                        if let desc = data.descriptionText { contextParts.append("Page Description: \(String(desc.prefix(200)))") }
                    case .qr(let url):
                        contextParts.append("QR Code URL: \(url.absoluteString)")
                    case .product(let code, let type, _):
                        contextParts.append("Product Code: \(code) (\(type.rawValue))")
                    case .entertainment(let title, let type, _):
                        contextParts.append("Entertainment: \(title) (\(type))")
                    case .siftedSubject(_, let label):
                        if let label { contextParts.append("Visual Subject: \(label)") }
                    case .purpose:
                        break // Skip existing purpose results
                    case .aesthetics(let score):
                        contextParts.append("Image Quality: \(String(format: "%.0f%%", score * 100))")
                    case .saliency(let result):
                        contextParts.append("Saliency: \(result.salientRegions.count) region(s)")
                    }
                }
                
                let richContext = contextParts.joined(separator: "\n")
                
                if !richContext.isEmpty {
                    if let service = await MainActor.run(body: { Services.shared.contextQuestionService }) {
                        do {
                            let suggestions = try await service.suggestPurposes(from: richContext)
                            if !suggestions.isEmpty {
                                continuation.yield(.purpose(statements: suggestions))
                            }
                        } catch {
                            print("⚠️ IntelligenceProcessor: Failed to verify contexts: \(error)")
                        }
                    }
                }
                
                // 2. Text Deep Dive
                let textResults = initialResults.compactMap { res -> String? in
                    if case .text(let text, _) = res { return text }
                    return nil
                }
                
                for text in textResults {
                    // Detect potential dates or emails (simple regex mock -> could upgrade to NSDataDetector)
                    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.date.rawValue),
                       let match = detector.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) {
                        
                        if match.resultType == .date {
                             continuation.yield(.semantic("Event Date Detected", confidence: 0.9))
                        } else if match.resultType == .link && text.contains("@") {
                             continuation.yield(.semantic("Contact Info", confidence: 0.9))
                        }
                    }
                }
                
                print("✅ IntelligenceProcessor: Verification Complete")
                continuation.finish()
            }
        }
    }
}

