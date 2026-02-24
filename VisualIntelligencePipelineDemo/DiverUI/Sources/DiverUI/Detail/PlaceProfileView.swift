//
//  PlaceProfileView.swift
//  DiverUI — cross-platform
//
//  normalize(color:) removed — replaced with .secondary.opacity(0.08)
//  UIActivityViewController guarded under #if os(iOS)
//  UIImpactFeedbackGenerator already guarded in original — kept
//  ActionButton renamed PlaceActionButton to avoid collision with iOS-target ActionButton
//

import SwiftUI
import DiverKit
import DiverShared
import MapKit

public struct PlaceProfileView: View {
    public let item: ProcessedItem
    @State private var showingPlaceDetails = false

    public init(item: ProcessedItem) { self.item = item }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let coordinate = extractCoordinate(from: item) {
                let name = item.placeContext?.name ?? item.location ?? "Location"
                LocationMapView(coordinate: coordinate, locationName: name) {}
                    .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
            }
            if let place = item.placeContext {
                PlaceContextCard(context: place, baseLocation: item.location)
                    .onTapGesture { showingPlaceDetails = true }
                    .sheet(isPresented: $showingPlaceDetails) {
                        PlaceDetailSheetView(context: place) { tag in
                            if !item.tags.contains(tag) { item.tags.append(tag) }
                            if !item.categories.contains(tag) { item.categories.append(tag) }
                            Task { @MainActor in try? item.modelContext?.save() }
                        }
                    }
                    .padding(.horizontal)
            }
        }
    }

    private func extractCoordinate(from item: ProcessedItem) -> CLLocationCoordinate2D? {
        if let p = item.placeContext, let lat = p.latitude, let lon = p.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let lat = item.latitude, let lon = item.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
}

// MARK: - Place Context Card

