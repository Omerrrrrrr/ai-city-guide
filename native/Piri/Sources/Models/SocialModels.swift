import Foundation

/// One entry in a friends/incoming/outgoing list -- `GET /social/follows`
/// returns the same shape for all three, just partitioned by relationship
/// state. `username` is `nil` only in the never-actually-happens case of a
/// relationship existing with an account that hasn't claimed one yet (the
/// client always claims a username before this screen is reachable).
struct SocialUser: Codable, Identifiable, Equatable {
    let id: String
    let username: String?
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

struct FollowRequestBody: Encodable {
    let username: String
}

/// All-optional/partial by design, same convention as `SyncPushRequest` --
/// a toggle flip only ever sends the one flag that changed.
struct SharingPreferencesRequest: Encodable {
    var shareXp: Bool?
    var shareTripStats: Bool?
    var shareTripHistory: Bool?
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
/// `id`/`username` is `nil` unless that specific category is turned on,
/// mirroring the backend's per-category opt-in
/// (`toSharedFriendProfile` in social.ts) exactly.
struct FriendProfile: Decodable {
    let id: String
    let username: String?
    let xp: Int?
    let level: Int?
    let completedTripCount: Int?
    let tripHistory: [TripHistoryEntry]?
}

struct OkResponse: Decodable {
    let ok: Bool
}
