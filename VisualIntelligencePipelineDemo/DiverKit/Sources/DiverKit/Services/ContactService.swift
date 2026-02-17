import Foundation
import Contacts
import CoreLocation
import MapKit
import DiverShared

/// Protocol defining the interface for contact services.
public protocol ContactServiceProvider: AnyObject, Sendable {
    func getHomeLocation() async throws -> CLLocation?
    func getWorkLocation() async throws -> CLLocation?
    func setMeContact(_ identifier: String)
    func getMeContactIdentifier() -> String?
    func requestAccess() async -> Bool
    func fetchContactsWithAddresses(sortedByDistanceFrom referenceLocation: CLLocation?) async -> [ContactAddress]
}

/// Service responsible for fetching the current user's home location from Contacts.
public final class ContactService: ContactServiceProvider, @unchecked Sendable {
    
    // We use @unchecked Sendable because CNContactStore is thread-safe documentation-wise but might not be marked Sendable yet in all swift versions?
    // Actually CNContactStore is generally safe effectively, but strict concurrency might flag it. 
    // Let's stick to simple implementation.
    
    private let contactStore = CNContactStore()
    // CLGeocoder removed — using MKGeocodingRequest (iOS 26+)
    
    public init() {}
    
    private let defaults = UserDefaults.standard
    private let meContactKey = "diver_me_contact_identifier"

    public func setMeContact(_ identifier: String) {
        defaults.set(identifier, forKey: meContactKey)
    }

    public func getMeContactIdentifier() -> String? {
        return defaults.string(forKey: meContactKey)
    }

