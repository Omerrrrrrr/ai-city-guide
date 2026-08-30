import Foundation
import Observation

private struct MyReviewsState: Codable {
    var count: Int = 0
}

/// Local, device-tracked count of Piri reviews this account has written --
/// same shape every other `Gamification.xp()` input already uses
/// (`TripsStore`, `SavedPlacesStore`, `RecentlyViewedStore` are all local,
/// UserDefaults-persisted, no server round trip for the count itself).
/// A review can later get flagged/rejected server-side (see the
/// trust-scaled moderation in `apps/api/src/index.ts`), but this
/// deliberately doesn't try to track that -- XP rewards the act of
/// contributing, same as a completed trip's XP not un-counting if the
/// trip is later deleted.
@Observable
final class MyReviewsStore {
    private(set) var count: Int

    private let persistence = UserDefaultsStore<MyReviewsState>(key: "my-reviews-count")

    init() {
        count = persistence.load()?.count ?? 0
    }

    /// Call only for a genuinely new review (`WriteReviewSheet`'s
    /// `existing == nil` case) -- editing an existing one re-uses the same
    /// upsert on the backend and shouldn't grant XP a second time.
    func recordReviewWritten() {
        count += 1
        persistence.save(MyReviewsState(count: count))
    }
}
