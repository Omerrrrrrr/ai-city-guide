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

    static func explain(_ request: ExplainRequest) async throws -> ExplainResult {
        try await APIClient.shared.post("/places/explain", body: request)
    }

    static func explainPOI(_ request: ExplainPOIRequest) async throws -> ExplainResult {
        try await APIClient.shared.post("/places/explain-poi", body: request)
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

enum WeatherAPI {
    static func fetch(lat: Double, lng: Double) async throws -> Weather {
        try await APIClient.shared.get("/weather", query: ["lat": String(lat), "lng": String(lng)])
    }
}
