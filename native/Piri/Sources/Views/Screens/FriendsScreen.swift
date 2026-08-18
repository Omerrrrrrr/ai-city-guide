import SwiftUI

/// Faz 1 social layer -- push-navigated from `ProfileScreen`'s "Arkadaşlar"
/// card, same pattern `TripsScreen` uses. Own username + sharing
/// preferences sit at the top since they determine what the friends list
/// below can actually see, before add-friend, pending requests, and the
/// accepted-friends list itself.
struct FriendsScreen: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FriendsStore.self) private var friendsStore

    @State private var usernameInput = ""
    @State private var usernameError: String?
    @State private var isSavingUsername = false

    @State private var addFriendInput = ""
    @State private var addFriendError: String?
    @State private var isSendingRequest = false
    @State private var searchResults: [LeaderboardEntry] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                usernameSection
                sharingSection
                leaderboardLinkSection
                addFriendSection
                if !friendsStore.incomingRequests.isEmpty {
                    incomingRequestsSection
                }
                friendsSection
            }
            .padding(16)
        }
        .navigationTitle("friends.title")
        .task {
            usernameInput = authStore.user?.username ?? ""
            if let token = authStore.token {
                await friendsStore.fetchFollows(token: token)
            }
        }
    }

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("friends.username.label")
            HStack(spacing: 10) {
                TextField(String(localized: String.LocalizationValue("friends.username.placeholder")), text: $usernameInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await saveUsername() }
                } label: {
                    if isSavingUsername {
                        ProgressView()
                    } else {
                        Text("common.save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.gold)
                .disabled(
                    usernameInput.trimmingCharacters(in: .whitespaces).isEmpty
                        || isSavingUsername
                        || usernameInput == (authStore.user?.username ?? "")
                )
            }
            if let usernameError {
                Text(usernameError).font(.footnote).foregroundStyle(Theme.closedRed)
            }
        }
    }

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("friends.sharing.title")
            Toggle("friends.sharing.xp", isOn: Binding(
                get: { authStore.user?.shareXp ?? false },
                set: { authStore.updateSharingPreferences(shareXp: $0) }
            ))
            Toggle("friends.sharing.tripStats", isOn: Binding(
                get: { authStore.user?.shareTripStats ?? false },
                set: { authStore.updateSharingPreferences(shareTripStats: $0) }
            ))
            Toggle("friends.sharing.tripHistory", isOn: Binding(
                get: { authStore.user?.shareTripHistory ?? false },
                set: { authStore.updateSharingPreferences(shareTripHistory: $0) }
            ))
            Divider().padding(.vertical, 4)
            Toggle("friends.sharing.leaderboardVisible", isOn: Binding(
                get: { authStore.user?.leaderboardVisible ?? true },
                set: { authStore.updateSharingPreferences(leaderboardVisible: $0) }
            ))
            Toggle("friends.sharing.showRealName", isOn: Binding(
                get: { authStore.user?.showRealName ?? false },
                set: { authStore.updateSharingPreferences(showRealName: $0) }
            ))
        }
        .tint(Theme.gold)
    }

    private var leaderboardLinkSection: some View {
        NavigationLink(destination: LeaderboardScreen()) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                Text("friends.leaderboard.title").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                Spacer()
                Text("›").font(.system(size: 20)).foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    /// The text field doubles as exact-username entry (existing "İstek
    /// Gönder" button, Faz 1 behavior) *and* Faz 2 live search -- typing
    /// triggers a debounced `/social/search` (only Faz-2-visible accounts
    /// match), and tapping a result sends the request by id directly
    /// (`sendFollowRequest(toUserId:)`) rather than needing to know their
    /// exact username, since a result's displayed name might be their real
    /// name instead.
    private var addFriendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("friends.add.title")
            HStack(spacing: 10) {
                TextField(String(localized: String.LocalizationValue("friends.username.placeholder")), text: $addFriendInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: addFriendInput) { _, newValue in
                        scheduleSearch(newValue)
                    }
                Button {
                    Task { await sendRequest() }
                } label: {
                    if isSendingRequest {
                        ProgressView()
                    } else {
                        Text("friends.add.send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.gold)
                .disabled(addFriendInput.trimmingCharacters(in: .whitespaces).isEmpty || isSendingRequest)
            }
            if let addFriendError {
                Text(addFriendError).font(.footnote).foregroundStyle(Theme.closedRed)
            }
            if !searchResults.isEmpty {
                VStack(spacing: 6) {
                    ForEach(searchResults) { result in
                        Button {
                            Task { await sendRequest(toUserId: result.id) }
                        } label: {
                            HStack(spacing: 10) {
                                LevelBadge(level: result.level)
                                Text(result.name ?? result.id).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemGroupedBackground)))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSendingRequest)
                    }
                }
            }
        }
    }

    private var incomingRequestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("friends.requests.title")
            ForEach(friendsStore.incomingRequests) { request in
                HStack(spacing: 10) {
                    Text(request.name ?? request.id).font(.system(size: 15, weight: .medium))
                    Spacer()
                    Button("friends.requests.accept") {
                        Task { if let token = authStore.token { await friendsStore.accept(request, token: token) } }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gold)
                    Button("friends.requests.reject") {
                        Task { if let token = authStore.token { await friendsStore.reject(request, token: token) } }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("friends.list.title")
            if friendsStore.friends.isEmpty {
                Text("friends.list.empty").font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                ForEach(friendsStore.friends) { friend in
                    NavigationLink(destination: FriendProfileScreen(friendId: friend.id, name: friend.name)) {
                        HStack(spacing: 10) {
                            Circle().fill(Theme.gold.opacity(0.15)).frame(width: 36, height: 36)
                                .overlay(
                                    Text(String((friend.name ?? "?").prefix(1)).uppercased())
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Theme.gold)
                                )
                            Text(friend.name ?? friend.id).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                            Spacer()
                            Text("›").font(.system(size: 20)).foregroundStyle(.secondary.opacity(0.5))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionHeader(_ key: String) -> some View {
        Text(String(localized: String.LocalizationValue(key)))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func saveUsername() async {
        isSavingUsername = true
        usernameError = nil
        do {
            try await authStore.setUsername(usernameInput)
        } catch {
            usernameError = error.localizedDescription
        }
        isSavingUsername = false
    }

    private func sendRequest() async {
        isSendingRequest = true
        addFriendError = nil
        guard let token = authStore.token else {
            isSendingRequest = false
            return
        }
        do {
            try await friendsStore.sendFollowRequest(username: addFriendInput, token: token)
            addFriendInput = ""
            searchResults = []
        } catch {
            addFriendError = error.localizedDescription
        }
        isSendingRequest = false
    }

    /// Tapping a search result -- same flow as `sendRequest()` but by id,
    /// since a result's displayed `name` might be a real name rather than
    /// their actual username.
    private func sendRequest(toUserId userId: String) async {
        isSendingRequest = true
        addFriendError = nil
        guard let token = authStore.token else {
            isSendingRequest = false
            return
        }
        do {
            try await friendsStore.sendFollowRequest(toUserId: userId, token: token)
            addFriendInput = ""
            searchResults = []
        } catch {
            addFriendError = error.localizedDescription
        }
        isSendingRequest = false
    }

    /// Debounced (~400ms) so search doesn't fire on every keystroke;
    /// cancels the previous in-flight search rather than letting an older,
    /// slower response race a newer one and overwrite fresher results.
    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let token = authStore.token else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let results = await friendsStore.search(query: trimmed, token: token)
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }
}
