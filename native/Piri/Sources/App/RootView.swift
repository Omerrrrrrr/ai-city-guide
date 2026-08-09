import SwiftUI

/// Port of `mobile/app/index.tsx`'s redirect gate: wait for local profile
/// state to hydrate, then route to onboarding or the main tabs.
struct RootView: View {
    @Environment(UserProfileStore.self) private var userProfileStore

    var body: some View {
        Group {
            if !userProfileStore.hasHydrated {
                Color.clear
            } else if userProfileStore.profile.onboardingCompleted {
                MainTabView()
            } else {
                OnboardingScreen()
            }
        }
    }
}
