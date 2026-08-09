import MapKit

/// A place discovered directly from Apple's MapKit POI data (via
/// `MKLocalSearch`) rather than from Piri's own curated `Place` records —
/// used wherever curated data is temporarily disabled in favor of testing
/// Apple's own map data (see `HomeScreen.useCuratedHomeData` and
/// `MapScreen.useCuratedMapData`).
struct POIPlace: Identifiable {
    let id = UUID()
    let name: String
    let category: MKPointOfInterestCategory?
    let coordinate: CLLocationCoordinate2D
    let mapItem: MKMapItem

    var categoryLabel: String {
        guard let category else { return "" }
        return category.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
    }
}
