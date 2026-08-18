import Foundation
import Observation

/// Mutual-follow-only social layer (Faz 1) -- friends and pending follow
/// requests. Username and this account's own sharing preferences/stats
/// live on `AuthStore.user` instead (see `AuthUser`'s social fields):
/// they're this account's own public identity, the same place displayName/
/// email already live, not a "relationship to someone else" concept.
/// Every method here is a best-effort no-op when called without a token,
/// matching `AuthStore.pushSync`'s existing swallow-and-no-op contract.
@Observable
final class FriendsStore {
    private(set) var friends: [SocialUser] = []
    private(set) var incomingRequests: [SocialUser] = []
    private(set) var outgoingRequests: [SocialUser] = []

    func fetchFollows(token: String) async {
        guard let state = try? await SocialAPI.fetchFollowState(token: token) else { return }
        friends = state.friends
        incomingRequests = state.incomingRequests
        outgoingRequests = state.outgoingRequests
    }

    /// Throws (rather than swallowing) since this is always a direct
    /// response to a user tapping "send request" -- they need to see the
    /// error (username not found, already requested, etc.), not have it
    /// silently vanish.
    func sendFollowRequest(username: String, token: String) async throws {
        try await SocialAPI.sendFollowRequest(username: username, token: token)
        await fetchFollows(token: token)
    }

    func accept(_ request: SocialUser, token: String) async {
        try? await SocialAPI.acceptFollowRequest(from: request.id, token: token)
        await fetchFollows(token: token)
    }

    func reject(_ request: SocialUser, token: String) async {
        try? await SocialAPI.rejectFollowRequest(from: request.id, token: token)
        await fetchFollows(token: token)
    }

    func fetchFriendProfile(id: String, token: String) async -> FriendProfile? {
        try? await SocialAPI.fetchFriendProfile(friendId: id, token: token)
    }
}
