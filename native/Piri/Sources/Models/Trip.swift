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

// This struct's stored breadcrumb/photos have no other copy anywhere --
// unlike `PlacesQuery`'s server-refetchable cache, a decode failure here
// is real, irreplaceable data loss, not just a slower next launch.
// `KeychainStore`/`UserDefaultsStore` both `try?` their decode and
// silently reset to empty on failure (by design, to avoid crashing), and
// because `TripsStore` persists `[Trip]` as one array, ONE trip failing to
// decode fails the WHOLE array, wiping every trip for every user on that
// device. `AuthUser` (see AuthModels.swift) already hit this exact failure
// mode for real once (a Faz 2 field addition silently signed out live
// accounts) and had to grow a custom `init(from:)` using
// `decodeIfPresent(...) ?? default` for every field added after its
// original three. Any new field added to `Trip` (or `SavedPOIReference`/
// `TripWaypoint`/`TripPhoto` below/above) MUST be `Optional` or carry a
// default and be added the same `decodeIfPresent` way if this struct ever
// grows a custom decoder -- a plain non-optional, no-default field added
// the "normal" way will repeat the `AuthUser` incident here, at a higher
// cost.
struct Trip: Codable, Identifiable, Hashable {
    var id: String
    var name: String?
    var stops: [SavedPOIReference]
    var routeGeometry: [[Double]]?
    var distanceMeters: Double?
    var durationSeconds: Double?
    var breadcrumb: [TripWaypoint]
    var photos: [TripPhoto]
    var startedAt: Double
    var endedAt: Double?

    // A custom `init(from:)` below suppresses Swift's free synthesized
    // memberwise init, so it's rebuilt explicitly here (`TripsStore`'s
    // `startTrip`/tests rely on it).
    init(
        id: String,
        name: String? = nil,
        stops: [SavedPOIReference],
        routeGeometry: [[Double]]? = nil,
        distanceMeters: Double? = nil,
        durationSeconds: Double? = nil,
        breadcrumb: [TripWaypoint] = [],
        photos: [TripPhoto] = [],
        startedAt: Double,
        endedAt: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.stops = stops
        self.routeGeometry = routeGeometry
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.breadcrumb = breadcrumb
        self.photos = photos
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, stops, routeGeometry, distanceMeters, durationSeconds, breadcrumb, photos, startedAt, endedAt
    }

    /// Custom decoder -- see this file's own top-of-file warning: a
    /// synthesized decoder throws on ANY missing key (confirmed for real
    /// against `UserProfile`, see that type's own decoder comment), and
    /// because `TripsStore` persists `[Trip]` as one array, one trip
    /// failing to decode fails the WHOLE array, wiping every trip for
    /// every user on that device. Every field falls back to a default
    /// instead.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name)
        stops = try c.decodeIfPresent([SavedPOIReference].self, forKey: .stops) ?? []
        routeGeometry = try c.decodeIfPresent([[Double]].self, forKey: .routeGeometry)
        distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        breadcrumb = try c.decodeIfPresent([TripWaypoint].self, forKey: .breadcrumb) ?? []
        photos = try c.decodeIfPresent([TripPhoto].self, forKey: .photos) ?? []
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt) ?? 0
        endedAt = try c.decodeIfPresent(Double.self, forKey: .endedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(stops, forKey: .stops)
        try c.encodeIfPresent(routeGeometry, forKey: .routeGeometry)
        try c.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
        try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try c.encode(breadcrumb, forKey: .breadcrumb)
        try c.encode(photos, forKey: .photos)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
    }

    var formattedDistance: String {
        guard let meters = distanceMeters, meters > 0 else { return "—" }
        return String(format: "%.1f km", meters / 1000)
    }

    /// Falls back to `endedAt - startedAt` when `durationSeconds` wasn't
    /// recorded (older/interrupted trips) rather than showing nothing.
    /// Abbreviated unit letters (localized) instead of spelled-out "hours"/
    /// "days" sidesteps needing plural-form handling for a value that's
    /// otherwise just a compact number pair.
    var formattedDuration: String {
        let seconds = durationSeconds ?? endedAt.map { $0 - startedAt }.map { $0 / 1000 }
        guard let seconds, seconds > 0 else { return "—" }

        let totalMinutes = Int(seconds / 60)
        let hourUnit = String(localized: "trips.unit.hour")
        let minuteUnit = String(localized: "trips.unit.minute")
        let dayUnit = String(localized: "trips.unit.day")

        if totalMinutes < 60 {
            return "\(totalMinutes)\(minuteUnit)"
        }
        let totalHours = totalMinutes / 60
        if totalHours < 24 {
            let remainingMinutes = totalMinutes % 60
            return remainingMinutes > 0 ? "\(totalHours)\(hourUnit) \(remainingMinutes)\(minuteUnit)" : "\(totalHours)\(hourUnit)"
        }
        let days = totalHours / 24
        let remainingHours = totalHours % 24
        return remainingHours > 0 ? "\(days)\(dayUnit) \(remainingHours)\(hourUnit)" : "\(days)\(dayUnit)"
    }

    var dateLabel: String {
        Date(timeIntervalSince1970: startedAt / 1000).formatted(date: .abbreviated, time: .omitted)
    }

    var displayTitle: String {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? dateLabel : trimmed
    }

    /// The most common category among this trip's stops -- not literally
    /// "time spent" (breadcrumb points aren't linked to which stop was
    /// nearby at the time, so that isn't a number we actually have), but a
    /// close, honest proxy: what kind of place did this trip revolve
    /// around. Shared by `TripSummarySheet` and `TripRecapData` rather than
    /// computed twice.
    var dominantCategory: (icon: String, label: String)? {
        let categories = stops.compactMap(\.category)
        guard !categories.isEmpty else { return nil }
        let counts = Dictionary(grouping: categories, by: \.rawValue).mapValues(\.count)
        guard let topRawValue = counts.max(by: { $0.value < $1.value })?.key,
              let topCategory = categories.first(where: { $0.rawValue == topRawValue }) else { return nil }
        return (POICategoryGroups.icon(for: topCategory), topCategory.rawValue.replacingOccurrences(of: "MKPOICategory", with: ""))
    }
}

struct RouteInfo {
    var routeGeometry: [[Double]]?
    var distanceMeters: Double?
    var durationSeconds: Double?
}
