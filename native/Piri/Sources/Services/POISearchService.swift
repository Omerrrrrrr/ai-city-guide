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
        naturalLanguageQuery: String? = nil,
        radiusMeters: CLLocationDistance = 4000
    ) async -> [POIPlace] {
        (try? await searchThrowing(near: coordinate, categories: categories, naturalLanguageQuery: naturalLanguageQuery, radiusMeters: radiusMeters)) ?? []
    }

    /// Same lookup as `search(...)`, but propagates the real error instead
    /// of swallowing every failure into an empty array — added so a caller
    /// that wants to tell "the network failed" apart from "genuinely no
    /// results" can (`CollectionDetailScreen`'s inline search is the only
    /// current caller of this variant; every other call site still uses
    /// the silent-degrade `search(...)` above, unchanged).
    static func searchThrowing(
        near coordinate: CLLocationCoordinate2D,
        categories: Set<MKPointOfInterestCategory>?,
        naturalLanguageQuery: String? = nil,
        radiusMeters: CLLocationDistance = 4000
    ) async throws -> [POIPlace] {
        let request = MKLocalSearch.Request()
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        request.resultTypes = .pointOfInterest
        request.naturalLanguageQuery = naturalLanguageQuery
        // A category-only browse (no `naturalLanguageQuery`) requires an
        // explicit `pointOfInterestFilter` — leaving it unset returns zero
        // results even with `resultTypes = .pointOfInterest` and a region.
        request.pointOfInterestFilter = categories.map { MKPointOfInterestFilter(including: Array($0)) } ?? .includingAll

        let response = try await MKLocalSearch(request: request).start()
        // `request.region` is only a ranking hint, not a hard filter —
        // confirmed live: searching "Başka" (Turkish for "other/another",
        // sent as a natural-language query from a conversational
        // follow-up) actually matched Baška, a real town on the island
        // of Krk, Croatia, ~1500km from Kristiansand, and MKLocalSearch
        // happily returned it. Drop anything wildly outside the
        // requested radius rather than trusting Apple's own relevance
        // ranking not to reach for a strong name match on the other
        // side of a continent. A generous multiple of the requested
        // radius, not the radius itself — this is still meant to allow
        // normal ranking slack, just reject the far outliers.
        let maxDistanceKm = radiusMeters * 3 / 1000
        return response.mapItems.compactMap { item -> POIPlace? in
            let itemCoordinate = item.placemark.coordinate
            guard geoDistanceKm(coordinate.latitude, coordinate.longitude, itemCoordinate.latitude, itemCoordinate.longitude) <= maxDistanceKm else {
                return nil
            }
            return POIPlace(
                name: item.name ?? "",
                category: item.pointOfInterestCategory,
                coordinate: itemCoordinate,
                mapItem: item
            )
        }
    }
}
