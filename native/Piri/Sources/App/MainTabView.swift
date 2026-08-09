import SwiftUI

/// Port of `mobile/app/(tabs)/_layout.tsx`. Explore and Saved are reachable
/// from within Home/Profile (the RN app hides them from the tab bar via
/// `href: null`), so they aren't top-level tabs here either.
struct MainTabView: View {
    @State private var tabSelection = TabSelection()

    @Environment(PushNotificationManager.self) private var pushManager
    @Environment(CityStore.self) private var cityStore

    var body: some View {
        TabView(selection: Bindable(tabSelection).selection) {
            NavigationStack {
                HomeScreen()
            }
            .tabItem { Label("tabs.home", systemImage: "house") }
            .tag(0)

            NavigationStack {
                ScanScreen()
            }
            .tabItem { Label("tabs.scan", systemImage: "camera.viewfinder") }
            .tag(1)

            NavigationStack {
                MapScreen()
            }
            .tabItem { Label("tabs.map", systemImage: "map") }
            .tag(2)

            NavigationStack {
                AIScreen()
            }
            .tabItem { Label("tabs.ai", systemImage: "sparkles") }
            .tag(3)

            NavigationStack {
                ProfileScreen()
            }
            .tabItem { Label("tabs.profile", systemImage: "person") }
            .tag(4)
        }
        .environment(tabSelection)
        .onChange(of: pushManager.pendingTapPayload) { _, payload in
            guard let payload else { return }
            cityStore.setCity(id: payload.cityId, name: payload.cityName)
            tabSelection.selection = 0
            pushManager.consumeTapPayload()
        }
    }
}
