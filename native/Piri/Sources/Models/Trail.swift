import Foundation

/// A named hiking trail near a coordinate, sourced live from OpenStreetMap
/// via `/trails/nearby` (Overpass, keyless, global — see backend
/// `overpass.ts`). Metadata-only, no line geometry: a trail's walkable
/// line is a separate fetch (`TrailsAPI.geometry`), only made once the
/// user actually taps a pin.
struct Trail: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    /// km, from the trail's own OSM `distance` tag — not every trail has one.
    var distanceKm: Double?
    /// Who maintains/waymarks it, e.g. "Den Norske Turistforening" — when tagged.
    var operatorName: String?
    /// OSM network tier: "iwn"=international, "nwn"=national, "rwn"=regional, "lwn"=local.
    var network: String?
    var centerLat: Double
    var centerLng: Double
    var approxDistanceFromQueryKm: Double

    enum CodingKeys: String, CodingKey {
        case id, name, distanceKm, network, centerLat, centerLng, approxDistanceFromQueryKm
        case operatorName = "operator"
    }
}

struct NearbyTrailsResponse: Decodable {
    var trails: [Trail]
}

struct TrailGeometry: Decodable {
    var id: Int
    var name: String?
    var points: [TrailPoint]
}

struct TrailPoint: Decodable {
    var lat: Double
    var lng: Double
}
