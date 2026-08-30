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
enum POIRecommendationConfidence: String, Decodable {
    case strong, weak
}

struct POIRecommendationIndex: Decodable {
    var index: Int
    var aiReason: String
    var confidence: POIRecommendationConfidence
}

struct RecommendPOIResponse: Decodable {
    var answer: String
    var isItinerary: Bool
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
    /// Real photos of this place from Wikipedia and/or Tripadvisor (never
    /// AI-generated) — Wikipedia's photo, when there is one, sorts first
    /// per the user's explicit priority. Each carries its own `source` for
    /// per-photo attribution rather than one blanket label, since a single
    /// place can have photos from both providers at once. An Unsplash photo
    /// only ever appears here as a last resort, when neither real source had
    /// one.
    var photos: [POIPhoto] = []
    /// Present only when this Apple POI matches one of Piri's own curated
    /// `places` rows (by name+proximity) — its AI-generated enrichment
    /// (vibe, best-for, price level, duration, rainy-day fit) is richer than
    /// anything Apple MapKit or Tripadvisor gives. `nil` when no curated
    /// match exists.
    var curatedInfo: CuratedPlaceInfo?
    /// Dietary tags (`halal`/`kosher`/`vegetarian`/`vegan`) matched against
    /// this POI in OpenStreetMap, when any are present — folded into this
    /// card so any restaurant tap shows dietary awareness, not just pins
    /// surfaced through the map's dietary filter. `nil` when no OSM match
    /// or no diet tags on the matched node.
    var dietaryTags: [String]?
    /// Which real source (if any) the headline/body/highlights above were
    /// actually grounded in server-side — "wikipedia", "tripadvisor", or
    /// `nil` when neither matched and the AI fell back to general
    /// knowledge about a place of this name/category. Surfaced via
    /// `SourceCaption` so that distinction (fact-grounded vs. plausible
    /// inference) isn't invisible to the person reading it.
    var groundingSource: String?
    /// Google Places' own aggregate rating — `nil` unless the caller is on
    /// a paid tier with quota remaining (same gate as `curatedInfo`'s
    /// Google-photo fallback). Read-only, like Tripadvisor's.
    var googleRating: SourceRating?
    /// Present only for photogenic categories (see the server's
    /// `WIKIPEDIA_PLAUSIBLE_CATEGORIES` gate) with known coordinates —
    /// `nil` for a run-of-the-mill shop/office where "best light for
    /// photos" isn't a meaningful thing to tell someone.
    var goldenHour: GoldenHour?
    /// Piri's own average/count from `poiReviews`, folded in here so
    /// `PiriReviewsSection`'s combined-average can render immediately
    /// instead of popping in after a separate `GET /poi/reviews` round
    /// trip resolves. That endpoint is still called separately for the
    /// full review list/text (only needed once the reviews section is
    /// actually opened) — this is just the number.
    var piriRating: SourceRating?
    /// One AI-synthesized sentence on what real reviewers (Google and/or
    /// Piri) commonly say, grounded in the actual review text the server
    /// had on hand — `nil` when there wasn't enough real review text to
    /// honestly summarize (the model is explicitly told not to invent
    /// one in that case, see the `reviewsSummaryGuard` server-side).
    var reviewsSummary: String?
    /// 0-4 specific things real reviewers discussed (from the same review
    /// text `reviewsSummary` draws from), each with its own honest
    /// sentiment — never a fixed food/service/price grid forced onto
    /// every place, only what the actual sample supports. Always present
    /// (possibly empty), not optional -- the server always includes it.
    var aspectHighlights: [AspectHighlight]
}

/// One aspect real reviewers discussed, e.g. `{aspect: "Coffee quality",
/// sentiment: .positive}` — see `ExplainResult.aspectHighlights`.
struct AspectHighlight: Codable, Hashable {
    var aspect: String
    var sentiment: AspectSentiment
}

enum AspectSentiment: String, Codable {
    case positive, mixed, negative
}

/// Today's sunrise/sunset and the two golden-hour windows around them, all
/// as ISO 8601 timestamps in the place's own local time (computed
/// server-side from lat/lng, not the device's timezone).
struct GoldenHour: Codable, Hashable {
    var sunrise: String
    var sunset: String
    var morningEndsAt: String
    var eveningStartsAt: String
}

