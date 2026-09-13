import Foundation

/// A city the user added to the weather forecast sheet's page list (Home's
/// weather badge → forecast sheet, swipeable). Separate from `CityResult`
/// (the full search-result shape) since only name+coordinates need to
/// persist here.
// Same `AuthUser`-precedent rule as `Trip`/`SavedCollection`/
// `SavedPOIReference`: any new field must be `Optional` or carry a
// default, or a decode failure silently wipes this list on next launch
// (`KeychainStore`/`UserDefaultsStore` both `try?` and reset to empty
// rather than crash).
struct SavedWeatherCity: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var lat: Double
    var lng: Double
}
