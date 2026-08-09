import Foundation
import Observation

private struct AdminAuthState: Codable {
    var adminToken: String?
}

/// Port of `mobile/src/store/admin-auth.ts`. Backs the dev-only admin
/// screens (Faz 7) — gated the same way the RN app gates them (build
/// configuration, not a hidden feature flag with real users behind it).
@Observable
final class AdminAuthStore {
    private(set) var adminToken: String?

    private let persistence = KeychainStore<AdminAuthState>(key: "ai-city-guide.admin-auth")

    init() {
        adminToken = persistence.load()?.adminToken
    }

    func setAdminToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        adminToken = trimmed.isEmpty ? nil : trimmed
        persistence.save(AdminAuthState(adminToken: adminToken))
    }

    func clearAdminToken() {
        adminToken = nil
        persistence.save(AdminAuthState(adminToken: nil))
    }
}
