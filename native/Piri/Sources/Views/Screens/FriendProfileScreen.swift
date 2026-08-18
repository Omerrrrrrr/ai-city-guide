import SwiftUI

/// Read-only view of a friend's profile -- shows exactly and only the
/// fields the backend actually returned, which is itself gated by that
/// friend's own `share*` flags (see `toSharedFriendProfile` in social.ts).
/// Never withholds anything on its own; a category the friend hasn't
/// shared renders an explicit "not shared" row rather than just omitting
/// it silently, so it's clear this is their choice, not a loading gap.
/// Id-based, matching `TripDetailScreen`/`CollectionDetailScreen`'s
/// convention -- `name` (that friend's chosen public display name, not
/// necessarily their literal username) is passed along from
/// `FriendsScreen`'s already-known row data purely for an instant title
/// before the fetch completes.
struct FriendProfileScreen: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FriendsStore.self) private var friendsStore

    let friendId: String
    let name: String?

    @State private var profile: FriendProfile?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let profile {
                    if let xp = profile.xp, let level = profile.level {
                        levelCard(xp: xp, level: level)
                    } else {
                        notSharedRow("friendProfile.category.xp")
                    }

                    if let count = profile.completedTripCount {
                        tripStatsCard(count: count)
                    } else {
                        notSharedRow("friendProfile.category.tripStats")
                    }

                    if let history = profile.tripHistory {
                        tripHistoryCard(history)
                    } else {
                        notSharedRow("friendProfile.category.tripHistory")
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(profile?.name ?? name ?? String(localized: String.LocalizationValue("friends.title")))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let token = authStore.token {
                profile = await friendsStore.fetchFriendProfile(id: friendId, token: token)
            }
            isLoading = false
        }
    }

    private func levelCard(xp: Int, level: Int) -> some View {
        HStack(spacing: 14) {
            LevelBadge(level: level)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("settings.xp.level", level)).font(.system(size: 15, weight: .semibold))
                Text(L("settings.xp.remaining", Gamification.xpRemainingToNextLevel(xp)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.18)))
    }

    private func tripStatsCard(count: Int) -> some View {
        Text(LPlural("trips.count", count: count))
            .font(.system(size: 15, weight: .medium))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.18)))
    }

    private func tripHistoryCard(_ history: [TripHistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("friendProfile.historyTitle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if history.isEmpty {
                Text("friends.list.empty").font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(history.enumerated()), id: \.offset) { _, entry in
                    HStack {
                        Text(entry.name).font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(entry.date).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.18)))
    }

    private func notSharedRow(_ categoryKey: String) -> some View {
        let categoryLabel = String(localized: String.LocalizationValue(categoryKey))
        return HStack(spacing: 8) {
            Image(systemName: "eye.slash").foregroundStyle(.secondary)
            Text(L("friendProfile.notShared", categoryLabel)).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }
}
