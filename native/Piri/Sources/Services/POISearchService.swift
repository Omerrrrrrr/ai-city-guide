import CoreLocation
import MapKit

/// Looks up nearby Apple Maps points of interest directly via `MKLocalSearch`
/// — the non-map-view equivalent of what `PiriMapView`'s `pointOfInterestFilter`
/// does for the map screen, used so list-based screens (Home) can also browse
/// Apple's POI data while curated data is disabled.
enum POISearchService {
    static func search(
        near coordinate: CLLocationCoordinate2D,
        categories: Set<MKPointOfInterestCategory>?,
        radiusMeters: CLLocationDistance = 4000
    ) async -> [POIPlace] {
        let request = MKLocalSearch.Request()
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        request.resultTypes = .pointOfInterest
        // A category-only browse (no `naturalLanguageQuery`) requires an
        // explicit `pointOfInterestFilter` — leaving it unset returns zero
        // results even with `resultTypes = .pointOfInterest` and a region.
        request.pointOfInterestFilter = categories.map { MKPointOfInterestFilter(including: Array($0)) } ?? .includingAll

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.map { item in
                POIPlace(
                    name: item.name ?? "",
                    category: item.pointOfInterestCategory,
                    coordinate: item.placemark.coordinate,
                    mapItem: item
                )
            }
        } catch {
            return []
        }
    }
}
