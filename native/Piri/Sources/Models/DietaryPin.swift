import Foundation

/// A filter for anyone with a dietary need, not one faith — Halal/Kosher/
/// Vegetarian/Vegan sit side by side as equal options.
enum DietTag: String, CaseIterable, Identifiable, Codable {
    case halal, kosher, vegetarian, vegan
    var id: String { rawValue }
}

/// A restaurant matching the currently-selected `DietTag`, sourced live from
/// OpenStreetMap via `/places/dietary` — no AI enrichment, just a dietary-
/// match indicator (unlike `LivePin`, which can be promoted into a full
/// curated place).
struct DietaryPin: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var dietTags: [String]
    var lat: Double
    var lng: Double
}

struct DietaryPinsResponse: Decodable {
    var dietaryPins: [DietaryPin]
}
