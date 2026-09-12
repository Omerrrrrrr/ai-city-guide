import AuthenticationServices
import Foundation
import Observation

private struct AuthState: Codable {
    var token: String?
    var user: AuthUser?
}

/// Optional account layer on top of the app's existing local-only stores.
/// Sign-in is opt-in, not a gate -- the app works fully signed-out exactly
/// as it did before this store existed. No `sessions` table on the
/// backend: the token here is a long-lived, self-issued JWT, so signing out
/// is just discarding it locally.
///
/// `signOut()` DOES clear the other local stores (saved places, trips,
/// profile, recently-viewed) -- it used to leave them alone entirely so a
/// signed-out session could keep working as "offline/guest data," but that
/// had a real cross-account leak: `performInitialSync` pushes local data to
/// the server to "seed" any account that has none server-side yet, so a
/// second person signing into their own (different, sync-empty) account on
/// the same device would inherit and permanently upload the first person's
/// saved places/trips/profile under their own account. Confirmed via a
/// review sweep, not hypothetical.
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

        // Fires if the user revokes Piri's Sign in with Apple access from
        // their Apple ID settings, entirely outside the app. Without this,
        // a locally "signed in" session would keep making authenticated API
        // calls with a token the backend may now consider invalid,
        // producing confusing repeated failures instead of a clean sign-out.
        // Deliberately only clears the session (token/user), not the local
        // data wipe `signOut()` does -- this is very likely still the same
        // person on the same device who just revoked API access, not a
        // second person taking over the device, so silently deleting their
        // saved places/trips here would be an unwanted, unrelated surprise.
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.clearSession() }
        }

        // Posted by `APIClient` on any 401 from an authenticated request --
        // an expired/revoked token used to surface as a generic error on
        // whatever screen happened to make the call, with nothing telling
        // the user (or the rest of the app) that re-authenticating is what
        // actually fixes it. Same "clear session, don't wipe local data"
        // reasoning as the Apple ID revocation case above.
        NotificationCenter.default.addObserver(
            forName: .piriAuthTokenExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.clearSession() }
        }
    }

    private func clearSession() {
        token = nil
        user = nil
        persistence.clear()
    }

    /// Explicit, user-initiated sign-out ("Sign Out" button) -- unlike
    /// `clearSession()` (used for the Apple ID revocation case above), this
    /// also wipes the other local stores. See this type's own doc comment
    /// for why: without it, a second person signing into their own account
    /// on the same device would inherit (and permanently upload) whatever
    /// the previous person left behind.
    func signOut(
        userProfileStore: UserProfileStore,
        savedPlacesStore: SavedPlacesStore,
        tripsStore: TripsStore,
        recentlyViewedStore: RecentlyViewedStore
    ) {
        clearSession()
        userProfileStore.resetProfile()
        savedPlacesStore.clearAllLocalData()
        tripsStore.clearAllLocalData()
        recentlyViewedStore.clearHistory()
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
