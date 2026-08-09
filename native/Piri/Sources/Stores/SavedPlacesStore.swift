import Foundation
import Observation

private struct SavedPlacesState: Codable {
    var favorites: [SavedPOIReference] = []
    var plan: [SavedPOIReference] = []
}

/// Port of `mobile/src/store/saved-places.ts`. Backed by Keychain, like the
/// RN store's `expo-secure-store` adapter — favorites/plan are treated as
/// the closest thing this account-less app has to personal data. Stores
/// `SavedPOIReference` snapshots (Apple POI data) rather than curated place
/// ids, since there's no curated database left to re-fetch from.
@Observable
final class SavedPlacesStore {
    private(set) var favorites: [SavedPOIReference] = []
    private(set) var plan: [SavedPOIReference] = []

    private let persistence = KeychainStore<SavedPlacesState>(key: "ai-city-guide.saved-places")

    init() {
        if let saved = persistence.load() {
            favorites = saved.favorites
            plan = saved.plan
        }
    }

    func isFavorite(_ identifier: String) -> Bool {
        favorites.contains { $0.identifier == identifier }
    }

    /// No-op if `poi.asReference` is `nil` (identifier unavailable) —
    /// nothing to persist in that case.
    func toggleFavorite(_ poi: POIPlace) {
        guard let reference = poi.asReference else { return }
        if let index = favorites.firstIndex(where: { $0.identifier == reference.identifier }) {
            favorites.remove(at: index)
        } else {
            favorites.append(reference)
        }
        persist()
    }

    func isInPlan(_ identifier: String) -> Bool {
        plan.contains { $0.identifier == identifier }
    }

    func togglePlan(_ poi: POIPlace) {
        guard let reference = poi.asReference else { return }
        if let index = plan.firstIndex(where: { $0.identifier == reference.identifier }) {
            plan.remove(at: index)
        } else {
            plan.append(reference)
        }
        persist()
    }

    func clearFavorites() {
        favorites = []
        persist()
    }

    func clearPlan() {
        plan = []
        persist()
    }

    private func persist() {
        persistence.save(SavedPlacesState(favorites: favorites, plan: plan))
    }
}
