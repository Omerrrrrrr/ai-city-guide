import Foundation

enum RouteProfile: String, Encodable {
    case footWalking = "foot-walking"
    case drivingCar = "driving-car"
}

struct DirectionsRequest: Encodable {
    var coordinates: [PlaceCoordinate]
    var profile: RouteProfile
}

struct DirectionsResult: Decodable {
    /// Backend returns [lat, lng] pairs, not GeoJSON [lng, lat] order.
    var route: [[Double]]
    var distanceMeters: Double?
    var durationSeconds: Double?
}
