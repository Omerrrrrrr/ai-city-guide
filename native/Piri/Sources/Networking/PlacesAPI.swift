import Foundation

/// Endpoint calls mirroring `mobile/src/api/places.ts`, `live-places.ts`,
/// `routes.ts`, `cities.ts`. Grouped by backend resource, not by mobile
/// screen, since several screens share the same endpoint.
enum PlacesAPI {
    static func fetchPlaces(city: String? = nil, lat: Double? = nil, lng: Double? = nil) async throws -> [Place] {
        try await APIClient.shared.get("/places", query: [
            "city": city,
            "lat": lat.map { String($0) },
            "lng": lng.map { String($0) },
        ])
    }

    static func fetchPlace(id: String) async throws -> Place {
        try await APIClient.shared.get("/places/\(id)")
    }

    static func createPlace(_ request: CreatePlaceRequest) async throws -> Place {
        try await APIClient.shared.post("/places", body: request)
    }

    static func lookupPlace(lat: Double, lng: Double) async throws -> PlaceLookupResult {
        try await APIClient.shared.get("/places/lookup", query: ["lat": String(lat), "lng": String(lng)])
    }

    static func recommend(_ request: RecommendRequest) async throws -> AIRecommendationResponse {
        try await APIClient.shared.post("/places/recommend", body: request)
    }

    static func recommendPOI(_ request: RecommendPOIRequest) async throws -> RecommendPOIResponse {
        try await APIClient.shared.post("/places/recommend-poi", body: request)
    }

    static func explain(_ request: ExplainRequest) async throws -> ExplainResult {
        try await APIClient.shared.post("/places/explain", body: request)
    }

    /// `token` is optional — signed-out/free accounts get the exact same
    /// response as before — but when a signed-in account's token IS
    /// passed, the backend can layer in paid-tier-only extras (Google
    /// photos/description/reviews, see `/places/explain-poi`). Every call
    /// site should pass `authStore.token` whenever one is available; this
    /// was missing for a while after that backend support shipped, which
    /// silently meant no paid account ever actually got the Google data
    /// despite the entitlement being real (confirmed live 2026-08-23).
    static func explainPOI(_ request: ExplainPOIRequest, token: String? = nil) async throws -> ExplainResult {
        try await APIClient.shared.post("/places/explain-poi", body: request, bearerToken: token)
    }

    static func chatAboutPOI(_ request: POIChatRequest) async throws -> POIChatResponse {
        try await APIClient.shared.post("/places/explain-poi/chat", body: request)
    }

    static func identify(_ request: IdentifyRequest) async throws -> IdentifyResult {
        try await APIClient.shared.post("/places/identify", body: request)
    }
}

enum LivePlacesAPI {
    static func fetchNearbyLive(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) async throws -> [LivePin] {
        let response: LivePinsResponse = try await APIClient.shared.get("/places/nearby-live", query: [
            "minLat": String(minLat),
            "maxLat": String(maxLat),
            "minLng": String(minLng),
            "maxLng": String(maxLng),
        ])
        return response.livePins
    }

    static func enrichLive(overtureId: String) async throws -> Place {
        try await APIClient.shared.post("/places/enrich-live", body: EnrichLiveRequest(overtureId: overtureId))
    }
}

enum DietaryPlacesAPI {
    static func fetchNearby(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double, diet: DietTag) async throws -> [DietaryPin] {
        let response: DietaryPinsResponse = try await APIClient.shared.get("/places/dietary", query: [
            "minLat": String(minLat),
            "maxLat": String(maxLat),
            "minLng": String(minLng),
            "maxLng": String(maxLng),
            "diet": diet.rawValue,
        ])
        return response.dietaryPins
    }
}

enum TrailsAPI {
    static func nearby(lat: Double, lng: Double, radiusMeters: Int = 10000) async throws -> [Trail] {
        let response: NearbyTrailsResponse = try await APIClient.shared.get("/trails/nearby", query: [
            "lat": String(lat),
            "lng": String(lng),
            "radiusMeters": String(radiusMeters),
        ])
        return response.trails
    }

    static func geometry(id: Int) async throws -> TrailGeometry {
        try await APIClient.shared.get("/trails/geometry", query: ["id": String(id)])
    }
}

/// Backs `CityStore`'s per-city context cache -- all three are constant for
/// every POI within the same city, so they're fetched once per city change
/// there rather than per-POI-tap like `/places/explain-poi`'s own signals.
enum CityContextAPI {
    static func countryInfo(lat: Double, lng: Double) async throws -> CountryInfo {
        try await APIClient.shared.get("/country-info", query: ["lat": String(lat), "lng": String(lng)])
    }

    static func timezone(lat: Double, lng: Double) async throws -> [String] {
        let response: TimezoneResponse = try await APIClient.shared.get("/timezone", query: [
            "lat": String(lat), "lng": String(lng),
        ])
        return response.timezones
    }

    static func currencyRates(base: String) async throws -> ExchangeRates {
        try await APIClient.shared.get("/currency/rates", query: ["base": base])
    }
}

private struct TimezoneResponse: Decodable {
    var timezones: [String]
}

enum RoutesAPI {
    static func directions(coordinates: [PlaceCoordinate], profile: RouteProfile = .footWalking) async throws -> DirectionsResult {
        try await APIClient.shared.post("/routes/directions", body: DirectionsRequest(coordinates: coordinates, profile: profile))
    }
}

