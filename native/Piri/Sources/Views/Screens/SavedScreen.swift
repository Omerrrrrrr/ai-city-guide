import SwiftUI

enum SavedTab: Hashable, Identifiable {
    case favorites, plan, visited
    var id: Self { self }
}

/// Port of `mobile/app/(tabs)/saved.tsx`.
struct SavedScreen: View {
    @Environment(PlacesQuery.self) private var placesQuery
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(TabSelection.self) private var tabSelection

    @State private var tab: SavedTab

    init(initialTab: SavedTab = .favorites) {
        _tab = State(initialValue: initialTab)
    }

    private var favorites: [Place] { placesQuery.places.filter { savedPlacesStore.isFavorite($0.id) } }
    private var plan: [Place] { savedPlacesStore.planPlaceIds.compactMap(placesQuery.place) }
    private var visited: [Place] { recentlyViewedStore.viewedIds.compactMap(placesQuery.place) }

    private var list: [Place] {
        switch tab {
        case .favorites: return favorites
        case .plan: return plan
        case .visited: return visited
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if tab == .plan, plan.count >= 2 {
                    optimizeButton
                }

                if list.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(list) { place in
                            NavigationLink(destination: PlaceDetailScreen(placeId: place.id)) {
                                PlaceRowView(place: place)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .task {
            if placesQuery.places.isEmpty {
                await placesQuery.load(cityName: nil, lat: nil, lng: nil)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("saved.title").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                Spacer()
                if !list.isEmpty {
                    Button("common.clear") {
                        switch tab {
                        case .favorites: savedPlacesStore.clearFavorites()
                        case .plan: savedPlacesStore.clearPlan()
                        case .visited: recentlyViewedStore.clearHistory()
                        }
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(spacing: 3) {
                segmentButton(.favorites, label: String(localized: "saved.tabs.favorites"), count: favorites.count)
                segmentButton(.plan, label: String(localized: "saved.tabs.plan"), count: plan.count)
                segmentButton(.visited, label: String(localized: "saved.tabs.visited"), count: visited.count)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Theme.navy)
    }

    private func segmentButton(_ value: SavedTab, label: String, count: Int) -> some View {
        let active = tab == value
        return Button {
            tab = value
        } label: {
            Text(label + (count > 0 ? " \(count)" : ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Theme.navy : .white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active ? RoundedRectangle(cornerRadius: 10).fill(.white) : nil)
        }
    }

    private var optimizeButton: some View {
        Button {
            let placeNames = plan.map(\.name).joined(separator: ", ")
            tabSelection.pendingAIQuery = L("saved.optimize.query", placeNames)
            tabSelection.selection = 3
        } label: {
            HStack(spacing: 14) {
                Text("◈").font(.system(size: 26)).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("saved.optimize.title").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text(LPlural("saved.optimize.sub", count: plan.count)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.navy))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(tab == .favorites ? "♡" : tab == .plan ? "＋" : "◎")
                .font(.system(size: 48)).opacity(0.25)
            Text(emptyTitle).font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
            Text(emptyBody).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }

    private var emptyTitle: String {
        switch tab {
        case .favorites: return String(localized: "saved.empty.favoritesTitle")
        case .plan: return String(localized: "saved.empty.planTitle")
        case .visited: return String(localized: "saved.empty.visitedTitle")
        }
    }

    private var emptyBody: String {
        switch tab {
        case .favorites: return String(localized: "saved.empty.favoritesBody")
        case .plan: return String(localized: "saved.empty.planBody")
        case .visited: return String(localized: "saved.empty.visitedBody")
        }
    }
}
