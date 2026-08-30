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

    /// Country/timezone/currency for the current city -- constant for every
    /// POI within it, so these are fetched once per city change here rather
    /// than duplicated as a per-POI-tap call in every screen that wants one
    /// of them (`POIExplainSheet`, a future Plan budget view, ...).
    /// `nil`/empty while loading or when `lat`/`lng` aren't known yet.
    private(set) var countryInfo: CountryInfo?
    private(set) var timezones: [String] = []
    private(set) var exchangeRates: ExchangeRates?

    private let persistence = UserDefaultsStore<CityState>(key: "current-city")
    private var contextTask: Task<Void, Never>?

    init() {
        if let saved = persistence.load() {
            cityId = saved.cityId
            cityName = saved.cityName
            lat = saved.lat
            lng = saved.lng
        }
        refreshContext()
    }

    func setCity(id: String, name: String, lat: Double? = nil, lng: Double? = nil) {
        cityId = id
        cityName = name
        self.lat = lat
        self.lng = lng
        persist()
        refreshContext()
    }

    func clearCity() {
        cityId = nil
        cityName = nil
        lat = nil
        lng = nil
        persist()
        refreshContext()
    }

    private func persist() {
        persistence.save(CityState(cityId: cityId, cityName: cityName, lat: lat, lng: lng))
    }

    /// Best-effort, same as every other external-data fetch in this app --
    /// a failure just leaves the relevant field `nil`/empty rather than
    /// surfacing an error, since none of this is essential to using the app.
    private func refreshContext() {
        contextTask?.cancel()
        countryInfo = nil
        timezones = []
        exchangeRates = nil
        guard let lat, let lng else { return }

        contextTask = Task { [weak self] in
            async let country = try? CityContextAPI.countryInfo(lat: lat, lng: lng)
            async let tz = try? CityContextAPI.timezone(lat: lat, lng: lng)
            let resolvedCountry = await country
            let resolvedTz = await tz
            guard !Task.isCancelled, let self else { return }
            self.countryInfo = resolvedCountry
            self.timezones = resolvedTz ?? []

            // Chained, not parallel with the two above -- the currency code
            // to convert from comes out of `resolvedCountry` itself.
            guard let currencyCode = resolvedCountry?.currencies.first?.code else { return }
            let rates = try? await CityContextAPI.currencyRates(base: currencyCode)
            guard !Task.isCancelled else { return }
            self.exchangeRates = rates
        }
    }
}
