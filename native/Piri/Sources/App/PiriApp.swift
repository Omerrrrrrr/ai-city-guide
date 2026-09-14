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
    @State private var weatherCitiesStore = WeatherCitiesStore()
    @State private var mapsProviderStore = MapsProviderStore()
    @State private var preferredCurrencyStore = PreferredCurrencyStore()
    @State private var myReviewsStore = MyReviewsStore()

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
                .environment(weatherCitiesStore)
                .environment(mapsProviderStore)
                .environment(preferredCurrencyStore)
                .environment(myReviewsStore)
                .environment(PushNotificationManager.shared)
                // The app has no working light theme -- every screen's own
                // colors (`Theme.swift`) are fixed dark-navy RGB values,
                // not adaptive ones, so this is the honest, explicit
                // statement of that instead of leaving it to whichever
                // screens remember to force `.dark` themselves. A tester
                // confirmed the old Settings Açık/Koyu/Sistem picker did
                // nothing visible -- removed there rather than left as a
                // choice with no effect.
                .preferredColorScheme(.dark)
        }
    }
}
