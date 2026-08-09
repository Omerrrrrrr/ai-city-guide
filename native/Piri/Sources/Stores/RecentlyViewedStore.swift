import Foundation
import Observation

private let maxRecent = 8

private struct RecentlyViewedState: Codable {
    var viewedIds: [String] = []
}

/// Port of `mobile/src/store/recently-viewed.ts`.
@Observable
final class RecentlyViewedStore {
    private(set) var viewedIds: [String] = []

    private let persistence = UserDefaultsStore<RecentlyViewedState>(key: "recently-viewed")

    init() {
        if let saved = persistence.load() {
            viewedIds = saved.viewedIds
        }
    }

    func markViewed(_ id: String) {
        var filtered = viewedIds.filter { $0 != id }
        filtered.insert(id, at: 0)
        viewedIds = Array(filtered.prefix(maxRecent))
        persistence.save(RecentlyViewedState(viewedIds: viewedIds))
    }

    func clearHistory() {
        viewedIds = []
        persistence.save(RecentlyViewedState(viewedIds: viewedIds))
    }
}
