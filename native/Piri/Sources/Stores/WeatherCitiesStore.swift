import Foundation
import Observation

/// Cities the user added to the weather forecast sheet's swipeable page
/// list (see `WeatherForecastSheet`) — same `UserDefaultsStore` persistence
/// pattern as every other local-only list in this app (saved places, trips).
@Observable
final class WeatherCitiesStore {
    private(set) var cities: [SavedWeatherCity] = []

    private let persistence = UserDefaultsStore<[SavedWeatherCity]>(key: "piri.weather-cities")

    init() {
        cities = persistence.load() ?? []
    }

    func add(_ city: SavedWeatherCity) {
        guard !cities.contains(where: { $0.id == city.id }) else { return }
        cities.append(city)
        persistence.save(cities)
    }

    func remove(_ city: SavedWeatherCity) {
        cities.removeAll { $0.id == city.id }
        persistence.save(cities)
    }
}
