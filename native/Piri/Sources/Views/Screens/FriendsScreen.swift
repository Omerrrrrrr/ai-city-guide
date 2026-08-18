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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                usernameSection
                sharingSection
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
        }
        .tint(Theme.gold)
    }

    private var addFriendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("friends.add.title")
            HStack(spacing: 10) {
                TextField(String(localized: String.LocalizationValue("friends.username.placeholder")), text: $addFriendInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
        }
    }

    private var incomingRequestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("friends.requests.title")
            ForEach(friendsStore.incomingRequests) { request in
                HStack(spacing: 10) {
                    Text(request.username ?? request.id).font(.system(size: 15, weight: .medium))
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
                    NavigationLink(destination: FriendProfileScreen(friendId: friend.id, username: friend.username)) {
                        HStack(spacing: 10) {
                            Circle().fill(Theme.gold.opacity(0.15)).frame(width: 36, height: 36)
                                .overlay(
                                    Text(String((friend.username ?? "?").prefix(1)).uppercased())
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Theme.gold)
                                )
                            Text(friend.username ?? friend.id).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
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
        } catch {
            addFriendError = error.localizedDescription
        }
        isSendingRequest = false
    }
}
