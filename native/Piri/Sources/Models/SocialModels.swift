import Foundation

/// One entry in a friends/incoming/outgoing list -- `GET /social/follows`
/// returns the same shape for all three, just partitioned by relationship
/// state. `name` is that person's chosen public display name (their real
/// name if `showRealName` is on, their username otherwise -- see
/// `publicDisplayName` in social.ts), never necessarily their literal
/// username. `nil` only in the never-actually-happens case of a
/// relationship existing with an account that hasn't claimed a username
/// yet (the client always claims one before this screen is reachable).
struct SocialUser: Codable, Identifiable, Equatable {
    let id: String
    let name: String?
}

struct FollowState: Decodable {
    let friends: [SocialUser]
    let incomingRequests: [SocialUser]
    let outgoingRequests: [SocialUser]
}

struct UsernameRequest: Encodable {
    let username: String
}

struct UsernameResponse: Decodable {
    let username: String?
}

struct UsernameLookupResponse: Decodable {
    let id: String
    let username: String?
}

/// Either an exact username (manual "add friend" entry) or a userId
/// (tapping a Faz 2 search/leaderboard row, which only ever carries that
/// person's chosen public name -- see `sendFollowRequestByUserId` in
/// social.ts). Exactly one of the two is ever set.
struct FollowRequestBody: Encodable {
    var username: String?
    var userId: String?
}

/// All-optional/partial by design, same convention as `SyncPushRequest` --
/// a toggle flip only ever sends the one flag that changed. The first
/// three are Faz 1 (friend-only sharing, default off); the last two are
/// Faz 2 (public leaderboard/search) -- `leaderboardVisible` alone gates
/// both, `showRealName` picks which name is shown wherever this account
/// appears to someone else (leaderboard, search, friends list, friend
/// profile), independent of the friend-sharing flags above.
struct SharingPreferencesRequest: Encodable {
    var shareXp: Bool?
    var shareTripStats: Bool?
    var shareTripHistory: Bool?
    var leaderboardVisible: Bool?
    var showRealName: Bool?
}

struct TripHistoryEntry: Codable, Equatable {
    let name: String
    let date: String
}

struct StatsPushRequest: Encodable {
    var xp: Int?
    var completedTripCount: Int?
    var sharedTripHistory: [TripHistoryEntry]?
}

/// What a friend has actually chosen to share -- every field besides
/// `id`/`name` is `nil` unless that specific category is turned on,
/// mirroring the backend's per-category opt-in
/// (`toSharedFriendProfile` in social.ts) exactly. `name` (like
/// `SocialUser.name`) is their chosen public display name, not
/// necessarily their literal username.
struct FriendProfile: Decodable {
    let id: String
    let name: String?
    let xp: Int?
    let level: Int?
    let completedTripCount: Int?
    let tripHistory: [TripHistoryEntry]?
}

struct OkResponse: Decodable {
    let ok: Bool
}

/// Faz 2: one row of `GET /social/leaderboard` or `GET /social/search` --
/// same shape for both (search just never populates `xp`, only used for
/// leaderboard ranking display).
struct LeaderboardEntry: Decodable, Identifiable {
    let id: String
    let name: String?
    let level: Int
    let xp: Int?
}
