import Foundation
import Contacts
import CoreLocation
import DiverShared

/// Protocol defining the interface for contact services.
public protocol ContactServiceProvider: AnyObject, Sendable {
    func getHomeLocation() async throws -> CLLocation?
    func getWorkLocation() async throws -> CLLocation?
    func setMeContact(_ identifier: String)
    func getMeContactIdentifier() -> String?
    func requestAccess() async -> Bool
}

/// Service responsible for fetching the current user's home location from Contacts.
public final class ContactService: ContactServiceProvider, @unchecked Sendable {
    
    // We use @unchecked Sendable because CNContactStore is thread-safe documentation-wise but might not be marked Sendable yet in all swift versions?
    // Actually CNContactStore is generally safe effectively, but strict concurrency might flag it. 
    // Let's stick to simple implementation.
    
    private let contactStore = CNContactStore()
    private let geocoder = CLGeocoder()
    
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
            
            // Geocode
            let postalAddress = homeAddress.value
            let addressString = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
            
            let placemarks = try await geocoder.geocodeAddressString(addressString)
            return placemarks.first?.location
            
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
            
            let placemarks = try await geocoder.geocodeAddressString(addressString)
            return placemarks.first?.location
            
        } catch {
            DiverLogger.pipeline.error("Error fetching me contact work location: \(error.localizedDescription)")
            return nil
        }
    }
}
