import Foundation

/// Accounts + whole-blob sync. Same `bearerToken` plumbing `AdminAPI` already
/// uses -- a user session token instead of the static admin one.
enum AuthAPI {
    static func signInWithApple(identityToken: String, email: String?, fullName: String?) async throws -> AuthTokenResponse {
        try await APIClient.shared.post(
            "/auth/apple",
            body: AppleSignInRequest(identityToken: identityToken, email: email, fullName: fullName)
        )
    }

    static func register(email: String, password: String, displayName: String?) async throws -> AuthTokenResponse {
        try await APIClient.shared.post(
            "/auth/register",
            body: RegisterRequest(email: email, password: password, displayName: displayName)
        )
    }

    static func logIn(email: String, password: String) async throws -> AuthTokenResponse {
        try await APIClient.shared.post("/auth/login", body: LoginRequest(email: email, password: password))
    }

    static func fetchSync(token: String) async throws -> SyncPullResponse {
        try await APIClient.shared.get("/me/sync", bearerToken: token)
    }

    static func pushSync(_ request: SyncPushRequest, token: String) async throws {
        let _: SyncPushResponse = try await APIClient.shared.put("/me/sync", body: request, bearerToken: token)
    }
}
