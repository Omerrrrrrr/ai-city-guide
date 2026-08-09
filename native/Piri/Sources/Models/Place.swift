import Foundation

enum PlaceImageType: String, Codable {
    case official, tourism, wikimedia, user, stock, unknown
}

enum PlaceImportanceTier: String, Codable {
    case hero, supporting
    case longTail = "long-tail"
}

struct PlaceImage: Codable, Hashable {
    var sourceUrl: String?
    var sourceName: String?
    var license: String?
    var attribution: String?
    var verified: Bool
    var type: PlaceImageType
}

struct PlaceVerifiedFacts: Codable, Hashable {
    var address: String?
    var type: String?
    var priceLevel: String?
    var sourceUrl: String?
}

struct OpeningHoursRange: Codable, Hashable {
    var start: String
    var end: String
}

struct OpeningHoursData: Codable, Hashable {
    enum Mode: String, Codable {
        case alwaysOpen = "always-open"
        case scheduled
    }

    var timezone: String
    var mode: Mode
    /// Keyed "0"..."6" (Sunday...Saturday), matching the backend's day-index convention.
    var days: [String: [OpeningHoursRange]]
}

struct PlaceVisitInfo: Codable, Hashable {
    var durationMinutes: Int?
    var hoursNote: String?
    var openingHours: OpeningHoursData?
    var hoursVerified: Bool
    var hoursSourceUrl: String?
    var hoursLastCheckedAt: String?
    var bestTime: String?
    var seasonality: String?
    var temporarilyClosed: Bool
}

struct PlaceLocalVibe: Codable, Hashable {
    var mood: String?
    var bestFor: String?
}

struct PlaceWiki: Codable, Hashable {
    enum Status: String, Codable {
        case matched
        case notFound = "not-found"
    }

    var pageTitle: String?
    var pageUrl: String?
    var summary: String?
    var confidence: Double?
    var status: Status?
}

struct PlaceCoordinate: Codable, Hashable {
    var lat: Double
    var lng: Double
}

/// Only present on `/places/:id` responses (the list endpoint omits it) —
/// see `getPlaceGalleryImages` in `apps/api/src/image-candidate-service.ts`.
struct PlaceGalleryImage: Codable, Hashable, Identifiable {
    var id: String
    var imageUrl: String
    var sourceUrl: String?
    var sourceName: String?
    var license: String?
    var attribution: String?
    var type: String
    var verified: Bool
    var status: String
    var confidence: Double
    var pageTitle: String?
    var notes: String?
}

struct Place: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var category: String
    var tags: [String]
    var description: String
    var imageUrl: String
    var image: PlaceImage
    var importanceTier: PlaceImportanceTier
    var shortStory: String
    var verifiedFacts: PlaceVerifiedFacts
    var visitInfo: PlaceVisitInfo
    var localVibe: PlaceLocalVibe
    var city: String
    var country: String?
    var wiki: PlaceWiki?
    var location: PlaceCoordinate?
    var gallery: [PlaceGalleryImage]?
}

struct CreatePlaceRequest: Encodable {
    var name: String
    var category: String
    var city: String
    var country: String?
    var description: String
    var lat: Double
    var lng: Double
    var tags: String?
    var shortStory: String?
}
