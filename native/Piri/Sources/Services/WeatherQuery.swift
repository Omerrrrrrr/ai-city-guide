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

    func load(lat: Double, lng: Double) async {
        let key = String(format: "%.3f,%.3f", lat, lng)
        if let cache = Self.cache, cache.key == key, Date().timeIntervalSince(cache.timestamp) < Self.cacheTTL {
            weather = cache.data
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await WeatherAPI.fetch(lat: lat, lng: lng)
            Self.cache = (key, result, Date())
            weather = result
        } catch {
            // non-critical — silently ignore, matching the RN hook
        }
    }
}
