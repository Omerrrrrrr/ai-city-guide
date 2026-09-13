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
// Same irreplaceable-local-data risk `Trip.swift` documents on itself:
// this is persisted (Keychain) with no server-side-only copy, decoded as
// one `[SavedCollection]` array, and `KeychainStore` silently resets to
// empty on any decode failure. Any new field added here MUST be
// `Optional` or carry a default, following `AuthUser`'s already-established
// `decodeIfPresent(...) ?? default` pattern (AuthModels.swift) if this
// struct ever grows a custom decoder -- a plain non-optional, no-default
// field added the "normal" way would wipe every saved list and plan for
// every user on that device the next time this struct changes shape.
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
