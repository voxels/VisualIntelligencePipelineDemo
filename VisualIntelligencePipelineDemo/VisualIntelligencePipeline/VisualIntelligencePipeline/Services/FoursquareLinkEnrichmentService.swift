import Foundation
import CoreLocation
import DiverKit
import DiverShared
import knowmaps

/// A service that enriches Foursquare links using knowmaps.
public final class FoursquareLinkEnrichmentService: LinkEnrichmentService, ContextualEnrichmentService {
    private let modelController: DefaultModelController
    
    public init(modelController: DefaultModelController) {
        self.modelController = modelController
    }
    
    public func enrich(url: URL) async throws -> EnrichmentData? {
        // 1. Check if it's a Foursquare URL
        guard url.host?.contains("foursquare.com") == true || url.host?.contains("4sq.com") == true else {
            return nil
        }
        
        // 2. Extract Foursquare ID (fsq_id)
        let pathComponents = url.pathComponents
        guard let vIndex = pathComponents.firstIndex(of: "v"), vIndex + 2 < pathComponents.count else {
            return nil
        }
        let fsqID = pathComponents[vIndex + 2]
        
        // 3. Create Request
        let request = PlaceDetailsRequest(
            fsqID: fsqID,
            core: true,
            description: true,
            tel: true,
            fax: false,
            email: false,
            website: true,
            socialMedia: true,
            verified: false,
            hours: true,
            hoursPopular: true,
            rating: true,
            stats: false,
            popularity: true,
            price: true,
            menu: true,
            tastes: true,
            features: false
        )
        
        do {
            let session = await MainActor.run { modelController.placeSearchService.placeSearchSession }
            
            // Fetch details, tips, and photos concurrently
            async let detailsTask = session.details(for: request)
            async let tipsTask = session.tips(for: fsqID)
            async let photosTask = session.photos(for: fsqID)
            
            let details = try await detailsTask
            let tips = try? await tipsTask
            let photos = try? await photosTask
            
            return try await convertToEnrichmentData(place: details, tips: tips, photos: photos, withQuestions: true)
        } catch {
             print("❌ FoursquareEnrichment: Failed to fetch details for \(fsqID): \(error)")
        }
        
        return nil
    }
    
    // MARK: - ContextualEnrichmentService
    
    public func enrich(location: CLLocationCoordinate2D) async throws -> EnrichmentData? {
        let request = PlaceSearchRequest(
            query: "",
            ll: "\(location.latitude),\(location.longitude)",
            radius: 250, // Expanded proximity to catch museums/venues
            categories: nil,
            fields: nil,
            minPrice: 1,
            maxPrice: 4,
            openAt: nil,
            openNow: nil,
            nearLocation: nil,
            sort: "DISTANCE",
            limit: 1,
            offset: 0
        )
        
        do {
            let session = await MainActor.run { modelController.placeSearchService.placeSearchSession }
            let response = try await session.query(request: request)
            guard let place = response.results?.first else { return nil }
            
            // Filter out known mocks or bad data
            if place.name == "Ruby Falls" {
                print("⚠️ FoursquareEnrichment: Ignored 'Ruby Falls' result (suspected mock)")
                return nil
            }
            
            // For single location enrichment, we could optionally fetch tips/photos too
            // But to keep latency low on passive enrichment, we stick to core data
            return try await convertToEnrichmentData(place: place, withQuestions: true)
        } catch {
             print("❌ FoursquareEnrichment: Failed to search location: \(error)")
             return nil
        }
    }
    
    public func enrich(query: String, location: CLLocationCoordinate2D?) async throws -> EnrichmentData? {
        var llString: String?
        if let loc = location {
            llString = "\(loc.latitude),\(loc.longitude)"
        }
        
        let request = PlaceSearchRequest(
            query: query,
            ll: llString,
            radius: 5000,
            categories: nil,
            fields: nil,
            minPrice: 1,
            maxPrice: 4,
            openAt: nil,
            openNow: nil,
            nearLocation: nil,
            sort: location != nil ? "DISTANCE" : nil,
            limit: 1,
            offset: 0
        )
        
        do {
            let session = await MainActor.run { modelController.placeSearchService.placeSearchSession }
            let response = try await session.query(request: request)
            guard let place = response.results?.first else { return nil }
            return try await convertToEnrichmentData(place: place, withQuestions: true)
        } catch {
             print("❌ FoursquareEnrichment: Failed to search query '\(query)': \(error)")
             return nil
        }
    }
    
    public func searchNearby(location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        let request = PlaceSearchRequest(
            query: "",
            ll: "\(location.latitude),\(location.longitude)",
            radius: 1000,
            categories: nil,
            fields: nil,
            minPrice: 1,
            maxPrice: 4,
            openAt: nil,
            openNow: nil,
            nearLocation: nil,
            sort: "DISTANCE",
            limit: limit,
            offset: 0
        )
        
        do {
            let session = await MainActor.run { modelController.placeSearchService.placeSearchSession }
            let response = try await session.query(request: request)
            guard let results = response.results else { return [] }
            
            var candidates: [EnrichmentData] = []
            for place in results {
                // Filter mocks/bad data
                if place.name == "Ruby Falls" { continue }
                
                // Skip full question generation for list view to stay snappy
                if let data = try? await convertToEnrichmentData(place: place, withQuestions: false) {
                    candidates.append(data)
                }
            }
            return candidates
        } catch {
             print("❌ FoursquareEnrichment: Failed to search nearby: \(error)")
             return []
        }
    }
    
