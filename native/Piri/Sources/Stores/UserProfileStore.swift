import Foundation
import Observation

/// Port of `mobile/src/store/user-profile.ts`. `hasHydrated` mirrors the RN
/// store's `_hasHydrated` flag, used by the root view to hold the
/// onboarding-vs-tabs redirect decision until local state has loaded.
@Observable
final class UserProfileStore {
    private(set) var profile = UserProfile()
    private(set) var hasHydrated = false

    private let persistence = UserDefaultsStore<UserProfile>(key: "piri.user-profile")

    init() {
        if let saved = persistence.load() {
            profile = saved
        }
        hasHydrated = true
    }

    func update(_ mutate: (inout UserProfile) -> Void) {
        mutate(&profile)
        persistence.save(profile)
    }

    func completeOnboarding() {
        profile.onboardingCompleted = true
        persistence.save(profile)
    }

    func resetProfile() {
        profile = UserProfile()
        persistence.save(profile)
    }

    var profileContext: String {
        buildProfileContext(profile)
    }
}
