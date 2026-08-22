import Foundation

/// Everything the Trip Recap story's cards need, assembled once right when
/// a trip ends (see `MapScreen+RouteMode.swift`'s `endRoute()`). Friends
/// comparison and leaderboard rank are best-effort and may come back
/// empty/nil -- same swallow-on-failure contract every other
/// `FriendsStore` method already uses (offline, no friends, or stats not
/// shared), so the Social card just omits itself rather than erroring.
struct TripRecapData {
    let trip: Trip
    let dominantCategory: (icon: String, label: String)?
    let xpBefore: Int
    let xpAfter: Int
    let levelBefore: Int
    let levelAfter: Int
    /// Lifetime completed-trip-count standing against friends who opted
    /// into `shareTripStats` -- NOT a per-trip "stops visited" comparison.
    /// A friend's stop count for this one trip isn't data Piri has (trips
    /// aren't shared object-for-object between friends, only aggregate
    /// stats via `FriendProfile`), so comparing lifetime trip counts is
    /// the honest version of this card rather than inventing a number.
    var friendsComparison: [(name: String, theirTripCount: Int)] = []
    var myLifetimeTripCount: Int = 0
    var leaderboardRank: Int?

    var xpDelta: Int { xpAfter - xpBefore }
    var leveledUp: Bool { levelAfter > levelBefore }

    static func build(
        trip: Trip,
        xpBefore: Int,
        xpAfter: Int,
        levelBefore: Int,
        levelAfter: Int,
        myLifetimeTripCount: Int,
        myUserId: String?,
        friendsStore: FriendsStore,
        token: String?
    ) async -> TripRecapData {
        var data = TripRecapData(
            trip: trip,
            dominantCategory: trip.dominantCategory,
            xpBefore: xpBefore,
            xpAfter: xpAfter,
            levelBefore: levelBefore,
            levelAfter: levelAfter,
            myLifetimeTripCount: myLifetimeTripCount
        )

        guard let token else { return data }

        // Up to 2 friends, matching the approved design -- best-effort,
        // a friend with trip-stats sharing off just comes back with a nil
        // completedTripCount and is skipped rather than shown as 0.
        for friend in friendsStore.friends.prefix(2) {
            if let profile = await friendsStore.fetchFriendProfile(id: friend.id, token: token),
               let theirCount = profile.completedTripCount {
                data.friendsComparison.append((name: profile.name ?? friend.name ?? "", theirTripCount: theirCount))
            }
        }

        if let myUserId {
            let leaderboard = await friendsStore.fetchLeaderboard(token: token)
            data.leaderboardRank = leaderboard.firstIndex(where: { $0.id == myUserId }).map { $0 + 1 }
        }

        return data
    }
}
