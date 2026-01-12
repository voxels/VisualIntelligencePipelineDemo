import Foundation
import DiverShared

extension DiverQueueItem {
    public static func items(intelligenceResults: [IntelligenceResult], capturedImage: Data? = nil, siftedImage: Data? = nil, attachments: [Data]? = nil, purpose: String? = nil, purposes: [String] = [], sessionID: String? = nil, contextImageURL: URL? = nil, placeID: String? = nil, latitude: Double? = nil, longitude: Double? = nil, locationName: String? = nil) -> [DiverQueueItem] {
        var items: [DiverQueueItem] = []
        
        let masterID = UUID().uuidString
        var fullText = ""
        var semanticLabels: [String] = []
        
        var findingsSummary = ""
        
        // Items to create
        var childDescriptors: [DiverItemDescriptor] = []
        
        let tagBlocklist: Set<String> = ["monitor", "screen", "display", "computer", "paper", "document", "text", "visual_intelligence", "keyboard", "peripheral", "output device", "electronics", "technology"]
        
        for result in intelligenceResults {
            switch result {
            case .richWeb(let url, let data):
                findingsSummary += "• Found Web Link: \(data.title ?? "URL")\n"
                // Create Web Child
                let id = DiverLinkWrapper.id(for: url)
                let desc = DiverItemDescriptor(
                    id: id,
                    url: url.absoluteString,
                    title: data.title ?? "Web Link",
                    descriptionText: data.descriptionText,
                    styleTags: [],
                    categories: ["web", "child"],
                    location: locationName,
                    type: .web,
                    purpose: purpose,
                    masterCaptureID: masterID,
                    sessionID: sessionID,
                    placeID: placeID,
                    latitude: latitude,
                    longitude: longitude,
                    purposes: purposes
                )
                childDescriptors.append(desc)
                
            case .text(let text, let url):
                fullText += text + "\n"
                if let url = url {
                     findingsSummary += "• Found Link in Text\n"
                     let id = DiverLinkWrapper.id(for: url)
                     let desc = DiverItemDescriptor(
                        id: id,
                        url: url.absoluteString,
                        title: "Recognized Link",
                        descriptionText: "Link found in text",
                        styleTags: [],
                        categories: ["web", "child"],
                        location: locationName,
                        type: .web,
                        purpose: purpose,
                        masterCaptureID: masterID,
                        sessionID: sessionID,
                        placeID: placeID,
                        latitude: latitude,
                        longitude: longitude,
                        purposes: purposes
                    )
                    childDescriptors.append(desc)
                }
                
            case .semantic(let label, let confidence):
                if confidence > 0.6 {
                    let normalized = label.lowercased()
                    if !tagBlocklist.contains(normalized) {
                        semanticLabels.append(label)
                    }
                }
                
            case .entertainment(let title, let type, let assets):
                let typeStr = String(describing: type)
                findingsSummary += "• Found Media: \(title) (\(typeStr))\n"
                let desc = DiverItemDescriptor(
                    id: UUID().uuidString,
                    url: "diver-media://\(UUID().uuidString)",
                    title: title,
                    descriptionText: "Detected Media: \(typeStr)",
                    styleTags: [typeStr],
                    categories: ["media", "child"],
                    location: locationName,
                    type: .media,
                    purpose: purpose,
                    masterCaptureID: masterID,
                    sessionID: sessionID,
                    coverImageURL: assets.first,
                    placeID: placeID,
                    latitude: latitude,
                    longitude: longitude,
                    purposes: purposes
                )
                childDescriptors.append(desc)
                
            case .product(let code, _, let mediaAssets):
                findingsSummary += "• Found Product: \(code)\n"
                let desc = DiverItemDescriptor(
                    id: UUID().uuidString,
                    url: "diver-product://\(code)",
                    title: "Product: \(code)",
                    descriptionText: "Detected Product Code",
                    styleTags: ["product"],
                    categories: ["product", "child"],
                    location: locationName,
                    type: .product,
                    purpose: purpose,
                    masterCaptureID: masterID,
                    sessionID: sessionID,
                    coverImageURL: mediaAssets.first,
                    placeID: placeID,
                    latitude: latitude,
                    longitude: longitude,
                    purposes: purposes
                )
                childDescriptors.append(desc)
                
            case .document(_, let text, let label):
                if let text { fullText += text + "\n" }
                if let label { semanticLabels.append(label) }
                
            case .purpose: break
            case .siftedSubject: break
            case .qr(let url):
                findingsSummary += "• Found QR Code\n"
                let id = DiverLinkWrapper.id(for: url)
                let desc = DiverItemDescriptor(
                    id: id,
                    url: url.absoluteString,
                    title: "QR Code Link",
                    descriptionText: nil,
                    styleTags: ["qr"],
                    categories: ["web", "qr", "child"],
                    location: locationName,
                    type: .web,
                    purpose: purpose,
                    masterCaptureID: masterID,
                    sessionID: sessionID,
                    placeID: placeID,
                    latitude: latitude,
                    longitude: longitude,
                    purposes: purposes
                )
                childDescriptors.append(desc)
            }
        }
        
        semanticLabels = semanticLabels.filter { !tagBlocklist.contains($0.lowercased()) }
        
        // Add Place Child if present
        if let placeID = placeID, let locationName = locationName {
            let placeDesc = DiverItemDescriptor(
                id: "place-\(placeID)-\(UUID().uuidString.prefix(8))",
                url: "foursquare://places/\(placeID)",
                title: locationName,
                descriptionText: "Location context for this capture",
                styleTags: ["place"],
                categories: ["place", "child"],
                location: locationName,
                type: .place,
                purpose: purpose,
                masterCaptureID: masterID,
                sessionID: sessionID,
                placeID: placeID,
                latitude: latitude,
                longitude: longitude,
                purposes: purposes
            )
            childDescriptors.append(placeDesc)
        }
        
        // MASTER ITEM
        let masterTitle = semanticLabels.first?.capitalized ?? "Captured Moment"
        let effectivePayload = siftedImage ?? capturedImage
        
        let combinedDescription = [
             findingsSummary.trimmingCharacters(in: .whitespacesAndNewlines),
             "---",
             fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
        
        let masterDescriptor = DiverItemDescriptor(
            id: masterID,
            url: "diver-capture://\(masterID)",
            title: masterTitle,
            descriptionText: combinedDescription,
            styleTags: semanticLabels,
            categories: ["visual_intelligence", "master"],
            location: locationName,
            type: .image, // Master is the Image/Container
            purpose: purpose,
            masterCaptureID: masterID,
            sessionID: sessionID,
            coverImageURL: contextImageURL,
            placeID: placeID,
            latitude: latitude,
            longitude: longitude,
            purposes: purposes
        )
        
        items.append(DiverQueueItem(
            action: "save",
            descriptor: masterDescriptor,
            source: "visual_intelligence",
            payload: effectivePayload,
            attachments: attachments
        ))
        
        // Add Children
        for desc in childDescriptors {
            items.append(DiverQueueItem(
                action: "save",
                descriptor: desc,
                source: "visual_intelligence"
            ))
        }
        
        return items
    }

    public static func from(documentImage: Data, title: String? = nil, tags: [String] = [], text: String? = nil, purpose: String? = nil, purposes: [String] = [], date: Date? = nil, sessionID: String? = nil, placeID: String? = nil, latitude: Double? = nil, longitude: Double? = nil, locationName: String? = nil, attachments: [Data]? = nil) -> DiverQueueItem {
        let id = UUID().uuidString
        let resolvedTitle = title ?? "Scanned Document"
        
        // Virtual URL for document captures
        let primaryURL = "diver-doc://\(id)"
        
        let descriptor = DiverItemDescriptor(
            id: id,
            url: primaryURL,
            title: resolvedTitle,
            descriptionText: text,
            styleTags: tags,
            categories: ["visual_intelligence", "document"],
            location: locationName,
            type: .document,
            purpose: purpose,
            masterCaptureID: id, // Self-master
            sessionID: sessionID,
            placeID: placeID,
            latitude: latitude,
            longitude: longitude,
            purposes: purposes
        )
        
        return DiverQueueItem(
            action: "save",
            descriptor: descriptor,
            source: "visual_intelligence",
            createdAt: date ?? Date(),
            payload: documentImage,
            attachments: attachments
        )
    }
    
    public static func determineType(from urls: [URL], labels: [String]) -> DiverItemType {
        if !urls.isEmpty { return .web }
        if labels.contains("book") { return .text }
        // Default to web for general content as it's the most flexible in Diver
        return .web
    }
}
