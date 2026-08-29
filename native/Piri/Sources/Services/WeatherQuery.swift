import Foundation
import Observation

/// Port of `useWeather` in `mobile/src/hooks/use-weather.ts` — same 30-minute
/// in-memory cache keyed by rounded coordinates.
@Observable
final class WeatherQuery {
    private(set) var weather: Weather?
    private(set) var isLoading = false

    private static var cache: (key: String, data: Weather, timestamp: Date)?
    private static let cacheTTL: TimeInterval = 30 * 60

    /// `cityName`, when the user has picked a city (vs. "Everywhere"/raw
    /// GPS), overrides OpenWeatherMap's own reverse-geocoded `city` --
    /// OpenWeather resolves the exact coordinate to whatever named
    /// locality is closest (e.g. "Skålevik", a small area inside
    /// Kristiansand), which doesn't match the city the user actually
    /// selected and is confusingly displayed everywhere `weather.city`
    /// shows up (the Home badge, the weather banner, the forecast sheet).
    func load(lat: Double, lng: Double, cityName: String? = nil) async {
        let key = String(format: "%.3f,%.3f", lat, lng)
        if let cache = Self.cache, cache.key == key, Date().timeIntervalSince(cache.timestamp) < Self.cacheTTL {
            weather = cache.data
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            var result = try await WeatherAPI.fetch(lat: lat, lng: lng)
            if let cityName {
                result.city = cityName
            }
            Self.cache = (key, result, Date())
            weather = result
        } catch {
            // non-critical — silently ignore, matching the RN hook
        }
    }
}
