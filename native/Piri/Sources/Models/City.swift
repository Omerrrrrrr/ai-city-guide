import Foundation

struct CityResult: Codable, Identifiable, Hashable {
    // `nil` for cities the backend only geocoded (not yet in our DB) —
    // `/cities` returns `id: null` for those, so this must stay optional or
    // decoding throws and every search for an unknown city silently fails.
    var id: String?
    var name: String
    var country: String?
    var centerLat: Double
    var centerLng: Double
    var status: String?
    var placeCount: Int?
    var isKnown: Bool?
}

struct CitySearchResponse: Decodable {
    var cities: [CityResult]
}

struct DiscoverCityRequest: Encodable {
    var name: String
    var lat: Double
    var lng: Double
    var country: String?
    var pushToken: String?
    var locale: String?
}

struct DiscoverCityResult: Decodable {
    var id: String
    var name: String
    var status: String
    var alreadyExists: Bool?
}
