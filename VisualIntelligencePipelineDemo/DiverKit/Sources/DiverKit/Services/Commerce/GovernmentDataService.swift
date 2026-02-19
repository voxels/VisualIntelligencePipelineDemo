//
//  GovernmentDataService.swift
//  DiverKit
//
//  Queries free US government APIs for product safety, health, environmental compliance,
//  and energy efficiency data. All APIs are public — no authentication required.
//
//  Sources:
//  - CPSC Recalls API (cpsc.gov)
//  - FDA openFDA API (open.fda.gov)
//  - EPA ECHO API (echo.epa.gov)
//  - Energy Star API (energystar.gov)
//

import Foundation
import DiverShared

// MARK: - Government Data Types

/// Combined government data enrichment for a product.
public struct GovernmentEnrichment: Codable, Sendable {
    public let recalls: [RecallNotice]
    public let fdaAlerts: [FDAAlert]
    public let epaCompliance: EPACompliance?
    public let energyStarRating: EnergyStarRating?
    
    public init(
        recalls: [RecallNotice] = [],
        fdaAlerts: [FDAAlert] = [],
        epaCompliance: EPACompliance? = nil,
        energyStarRating: EnergyStarRating? = nil
    ) {
        self.recalls = recalls
        self.fdaAlerts = fdaAlerts
        self.epaCompliance = epaCompliance
        self.energyStarRating = energyStarRating
    }
    
    /// Whether any government source flagged a concern.
    public var hasConcerns: Bool {
        !recalls.isEmpty || !fdaAlerts.isEmpty ||
        epaCompliance?.hasViolations == true
    }
}

/// A product recall notice from CPSC.
public struct RecallNotice: Codable, Sendable, Identifiable {
    public var id: String { recallID }
    public let recallID: String
    public let title: String
    public let description: String
    public let date: Date?
    public let hazard: String?
    public let remedy: String?
    
    public init(recallID: String, title: String, description: String, date: Date? = nil, hazard: String? = nil, remedy: String? = nil) {
        self.recallID = recallID
        self.title = title
        self.description = description
        self.date = date
        self.hazard = hazard
        self.remedy = remedy
    }
}

/// An FDA enforcement or recall alert.
public struct FDAAlert: Codable, Sendable, Identifiable {
    public var id: String { eventID }
    public let eventID: String
    public let classification: String    // "Class I", "Class II", "Class III"
    public let reason: String
    public let status: String
    public let recallingFirm: String?
    
    public init(eventID: String, classification: String, reason: String, status: String, recallingFirm: String? = nil) {
        self.eventID = eventID
        self.classification = classification
        self.reason = reason
        self.status = status
        self.recallingFirm = recallingFirm
    }
}

/// EPA ECHO compliance status for a manufacturer/facility.
public struct EPACompliance: Codable, Sendable {
    public let facilityName: String?
    public let complianceStatus: String   // "In Compliance", "Significant Violation"
    public let hasViolations: Bool
    public let lastInspectionDate: Date?
    public let violationCount: Int
    
    public init(facilityName: String? = nil, complianceStatus: String, hasViolations: Bool, lastInspectionDate: Date? = nil, violationCount: Int = 0) {
        self.facilityName = facilityName
        self.complianceStatus = complianceStatus
        self.hasViolations = hasViolations
        self.lastInspectionDate = lastInspectionDate
        self.violationCount = violationCount
    }
}

/// Energy Star rating for an appliance/product.
public struct EnergyStarRating: Codable, Sendable {
    public let isCertified: Bool
    public let productCategory: String?
    public let annualEnergyUseKWh: Float?
    public let energyCostPerYear: Float?
    public let modelNumber: String?
    
    public init(isCertified: Bool, productCategory: String? = nil, annualEnergyUseKWh: Float? = nil, energyCostPerYear: Float? = nil, modelNumber: String? = nil) {
        self.isCertified = isCertified
        self.productCategory = productCategory
        self.annualEnergyUseKWh = annualEnergyUseKWh
        self.energyCostPerYear = energyCostPerYear
        self.modelNumber = modelNumber
    }
}

// MARK: - Government Data Service

/// Queries free US government APIs for product safety and compliance data.
/// All APIs are public with no authentication required.
public final class GovernmentDataService: Sendable {
    
    private let session: URLSession
    private let decoder: JSONDecoder
    
    public init(session: URLSession = .shared) {
        self.session = session
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }
    
    /// Fetch all government data for a product in parallel.
    public func enrich(product: ProductClassification) async -> GovernmentEnrichment {
        async let recalls = fetchCPSCRecalls(query: product.name)
        async let fda = fetchFDAAlerts(query: product.name)
        async let epa = fetchEPACompliance(brand: product.brand)
        async let energy = fetchEnergyStarRating(product: product)
        
        return await GovernmentEnrichment(
            recalls: recalls,
            fdaAlerts: fda,
            epaCompliance: epa,
            energyStarRating: energy
        )
    }
    
    // MARK: - CPSC Recalls
    
