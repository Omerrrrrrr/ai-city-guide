import Foundation

/// XP/level score, deliberately just derived from data the app already
/// tracks (profile completeness, saved places, completed trips, recently-
/// viewed count) rather than a separately persisted XP counter or event
/// log — there's nothing to keep in sync, migrate, or lose: the level
/// shown always matches exactly what the current state says the user has
/// done. Still no leaderboard and no public profile (see the
/// gamification/social idea memory this was scoped down from), but as of
/// Faz 1 this score IS shared with mutual-follow friends who opt in via
/// `shareXp` — see `RootView`'s stats push and `FriendProfileScreen`.
enum Gamification {
    static let xpPerLevel = 100

    static func xp(profile: UserProfile, savedPlaceCount: Int, completedTripCount: Int, visitedCount: Int) -> Int {
        let profileXP = ProfileOptions.summaryParts(for: profile).count * 20
        let savedXP = savedPlaceCount * 5
        let tripXP = completedTripCount * 50
        // Recently-viewed is the lowest-effort signal (just opening a
        // card) -- capped so it can't dominate the score the way actually
        // saving a place or completing a trip should.
        let visitedXP = min(visitedCount, 30) * 2
        return profileXP + savedXP + tripXP + visitedXP
    }

    static func level(forXP xp: Int) -> Int {
        xp / xpPerLevel + 1
    }

    static func xpRemainingToNextLevel(_ xp: Int) -> Int {
        xpPerLevel - (xp % xpPerLevel)
    }

    static func progressIntoCurrentLevel(_ xp: Int) -> Double {
        Double(xp % xpPerLevel) / Double(xpPerLevel)
    }
}
