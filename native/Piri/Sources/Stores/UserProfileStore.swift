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

    /// Called on sign-out ([[AuthStore.signOut]]) -- clears the personal
    /// onboarding answers (name/profession/faith/budget/travel style/
    /// interests) so a different person signing in afterward on the same
    /// device doesn't inherit them (or, via `AuthStore.performInitialSync`'s
    /// "push local data to seed the account" path, have them permanently
    /// uploaded under a different person's account). Deliberately keeps
    /// `onboardingCompleted` true regardless -- this device has already
    /// been through onboarding, and resetting that flag would incorrectly
    /// send whoever opens the app next back through the wizard, which
    /// signing out was never meant to trigger.
    func resetProfile() {
        var cleared = UserProfile()
        cleared.onboardingCompleted = true
        profile = cleared
        persistence.save(profile)
    }

    /// Overwrites local state with a pulled server copy (account sync only —
    /// never called from local editing flows, which go through `update`).
    func replaceProfile(_ newProfile: UserProfile) {
        profile = newProfile
        persistence.save(profile)
    }
}
