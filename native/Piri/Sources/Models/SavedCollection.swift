import Foundation

/// A user-named group of saved places — e.g. "Weekend trip" or "Restaurants
/// to try". This is the *only* way a place is saved now — the app used to
/// also have separate built-in "Favorites" and "Plan" buckets, but per the
/// user's explicit choice both became just user-named collections like any
/// other. A place can be in any number of collections at once (not
/// exclusive membership).
struct SavedCollection: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Double
    var places: [SavedPOIReference]
}
