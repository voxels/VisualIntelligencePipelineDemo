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
            let details = try await modelController.placeSearchService.placeSearchSession.details(for: request)
            return try await convertToEnrichmentData(place: details, withQuestions: true)
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
            let response = try await modelController.placeSearchService.placeSearchSession.query(request: request)
            guard let place = response.results?.first else { return nil }
            
            // Filter out known mocks or bad data
            if place.name == "Ruby Falls" {
                print("⚠️ FoursquareEnrichment: Ignored 'Ruby Falls' result (suspected mock)")
                return nil
            }
            
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
            let response = try await modelController.placeSearchService.placeSearchSession.query(request: request)
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
            let response = try await modelController.placeSearchService.placeSearchSession.query(request: request)
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
            let response = try await modelController.placeSearchService.placeSearchSession.query(request: request)
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
    
    private func convertToEnrichmentData(place: FSQPlace, withQuestions: Bool = true) async throws -> EnrichmentData {
        let cats = place.categories?.compactMap { $0.name } ?? []
        let placeName = place.name ?? "Unknown Place"
        
        // Extract coordinates
        var lat: Double?
        var lon: Double?
        if let main = place.geocodes?.main {
            lat = main.latitude
            lon = main.longitude
        } else if let roof = place.geocodes?.roof {
            lat = roof.latitude
            lon = roof.longitude
        }
        
        let placeContext = PlaceContext(
            name: placeName,
            categories: cats,
            placeID: place.fsq_id,
            address: place.location?.formatted_address,
            rating: place.rating,
            isOpen: place.hours?.open_now,
            latitude: lat,
            longitude: lon
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
