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
    var stops: [SavedPOIReference]
    var routeGeometry: [[Double]]?
    var distanceMeters: Double?
    var durationSeconds: Double?
    var breadcrumb: [TripWaypoint]
    var photos: [TripPhoto]
    var startedAt: Double
    var endedAt: Double?

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
}

struct RouteInfo {
    var routeGeometry: [[Double]]?
    var distanceMeters: Double?
    var durationSeconds: Double?
}
