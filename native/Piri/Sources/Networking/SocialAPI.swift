import Foundation

/// Faz 1 social layer (mutual-follow, username, opt-in stat sharing) + Faz
/// 2 (public leaderboard/search). Same `bearerToken` plumbing
/// `AuthAPI`/`AdminAPI` already use.
enum SocialAPI {
    static func setUsername(_ username: String, token: String) async throws -> UsernameResponse {
        try await APIClient.shared.patch("/me/username", body: UsernameRequest(username: username), bearerToken: token)
    }

    /// `nil` removes the current photo. `avatarUrl` (when non-nil) must
    /// already be a `data:image/jpeg;base64,...` string -- see
    /// `ProfileScreen`'s avatar picker for the resize+encode step.
    static func updateAvatar(_ avatarUrl: String?, token: String) async throws -> AvatarResponse {
        try await APIClient.shared.patch("/me/avatar", body: AvatarRequest(avatarUrl: avatarUrl), bearerToken: token)
    }

    static func lookupUsername(_ username: String, token: String) async throws -> UsernameLookupResponse {
        try await APIClient.shared.get("/users/lookup", query: ["username": username], bearerToken: token)
    }

    static func sendFollowRequest(username: String, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.post(
            "/social/follow-requests",
            body: FollowRequestBody(username: username),
            bearerToken: token
        )
    }

    static func sendFollowRequest(toUserId userId: String, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.post(
            "/social/follow-requests",
            body: FollowRequestBody(userId: userId),
            bearerToken: token
        )
    }

    static func acceptFollowRequest(from followerId: String, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.post("/social/follow-requests/\(followerId)/accept", bearerToken: token)
    }

    static func rejectFollowRequest(from followerId: String, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.post("/social/follow-requests/\(followerId)/reject", bearerToken: token)
    }

    static func fetchFollowState(token: String) async throws -> FollowState {
        try await APIClient.shared.get("/social/follows", bearerToken: token)
    }

    static func updateSharingPreferences(_ request: SharingPreferencesRequest, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.patch("/me/sharing-preferences", body: request, bearerToken: token)
    }

    static func pushStats(_ request: StatsPushRequest, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.patch("/me/stats", body: request, bearerToken: token)
    }

    static func fetchFriendProfile(friendId: String, token: String) async throws -> FriendProfile {
        try await APIClient.shared.get("/social/friends/\(friendId)/profile", bearerToken: token)
    }

    static func fetchLeaderboard(limit: Int = 50, token: String) async throws -> [LeaderboardEntry] {
        try await APIClient.shared.get("/social/leaderboard", query: ["limit": String(limit)], bearerToken: token)
    }

    static func searchUsers(query: String, token: String) async throws -> [LeaderboardEntry] {
        try await APIClient.shared.get("/social/search", query: ["q": query], bearerToken: token)
    }
}
