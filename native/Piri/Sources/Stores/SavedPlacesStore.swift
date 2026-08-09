import Foundation
import Observation

private struct SavedPlacesState: Codable {
    var collections: [SavedCollection] = []
}

/// Port of `mobile/src/store/saved-places.ts`, since generalized: the app
/// used to have exactly one "Favorites" bucket and one "Plan" bucket, but
/// per the user's explicit choice both are now just user-named
/// `SavedCollection`s — someone can make as many named lists as they want
/// ("Weekend trip", "Cafes to try", ...), and any list of 2+ places can be
/// turned into an AI-optimized suggestion or an actual map route
/// (`CollectionDetailScreen`), not just a specially-named "Plan" one.
/// Backed by Keychain, like the RN store's `expo-secure-store` adapter —
/// saved places are treated as the closest thing this account-less app has
/// to personal data.
@Observable
final class SavedPlacesStore {
    private(set) var collections: [SavedCollection] = []

    private let persistence = KeychainStore<SavedPlacesState>(key: "ai-city-guide.saved-places")

    init() {
        if let saved = persistence.load() {
            collections = saved.collections
        }
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

    /// True if the given place is in *any* list — drives the bookmark
    /// icon's filled/outline state on a place's detail page.
    func isSaved(_ identifier: String) -> Bool {
        for collection in collections {
            if collection.places.contains(where: { $0.identifier == identifier }) { return true }
        }
        return false
    }

    func isIn(collection id: String, identifier: String) -> Bool {
        guard let collection = collections.first(where: { $0.id == id }) else { return false }
        return collection.places.contains { $0.identifier == identifier }
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
        persistence.save(SavedPlacesState(collections: collections))
    }
}