    /// Query CPSC Recalls API for product safety recalls.
    /// API: https://www.saferproducts.gov/api-docs
    func fetchCPSCRecalls(query: String) async -> [RecallNotice] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.saferproducts.gov/RestWebServices/Recall?format=json&RecallTitle=\(encoded)") else {
            return []
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }
            
            let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            
            return results.prefix(5).compactMap { dict -> RecallNotice? in
                guard let recallID = dict["RecallID"] as? Int,
                      let title = dict["RecallTitle"] as? String else { return nil }
                
                return RecallNotice(
                    recallID: String(recallID),
                    title: title,
                    description: dict["Description"] as? String ?? "",
                    hazard: (dict["Hazards"] as? [[String: Any]])?.first?["Name"] as? String,
                    remedy: (dict["Remedies"] as? [[String: Any]])?.first?["Name"] as? String
                )
            }
        } catch {
            print("⚠️ CPSC API error: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - FDA openFDA
    
    /// Query FDA openFDA enforcement reports.
    /// API: https://open.fda.gov/apis/
    func fetchFDAAlerts(query: String) async -> [FDAAlert] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.fda.gov/food/enforcement.json?search=reason_for_recall:\"\(encoded)\"&limit=5") else {
            return []
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = json?["results"] as? [[String: Any]] ?? []
            
            return results.compactMap { dict -> FDAAlert? in
                guard let eventID = dict["event_id"] as? String ?? (dict["recall_number"] as? String) else { return nil }
                
                return FDAAlert(
                    eventID: eventID,
                    classification: dict["classification"] as? String ?? "Unknown",
                    reason: dict["reason_for_recall"] as? String ?? "",
                    status: dict["status"] as? String ?? "Unknown",
                    recallingFirm: dict["recalling_firm"] as? String
                )
            }
        } catch {
            print("⚠️ FDA API error: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - EPA ECHO
    
    /// Query EPA ECHO for facility compliance.
    /// API: https://echo.epa.gov/tools/web-services
    func fetchEPACompliance(brand: String?) async -> EPACompliance? {
        guard let brand = brand,
              let encoded = brand.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://echodata.epa.gov/echo/dfr_rest_services.get_facilities?output=JSON&p_fn=\(encoded)&p_act=Y") else {
            return nil
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = json?["Results"] as? [String: Any]
            let facilities = results?["Facilities"] as? [[String: Any]] ?? []
            
            guard let facility = facilities.first else { return nil }
            
            let status = facility["CurrSvFlag"] as? String ?? "N"
            let hasViolations = status == "Y"
            let violationCount = facility["Infea5yrCnt"] as? Int ?? 0
            
            return EPACompliance(
                facilityName: facility["FacName"] as? String,
                complianceStatus: hasViolations ? "Significant Violation" : "In Compliance",
                hasViolations: hasViolations,
                violationCount: violationCount
            )
        } catch {
            print("⚠️ EPA ECHO API error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Energy Star
    
    /// Query Energy Star product database.
    /// API: https://data.energystar.gov/
    func fetchEnergyStarRating(product: ProductClassification) async -> EnergyStarRating? {
        // Energy Star uses Socrata Open Data API (SODA)
        // Product categories each have their own dataset
        let category = mapToEnergyStarCategory(product.category)
        guard !category.isEmpty,
              let encoded = product.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://data.energystar.gov/resource/\(category).json?$where=brand_name like '%\(encoded)%'&$limit=1") else {
            return EnergyStarRating(isCertified: false)
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return EnergyStarRating(isCertified: false)
            }
            
            let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            
            if let first = results.first {
                let kwh = (first["annual_energy_use_kwh"] as? String).flatMap { Float($0) }
                let cost = (first["estimated_annual_energy_cost"] as? String).flatMap { Float($0) }
                
                return EnergyStarRating(
                    isCertified: true,
                    productCategory: product.category,
                    annualEnergyUseKWh: kwh,
                    energyCostPerYear: cost,
                    modelNumber: first["model_number"] as? String
                )
            }
            
            return EnergyStarRating(isCertified: false)
        } catch {
            print("⚠️ Energy Star API error: \(error.localizedDescription)")
            return EnergyStarRating(isCertified: false)
        }
    }
    
    /// Map product categories to Energy Star dataset IDs (Socrata resource identifiers).
    private func mapToEnergyStarCategory(_ category: String) -> String {
        let mapping: [String: String] = [
            "electronics": "j7nj-ieq2",     // Computers & Monitors
            "appliance": "fkev-bsij",        // Refrigerators
            "hvac": "yrwj-wmke",             // HVAC
            "lighting": "ebz2-yyfa",         // Light Bulbs
            "laundry": "5dkr-6m84",          // Clothes Washers 
            "dishwasher": "d76v-r4r3",       // Dishwashers
            "television": "dqia-k99d",       // Televisions
        ]
        
        let lower = category.lowercased()
        for (key, value) in mapping {
            if lower.contains(key) { return value }
        }
        return ""
    }
}
