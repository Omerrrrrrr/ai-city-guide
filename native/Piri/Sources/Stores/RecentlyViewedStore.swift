import Foundation
import Observation

private let maxRecent = 8

private struct RecentlyViewedState: Codable {
    var viewed: [SavedPOIReference] = []
}

/// Port of `mobile/src/store/recently-viewed.ts`.
@Observable
final class RecentlyViewedStore {
    private(set) var viewed: [SavedPOIReference] = []

    private let persistence = UserDefaultsStore<RecentlyViewedState>(key: "recently-viewed")

    init() {
        if let saved = persistence.load() {
            viewed = saved.viewed
        }
    }

    func markViewed(_ poi: POIPlace) {
        let reference = poi.asReference
        var filtered = viewed.filter { $0.identifier != reference.identifier }
        filtered.insert(reference, at: 0)
        viewed = Array(filtered.prefix(maxRecent))
        persistence.save(RecentlyViewedState(viewed: viewed))
    }

    func clearHistory() {
        viewed = []
        persistence.save(RecentlyViewedState(viewed: viewed))
    }
}
