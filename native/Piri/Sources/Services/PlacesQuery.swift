import Foundation
import Observation

/// Port of `usePlaces`/`usePlace` in `mobile/src/hooks/use-places.ts`: a
/// shared, cache-then-network places query. One instance lives in the
/// environment so Home/Explore/Saved/Place Detail all see the same list
/// instead of each re-fetching independently.
@Observable
final class PlacesQuery {
    private(set) var places: [Place] = []
    private(set) var isLoading = true
    private(set) var isStale = false
    private(set) var errorMessage: String?

    private var lastCityName: String?
    private var lastLat: Double?
    private var lastLng: Double?

    private func cacheKey(cityName: String?) -> String {
        "places_cache_v1_\(cityName ?? "__all__")"
    }

    func load(cityName: String?, lat: Double?, lng: Double?) async {
        lastCityName = cityName
        lastLat = lat
        lastLng = lng

        isLoading = true
        errorMessage = nil

        let key = cacheKey(cityName: cityName)
        let cache = UserDefaultsStore<[Place]>(key: key)
        var hadCache = false
        if let cached = cache.load() {
            places = cached
            isStale = true
            isLoading = false
            hadCache = true
        }

        do {
            let fetched = try await PlacesAPI.fetchPlaces(city: cityName, lat: lat, lng: lng)
            places = fetched
            isStale = false
            cache.save(fetched)
        } catch {
            if !hadCache {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func refresh() async {
        await load(cityName: lastCityName, lat: lastLat, lng: lastLng)
    }

    func place(id: String) -> Place? {
        places.first { $0.id == id }
    }

    func nearby(to place: Place, limit: Int = 3) -> [PlaceWithDistance] {
        guard let location = place.location else { return [] }
        return places
            .filter { $0.id != place.id }
            .compactMap { other -> PlaceWithDistance? in
                guard let otherLocation = other.location else { return nil }
                return PlaceWithDistance(
                    place: other,
                    distanceKm: geoDistanceKm(location.lat, location.lng, otherLocation.lat, otherLocation.lng)
                )
            }
            .sorted { $0.distanceKm < $1.distanceKm }
            .prefix(limit)
            .map { $0 }
    }

    func nearbyUser(lat: Double, lng: Double, limit: Int = 6) -> [PlaceWithDistance] {
        places
            .compactMap { place -> PlaceWithDistance? in
                guard let location = place.location else { return nil }
                return PlaceWithDistance(place: place, distanceKm: geoDistanceKm(lat, lng, location.lat, location.lng))
            }
            .sorted { $0.distanceKm < $1.distanceKm }
            .prefix(limit)
            .map { $0 }
    }
}
