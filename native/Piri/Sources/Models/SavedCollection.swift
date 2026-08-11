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
    /// Optional target date for a `.plan` collection (epoch seconds,
    /// day-granularity — the time-of-day component is ignored). Never
    /// meaningful for `.saved`-kind lists. `CollectionDetailScreen` fetches
    /// weather/hours fresh against this date each time it's opened rather
    /// than persisting them here — a forecast baked in once would just go
    /// stale.
    var targetDate: Double? = nil
}
