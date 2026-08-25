import SwiftUI

/// Port of `mobile/app/index.tsx`'s redirect gate: wait for local profile
/// state to hydrate, then route to onboarding or the main tabs.
struct RootView: View {
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(TripsStore.self) private var tripsStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(AuthStore.self) private var authStore
    @Environment(PurchaseStore.self) private var purchaseStore

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
            pushStats()
        }
        .onChange(of: savedPlacesStore.collections) { _, _ in pushStats() }
        .onChange(of: userProfileStore.profile) { _, _ in pushStats() }
        // Runs for the app's whole lifetime -- picks up a purchase made
        // outside `PurchaseStore.purchase(_:)`'s own call (another device,
        // a renewal, App Store's own restore UI) and verifies+syncs it the
        // same way. Was documented on `PurchaseStore` since it shipped but
        // never actually started anywhere until now -- StoreKit purchases
        // were reaching this app with nothing listening for them.
        .task {
            await purchaseStore.observeTransactionUpdates(authStore: authStore)
        }
    }

    /// Recomputes `Gamification.xp(...)` (same inputs `ProfileScreen`'s
    /// `xpLevelCard` already uses) and pushes it, alongside the raw trip
    /// history a friend's shared profile can show, whenever any of those
    /// inputs change. Privacy is enforced server-side (see
    /// `toSharedFriendProfile` in social.ts) purely by this account's own
    /// `share*` flags -- the client always pushes the full computed value,
    /// same as it always pushes the full sync blobs regardless of who (if
    /// anyone) is signed in to read them.
    private func pushStats() {
        let completedTrips = tripsStore.trips.filter { $0.endedAt != nil }
        let savedPlaceCount = savedPlacesStore.collections.reduce(0) { $0 + $1.places.count }
        let xp = Gamification.xp(
            profile: userProfileStore.profile,
            savedPlaceCount: savedPlaceCount,
            completedTripCount: completedTrips.count,
            visitedCount: recentlyViewedStore.viewed.count
        )
        let history = completedTrips.map {
            TripHistoryEntry(name: $0.displayTitle, date: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0.startedAt / 1000)))
        }
        authStore.pushStats(StatsPushRequest(xp: xp, completedTripCount: completedTrips.count, sharedTripHistory: history))
    }
}
