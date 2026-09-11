import SwiftUI

struct MainTabView: View {
    @State private var tabSelection = TabSelection()
    @Environment(PushNotificationManager.self) private var pushManager
    @Environment(CityStore.self) private var cityStore

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: Bindable(tabSelection).selection) {
                NavigationStack { HomeScreen() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(0)
                NavigationStack { ScanScreen() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(1)
                NavigationStack { MapScreen() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(2)
                NavigationStack { AIScreen() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(3)
                NavigationStack { ProfileScreen() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            navigationBar
        }
        .background(Theme.navy.ignoresSafeArea())
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .environment(tabSelection)
        .onChange(of: pushManager.pendingTapPayload) { _, payload in
            guard let payload else { return }
            cityStore.setCity(id: payload.cityId, name: payload.cityName)
            tabSelection.selection = 0
            pushManager.consumeTapPayload()
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            tabButton(0, title: String(localized: "design.tabs.explore"), icon: "house", selectedIcon: "house.fill")
            tabButton(1, title: String(localized: "tabs.scan"), icon: "camera", selectedIcon: "camera.fill")
            tabButton(2, title: String(localized: "tabs.map"), icon: "map", selectedIcon: "map.fill")
            tabButton(3, title: "Piri", icon: "sparkle", selectedIcon: "sparkle")
            tabButton(4, title: String(localized: "tabs.profile"), icon: "person", selectedIcon: "person.fill")
        }
        .padding(.top, 11)
        .padding(.bottom, 6)
        .background(Theme.navy.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }

    private func tabButton(_ index: Int, title: String, icon: String, selectedIcon: String) -> some View {
        let selected = tabSelection.selection == index
        return Button {
            Haptics.light()
            tabSelection.selection = index
        } label: {
            VStack(spacing: 6) {
                Image(systemName: selected ? selectedIcon : icon)
                    .font(.system(size: 21, weight: .regular))
                    .frame(height: 23)
                Text(title).font(.system(size: 10, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Theme.gold : Theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("piri.tab.\(index)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
