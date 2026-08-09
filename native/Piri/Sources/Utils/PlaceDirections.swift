import MapKit

/// Port of `mobile/src/utils/directions.ts`, adapted to open natively in
/// Apple Maps (`MKMapItem`) instead of building a Google Maps web URL —
/// the RN app had no native Maps integration to call into, this one does.
enum PlaceDirections {
    static func openInMaps(_ place: Place) {
        guard let location = place.location else { return }
        let coordinate = CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = place.name
        mapItem.openInMaps()
    }

    static func canOpenInMaps(_ place: Place) -> Bool {
        place.location != nil
    }
}
