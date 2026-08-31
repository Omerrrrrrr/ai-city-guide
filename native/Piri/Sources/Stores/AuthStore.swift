import Foundation
import Observation

private struct AuthState: Codable {
    var token: String?
    var user: AuthUser?
}

/// Optional account layer on top of the app's existing local-only stores.
/// Sign-in is opt-in, not a gate -- the app works fully signed-out exactly
/// as it did before this store existed, and local data is never cleared on
/// sign-out (it just keeps working as offline/guest data). No `sessions`
/// table on the backend: the token here is a long-lived, self-issued JWT,
/// so signing out is just discarding it locally.
@Observable
final class AuthStore {
    private(set) var token: String?
    private(set) var user: AuthUser?

    var isSignedIn: Bool { token != nil }

    private let persistence = KeychainStore<AuthState>(key: "ai-city-guide.auth")

    init() {
        let saved = persistence.load()
        token = saved?.token
        user = saved?.user
    }

    func signOut() {
        token = nil
        user = nil
        persistence.clear()
    }

    func signInWithApple(identityToken: String, email: String?, fullName: String?) async throws {
        let response = try await AuthAPI.signInWithApple(identityToken: identityToken, email: email, fullName: fullName)
        setSession(response)
    }

    func register(email: String, password: String, displayName: String?) async throws {
        let response = try await AuthAPI.register(email: email, password: password, displayName: displayName)
        setSession(response)
    }

    func logIn(email: String, password: String) async throws {
        let response = try await AuthAPI.logIn(email: email, password: password)
        setSession(response)
    }

    /// Runs once right after sign-in succeeds. For each of the 3 synced
    /// keys: the server's value wins if it has one, otherwise whatever's on
    /// this device gets pushed up to seed the account. Whole-blob,
    /// last-write-wins -- not a field-level merge.
    func performInitialSync(
        userProfileStore: UserProfileStore,
        savedPlacesStore: SavedPlacesStore,
        tripsStore: TripsStore
    ) async {
        guard let token, let pulled = try? await AuthAPI.fetchSync(token: token) else { return }

        if let profile = pulled.profile?.value {
            userProfileStore.replaceProfile(profile)
        } else if userProfileStore.profile != UserProfile() {
            pushSync(SyncPushRequest(profile: userProfileStore.profile))
        }

        if let savedPlaces = pulled.savedPlaces?.value {
            savedPlacesStore.replaceCollections(savedPlaces)
        } else if !savedPlacesStore.collections.isEmpty {
            pushSync(SyncPushRequest(savedPlaces: savedPlacesStore.collections))
        }

        if let trips = pulled.trips?.value {
            tripsStore.replaceTrips(trips)
        } else if !tripsStore.trips.isEmpty {
            pushSync(SyncPushRequest(trips: tripsStore.trips))
        }
    }

    /// Re-pulls this account's own public fields (username, sharing
    /// preferences, xp/completedTripCount) -- these can change without a
    /// fresh sign-in (e.g. claiming a username on `FriendsScreen`), so a
    /// stale `user` from whenever the session token was issued isn't
    /// enough. Best-effort, same swallow-and-no-op-when-signed-out
    /// contract as `pushSync`.
    func refreshMe() async {
        guard let token, let refreshed = try? await AuthAPI.fetchMe(token: token) else { return }
        user = refreshed
        persistence.save(AuthState(token: token, user: refreshed))
    }

    /// Fire-and-forget background push, a no-op when signed out -- matches
    /// the app's existing `try?`-swallow style for non-critical network
    /// calls elsewhere (e.g. PlacesQuery's best-effort fetches).
    func pushSync(_ request: SyncPushRequest) {
        guard let token else { return }
        Task {
            try? await AuthAPI.pushSync(request, token: token)
        }
    }

    /// Same fire-and-forget contract as `pushSync`, for the Faz 1
    /// social-layer stats (`xp`/`completedTripCount`/`sharedTripHistory`)
    /// a friend's shared profile reads server-side.
    func pushStats(_ request: StatsPushRequest) {
        guard let token else { return }
        Task {
            try? await SocialAPI.pushStats(request, token: token)
        }
    }

    /// Throws (unlike the fire-and-forget pushes above) since this is a
    /// direct response to a user tapping "save" -- they need to see why it
    /// failed (already taken, invalid format), not have it silently no-op.
    func setUsername(_ username: String) async throws {
        guard let token else { return }
        let response = try await SocialAPI.setUsername(username, token: token)
        guard var updatedUser = user else { return }
        updatedUser.username = response.username
        setSession(AuthTokenResponse(token: token, user: updatedUser))
    }

    /// `nil` removes the current photo. Awaits the server round trip (unlike
    /// `updateSharingPreferences`'s optimistic update) since a failed upload
    /// shouldn't silently look like it succeeded -- the caller sees the throw.
    func updateAvatar(_ avatarUrl: String?) async throws {
        guard let token else { return }
        let response = try await SocialAPI.updateAvatar(avatarUrl, token: token)
        guard var updatedUser = user else { return }
        updatedUser.avatarUrl = response.avatarUrl
        setSession(AuthTokenResponse(token: token, user: updatedUser))
    }

    /// Optimistic local update (instant toggle feedback) + background push
    /// -- a wrong guess here just gets silently corrected on the next
    /// `refreshMe()`, same tolerance `pushSync`'s whole-blob overwrite
    /// already has for a lost/failed push.
    func updateSharingPreferences(
        shareXp: Bool? = nil,
        shareTripStats: Bool? = nil,
        shareTripHistory: Bool? = nil,
        leaderboardVisible: Bool? = nil,
        showRealName: Bool? = nil
    ) {
        guard let token, var updatedUser = user else { return }
        if let shareXp { updatedUser.shareXp = shareXp }
        if let shareTripStats { updatedUser.shareTripStats = shareTripStats }
        if let shareTripHistory { updatedUser.shareTripHistory = shareTripHistory }
        if let leaderboardVisible { updatedUser.leaderboardVisible = leaderboardVisible }
        if let showRealName { updatedUser.showRealName = showRealName }
        setSession(AuthTokenResponse(token: token, user: updatedUser))

        Task {
            try? await SocialAPI.updateSharingPreferences(
                SharingPreferencesRequest(
                    shareXp: shareXp,
                    shareTripStats: shareTripStats,
                    shareTripHistory: shareTripHistory,
                    leaderboardVisible: leaderboardVisible,
                    showRealName: showRealName
                ),
                token: token
            )
        }
    }

    private func setSession(_ response: AuthTokenResponse) {
        token = response.token
        user = response.user
        persistence.save(AuthState(token: response.token, user: response.user))
    }
}