private struct PlaceContextCard: View {
    let context: PlaceContext
    let baseLocation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.name ?? baseLocation ?? "Location").font(.headline)
                    if let cat = context.categories.first { Text(cat).font(.caption).foregroundStyle(.secondary) }
                    if let addr = context.address { Text(addr).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer()
                Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.red)
            }
            Divider()
            HStack(spacing: 12) {
                if let rating = context.rating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.caption).foregroundStyle(.orange).padding(6).glassEffect()
                }
                if let price = context.priceLevel {
                    Text(price).font(.caption).foregroundStyle(.green).padding(6).glassEffect()
                }
                if let isOpen = context.isOpen {
                    Text(isOpen ? "Open" : "Closed")
                        .font(.caption).fontWeight(.bold).foregroundStyle(isOpen ? .green : .red)
                        .padding(6).glassEffect()
                }
                Spacer()
            }
            if context.phoneNumber != nil || context.website != nil {
                Divider()
                HStack(spacing: 16) {
                    if let phone = context.phoneNumber, let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
                        Button {
                            #if os(iOS)
                            UIApplication.shared.open(url)
                            #else
                            NSWorkspace.shared.open(url)
                            #endif
                        } label: { Label("Call", systemImage: "phone.fill").font(.caption) }.buttonStyle(.bordered)
                    }
                    if let site = context.website, let url = URL(string: site) {
                        Link(destination: url) { Label("Website", systemImage: "globe").font(.caption) }.buttonStyle(.bordered)
                    }
                }
            }
            if let tips = context.tips, !tips.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips & Highlights").font(.subheadline).fontWeight(.semibold)
                    ForEach(tips.prefix(3), id: \.self) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "quote.opening").font(.caption2).foregroundStyle(.secondary)
                            Text(tip).font(.caption).foregroundStyle(.secondary).italic()
                        }
                    }
                }
            }
            if let photos = context.photos, !photos.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos, id: \.self) { photoUrl in
                            if let url = URL(string: photoUrl) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Color.gray.opacity(0.3).frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding().background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Place Detail Sheet

private struct PlaceDetailSheetView: View {
    let context: PlaceContext
    let onAddTag: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition

    init(context: PlaceContext, onAddTag: ((String) -> Void)? = nil) {
        self.context = context
        self.onAddTag = onAddTag
        if let lat = context.latitude, let lon = context.longitude {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let lat = context.latitude, let lon = context.longitude {
                        Map(position: $position) {
                            Marker(context.name ?? "Location", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                        }
                        .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(radius: 4)
                        .overlay(alignment: .bottomTrailing) {
                            Button { openInMaps(lat: lat, lon: lon, name: context.name) } label: {
                                Image(systemName: "location.fill").padding(8).glassEffect().clipShape(Circle()).padding(8)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.name ?? "Unknown Place").font(.largeTitle).fontWeight(.bold)
                        if !context.categories.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(context.categories, id: \.self) { category in
                                    Button {
                                        onAddTag?(category)
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        #endif
                                    } label: {
                                        Text(category).font(.subheadline.bold())
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(Color.orange.opacity(0.1)).foregroundStyle(.orange).clipShape(Capsule())
                                            .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1))
                                    }
                                }
                            }
                        }
                        if let addr = context.address { Text(addr).font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.horizontal)

                    HStack(spacing: 12) {
                        if let rating = context.rating {
                            Text(String(format: "⭐ %.1f", rating)).padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.yellow.opacity(0.2)).foregroundStyle(.yellow).clipShape(Capsule())
                        }
                        if let price = context.priceLevel {
                            Text(price).padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.green.opacity(0.2)).foregroundStyle(.green).clipShape(Capsule())
                        }
                        if let isOpen = context.isOpen {
                            Text(isOpen ? "Open Now" : "Closed").padding(.horizontal, 12).padding(.vertical, 6)
                                .background(isOpen ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .foregroundStyle(isOpen ? .green : .red).clipShape(Capsule())
                        }
                    }.font(.caption.bold()).padding(.horizontal)

                    Divider().padding(.horizontal)

                    HStack(spacing: 20) {
                        if let phone = context.phoneNumber {
                            PlaceActionButton(icon: "phone.fill", label: "Call") {
                                if let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
                                    #if os(iOS)
                                    UIApplication.shared.open(url)
                                    #else
                                    NSWorkspace.shared.open(url)
                                    #endif
                                }
                            }
                        }
                        if let site = context.website, let url = URL(string: site) {
                            PlaceActionButton(icon: "globe", label: "Website") {
                                #if os(iOS)
                                UIApplication.shared.open(url)
                                #else
                                NSWorkspace.shared.open(url)
                                #endif
                            }
                        }
                        PlaceActionButton(icon: "square.and.arrow.up", label: "Share") {
                            sharePlace(name: context.name, url: context.website)
                        }
                    }.padding(.horizontal)

                    if let photos = context.photos, !photos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Photos").font(.title3.bold()).padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(photos, id: \.self) { photoUrl in
                                        AsyncImage(url: URL(string: photoUrl)) { img in
                                            img.resizable().scaledToFill()
                                                .frame(width: 200, height: 150).clipShape(RoundedRectangle(cornerRadius: 12))
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.2))
                                                .frame(width: 200, height: 150).overlay(ProgressView())
                                        }
                                    }
                                }.padding(.horizontal)
                            }
                        }
                    }

                    if let tips = context.tips, !tips.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Highlights & Tips").font(.title3.bold()).padding(.horizontal)
                            ForEach(tips, id: \.self) { tip in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "quote.opening").foregroundStyle(.secondary)
                                    Text(tip).font(.body).italic().foregroundStyle(.primary.opacity(0.9))
                                }
                                .padding().background(Color.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }
                        }
                    }
                    Spacer(minLength: 50)
                }
            }
            .navigationTitle("Place Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func openInMaps(lat: Double, lon: Double, name: String?) {
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        item.name = name; item.openInMaps()
    }

    private func sharePlace(name: String?, url: String?) {
        #if os(iOS)
        var items: [Any] = ["Check out \(name ?? "this place")!"]
        if let u = url, let link = URL(string: u) { items.append(link) }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
        #elseif os(macOS)
        if let u = url, let link = URL(string: u) { NSWorkspace.shared.open(link) }
        #endif
    }
}

// MARK: - Place Action Button

public struct PlaceActionButton: View {
    public let icon: String; public let label: String; public let action: () -> Void
    public init(icon: String, label: String, action: @escaping () -> Void) {
        self.icon = icon; self.label = label; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption.bold())
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color.blue.opacity(0.1)).foregroundStyle(.blue).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
