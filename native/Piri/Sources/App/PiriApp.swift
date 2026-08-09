import SwiftUI

@main
struct PiriApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var cityStore = CityStore()
    @State private var userProfileStore = UserProfileStore()
    @State private var savedPlacesStore = SavedPlacesStore()
    @State private var tripsStore = TripsStore()
    @State private var recentlyViewedStore = RecentlyViewedStore()
    @State private var adminAuthStore = AdminAuthStore()
    @State private var placesQuery = PlacesQuery()
    @State private var languageStore = LanguageStore()

    init() {
        SentryConfig.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(cityStore)
                .environment(userProfileStore)
                .environment(savedPlacesStore)
                .environment(tripsStore)
                .environment(recentlyViewedStore)
                .environment(adminAuthStore)
                .environment(placesQuery)
                .environment(languageStore)
                .environment(PushNotificationManager.shared)
        }
    }
}
