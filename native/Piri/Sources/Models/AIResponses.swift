import Foundation

struct AIConversationMessage: Codable {
    enum Role: String, Codable {
        case user, assistant
    }

    var role: Role
    var content: String
}

/// Mirrors `mobile/src/store/user-profile.ts` `UserProfile`, sent to the
/// backend as free-form personalization context (not an auth identity —
/// the app has no user accounts).
struct PersonalizationProfile: Encodable {
    var name: String?
    var profession: String?
    var interests: [String]?
    var faith: String?
    var budget: String?
    var groupType: String?
    var pace: String?
}

struct WeatherContext: Encodable {
    var condition: String
    var temp: Double
    var city: String
    var description: String
}

struct RecommendRequest: Encodable {
    var query: String
    var messages: [AIConversationMessage]
    var userProfile: PersonalizationProfile?
    var weather: WeatherContext?
    var city: String?
    var lat: Double?
    var lng: Double?
    var imageBase64: String?
    var mimeType: String?
    var locale: String?
    var recentlyViewedPlaceIds: [String]?
}

struct AIRecommendation: Codable, Identifiable, Hashable {
    var place: Place
    var aiReason: String

    var id: String { place.id }

    // The backend flattens `aiReason` onto the place object rather than
    // nesting it, so this needs a custom decode instead of a plain struct.
    init(from decoder: Decoder) throws {
        place = try Place(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aiReason = try container.decode(String.self, forKey: .aiReason)
    }

    init(place: Place, aiReason: String) {
        self.place = place
        self.aiReason = aiReason
    }

    func encode(to encoder: Encoder) throws {
        try place.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aiReason, forKey: .aiReason)
    }

    enum CodingKeys: String, CodingKey {
        case aiReason
    }
}

struct AIRecommendationResponse: Decodable {
    var answer: String
    var recommendations: [AIRecommendation]
}

/// Client-supplied candidate for `/places/recommend-poi` — an Apple MapKit
/// POI, not a Piri DB record. See `POIPlace`/`POISearchService`.
struct POICandidateInput: Encodable {
    var name: String
    var category: String?
    var lat: Double?
    var lng: Double?
    var address: String?
}

struct RecommendPOIRequest: Encodable {
    var query: String
    var messages: [AIConversationMessage]
    var userProfile: PersonalizationProfile?
    var weather: WeatherContext?
    var city: String?
    var lat: Double?
    var lng: Double?
    var poiCandidates: [POICandidateInput]
    var imageBase64: String?
    var mimeType: String?
    var locale: String?
    var recentlyViewedPlaceIds: [String]?
}

/// References a candidate by its index in the request's `poiCandidates`,
/// not by re-sending name/coordinates — the client resolves this back into
/// its own already-held `[POIPlace]` array from that same turn.
struct POIRecommendationIndex: Decodable {
    var index: Int
    var aiReason: String
}

struct RecommendPOIResponse: Decodable {
    var answer: String
    var recommendations: [POIRecommendationIndex]
}

struct ExplainRequest: Encodable {
    var placeId: String
    var userProfile: PersonalizationProfile?
    var locale: String?
    var recentlyViewedPlaceIds: [String]?
}

struct ExplainResult: Codable {
    var headline: String
    var body: String
    var highlights: [String]
    /// Only ever present from `/places/explain-poi` — `nil` whenever
    /// `TRIPADVISOR_API_KEY` is unset server-side or no matching Tripadvisor
    /// location was found nearby.
    var rating: TripAdvisorRating?
}

/// Tripadvisor's own bubble-rating icon URL is used as-is (`iconUrl`) rather
/// than a custom rating widget — their display terms require using the
/// rating graphic they provide, not a home-grown one.
struct TripAdvisorRating: Codable {
    var score: Double
    var reviewCount: Int
    var url: String
    var iconUrl: String
    /// Tripadvisor's own human-readable weekly schedule lines — real plain
    /// data, unlike Apple's `MKMapItem` which has no hours field at all.
    var hoursFormatted: [String]?
    /// Computed server-side from Tripadvisor's structured hours; `nil` when
    /// Tripadvisor didn't return hours for this location.
    var isOpenNow: Bool?
    /// Real Tripadvisor traveler/management photos of this place — never
    /// AI-generated or sourced elsewhere. Empty when the location has none
    /// on file.
    var photoUrls: [String] = []
}

/// Port-side request for `/places/explain-poi` — same personalized-blurb
/// shape as `/places/explain`, but for a place that only exists as an Apple
/// Maps POI (or any other ad-hoc tapped point), not a placeId in our DB.
struct ExplainPOIRequest: Encodable {
    var name: String
    var category: String?
    var lat: Double?
    var lng: Double?
    var address: String?
    var locale: String?
    var userProfile: PersonalizationProfile?
    var recentlyViewedPlaceIds: [String]?
}

/// One turn in a `/places/explain-poi/chat` follow-up conversation.
struct POIChatTurn: Codable, Identifiable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    var id = UUID()
    var role: Role
    var content: String

    enum CodingKeys: String, CodingKey {
        case role, content
    }
}

struct POIChatRequest: Encodable {
    var name: String
    var category: String?
    var address: String?
    var locale: String?
    var userProfile: PersonalizationProfile?
    var history: [POIChatTurn]
    var message: String
}

struct POIChatResponse: Decodable {
    var reply: String
}

struct IdentifyRequest: Encodable {
    var imageBase64: String
    var mimeType: String?
    var lat: Double?
    var lng: Double?
    var locale: String?
    var userProfile: PersonalizationProfile?
}

struct IdentifyResult: Decodable {
    var title: String
    var subtitle: String
    var explanation: String
    var highlights: [String]
    var matchedPlaceId: String?
}

struct PlaceLookupResult: Decodable {
    struct Enrichment: Decodable {
        enum Status: String, Decodable {
            case matched
            case notFound = "not-found"
        }

        var status: Status
        var pageTitle: String?
        var pageUrl: String?
        var summary: String?
        var confidence: Double?
    }

    var coordinates: PlaceCoordinate
    var name: String
    var city: String
    var country: String
    var displayName: String
    var enrichment: Enrichment
}
