import Foundation
import Photos
import Vision
import SwiftData
import os.log
import Contacts
#if canImport(UIKit)
import UIKit
#endif

/// A service responsible for bootstrapping a local Face Vector database from the user's Photos Library.
///
/// Due to the extremely sensitive nature of biometric data, this service NEVER transmits
/// facial vectors or crops off-device. All `VNFeaturePrintObservation` embeddings are stored
/// in the local SwiftData `PersonVector` store, which inherits CloudKit encryption at rest.
///
/// **Privacy Architecture:**
/// 1. Uses `VNDetectFaceRectanglesRequest` purely on-device to isolate faces in `PHAsset`s.
/// 2. Uses `VNGenerateImageFeaturePrintRequest` to create mathematical representations (vectors).
/// 3. Does not use private `PHPerson` APIs. Instead, it relies on User-Curated "Favorites" or
///    selected smart albums to bootstrap the identity matrix.
public actor PhotoKitIndexerService {
    
    private let modelContainer: ModelContainer
    private let logger = Logger(subsystem: "com.secretatomics.VisualIntelligence", category: "FaceIndexer")
    
    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    public enum IndexerError: Error {
        case authorizationDenied
        case faceDetectionFailed
        case featureExtractionFailed
    }
    
    /// Requests access to the Photo Library and begins indexing known faces.
    /// This should be triggered from the Settings view manually, or periodically in the background.
    public func bootstrapFaceIndex() async throws -> Int {
        // 1. Request Authorization
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            logger.error("PhotoKit authorization denied. Cannot bootstrap face index.")
            throw IndexerError.authorizationDenied
        }
        
        // 2. Setup Background Context
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        
        // Fetch existing vectors to prevent duplicate indexing
        let existingDescriptor = FetchDescriptor<PersonVector>()
        let existingVectors = (try? context.fetch(existingDescriptor)) ?? []
        let existingLocalIdentifiers = Set(existingVectors.compactMap { $0.localIdentifier })
        
        logger.info("Starting Face Indexing. Found \(existingLocalIdentifiers.count) existing vectors.")
        
        var addedCount = 0
        
        // 3. Apple does not expose `PHPerson` to 3rd party apps publicly.
        // Therefore, we bootstrap the vector index by specifically requesting the user's *Favorites* album 
        // or asking the user to manually pick photos of people they want the app to remember using `PhotosPicker`.
        //
        // We calculate a dynamic fetch limit based on the user's contacts.
        // N = 10 (target 10 different angles/lighting conditions per contact for robust vector matching)
        let nAnglesPerPerson = 10
        var estimatedPeopleCount = 20 // Default fallback
        
        // Attempt to get a rough count of contacts to scale the fetch limit appropriately,
        // without requesting full Contacts access if not already granted.
        let contactStore = CNContactStore()
        if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
            do {
                let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
                var count = 0
                try contactStore.enumerateContacts(with: request) { _, _ in count += 1 }
                if count > 0 { estimatedPeopleCount = count }
            } catch {
                logger.warning("Failed to count contacts: \(error)")
            }
        }
        
        let dynamicFetchLimit = max(100, estimatedPeopleCount * nAnglesPerPerson)
        logger.info("Calculated dynamic fetch limit: \(dynamicFetchLimit) (Est. People: \(estimatedPeopleCount), Angles: \(nAnglesPerPerson))")
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = dynamicFetchLimit // Cap to prevent memory bloat, scaled by contacts
        // Only fetch images
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let targetSubtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumSelfPortraits,
            .smartAlbumDepthEffect,
            .smartAlbumRecentlyAdded
        ]
        
        var uniqueAssets: [PHAsset] = []
        var seenAssetIDs = Set<String>()
        
        for subtype in targetSubtypes {
            let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            guard let album = collections.firstObject else {
                logger.debug("Smart album \(subtype.rawValue) not found. Skipping.")
                continue
            }
            
            let fetchedAssets = PHAsset.fetchAssets(in: album, options: fetchOptions)
            for i in 0..<fetchedAssets.count {
                let asset = fetchedAssets.object(at: i)
                if !seenAssetIDs.contains(asset.localIdentifier) {
                    seenAssetIDs.insert(asset.localIdentifier)
                    uniqueAssets.append(asset)
                }
            }
        }
        
        guard !uniqueAssets.isEmpty else {
            logger.warning("No suitable assets found in target smart albums. Cannot automatically bootstrap.")
            return 0
        }
        
        // Proceed to process the assets on the actor
        addedCount = try await self.processAssetsForFaces(assets: uniqueAssets, context: context, existingIDs: existingLocalIdentifiers)
        
        try? context.save()
        logger.info("Face Indexing complete. Added \(addedCount) new vectors.")
        
        return addedCount
    }
    
    /// Processes a batch of `PHAsset`s to extract faces and generate feature prints.
    private func processAssetsForFaces(assets: [PHAsset], context: ModelContext, existingIDs: Set<String>) async -> Int {
        var newCount = 0
        
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isNetworkAccessAllowed = true // Allow iCloud download if necessary
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isSynchronous = false
        
        // Iterate through assets
        // We do this sequentially to prevent massive memory spikes from Vision requests
        for asset in assets {
            
            // Skip already indexed assets
            if existingIDs.contains(asset.localIdentifier) { continue }
            
            // Extract image data
            guard let imageData = await self.requestImageData(for: asset, manager: imageManager, options: requestOptions) else {
                continue
            }
            
            // Run Vision Face Detection
            do {
                if let vectors = try await self.extractFaceVectors(from: imageData, assetID: asset.localIdentifier) {
                    for vector in vectors {
                        context.insert(vector)
                        newCount += 1
                    }
                }
            } catch {
                self.logger.error("Failed to extract faces from asset \(asset.localIdentifier): \(error.localizedDescription)")
            }
        }
        
        return newCount
    }
    
    /// Wraps the callback-based PhotoKit request in an async continuation.
    private func requestImageData(for asset: PHAsset, manager: PHImageManager, options: PHImageRequestOptions) async -> Data? {
        return await withCheckedContinuation { continuation in
            manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    self.logger.error("Error fetching image data: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
    
    /// Executes Vision pipeline to find faces, crop them, and generate a VNFeaturePrintObservation
    private func extractFaceVectors(from imageData: Data, assetID: String) async throws -> [PersonVector]? {
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        let faceRequest = VNDetectFaceRectanglesRequest()
        
        // Need to run synchronously on the utility thread this is currently on
        try handler.perform([faceRequest])
        
        guard let results = faceRequest.results, !results.isEmpty else {
            return nil
        }
        
        var vectors: [PersonVector] = []
        
        // Convert Data to CGImage for cropping
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        
        for face in results {
            // Convert normalized coordinates to image coordinates
            let width = CGFloat(sourceImage.width)
            let height = CGFloat(sourceImage.height)
            let boundingBox = face.boundingBox
            
            let rect = CGRect(
                x: boundingBox.origin.x * width,
                y: (1 - boundingBox.origin.y - boundingBox.height) * height,
                width: boundingBox.width * width,
                height: boundingBox.height * height
            )
            
            // Expand crop slightly to include full head (1.2x multiplier)
            let expandedRect = rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1)
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            
            guard let faceCrop = sourceImage.cropping(to: expandedRect) else { continue }
            
            // Generate Feature Print on the cropped face
            let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
            featurePrintRequest.imageCropAndScaleOption = .scaleFill
            
            let cropHandler = VNImageRequestHandler(cgImage: faceCrop, options: [:])
            try cropHandler.perform([featurePrintRequest])
            
            guard let featurePrint = featurePrintRequest.results?.first else { continue }
            
            // Serialize Feature Print data
            let printData = try NSKeyedArchiver.archivedData(withRootObject: featurePrint, requiringSecureCoding: true)
            
            // Generate small uncompressed thumbnail for UI
            let mutableData = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.jpeg" as CFString, 1, nil) {
                let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.6]
                CGImageDestinationAddImage(dest, faceCrop, options as CFDictionary)
                CGImageDestinationFinalize(dest)
            }
            let uiCropData = mutableData as Data
            
            // We do not have a name yet (user must tag it manually later in the app)
            let vector = PersonVector(
                localIdentifier: assetID, // Note: Tracking origin asset, not PHPerson
                featurePrintData: printData,
                faceCropData: uiCropData
            )
            vectors.append(vector)
        }
        
        return vectors
    }
}
