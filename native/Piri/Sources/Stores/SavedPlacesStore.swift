import Foundation
import Observation

private struct SavedPlacesState: Codable {
    var favorites: [SavedPOIReference] = []
    var plan: [SavedPOIReference] = []
    var collections: [SavedCollection] = []
}

/// Port of `mobile/src/store/saved-places.ts`. Backed by Keychain, like the
/// RN store's `expo-secure-store` adapter — favorites/plan are treated as
/// the closest thing this account-less app has to personal data. Stores
/// `SavedPOIReference` snapshots (Apple POI data) rather than curated place
/// ids, since there's no curated database left to re-fetch from.
///
/// `collections` are user-named groups on top of favorites/plan (e.g.
/// "Weekend trip") — a place can be in any number of them at once, same
/// tagging-not-filing model favorites/plan already use relative to each
/// other (a place can be both favorited and planned).
@Observable
final class SavedPlacesStore {
    private(set) var favorites: [SavedPOIReference] = []
    private(set) var plan: [SavedPOIReference] = []
    private(set) var collections: [SavedCollection] = []

    private let persistence = KeychainStore<SavedPlacesState>(key: "ai-city-guide.saved-places")

    init() {
        if let saved = persistence.load() {
            favorites = saved.favorites
            plan = saved.plan
            collections = saved.collections
        }
    }

    func isFavorite(_ identifier: String) -> Bool {
        favorites.contains { $0.identifier == identifier }
    }

    func toggleFavorite(_ poi: POIPlace) {
        let reference = poi.asReference
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
        let reference = poi.asReference
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

    @discardableResult
    func createCollection(name: String) -> String {
        let id = "collection-\(Int(Date().timeIntervalSince1970 * 1000))"
        collections.append(SavedCollection(id: id, name: name, createdAt: Date().timeIntervalSince1970 * 1000, places: []))
        persist()
        return id
    }

    func renameCollection(_ id: String, name: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = name
        persist()
    }

    func deleteCollection(_ id: String) {
        collections.removeAll { $0.id == id }
        persist()
    }

    func isIn(collection id: String, identifier: String) -> Bool {
        collections.first { $0.id == id }?.places.contains { $0.identifier == identifier } ?? false
    }

    func toggle(_ poi: POIPlace, inCollection id: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let reference = poi.asReference
        if let placeIndex = collections[index].places.firstIndex(where: { $0.identifier == reference.identifier }) {
            collections[index].places.remove(at: placeIndex)
        } else {
            collections[index].places.append(reference)
        }
        persist()
    }

    func removeFromCollection(_ id: String, identifier: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].places.removeAll { $0.identifier == identifier }
        persist()
    }

    private func persist() {
        persistence.save(SavedPlacesState(favorites: favorites, plan: plan, collections: collections))
    }
}
