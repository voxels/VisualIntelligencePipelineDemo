import Foundation
import DiverShared

public extension DiverQueueItem {
    static func items(intelligenceResults: [IntelligenceResult], capturedImage: Data? = nil, siftedImage: Data? = nil, attachments: [Data]? = nil, purpose: String? = nil, purposes: Set<String> = [], sessionID: String? = nil, contextImageURL: URL? = nil, placeID: String? = nil, latitude: Double? = nil, longitude: Double? = nil, locationName: String? = nil, depthPayload: Data? = nil, attachmentDepthPayloads: [Data?]? = nil, siftedMask: Data? = nil) -> [DiverQueueItem] {        var items: [DiverQueueItem] = []
        
        let masterID = UUID().uuidString
        var fullText = ""
        var semanticLabels: [String] = []
        
        var findingsSummary = ""
        
        // Items to create
        var childDescriptors: [(DiverItemDescriptor, Data?)] = []
        
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
                childDescriptors.append((desc, nil))
                
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
                    childDescriptors.append((desc, nil))
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
                childDescriptors.append((desc, nil))
                
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
                childDescriptors.append((desc, nil))
                
            case .document(_, let text, let label, let rectifiedImage):
                if let text { fullText += text + "\n" }
                if let label { semanticLabels.append(label) }
                findingsSummary += "• Found Document: \(label ?? "Scanned Document")\n"
                let docID = UUID().uuidString
                let desc = DiverItemDescriptor(
                    id: docID,
                    url: "secretatomics://open-doc?id=\(docID)",
                    title: label ?? "Scanned Document",
                    descriptionText: text,
                    styleTags: label.map { [$0] } ?? [],
                    categories: ["document", "child"],
                    location: locationName,
                    type: .document,
                    purpose: purpose,
                    masterCaptureID: masterID,
                    sessionID: sessionID,
                    placeID: placeID,
                    latitude: latitude,
                    longitude: longitude,
                    purposes: purposes
                )
                childDescriptors.append((desc, rectifiedImage))
                
            case .purpose: break
            case .siftedSubject(_, _): break
            case .aesthetics: break
            case .saliency: break
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
                childDescriptors.append((desc, nil))
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
            childDescriptors.append((placeDesc, nil))
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
            purposes: purposes,
            siftedMask: siftedMask
        )
        
        items.append(DiverQueueItem(
            action: "save",
            descriptor: masterDescriptor,
            source: "visual_intelligence",
            payload: effectivePayload,
            attachments: attachments,
            depthPayload: depthPayload
        ))
        
        // Enqueue child items (web links, QR codes, products, entertainment, places)
        // These carry the same sessionID as the master so they appear in the correct session.
        for (childDesc, childPayload) in childDescriptors {
            items.append(DiverQueueItem(
                action: "save",
                descriptor: childDesc,
                source: "visual_intelligence",
                payload: childPayload
            ))
        }
        
        // Add additional images from attachments as independent child items
        // This ensures they are processed by the pipeline into their own ProcessedItems
        if let attachments = attachments {
            for (index, data) in attachments.enumerated() {
                // Skip if this is already the primary payload
                if data == effectivePayload { continue }
                
                let childID = UUID().uuidString
                let childDescriptor = DiverItemDescriptor(
                    id: childID,
                    url: "diver-capture://\(childID)",
                    title: "Photo: \(masterTitle) #\(index + 1)",
                    descriptionText: "Secondary capture from the same session.",
                    styleTags: semanticLabels,
                    categories: ["visual_intelligence", "child_image"],
                    location: locationName,
                    type: .image,
                    purpose: purpose,
                    masterCaptureID: masterID,
                    sessionID: sessionID,
                    placeID: placeID,
                    latitude: latitude,
                    longitude: longitude,
                    purposes: purposes
                )
                
                items.append(DiverQueueItem(
                    action: "save",
                    descriptor: childDescriptor,
                    source: "visual_intelligence",
                    payload: data,
                    depthPayload: attachmentDepthPayloads?.indices.contains(index) == true ? attachmentDepthPayloads?[index] : nil
                ))
            }
        }
        
        return items
    }

    static func from(documentImage: Data? = nil, title: String? = nil, tags: [String] = [], text: String? = nil, purpose: String? = nil, purposes: Set<String> = [], date: Date? = nil, sessionID: String? = nil, placeID: String? = nil, latitude: Double? = nil, longitude: Double? = nil, locationName: String? = nil, attachments: [Data]? = nil) -> DiverQueueItem {
        let id = UUID().uuidString
        let resolvedTitle = title ?? "Scanned Document"
        
        // Virtual URL for document captures (using unified secretatomics scheme)
        let primaryURL = "secretatomics://open-doc?id=\(id)"
        
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
            payload: documentImage ?? Data(), // Use empty Data if nil
            attachments: attachments
        )
    }
    
    static func determineType(from urls: [URL], labels: [String]) -> DiverItemType {
        if !urls.isEmpty { return .web }
        if labels.contains("book") { return .text }
        // Default to web for general content as it's the most flexible in Diver
        return .web
    }
}
