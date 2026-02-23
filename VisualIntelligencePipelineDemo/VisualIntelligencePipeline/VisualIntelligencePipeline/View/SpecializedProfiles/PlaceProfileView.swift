import SwiftUI
import DiverKit
import DiverShared
import MapKit

public struct PlaceProfileView: View {
    let item: ProcessedItem
    @State private var showingPlaceDetails = false
    
    public init(item: ProcessedItem) {
        self.item = item
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Interactive Map View
            if let coordinate = extractCoordinate(from: item) {
                let locationName = item.placeContext?.name ?? item.location ?? "Location"
                LocationMapView(coordinate: coordinate, locationName: locationName) {
                    // Action triggered on map tap
                }
                .frame(height: 250)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // Foursquare / Detailed Place Context
            if let place = item.placeContext {
                PlaceContextView(context: place, baseLocation: item.location)
                    .onTapGesture {
                        showingPlaceDetails = true
                    }
                    .sheet(isPresented: $showingPlaceDetails) {
                        PlaceDetailSheet(context: place) { tag in
                            // Add tag to item
                            var updated = false
                            if !item.tags.contains(tag) {
                                item.tags.append(tag)
                                updated = true
                            }
                            if !item.categories.contains(tag) {
                                item.categories.append(tag)
                                updated = true
                            }
                            
                            if updated {
                                Task { @MainActor in try? item.modelContext?.save() }
                            }
                        }
                    }
                    .padding(.horizontal)
            }
        }
    }
    
    private func extractCoordinate(from item: ProcessedItem) -> CLLocationCoordinate2D? {
        if let place = item.placeContext, let lat = place.latitude, let lon = place.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let lat = item.latitude, let lon = item.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
}

// MARK: - Detailed Place Info
struct PlaceContextView: View {
    let context: PlaceContext
    let baseLocation: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Name and Category
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.name ?? baseLocation ?? "Location")
                        .font(.headline)
                    
                    if let category = context.categories.first {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let addr = context.address {
                         Text(addr)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
            
            Divider()
            
            // Details Row: Rating, Price, Status
            HStack(spacing: 12) {
                if let rating = context.rating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(6)
                        .glass(cornerRadius: 6)
                }
                
                if let price = context.priceLevel {
                    Text(price)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(6)
                        .glass(cornerRadius: 6)
                }
                
                if let isOpen = context.isOpen {
                    Text(isOpen ? "Open" : "Closed")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(isOpen ? .green : .red)
                        .padding(6)
                        .glass(cornerRadius: 6)
                }
                
                Spacer()
            }
            
            // Actions: Phone & Website
            if context.phoneNumber != nil || context.website != nil {
                Divider()
                HStack(spacing: 16) {
                    if let phone = context.phoneNumber, let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
                        Button {
                            #if os(iOS)
                            UIApplication.shared.open(url)
                            #endif
                        } label: {
                            Label("Call", systemImage: "phone.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if let website = context.website, let url = URL(string: website) {
                         Link(destination: url) {
                             Label("Website", systemImage: "globe")
                                 .font(.caption)
                         }
                         .buttonStyle(.bordered)
                    }
                }
            }
            
            // Tips
            if let tips = context.tips, !tips.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips & Highlights")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    ForEach(tips.prefix(3), id: \.self) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "quote.opening")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(tip)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                }
            }
            
            // Photos
            if let photos = context.photos, !photos.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos, id: \.self) { photoUrl in
                            if let url = URL(string: photoUrl) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 100)
                                            .cornerRadius(8)
                                    } else if phase.error != nil {
                                        Color.gray.opacity(0.3)
                                            .frame(width: 100, height: 100)
                                            .cornerRadius(8)
                                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                                    } else {
                                        ProgressView()
                                            .frame(width: 100, height: 100)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(normalize(color: .secondarySystemGroupedBackground)))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Place Detail Sheet
struct PlaceDetailSheet: View {
    let context: PlaceContext
    var onAddTag: ((String) -> Void)? = nil // Callback for adding context
    @Environment(\.dismiss) private var dismiss
    
    @State private var position: MapCameraPosition
    
