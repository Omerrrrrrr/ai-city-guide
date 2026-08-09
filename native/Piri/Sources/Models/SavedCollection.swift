import Foundation

/// A user-named group of saved places — e.g. "Weekend trip" or "Restaurants
/// to try" — independent of the built-in Favorites/Plan buckets. A place can
/// be in any number of collections at once (not exclusive membership), same
/// tagging-not-filing model `SavedPlacesStore.favorites`/`.plan` already use.
struct SavedCollection: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Double
    var places: [SavedPOIReference]
}
