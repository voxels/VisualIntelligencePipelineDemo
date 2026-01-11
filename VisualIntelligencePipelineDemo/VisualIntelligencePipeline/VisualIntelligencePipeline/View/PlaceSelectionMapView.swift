import SwiftUI
import MapKit
import DiverKit
import DiverShared

struct PlaceSelectionMapView: View {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            MapViewWrapper(viewModel: viewModel) {
                dismiss()
            }
            .ignoresSafeArea()
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct MapViewWrapper: UIViewRepresentable {
    @ObservedObject var viewModel: VisualIntelligenceViewModel
    var onSelect: () -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        
        // Enable POI selection
        mapView.selectableMapFeatures = [.pointsOfInterest]
        
        // Long Press Gesture
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Update Annotations
        let currentAnnotations = uiView.annotations
        uiView.removeAnnotations(currentAnnotations)
        
        let newAnnotations = viewModel.placeCandidates.compactMap { data -> MKPointAnnotation? in
            guard let lat = data.placeContext?.latitude,
                  let lng = data.placeContext?.longitude else { return nil }
            let ann = MKPointAnnotation()
            ann.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            ann.title = data.title
            ann.subtitle = data.descriptionText
            return ann
        }
        
        uiView.addAnnotations(newAnnotations)
        
        // Initial Region Set (only once)
        if !context.coordinator.hasSetRegion {
            if let first = newAnnotations.first {
                let region = MKCoordinateRegion(center: first.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
                uiView.setRegion(region, animated: false)
                context.coordinator.hasSetRegion = true
            } else if let loc = Services.shared.locationService?.lastLocation {
                let region = MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
                uiView.setRegion(region, animated: false)
                context.coordinator.hasSetRegion = true
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWrapper
        var hasSetRegion = false
        
        init(_ parent: MapViewWrapper) {
            self.parent = parent
        }
        
        // Handle Annotation Selection (Existing Candidates & POIs)
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Case 1: Existing Candidate (MKPointAnnotation)
            if let pointAnnotation = view.annotation as? MKPointAnnotation {
                // Find matching candidate
                if let match = parent.viewModel.placeCandidates.first(where: {
                    $0.placeContext?.latitude == pointAnnotation.coordinate.latitude &&
                    $0.placeContext?.longitude == pointAnnotation.coordinate.longitude
                }) {
                    parent.viewModel.selectPlace(match)
                    parent.onSelect()
                } 
                // Case 1b: Custom Dropped Pin (also MKPointAnnotation)
                else {
                   // This might be the custom pin we dropped
                   // No-op here as selectPlace is called on drop, but good for re-selection
                   let placeData = EnrichmentData(
                        title: pointAnnotation.title,
                        descriptionText: "Custom Location",
                        categories: ["Custom"],
                        location: pointAnnotation.title,
                        placeContext: PlaceContext(
                            name: pointAnnotation.title,
                            categories: ["Custom"],
                            latitude: pointAnnotation.coordinate.latitude,
                            longitude: pointAnnotation.coordinate.longitude
                        )
                    )
                    parent.viewModel.selectPlace(placeData)
                }
                return
            }
            
            // Case 2: Native Map Feature (POI)
            if let featureAnnotation = view.annotation as? MKMapFeatureAnnotation {
                let placeData = EnrichmentData(
                   title: featureAnnotation.title ?? "Unknown Place",
                   descriptionText: featureAnnotation.subtitle,
                   categories: ["Point of Interest"],
                   location: featureAnnotation.title,
                   placeContext: PlaceContext(
                       name: featureAnnotation.title ?? "Unknown",
                       categories: ["POI"],
                       latitude: featureAnnotation.coordinate.latitude,
                       longitude: featureAnnotation.coordinate.longitude
                   )
                )
                
                parent.viewModel.selectPlace(placeData)
                parent.onSelect()
            }
        }
        
        // Handle Long Press (Pin Drop)
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                let mapView = gesture.view as! MKMapView
                let point = gesture.location(in: mapView)
                let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
                
                // Reverse Geocode for Title
                let geocoder = CLGeocoder()
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                
                geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
                    guard let self = self else { return }
                    
                    let title = placemarks?.first?.name ?? "Dropped Pin"
                    
                    let placeData = EnrichmentData(
                        title: title,
                        descriptionText: "Custom Location",
                        categories: ["Custom"],
                        location: title,
                        placeContext: PlaceContext(
                            name: title,
                            categories: ["Custom"],
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )
                    )
                    
                    DispatchQueue.main.async {
                        self.parent.viewModel.selectPlace(placeData)
                        self.parent.onSelect()
                        
                        // Optional: Add visual pin immediately before dismissing
                        let annotation = MKPointAnnotation()
                        annotation.coordinate = coordinate
                        annotation.title = title
                        mapView.addAnnotation(annotation)
                    }
                }
            }
        }
    }
}
