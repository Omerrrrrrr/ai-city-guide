import Foundation

/// XP/level score, deliberately just derived from data the app already
/// tracks (profile completeness, saved places, completed trips, recently-
/// viewed count) rather than a separately persisted XP counter or event
/// log — there's nothing to keep in sync, migrate, or lose: the level
/// shown always matches exactly what the current state says the user has
/// done. Shared with mutual-follow friends who opt in via `shareXp` — see
/// `RootView`'s stats push, `FriendProfileScreen`, and the opt-in
/// `LeaderboardScreen` ranked by this same score.
enum Gamification {
    static let xpPerLevel = 100

    static func xp(profile: UserProfile, savedPlaceCount: Int, completedTripCount: Int, visitedCount: Int, reviewCount: Int) -> Int {
        let profileXP = ProfileOptions.summaryParts(for: profile).count * 20
        let savedXP = savedPlaceCount * 5
        let tripXP = completedTripCount * 50
        // Recently-viewed is the lowest-effort signal (just opening a
        // card) -- capped so it can't dominate the score the way actually
        // saving a place or completing a trip should.
        let visitedXP = min(visitedCount, 30) * 2
        // Writing a review is a real, useful contribution -- weighted
        // above a save (5) but below completing a whole trip (50).
        // Required, not defaulted -- every call site reads
        // `MyReviewsStore.count`, deliberately so a future call site that
        // forgets it fails to compile instead of silently under-counting
        // (which would show a different XP/level for the same person
        // depending which screen computed it).
        let reviewXP = reviewCount * 15
        return profileXP + savedXP + tripXP + visitedXP + reviewXP
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

    /// A flavor title alongside the raw level number -- every mockup this
    /// app's visual-design pass drew from gave the level a name ("Explorer"),
    /// not just a number, so this reuses that exact framing without adding
    /// any new tracked data (still purely a function of the same `level`
    /// value everything else here already computes).
    static func rankName(forLevel level: Int) -> String {
        switch level {
        case ..<3: return String(localized: "settings.rank.newcomer")
        case 3..<7: return String(localized: "settings.rank.explorer")
        case 7..<12: return String(localized: "settings.rank.wanderer")
        case 12..<20: return String(localized: "settings.rank.adventurer")
        default: return String(localized: "settings.rank.globetrotter")
        }
    }
}
