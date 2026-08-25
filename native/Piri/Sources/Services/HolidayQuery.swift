import Foundation

/// Same shape as `WeatherQuery` — in-memory, coord-keyed, TTL cache over
/// `HolidayAPI.upcoming`. A much longer TTL than weather's 30 minutes is
/// fine (a country's holiday calendar doesn't change minute to minute),
/// but still short enough that crossing into a new day/week naturally
/// refetches on the next cold load rather than needing app-restart logic.
@Observable
final class HolidayQuery {
    private(set) var holidays: [UpcomingHoliday] = []
    private(set) var isLoading = false

    private static var cache: (key: String, data: [UpcomingHoliday], timestamp: Date)?
    private static let cacheTTL: TimeInterval = 6 * 60 * 60

    func load(lat: Double, lng: Double, locale: String? = nil) async {
        let key = String(format: "%.2f,%.2f,%@", lat, lng, locale ?? "")
        if let cache = Self.cache, cache.key == key, Date().timeIntervalSince(cache.timestamp) < Self.cacheTTL {
            holidays = cache.data
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await HolidayAPI.upcoming(lat: lat, lng: lng, days: 60, locale: locale)
            Self.cache = (key, result.holidays, Date())
            holidays = result.holidays
        } catch {
            // non-critical — silently ignore, matching WeatherQuery
        }
    }
}
