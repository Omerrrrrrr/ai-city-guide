import Foundation
import Observation

private struct CityState: Codable {
    var cityId: String?
    var cityName: String?
    var lat: Double?
    var lng: Double?
}

/// Port of `mobile/src/store/city.ts`.
@Observable
final class CityStore {
    private(set) var cityId: String?
    private(set) var cityName: String?
    private(set) var lat: Double?
    private(set) var lng: Double?

    private let persistence = UserDefaultsStore<CityState>(key: "current-city")

    init() {
        if let saved = persistence.load() {
            cityId = saved.cityId
            cityName = saved.cityName
            lat = saved.lat
            lng = saved.lng
        }
    }

    func setCity(id: String, name: String, lat: Double? = nil, lng: Double? = nil) {
        cityId = id
        cityName = name
        self.lat = lat
        self.lng = lng
        persist()
    }

    func clearCity() {
        cityId = nil
        cityName = nil
        lat = nil
        lng = nil
        persist()
    }

    private func persist() {
        persistence.save(CityState(cityId: cityId, cityName: cityName, lat: lat, lng: lng))
    }
}
