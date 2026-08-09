import SwiftUI

enum SavedTab: Hashable, Identifiable {
    case favorites, plan, visited, collections
    var id: Self { self }
}

/// Port of `mobile/app/(tabs)/saved.tsx`. Rows are `SavedPOIReference`
/// snapshots (Apple POI data) — tapping one resolves the live `MKMapItem`
/// on demand and opens `POIExplainSheet`, the one detail view used
/// app-wide now that there's no curated place-detail page to route to.
struct SavedScreen: View {
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(TabSelection.self) private var tabSelection
    @Environment(\.dismiss) private var dismiss

    @State private var tab: SavedTab
    @State private var selectedPOI: POIPlace?
    @State private var resolvingIdentifier: String?
    @State private var selectedCollection: SavedCollection?
    @State private var showingNewCollectionField = false
    @State private var newCollectionName = ""

    init(initialTab: SavedTab = .favorites) {
        _tab = State(initialValue: initialTab)
    }

    private var favorites: [SavedPOIReference] { savedPlacesStore.favorites }
    private var plan: [SavedPOIReference] { savedPlacesStore.plan }
    private var visited: [SavedPOIReference] { recentlyViewedStore.viewed }
    private var collections: [SavedCollection] { savedPlacesStore.collections }

    private var list: [SavedPOIReference] {
        switch tab {
        case .favorites: return favorites
        case .plan: return plan
        case .visited: return visited
        case .collections: return []
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if tab == .plan, plan.count >= 2 {
                    optimizeButton
                    createRouteButton
                }

                if tab == .collections {
                    collectionsSection
                } else if list.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(list) { reference in
                            referenceRow(reference)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedPOI) { poi in POIExplainSheet(poi: poi) }
        .sheet(item: $selectedCollection) { collection in CollectionDetailScreen(collectionId: collection.id) }
    }

    private var collectionsSection: some View {
        VStack(spacing: 12) {
            if showingNewCollectionField {
                HStack(spacing: 10) {
                    TextField(String(localized: "saved.collections.namePlaceholder"), text: $newCollectionName)
                        .textFieldStyle(.plain)
                        .onSubmit { createCollection() }
                    Button("common.done") { createCollection() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            } else {
                Button {
                    newCollectionName = ""
                    showingNewCollectionField = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.gold)
                        Text("saved.collections.new").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }

            if collections.isEmpty {
                VStack(spacing: 12) {
                    Text("◈").font(.system(size: 48)).opacity(0.25)
                    Text("saved.collections.noListsTitle").font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
                    Text("saved.collections.noListsBody").font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(collections) { collection in
                    Button {
                        selectedCollection = collection
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.gold)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Theme.gold.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                                Text(LPlural("saved.collections.placesCount", count: collection.places.count))
                                    .font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("›").font(.system(size: 20)).foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func createCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        savedPlacesStore.createCollection(name: trimmed)
        newCollectionName = ""
        showingNewCollectionField = false
    }

    private func referenceRow(_ reference: SavedPOIReference) -> some View {
        Button {
            Task { await open(reference) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: POICategoryGroups.icon(for: reference.category))
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.gold.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                    if let category = reference.category?.rawValue {
                        Text(category.replacingOccurrences(of: "MKPOICategory", with: ""))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if resolvingIdentifier == reference.identifier {
                    ProgressView()
                } else {
                    Text("›").font(.system(size: 20)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .disabled(resolvingIdentifier != nil)
    }

    private func open(_ reference: SavedPOIReference) async {
        resolvingIdentifier = reference.identifier
        selectedPOI = await reference.resolve()
        resolvingIdentifier = nil
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
                        case .collections: break
                        }
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(spacing: 3) {
                segmentButton(.favorites, label: String(localized: "saved.tabs.favorites"), count: favorites.count)
                segmentButton(.plan, label: String(localized: "saved.tabs.plan"), count: plan.count)
                segmentButton(.visited, label: String(localized: "saved.tabs.visited"), count: visited.count)
                segmentButton(.collections, label: String(localized: "saved.tabs.collections"), count: collections.count)
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
            // SavedScreen is presented as a `.sheet` from ProfileScreen —
            // switching `tabSelection.selection` alone changes the tab
            // underneath, invisibly, while this sheet keeps covering the
            // whole screen. Dismissing it is what actually makes the tab
            // switch to Ask Piri visible.
            dismiss()
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

    private var createRouteButton: some View {
        Button {
            // `/routes/directions` caps at 10 coordinates server-side —
            // matched here so a large plan doesn't get silently rejected.
            tabSelection.pendingRouteStops = Array(plan.prefix(10))
            tabSelection.selection = 2
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.gold)
                Text("saved.createRoute.title")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.gold.opacity(0.3), lineWidth: 1.5))
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
        case .collections: return ""
        }
    }

    private var emptyBody: String {
        switch tab {
        case .favorites: return String(localized: "saved.empty.favoritesBody")
        case .plan: return String(localized: "saved.empty.planBody")
        case .visited: return String(localized: "saved.empty.visitedBody")
        case .collections: return ""
        }
    }
}