enum CitiesAPI {
    static func search(_ query: String) async throws -> [CityResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let response: CitySearchResponse = try await APIClient.shared.get("/cities", query: ["q": query])
        return response.cities
    }

    static func discover(_ request: DiscoverCityRequest) async throws -> DiscoverCityResult {
        try await APIClient.shared.post("/cities/discover", body: request)
    }

    static func status(cityId: String) async throws -> CityResult {
        try await APIClient.shared.get("/cities/\(cityId)")
    }
}

enum HolidayAPI {
    /// `days` bounds how far ahead to look (backend clamps to 1-365,
    /// defaults 30). `locale` steers the AI-written `summary`/`activities`
    /// language — omit for the backend's own default (English).
    static func upcoming(lat: Double, lng: Double, days: Int = 30, locale: String? = nil) async throws -> HolidaysUpcomingResponse {
        try await APIClient.shared.get("/holidays/upcoming", query: [
            "lat": String(lat),
            "lng": String(lng),
            "days": String(days),
            "locale": locale,
        ])
    }
}

enum WeatherAPI {
    static func fetch(lat: Double, lng: Double) async throws -> Weather {
        try await APIClient.shared.get("/weather", query: ["lat": String(lat), "lng": String(lng)])
    }

    /// Only meaningfully accurate within OpenWeatherMap's free-tier ~5-day
    /// forecast horizon — callers (`CollectionDetailScreen`) are expected to
    /// check the target date is within that window before calling this.
    static func forecast(lat: Double, lng: Double, date: Date) async throws -> Weather {
        try await APIClient.shared.get("/weather/forecast", query: [
            "lat": String(lat),
            "lng": String(lng),
            "date": ISO8601DateFormatter().string(from: date),
        ])
    }

    /// Up to 5 days out (OpenWeatherMap's free-tier forecast horizon) — for
    /// the Home screen's weather badge tap, not tied to any specific Plan date.
    static func daily(lat: Double, lng: Double) async throws -> DailyForecastResponse {
        try await APIClient.shared.get("/weather/daily", query: ["lat": String(lat), "lng": String(lng)])
    }
}

struct HoursCheckPlace: Encodable {
    var name: String
    var lat: Double
    var lng: Double
    /// Per-place override of `HoursCheckRequest.date` — see
    /// `CollectionDetailScreen.loadHoursIfNeeded` for why every stop
    /// shouldn't be checked against the exact same instant.
    var date: String?
}

struct HoursCheckRequest: Encodable {
    var places: [HoursCheckPlace]
    var date: String
}

struct HoursCheckResult: Decodable, Identifiable {
    var name: String
    var willBeOpen: Bool?
    var hoursFormatted: [String]?
    var id: String { name }
}

struct HoursCheckResponse: Decodable {
    var results: [HoursCheckResult]
}

enum PlanSchedulingAPI {
    static func checkHours(_ request: HoursCheckRequest) async throws -> HoursCheckResponse {
        try await APIClient.shared.post("/places/hours-check", body: request)
    }
}

struct PhotoBulkPlace: Encodable {
    var name: String
    var lat: Double
    var lng: Double
    /// `POIPlace.categoryLabel` — lets the backend's Wikipedia lookup only
    /// trust a distance-only fallback match (no literal name overlap) for
    /// categories where a Wikipedia article is actually plausible, instead
    /// of ever attaching an unrelated nearby landmark's photo to a shop.
    var category: String?
}

struct PhotoBulkRequest: Encodable {
    var places: [PhotoBulkPlace]
}

struct PhotoBulkResult: Decodable {
    var name: String
    var photoUrl: String?
    var source: String?
    var attributionUrl: String?
    /// Unsplash-only — their API Terms require naming the photographer, not
    /// just linking through to Unsplash. `nil` for Wikipedia/Tripadvisor.
    var photographerName: String?
    var photographerUrl: String?
}

struct PhotoBulkResponse: Decodable {
    var results: [PhotoBulkResult]
}

extension PlacesAPI {
    /// Cache-first — the same request shape hitting the same places
    /// repeatedly (any two people browsing the same city) resolves from
    /// `poi_photo_cache` server-side after the first live lookup, not one
    /// live Tripadvisor/Wikipedia call per card per screen load. `token`
    /// is optional, same contract as `explainPOI` above — pass
    /// `authStore.token` whenever one exists so a paid account can get a
    /// live Google photo layered onto an otherwise-Unsplash grid result.
    static func photosBulk(_ request: PhotoBulkRequest, token: String? = nil) async throws -> PhotoBulkResponse {
        try await APIClient.shared.post("/places/photos-bulk", body: request, bearerToken: token)
    }

    /// On-demand only — called when the reviews sheet actually opens, not
    /// as part of the initial POI card load.
    static func reviews(_ request: ReviewsRequest) async throws -> ReviewsResponse {
        try await APIClient.shared.post("/places/reviews", body: request)
    }

    /// Paid-tier-only (basic/pro) — 403s for a free account, 429s once the
    /// month's `google_places` quota is spent. See `PremiumDetailsSection`.
    static func premiumDetails(_ request: PremiumDetailsRequest, token: String) async throws -> PremiumPlaceDetails {
        try await APIClient.shared.post("/places/premium-details", body: request, bearerToken: token)
    }
}
