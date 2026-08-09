import Foundation

struct TripWaypoint: Codable, Hashable {
    var lat: Double
    var lng: Double
    var timestamp: Double
}

struct TripPhoto: Codable, Hashable, Identifiable {
    var uri: String
    var timestamp: Double
    var lat: Double?
    var lng: Double?

    var id: String { "\(uri)-\(timestamp)" }
}

struct Trip: Codable, Identifiable, Hashable {
    var id: String
    var name: String?
    var placeIds: [String]
    var routeGeometry: [[Double]]?
    var distanceMeters: Double?
    var durationSeconds: Double?
    var breadcrumb: [TripWaypoint]
    var photos: [TripPhoto]
    var startedAt: Double
    var endedAt: Double?
}

struct RouteInfo {
    var routeGeometry: [[Double]]?
    var distanceMeters: Double?
    var durationSeconds: Double?
}
