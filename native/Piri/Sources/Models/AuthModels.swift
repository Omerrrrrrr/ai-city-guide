import Foundation

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String
    let displayName: String?
    /// Social-layer (Faz 1) fields -- `toPublicUser` on the backend already
    /// includes these on every `/auth/*` response and `/me`, so `AuthUser`
    /// carries this account's own username/sharing-preference/stat state
    /// alongside its existing identity fields rather than needing a
    /// separate fetch. `nil`/`false`/`0` for any account that predates
    /// this or hasn't touched it yet.
    var username: String?
    var shareXp: Bool = false
    var shareTripStats: Bool = false
    var shareTripHistory: Bool = false
    var xp: Int = 0
    var completedTripCount: Int = 0
    /// Faz 2 (public leaderboard/search) -- `leaderboardVisible` defaults
    /// `true` (unlike the Faz 1 `share*` flags above, which default off):
    /// a leaderboard needs entries to be worth anything, and it's still
    /// user-controllable, just not opt-in-from-empty the way friend-only
    /// sharing is. `showRealName` still defaults `false` (rumuz first).
    var leaderboardVisible: Bool = true
    var showRealName: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, email, displayName, username, shareXp, shareTripStats, shareTripHistory
        case xp, completedTripCount, leaderboardVisible, showRealName
    }

    // Custom decode: a non-optional property with a default value is NOT
    // automatically treated as "decode if present, else default" by
    // Swift's synthesized `Decodable` -- only `Optional` properties get
    // that `decodeIfPresent` treatment. Without this, every one of the
    // 7 fields above added after `AuthUser`'s original 3 would throw on
    // any Keychain-persisted `AuthState` written before that field
    // existed, and `KeychainStore.load()`'s `try?` would swallow that
    // into a silent, total sign-out (confirmed live: a real account
    // dropped out of `authStore.isSignedIn` this way after Faz 2 added
    // `leaderboardVisible`/`showRealName`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        shareXp = try container.decodeIfPresent(Bool.self, forKey: .shareXp) ?? false
        shareTripStats = try container.decodeIfPresent(Bool.self, forKey: .shareTripStats) ?? false
        shareTripHistory = try container.decodeIfPresent(Bool.self, forKey: .shareTripHistory) ?? false
        xp = try container.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        completedTripCount = try container.decodeIfPresent(Int.self, forKey: .completedTripCount) ?? 0
        leaderboardVisible = try container.decodeIfPresent(Bool.self, forKey: .leaderboardVisible) ?? true
        showRealName = try container.decodeIfPresent(Bool.self, forKey: .showRealName) ?? false
    }

    init(
        id: String,
        email: String,
        displayName: String?,
        username: String? = nil,
        shareXp: Bool = false,
        shareTripStats: Bool = false,
        shareTripHistory: Bool = false,
        xp: Int = 0,
        completedTripCount: Int = 0,
        leaderboardVisible: Bool = true,
        showRealName: Bool = false
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.username = username
        self.shareXp = shareXp
        self.shareTripStats = shareTripStats
        self.shareTripHistory = shareTripHistory
        self.xp = xp
        self.completedTripCount = completedTripCount
        self.leaderboardVisible = leaderboardVisible
        self.showRealName = showRealName
    }
}

struct AuthTokenResponse: Decodable {
    let token: String
    let user: AuthUser
}

struct AppleSignInRequest: Encodable {
    let identityToken: String
    let email: String?
    let fullName: String?
}

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let displayName: String?
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// Mirrors the backend's whole-blob sync shape 1:1: each of the three synced
/// stores already serializes itself to one JSON value for local persistence
/// (see UserDefaultsStore/KeychainStore), and the server stores/returns
/// exactly that same shape under a `value` + `updatedAt` envelope.
struct SyncEntry<Value: Codable>: Codable {
    let value: Value
    let updatedAt: String
}

struct SyncPullResponse: Decodable {
    let profile: SyncEntry<UserProfile>?
    let savedPlaces: SyncEntry<[SavedCollection]>?
    let trips: SyncEntry<[Trip]>?
}

/// Partial by design (all-optional, synthesized `Encodable` omits nil
/// members entirely) -- a push only ever carries whichever one store
/// actually changed, not the other two.
struct SyncPushRequest: Encodable {
    var profile: UserProfile?
    var savedPlaces: [SavedCollection]?
    var trips: [Trip]?
}

struct SyncPushResponse: Decodable {
    let updatedAt: String
}
