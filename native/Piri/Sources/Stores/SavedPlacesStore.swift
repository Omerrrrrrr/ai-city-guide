import Foundation
import Observation

private struct SavedPlacesState: Codable {
    var favoritePlaceIds: Set<String> = []
    var planPlaceIds: [String] = []
}

/// Port of `mobile/src/store/saved-places.ts`. Backed by Keychain, like the
/// RN store's `expo-secure-store` adapter — favorites/plan are treated as
/// the closest thing this account-less app has to personal data.
@Observable
final class SavedPlacesStore {
    private(set) var favoritePlaceIds: Set<String> = []
    private(set) var planPlaceIds: [String] = []

    private let persistence = KeychainStore<SavedPlacesState>(key: "ai-city-guide.saved-places")

    init() {
        if let saved = persistence.load() {
            favoritePlaceIds = saved.favoritePlaceIds
            planPlaceIds = saved.planPlaceIds
        }
    }

    func isFavorite(_ placeId: String) -> Bool {
        favoritePlaceIds.contains(placeId)
    }

    func toggleFavorite(_ placeId: String) {
        if favoritePlaceIds.contains(placeId) {
            favoritePlaceIds.remove(placeId)
        } else {
            favoritePlaceIds.insert(placeId)
        }
        persist()
    }

    func isInPlan(_ placeId: String) -> Bool {
        planPlaceIds.contains(placeId)
    }

    func togglePlan(_ placeId: String) {
        if let index = planPlaceIds.firstIndex(of: placeId) {
            planPlaceIds.remove(at: index)
        } else {
            planPlaceIds.append(placeId)
        }
        persist()
    }

    func clearFavorites() {
        favoritePlaceIds = []
        persist()
    }

    func clearPlan() {
        planPlaceIds = []
        persist()
    }

    private func persist() {
        persistence.save(SavedPlacesState(favoritePlaceIds: favoritePlaceIds, planPlaceIds: planPlaceIds))
    }
}