/// A third-party source's rating, reduced to just what a combined-average
/// display needs — score + how many ratings it's built on.
struct SourceRating: Codable {
    var rating: Double
    var count: Int
}

enum POIPhotoSource: String, Codable {
    case wikipedia
    case tripadvisor
    case google
    case unsplash
}

struct CuratedPlaceInfo: Codable {
    var priceLevel: String?
    var vibe: String?
    var bestFor: String?
    var familyFriendly: Bool?
    var durationMinutes: Int?
    var rainyDayFit: Bool?
}

struct POIPhoto: Codable, Identifiable, Hashable {
    var url: String
    var source: POIPhotoSource
    /// Link to the source page (Wikipedia article / Tripadvisor listing) —
    /// present for Wikipedia photos, `nil` for Tripadvisor ones (its photos
    /// endpoint doesn't return a per-photo page link).
    var attributionUrl: String?
    /// Unsplash-only — their API Terms (§9) require attributing the
    /// photographer by name, not just linking through to Unsplash
    /// generically. `nil` for Wikipedia/Tripadvisor.
    var photographerName: String?
    var photographerUrl: String?
    var id: String { url }
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
}

/// A single real Tripadvisor traveler review — user-written text, not an
/// AI summary of it. Fetched on demand via `/places/reviews`, separate
/// from `ExplainResult` so browsing full review text isn't paid for on
/// every card load, only when someone actually opens the reviews sheet.
struct TripAdvisorReview: Codable, Identifiable {
    var id: Int
    var rating: Int
    var publishedAt: String
    var title: String?
    var text: String
    var authorName: String
    var authorLocation: String?
    var authorAvatarUrl: String?
    var url: String
}

struct ReviewsRequest: Encodable {
    var name: String
    var lat: Double
    var lng: Double
}

struct ReviewsResponse: Decodable {
    var reviews: [TripAdvisorReview]
    var tripadvisorUrl: String?
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
    /// `MKMapItem.url` when Apple's own POI data has one — free for every
    /// account (no Google Places call involved), lets the backend ground
    /// the description in the business's real official site regardless of
    /// tier. `nil` for most POIs (Apple doesn't have this for everything).
    var website: String?
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

/// Client-supplied, from `CityStore`'s per-city cache (country/timezone/
/// currency, fetched once per city change — see `CityStore.refreshContext`)
/// rather than making the backend re-resolve them from scratch on every
/// single chat message. Same shape as the server's own `cityContext` zod
/// schema in `/places/explain-poi/chat`.
struct CityContextSummary: Encodable {
    var countryName: String
    var callingCode: String?
    var currencyCode: String?
    var currencyName: String?
    var timezone: String?
    /// Currency code -> how many units of it equal 1 unit of `currencyCode`
    /// — the whole table `CityStore` already cached (`open.er-api.com`
    /// covers ~160 currencies per call), not trimmed down to a handful of
    /// guessed-likely codes. Sending it costs nothing extra: it's already
    /// sitting in memory from the one fetch per city change, so there's no
    /// reason not to let the AI answer whatever currency someone actually
    /// asks about (this trip or, since `CityStore` re-fetches fresh per
    /// city, a completely different one next trip) instead of only the 2-3
    /// codes a fixed shortlist happened to guess.
    var referenceRates: [String: Double]?

    init?(countryInfo: CountryInfo?, timezone: String?, exchangeRates: ExchangeRates?) {
        guard let countryInfo else { return nil }
        self.countryName = countryInfo.name
        self.callingCode = countryInfo.callingCode
        self.currencyCode = countryInfo.currencies.first?.code
        self.currencyName = countryInfo.currencies.first?.name
        self.timezone = timezone
        self.referenceRates = exchangeRates?.rates
    }
}

struct POIChatRequest: Encodable {
    var name: String
    var category: String?
    var address: String?
    /// `MKMapItem.url` — lets the backend fetch a real excerpt of the
    /// business's own site to answer specific questions (ticket prices,
    /// hours) instead of always deflecting to "check their website."
    var website: String?
    var locale: String?
    var userProfile: PersonalizationProfile?
    var cityContext: CityContextSummary?
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
