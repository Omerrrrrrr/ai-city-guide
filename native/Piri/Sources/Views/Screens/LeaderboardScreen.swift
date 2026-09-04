import SwiftUI

/// Faz 2: public leaderboard, ranked by `xp`. Only accounts that opted in
/// (`leaderboardVisible`, default true) appear -- see `getLeaderboard` in
/// social.ts. Read-only, no per-row navigation (unlike `FriendsScreen`'s
/// friend rows) since these aren't necessarily people you're connected to.
struct LeaderboardScreen: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FriendsStore.self) private var friendsStore

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            } else if entries.isEmpty {
                Text("friends.list.empty").font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 14) {
                            Text("\(index + 1)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)
                            LevelBadge(level: entry.level)
                            Text(entry.name ?? entry.id).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                            Spacer()
                            if let xp = entry.xp {
                                Text("\(xp) XP").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardFill))
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("friends.leaderboard.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let token = authStore.token {
                entries = await friendsStore.fetchLeaderboard(token: token)
            }
            isLoading = false
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}