    public func search(query: String, location: CLLocationCoordinate2D, limit: Int) async throws -> [EnrichmentData] {
        let request = PlaceSearchRequest(
            query: query,
            ll: "\(location.latitude),\(location.longitude)",
            radius: 5000,
            categories: nil,
            fields: nil,
            minPrice: 1,
            maxPrice: 4,
            openAt: nil,
            openNow: nil,
            nearLocation: nil,
            sort: "DISTANCE",
            limit: limit,
            offset: 0
        )
        
        do {
            let session = await MainActor.run { modelController.placeSearchService.placeSearchSession }
            let response = try await session.query(request: request)
            guard let results = response.results else { return [] }
            
            var candidates: [EnrichmentData] = []
            for place in results {
                // Filter mocks/bad data
                if place.name == "Ruby Falls" { continue }
                
                if let data = try? await convertToEnrichmentData(place: place, withQuestions: false) {
                    candidates.append(data)
                }
            }
            return candidates
        } catch {
             print("❌ FoursquareEnrichment: Failed to search query '\(query)': \(error)")
             return []
        }
    }
    
    // MARK: - Helper
    
    private func getMirrorValue<T>(_ object: Any, key: String) -> T? {
        let mirror = Mirror(reflecting: object)
        for child in mirror.children {
            if child.label == key {
               return child.value as? T
            }
        }
        return nil
    }
    
    private func convertToEnrichmentData(place: FSQPlace, tips: [FSQTip]? = nil, photos: [FSQPhoto]? = nil, withQuestions: Bool = true) async throws -> EnrichmentData {
        let cats = place.categories?.compactMap { $0.name } ?? []
        let placeName = place.name ?? "Unknown Place"
        
        // Extract coordinates using Mirror because FSQGeocodes.main is internal in remote dependency
        var lat: Double?
        var lon: Double?
        
        if let geocodes = place.geocodes {
            // Attempt to get 'main' then 'roof'
            if let main: Any = getMirrorValue(geocodes, key: "main"),
               let unwrappedMain = main as? FSQGeocodePoint {
                 lat = getMirrorValue(unwrappedMain, key: "latitude")
                 lon = getMirrorValue(unwrappedMain, key: "longitude")
            }
            
            if (lat == nil || lon == nil) {
                if let roof: Any = getMirrorValue(geocodes, key: "roof"),
                   let unwrappedRoof = roof as? FSQGeocodePoint {
                     lat = getMirrorValue(unwrappedRoof, key: "latitude")
                     lon = getMirrorValue(unwrappedRoof, key: "longitude")
                }
            }
        }

        // Map Tips
        var tipStrings: [String] = []
        if let tips = tips {
            for tip in tips {
                if let text: String = getMirrorValue(tip, key: "text") {
                    tipStrings.append(text)
                }
            }
        }
        
        // Map Photos
        var photoUrls: [String] = []
        if let photos = photos {
            for photo in photos {
                if let prefix: String = getMirrorValue(photo, key: "prefix"),
                   let suffix: String = getMirrorValue(photo, key: "suffix") {
                   photoUrls.append(prefix + "original" + suffix)
                }
            }
        }
        
        var priceLevel: String?
        if let p = place.price {
            priceLevel = String(repeating: "$", count: p)
        }
        
        let placeContext = PlaceContext(
            name: placeName,
            categories: cats,
            placeID: place.fsq_id,
            address: place.location?.formatted_address,
            rating: place.rating,
            isOpen: nil, 
            latitude: lat,
            longitude: lon,
            priceLevel: priceLevel,
            phoneNumber: place.tel,
            website: place.website,
            photos: photoUrls,
            tips: tipStrings
        )
        
        var generatedQuestions: [String] = []
        if withQuestions {
            // Generate Questions via ContextQuestionService
            let contextService = ContextQuestionService()
            // We use the questions generated by the service
            let initialForQuestions = EnrichmentData(
                title: placeName,
                descriptionText: place.place_description,
                categories: cats,
                placeContext: placeContext
            )
            let (_, questions, _, _) = try await contextService.processContext(from: initialForQuestions)
            generatedQuestions = questions
            print("💡 Generated \(generatedQuestions.count) questions for \(placeName)")
        }
        
        return EnrichmentData(
            title: placeName,
            descriptionText: place.place_description,
            categories: cats,
            styleTags: place.tastes ?? [],
            location: place.location?.formatted_address,
            price: place.price != nil ? Double(place.price!) : nil,
            rating: place.rating,
            questions: generatedQuestions,
            placeContext: placeContext
        )
    }
}
