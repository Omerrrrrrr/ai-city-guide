import Foundation
import Observation

private struct SavedPlacesState: Codable {
    var collections: [SavedCollection] = []
}

/// Port of `mobile/src/store/saved-places.ts`, since generalized: "Kaydedilen"
/// and "Plan" both used to be exactly one flat bucket each — per the user's
/// explicit choice, both are now user-named `SavedCollection`s instead, so
/// someone can make multiple named saved-lists *and* multiple named plans
/// ("Hafta Sonu", "Yaz Tatili"), then pick whichever one to act on. Backed
/// by Keychain, like the RN store's `expo-secure-store` adapter — saved
/// places are treated as the closest thing this account-less app has to
/// personal data.
@Observable
final class SavedPlacesStore {
    private(set) var collections: [SavedCollection] = []

    var savedLists: [SavedCollection] { collections.filter { $0.kind == .saved } }
    var plans: [SavedCollection] { collections.filter { $0.kind == .plan } }

    private let persistence = KeychainStore<SavedPlacesState>(key: "ai-city-guide.saved-places")

    init() {
        if let saved = persistence.load() {
            collections = saved.collections
        }
    }

    /// `places` defaults to empty for the common "create then add one at a
    /// time" flow (`SavedScreen`) — `MapScreen`'s "Rotayı Kaydet" is the one
    /// caller that already has an ordered stop list in hand and wants it
    /// saved as-is in one shot, not built up place-by-place afterward.
    @discardableResult
    func createCollection(name: String, kind: SavedCollectionKind, places: [SavedPOIReference] = []) -> String {
        let id = "collection-\(Int(Date().timeIntervalSince1970 * 1000))"
        collections.append(SavedCollection(id: id, name: name, kind: kind, createdAt: Date().timeIntervalSince1970 * 1000, places: places))
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

    func setTargetDate(_ id: String, date: Double?) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].targetDate = date
        persist()
    }

    /// True if the given place is in any *saved* list — drives the bookmark
    /// icon's filled/outline state on a place's detail page.
    func isSaved(_ identifier: String) -> Bool {
        for collection in savedLists {
            if collection.places.contains(where: { $0.identifier == identifier }) { return true }
        }
        return false
    }

    /// True if the given place is in any *plan* — drives the plan icon's
    /// filled/outline state on a place's detail page.
    func isPlanned(_ identifier: String) -> Bool {
        for collection in plans {
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

    /// Manual reordering (not drag-and-drop — these rows live in a plain
    /// `VStack`/`ScrollView`, not a `List`, matching every other card list
    /// in the app) so a Plan's visiting order is actually editable, not just
    /// its membership.
    func moveInCollection(_ id: String, identifier: String, offset: Int) {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == id }) else { return }
        guard let placeIndex = collections[collectionIndex].places.firstIndex(where: { $0.identifier == identifier }) else { return }
        let targetIndex = placeIndex + offset
        guard collections[collectionIndex].places.indices.contains(targetIndex) else { return }
        collections[collectionIndex].places.swapAt(placeIndex, targetIndex)
        persist()
    }

    /// Native `List`/`.onMove` drag-reorder variant (used by
    /// `CollectionDetailScreen`'s reference list, matching
    /// `MapScreen+RouteMode.swift`'s `moveStops`/`plannedStops.move`) — same
    /// underlying persistence as `moveInCollection(_:identifier:offset:)`
    /// above, just driven by `IndexSet`/destination instead of a single
    /// adjacent swap.
    func moveInCollection(_ id: String, fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[collectionIndex].places.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    /// Overwrites local state with a pulled server copy (account sync only).
    func replaceCollections(_ newCollections: [SavedCollection]) {
        collections = newCollections
        persist()
    }

    private func persist() {
        persistence.save(SavedPlacesState(collections: collections))
    }
}
