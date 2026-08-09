import Foundation

/// Port of `getDistance` in `mobile/src/utils/location.ts` (haversine, km).
func geoDistanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6371.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return r * c
}

struct PlaceWithDistance: Identifiable, Hashable {
    var place: Place
    var distanceKm: Double
    var id: String { place.id }
}
