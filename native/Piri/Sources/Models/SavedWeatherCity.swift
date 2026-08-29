import Foundation

/// A city the user added to the weather forecast sheet's page list (Home's
/// weather badge → forecast sheet, swipeable). Separate from `CityResult`
/// (the full search-result shape) since only name+coordinates need to
/// persist here.
struct SavedWeatherCity: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var lat: Double
    var lng: Double
}
