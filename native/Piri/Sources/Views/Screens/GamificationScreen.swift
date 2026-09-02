import SwiftUI

/// Drill-in from `ProfileScreen`'s header level badge -- pulls the bigger,
/// more detailed level/XP view and the Leaderboard link out of Profile's
/// main scroll, mirroring the Gemini mockup's separate "Gamification"
/// screen. Deliberately has no "Achievements" section: the app tracks no
/// actual achievement/badge data anywhere, and inventing one here would be
/// exactly the kind of ungrounded filler this app avoids elsewhere (see
/// the Trip Recap caption-text note in the same visual-design pass this
/// screen came out of).
struct GamificationScreen: View {
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(MyReviewsStore.self) private var myReviewsStore
    @Environment(TripsStore.self) private var tripsStore

    private var profile: UserProfile { userProfileStore.profile }

    private var savedPlaceCount: Int { savedPlacesStore.collections.reduce(0) { $0 + $1.places.count } }
    private var completedTripCount: Int { tripsStore.trips.filter { $0.endedAt != nil }.count }
    private var visitedCount: Int { recentlyViewedStore.viewed.count }
    private var reviewCount: Int { myReviewsStore.count }

    private var xp: Int {
        Gamification.xp(
            profile: profile,
            savedPlaceCount: savedPlaceCount,
            completedTripCount: completedTripCount,
            visitedCount: visitedCount,
            reviewCount: reviewCount
        )
    }
    private var level: Int { Gamification.level(forXP: xp) }

    private var breakdown: [(labelKey: String, points: Int, icon: String)] {
        [
            ("gamification.source.profile", ProfileOptions.summaryParts(for: profile).count * 20, "person.fill"),
            ("gamification.source.saved", savedPlaceCount * 5, "bookmark.fill"),
            ("gamification.source.trips", completedTripCount * 50, "suitcase.fill"),
            ("gamification.source.visited", min(visitedCount, 30) * 2, "eye.fill"),
            ("gamification.source.reviews", reviewCount * 15, "star.fill"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    LevelBadge(level: level, size: 100)
                    Text(L("settings.xp.level", level)).font(.system(size: 20, weight: .bold))
                    ProgressView(value: Gamification.progressIntoCurrentLevel(xp))
                        .tint(Theme.gold)
                        .frame(maxWidth: 220)
                    Text(L("settings.xp.remaining", Gamification.xpRemainingToNextLevel(xp)))
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "gamification.breakdown.title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    VStack(spacing: 10) {
                        ForEach(breakdown, id: \.labelKey) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.gold)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Theme.gold.opacity(0.12)))
                                Text(String(localized: String.LocalizationValue(item.labelKey)))
                                    .font(.system(size: 15))
                                Spacer()
                                Text("+\(item.points)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
                }
                .padding(.horizontal, 16)

                NavigationLink(destination: LeaderboardScreen()) {
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                        Text("friends.leaderboard.title").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        Spacer()
                        Text("›").font(.system(size: 20)).foregroundStyle(.secondary.opacity(0.5))
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
        .navigationTitle(String(localized: "gamification.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
