import Foundation

/// "Kaydedilen" collections are just for keeping places (no route/AI-plan
/// tools); "Plan" collections are meant to become an actual trip — they get
/// the "AI ile optimize et" / "Haritada Rota Oluştur" buttons in
/// `CollectionDetailScreen` once they have 2+ places. The user can create
/// any number of named lists of either kind (e.g. multiple named plans —
/// "Hafta Sonu", "Yaz Tatili" — and pick whichever one to act on later).
enum SavedCollectionKind: String, Codable, Identifiable {
    case saved, plan
    var id: Self { self }
}

/// A user-named group of saved places — e.g. "Weekend trip" (a plan) or
/// "Restaurants to try" (a saved list). A place can be in any number of
/// collections at once, of either kind (not exclusive membership).
struct SavedCollection: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: SavedCollectionKind
    var createdAt: Double
    var places: [SavedPOIReference]
}
