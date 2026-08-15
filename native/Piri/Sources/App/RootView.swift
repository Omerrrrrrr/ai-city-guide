import SwiftUI

/// Port of `mobile/app/index.tsx`'s redirect gate: wait for local profile
/// state to hydrate, then route to onboarding or the main tabs.
struct RootView: View {
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(TripsStore.self) private var tripsStore
    @Environment(AuthStore.self) private var authStore

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
        // Best-effort background sync on every local change while signed in
        // -- each of these is a no-op when signed out. Account sign-in
        // itself is optional and lives in ProfileScreen, not gated here.
        .onChange(of: userProfileStore.profile) { _, newValue in
            authStore.pushSync(SyncPushRequest(profile: newValue))
        }
        .onChange(of: savedPlacesStore.collections) { _, newValue in
            authStore.pushSync(SyncPushRequest(savedPlaces: newValue))
        }
        .onChange(of: tripsStore.trips) { _, newValue in
            authStore.pushSync(SyncPushRequest(trips: newValue))
        }
    }
}
