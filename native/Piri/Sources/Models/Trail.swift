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
    /// Normalized server-side from OSM's `sac_scale` tag — `nil` when untagged,
    /// which is common for local (lwn) trails, not a sign of missing data.
    var difficulty: TrailDifficulty?
    /// Raw OSM `surface` tag (e.g. "unpaved", "asphalt") — shown as-is, untranslated.
    var surface: String?
    /// From OSM's `dog` tag. `nil` (untagged) is deliberately not shown as
    /// "unknown" in the UI — silence on this tag is the norm, not a signal.
    var dogsAllowed: Bool?
    var centerLat: Double
    var centerLng: Double
    var approxDistanceFromQueryKm: Double

    enum CodingKeys: String, CodingKey {
        case id, name, distanceKm, network, difficulty, surface, dogsAllowed
        case centerLat, centerLng, approxDistanceFromQueryKm
        case operatorName = "operator"
    }
}

/// Mirrors the backend's `TrailDifficulty` union (`overpass.ts`) — AllTrails-style
/// tiers derived from OSM's six-step `sac_scale`, plus "extreme" for its top rung.
enum TrailDifficulty: String, Codable {
    case easy, moderate, hard, extreme
}

struct NearbyTrailsResponse: Decodable {
    var trails: [Trail]
}

struct TrailGeometry: Decodable {
    var id: Int
    var name: String?
    var points: [TrailPoint]
    var routeType: TrailRouteType
    /// `nil` when the backend's Open-Elevation lookup failed/timed out —
    /// a missing chart, not an error, same as every other best-effort field here.
    var elevationProfile: [TrailElevationPoint]?
}

struct TrailElevationPoint: Decodable {
    /// Cumulative distance walked from the trail's start, in km.
    var distanceKm: Double
    var elevationM: Double
}

/// Mirrors the backend's `TrailRouteType` (`overpass.ts`) — classified from
/// the walked line's start/end proximity, not an OSM tag. Deliberately just
/// loop-vs-not: distinguishing "out-and-back" from "point-to-point" isn't
/// reliably derivable from OSM's data model, so this doesn't guess at it.
enum TrailRouteType: String, Codable {
    case loop, linear
}

struct TrailPoint: Decodable {
    var lat: Double
    var lng: Double
}

/// `/trails/summary` -- an AI blurb grounded in this trail's OSM tags and,
/// once any exist, real Piri reviews for it. Mirrors `ExplainResult`'s
/// `reviewsSummary`/`aspectHighlights` contract: `summary` is `nil` and
/// `aspectHighlights` is empty when there's genuinely nothing grounded to say.
struct TrailSummaryResponse: Decodable {
    var summary: String?
    var aspectHighlights: [AspectHighlight]
}
