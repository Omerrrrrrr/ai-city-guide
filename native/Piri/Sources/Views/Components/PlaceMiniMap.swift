import MapKit
import SwiftUI

/// Port of `mobile/components/place-mini-map.tsx` — a small, mostly-static
/// map used inside Place Detail (Faz 2) and the Trips list (Faz 4).
struct PlaceMiniMap: View {
    let coordinate: CLLocationCoordinate2D
    var interactive: Bool = false
    var routeCoordinates: [CLLocationCoordinate2D] = []

    var body: some View {
        PiriMapView(
            places: [],
            livePins: [],
            routeCoordinates: routeCoordinates,
            showsUserLocation: false,
            onRegionChange: { _ in },
            onSelectPlace: { _ in },
            onSelectLivePin: { _ in },
            onSelectMapFeature: { _ in },
            pointOfInterestCategories: nil,
            centerOnce: MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
        .allowsHitTesting(interactive)
        // Same fix as `PlaceImageView`: `MKMapView` has no intrinsic content
        // size, and `UIViewRepresentable`'s default sizing for that case can
        // report an oversized concrete width when only height is constrained
        // by the caller (e.g. `.frame(height: 180)`), which then inflates
        // every ancestor container's width — force both dimensions flexible
        // here so callers only ever need to constrain what they care about.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
