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
    @State private var authStore = AuthStore()
    @State private var friendsStore = FriendsStore()
    @State private var placesQuery = PlacesQuery()
    @State private var languageStore = LanguageStore()
    @State private var purchaseStore = PurchaseStore()
    @State private var appearanceStore = AppearanceStore()
    @State private var weatherCitiesStore = WeatherCitiesStore()
    @State private var mapsProviderStore = MapsProviderStore()

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
                .environment(authStore)
                .environment(friendsStore)
                .environment(placesQuery)
                .environment(languageStore)
                .environment(purchaseStore)
                .environment(appearanceStore)
                .environment(weatherCitiesStore)
                .environment(mapsProviderStore)
                .environment(PushNotificationManager.shared)
                .preferredColorScheme(appearanceStore.scheme)
        }
    }
}
