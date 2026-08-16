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
    /// Real turn-by-turn instructions from OpenRouteService, in order for
    /// the whole multi-stop route — empty for the straight-line fallback
    /// (no OPENROUTESERVICE_API_KEY, or ORS itself failed), which has no
    /// real streets to give directions along.
    var steps: [RouteStep] = []
}

struct RouteStep: Decodable, Hashable {
    var instruction: String
    var distanceMeters: Double
}
