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

    // A custom `init(from:)` below suppresses Swift's free synthesized
    // memberwise init, so it's rebuilt explicitly here.
    init(id: String, name: String, lat: Double, lng: Double) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lng = lng
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, lat, lng
    }

    /// Custom decoder -- see this file's own top-of-file warning: a
    /// synthesized decoder throws on ANY missing key (confirmed for real
    /// against `UserProfile`, see that type's own decoder comment), which
    /// fails this whole list's decode, wiping it on next launch. Every
    /// field falls back to a default instead.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        lat = try c.decodeIfPresent(Double.self, forKey: .lat) ?? 0
        lng = try c.decodeIfPresent(Double.self, forKey: .lng) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(lat, forKey: .lat)
        try c.encode(lng, forKey: .lng)
    }
}