    public func requestAccess() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined:
            do {
                return try await contactStore.requestAccess(for: .contacts)
            } catch {
                DiverLogger.pipeline.error("Contact access request failed: \(error.localizedDescription)")
                return false
            }
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }
    
    /// Requests access to contacts and attempts to fetch the "Me" contact's home address, then geocodes it.
    public func getHomeLocation() async throws -> CLLocation? {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        
        switch status {
        case .notDetermined:
            let granted = try await contactStore.requestAccess(for: .contacts)
            if !granted {
                return nil
            }
        case .denied, .restricted:
            return nil
        case .authorized, .limited:
            break
        @unknown default:
            return nil
        }
        
        // Fetch "Me" contact
        // Keys to fetch: PostalAddresses
        let keys = [CNContactPostalAddressesKey] as [CNKeyDescriptor]
        
        // Note: CNContactStore.unifiedMeContactWithKeys errors if no "me" card is set.
        // We should handle that gracefully.
        do {
            let meContact: CNContact
            
            #if os(macOS)
            meContact = try contactStore.unifiedMeContactWithKeys(toFetch: keys)
            #else
            // On iOS, check for manually set contact identifier
            if let savedId = getMeContactIdentifier() {
                meContact = try contactStore.unifiedContact(withIdentifier: savedId, keysToFetch: keys)
            } else {
                return nil
            }
            #endif
            
            // Find home address
            // We look for the label "Home" (CNLabelHome)
            guard let homeAddress = meContact.postalAddresses.first(where: { $0.label == CNLabelHome }) else {
                return nil
            }
            
            // Geocode via MapKit
            let postalAddress = homeAddress.value
            let addressString = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
            
            guard let request = MKGeocodingRequest(addressString: addressString) else { return nil }
            let mapItems = try await request.mapItems
            guard let coordinate = mapItems.first?.placemark.coordinate else { return nil }
            return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            
        } catch {
            // "Me" contact might not exist or other errors
            DiverLogger.pipeline.error("Error fetching me contact or geocoding: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Requests access to contacts and attempts to fetch the "Me" contact's work address, then geocodes it.
    public func getWorkLocation() async throws -> CLLocation? {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        
        switch status {
        case .notDetermined:
            let granted = try await contactStore.requestAccess(for: .contacts)
            if !granted {
                return nil
            }
        case .denied, .restricted:
            return nil
        case .authorized, .limited:
            break
        @unknown default:
            return nil
        }
        
        let keys = [CNContactPostalAddressesKey] as [CNKeyDescriptor]
        
        do {
            let meContact: CNContact
            
            #if os(macOS)
            meContact = try contactStore.unifiedMeContactWithKeys(toFetch: keys)
            #else
            if let savedId = getMeContactIdentifier() {
                meContact = try contactStore.unifiedContact(withIdentifier: savedId, keysToFetch: keys)
            } else {
                return nil
            }
            #endif
            
            // Find work address
            guard let workAddress = meContact.postalAddresses.first(where: { $0.label == CNLabelWork }) else {
                return nil
            }
            
            let postalAddress = workAddress.value
            let addressString = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
            
            guard let request = MKGeocodingRequest(addressString: addressString) else { return nil }
            let mapItems = try await request.mapItems
            guard let coordinate = mapItems.first?.placemark.coordinate else { return nil }
            return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            
        } catch {
            DiverLogger.pipeline.error("Error fetching me contact work location: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetches all contacts that have postal addresses, geocodes them, and sorts by distance from a reference location.
    /// This method uses a persistent cache to avoid re-geocoding known addresses, significantly reducing MKGeocodingRequest usage.
    /// - Parameter referenceLocation: The location to sort by distance from (e.g., current location or pinned location)
    /// - Returns: Array of ContactAddress sorted by distance (nearest first)
    public func fetchContactsWithAddresses(sortedByDistanceFrom referenceLocation: CLLocation?) async -> [ContactAddress] {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        
        // Handle authorization
        switch status {
        case .authorized, .limited:
            break // Continue to fetch
        case .notDetermined:
            let granted = (try? await contactStore.requestAccess(for: .contacts)) ?? false
            if !granted { return [] }
        default:
            return []
        }
        
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .familyName
        
        var contactAddresses: [ContactAddress] = []
        
        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                for labeledAddress in contact.postalAddresses {
                    let postalAddress = labeledAddress.value
                    let addressString = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
                    
                    let labelString: String
                    if let label = labeledAddress.label {
                        labelString = CNLabeledValue<NSString>.localizedString(forLabel: label)
                    } else {
                        labelString = "Address"
                    }
                    
                    let contactName = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    
                    let displayName = contactName.isEmpty ? "Unknown" : contactName
                    
                    contactAddresses.append(ContactAddress(
                        contactIdentifier: contact.identifier,
                        contactName: displayName,
                        addressLabel: labelString,
                        formattedAddress: addressString,
                        location: nil, // Will be geocoded below
                        distance: nil
                    ))
                }
            }
        } catch {
            DiverLogger.pipeline.error("Failed to enumerate contacts: \(error.localizedDescription)")
            return []
        }
        
        // Load Cache
        var addressCache = defaults.dictionary(forKey: "diver_address_geocoding_cache") as? [String: [Double]] ?? [:]
        var cacheUpdated = false
        
        // Geocode addresses (Check cache first)
        var geocodedAddresses: [ContactAddress] = []
        var newGeocodeCount = 0
        let maxNewGeocodes = 5 // Safe limit per session to avoid throttling
        
        for var address in contactAddresses {
            // Check Cache
            if let cachedCoords = addressCache[address.formattedAddress], cachedCoords.count == 2 {
                let cachedLocation = CLLocation(latitude: cachedCoords[0], longitude: cachedCoords[1])
                address.location = cachedLocation
                if let ref = referenceLocation {
                    address.distance = cachedLocation.distance(from: ref)
                }
                geocodedAddresses.append(address)
                continue
            }
            
            // Limit new geocodes
            if newGeocodeCount >= maxNewGeocodes { continue }
            
            do {
                // Throttle slightly
                try? await Task.sleep(nanoseconds: 100 * 1_000_000) // 100ms delay
                
                guard let geoRequest = MKGeocodingRequest(addressString: address.formattedAddress) else { continue }
                let mapItems = try await geoRequest.mapItems
                if let coordinate = mapItems.first?.placemark.coordinate {
                    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    address.location = location
                    if let ref = referenceLocation {
                        address.distance = location.distance(from: ref)
                    }
                    geocodedAddresses.append(address)
                    
                    // Update cache
                    addressCache[address.formattedAddress] = [location.coordinate.latitude, location.coordinate.longitude]
                    cacheUpdated = true
                    newGeocodeCount += 1
                }
            } catch {
                // Skip addresses that fail to geocode
                DiverLogger.pipeline.debug("Failed to geocode address: \(address.formattedAddress)")
            }
        }
        
        // Save Cache
        if cacheUpdated {
            defaults.set(addressCache, forKey: "diver_address_geocoding_cache")
        }
        
        // Sort by distance if reference location provided
        if referenceLocation != nil {
            geocodedAddresses.sort { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
        }
        
        return geocodedAddresses
    }
}

/// Represents a contact's address with geocoded location
public struct ContactAddress: Identifiable, Sendable {
    public let id = UUID()
    public let contactIdentifier: String
    public let contactName: String
    public let addressLabel: String
    public let formattedAddress: String
    public var location: CLLocation?
    public var distance: CLLocationDistance?
    
    /// Display title combining contact name and address label (e.g., "Mom's Home")
    public var displayTitle: String {
        "\(contactName)'s \(addressLabel)"
    }
}

