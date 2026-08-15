import MapKit

/// Curated place pin. Given its own `clusteringIdentifier` so it clusters
/// separately from live pins — the two layers read differently (verified
/// vs. raw-Overture) and shouldn't merge into mixed clusters.
final class PlaceAnnotation: NSObject, MKAnnotation {
    let place: Place

    var coordinate: CLLocationCoordinate2D {
        guard let location = place.location else { return CLLocationCoordinate2D() }
        return CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
    }

    var title: String? { place.name }
    var subtitle: String? { place.category }

    init(place: Place) {
        self.place = place
    }
}

/// Un-enriched live pin from `/places/nearby-live`. Unlike react-native-maps,
/// MKMapView's clustering absorbs however many of these the backend returns
/// without a client-side cap — see `mobile/app/(tabs)/map.tsx` comments on
/// why that cap (`MAX_LIVE_PINS_RESPONSE = 25`) exists at all today.
final class LivePinAnnotation: NSObject, MKAnnotation {
    let livePin: LivePin

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: livePin.lat, longitude: livePin.lng)
    }

    var title: String? { livePin.name }
    var subtitle: String? { livePin.category }

    init(livePin: LivePin) {
        self.livePin = livePin
    }
}

/// A dietary-filter match (halal/kosher/vegetarian/vegan) from
/// `/places/dietary`. No enrichment path, unlike `LivePinAnnotation` — this
/// is purely a "matches your filter" indicator, tapping it just shows the
/// name and which diet tags matched.
final class DietaryPinAnnotation: NSObject, MKAnnotation {
    let dietaryPin: DietaryPin

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: dietaryPin.lat, longitude: dietaryPin.lng)
    }

    var title: String? { dietaryPin.name }
    var subtitle: String? { dietaryPin.dietTags.joined(separator: ", ") }

    init(dietaryPin: DietaryPin) {
        self.dietaryPin = dietaryPin
    }
}

enum MapAnnotationReuseID {
    static let place = "PlaceAnnotation"
    static let livePin = "LivePinAnnotation"
    static let dietaryPin = "DietaryPinAnnotation"
    static let cluster = "ClusterAnnotation"
}