    init(context: PlaceContext, onAddTag: ((String) -> Void)? = nil) {
        self.context = context
        self.onAddTag = onAddTag
        
        if let lat = context.latitude, let lon = context.longitude {
            self._position = State(initialValue: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))))
        } else {
            self._position = State(initialValue: .automatic)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // 1. Map Header
                    if let lat = context.latitude, let lon = context.longitude {
                        Map(position: $position) {
                            Marker(context.name ?? "Location", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                        }
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 4)
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                openInMaps(lat: lat, lon: lon, name: context.name)
                            } label: {
                                Image(systemName: "location.fill")
                                    .padding(8)
                                    .glassEffect()
                                    .clipShape(Circle())
                                    .padding(8)
                            }
                        }
                    }
                    
                    // 2. Title & Basic Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.name ?? "Unknown Place")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        // Categories / Taste Chips
                        if !context.categories.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(context.categories, id: \.self) { category in
                                    Button {
                                        onAddTag?(category)
                                        // Optional feedback
                                        #if os(iOS)
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        #endif
                                    } label: {
                                        Text(category)
                                            .font(.subheadline.bold())
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.orange.opacity(0.1))
                                            .foregroundStyle(.orange)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                        
                        if let address = context.address {
                            Text(address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // 3. Status Pills (Rating, Price, Open)
                    HStack(spacing: 12) {
                        if let rating = context.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.yellow.opacity(0.2))
                                .foregroundStyle(.yellow)
                                .clipShape(Capsule())
                        }
                        
                        if let price = context.priceLevel {
                            Text(price)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                        
                        if let isOpen = context.isOpen {
                            Text(isOpen ? "Open Now" : "Closed")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isOpen ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .foregroundStyle(isOpen ? .green : .red)
                                .clipShape(Capsule())
                        }
                    }
                    .font(.caption.bold())
                    .padding(.horizontal)
                    
                    Divider().padding(.horizontal)
                    
                    // 4. Actions
                    HStack(spacing: 20) {
                        if let phone = context.phoneNumber {
                            ActionButton(icon: "phone.fill", label: "Call") {
                                if let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
                                    #if os(iOS)
                                    UIApplication.shared.open(url)
                                    #endif
                                }
                            }
                        }
                        
                        if let website = context.website, let url = URL(string: website) {
                            ActionButton(icon: "globe", label: "Website") {
                                #if os(iOS)
                                UIApplication.shared.open(url)
                                #endif
                            }
                        }
                        
                        ActionButton(icon: "square.and.arrow.up", label: "Share") {
                            // Simple share action
                            sharePlace(name: context.name, url: context.website)
                        }
                    }
                    .padding(.horizontal)
                    
                    // 5. Photos
                    if let photos = context.photos, !photos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Photos")
                                .font(.title3.bold())
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(photos, id: \.self) { photoUrl in
                                        AsyncImage(url: URL(string: photoUrl)) { image in
                                            image.resizable()
                                                 .scaledToFill()
                                                 .frame(width: 200, height: 150)
                                                 .clipShape(RoundedRectangle(cornerRadius: 12))
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 200, height: 150)
                                                .overlay(ProgressView())
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // 6. Tips & Reviews
                    if let tips = context.tips, !tips.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Highlights & Tips")
                                .font(.title3.bold())
                                .padding(.horizontal)
                            
                            ForEach(tips, id: \.self) { tip in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "quote.opening")
                                        .foregroundStyle(.secondary)
                                    Text(tip)
                                        .font(.body)
                                        .italic()
                                        .foregroundStyle(.primary.opacity(0.9))
                                }
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    Spacer(minLength: 50)
                }
            }
            .navigationTitle("Place Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func openInMaps(lat: Double, lon: Double, name: String?) {
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = name
        mapItem.openInMaps()
    }
    
    private func sharePlace(name: String?, url: String?) {
        #if os(iOS)
        let text = "Check out \(name ?? "this place")!"
        var items: [Any] = [text]
        if let u = url, let link = URL(string: u) {
            items.append(link)
        }
        
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Find top controller to present
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
        #endif
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
