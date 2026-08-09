import MapKit
import SwiftUI

/// Small, non-interactive polyline preview used in the trips list — port of
/// the inline `MapView` + `Polyline` in `mobile/app/trips.tsx`'s `TripRow`.
struct TripMiniMap: View {
    let points: [CLLocationCoordinate2D]

    var body: some View {
        if let region = regionForPoints(points) {
            PiriMapView(
                places: [],
                livePins: [],
                routeCoordinates: points,
                showsUserLocation: false,
                onRegionChange: { _ in },
                onSelectPlace: { _ in },
                onSelectLivePin: { _ in },
                onSelectMapFeature: { _ in },
                pointOfInterestCategories: nil,
                centerOnce: region
            )
            .allowsHitTesting(false)
        } else {
            ZStack {
                Color(.secondarySystemBackground)
                Text("◈").font(.system(size: 24)).foregroundStyle(Theme.gold)
            }
        }
    }
}
