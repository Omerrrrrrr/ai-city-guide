import Foundation

enum RouteProfile: String, Encodable, CaseIterable {
    case footWalking = "foot-walking"
    case drivingCar = "driving-car"
    case cyclingRegular = "cycling-regular"
    /// Never sent to `/routes/directions` -- ORS has no transit profile at
    /// all, so this branches client-side to `TransitDirections` instead
    /// (see `MapScreen+RouteMode.swift`'s `fetchDirectionsResult()`). The
    /// raw value only needs to be a stable identifier, not a real ORS
    /// profile name.
    case transit = "transit"

    var icon: String {
        switch self {
        case .footWalking: return "figure.walk"
        case .drivingCar: return "car.fill"
        case .cyclingRegular: return "bicycle"
        case .transit: return "tram.fill"
        }
    }
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
