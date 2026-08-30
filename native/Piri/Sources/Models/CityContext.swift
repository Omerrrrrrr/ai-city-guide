import Foundation

/// Mirrors the server's `CountryInfo` (`apps/api/src/country-info.ts`) --
/// offline `world-countries` data, no network call server-side.
struct CountryInfo: Codable, Hashable {
    var name: String
    var officialName: String
    var capital: [String]
    var region: String
    var subregion: String
    var currencies: [CountryCurrency]
    var callingCode: String?
    var languages: [String]
    var borders: [String]
    var flagEmoji: String
    var areaKm2: Double
    var landlocked: Bool
}

struct CountryCurrency: Codable, Hashable {
    var code: String
    var name: String
    var symbol: String
}

struct ExchangeRates: Codable, Hashable {
    var base: String
    var rates: [String: Double]
    var updatedAt: String
}
