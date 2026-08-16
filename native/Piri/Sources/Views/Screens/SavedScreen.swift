import SwiftUI

enum SavedTab: Hashable, Identifiable {
    case saved, plan, visited
    var id: Self { self }
}

/// Port of `mobile/app/(tabs)/saved.tsx`, since generalized: "Kaydedilen"
/// and "Plan" used to each be a single flat list — per the user's explicit
/// choice, both are now collections of user-named `SavedCollection`s
/// instead, so someone can make multiple named saved-lists *and* multiple
/// named plans ("Hafta Sonu", "Yaz Tatili"), then pick whichever one to open
/// (`CollectionDetailScreen`). `.visited` (recently viewed, automatic
/// history) is unaffected — still one flat list.
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
    @State private var showingPlanBuilder = false

    init(initialTab: SavedTab = .saved) {
        _tab = State(initialValue: initialTab)
    }

    private var visited: [SavedPOIReference] { recentlyViewedStore.viewed }
    private var savedLists: [SavedCollection] { savedPlacesStore.savedLists }
    private var plans: [SavedCollection] { savedPlacesStore.plans }

    private var currentKind: SavedCollectionKind? {
        switch tab {
        case .saved: return .saved
        case .plan: return .plan
        case .visited: return nil
        }
    }

    private var currentCollections: [SavedCollection] {
        switch tab {
        case .saved: return savedLists
        case .plan: return plans
        case .visited: return []
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let kind = currentKind {
                    collectionsSection(kind: kind)
                } else if visited.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(visited) { reference in
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
        .sheet(isPresented: $showingPlanBuilder) {
            PlanBuilderScreen()
                // A swipe-down used to silently discard whatever themes/
                // pace/candidates had been picked so far. The screen
                // already has its own explicit "common.cancel" button for
                // deliberately backing out — require that instead of an
                // easy-to-trigger-by-accident gesture.
                .interactiveDismissDisabled()
        }
        // "Piri ile günümü optimize et" (CollectionDetailScreen's optimize
        // button) sets pendingAIQuery + switches tabSelection to Ask Piri,
        // then dismisses itself -- but CollectionDetailScreen is a sheet
        // presented *from this screen*, which is itself a sheet presented
        // from ProfileScreen. That single dismiss only closed
        // CollectionDetailScreen, landing back on this screen (still
        // covering the tab bar) instead of actually reaching Ask Piri --
        // confirmed live. Cascading the dismissal here closes this sheet
        // too, so the tab switch underneath actually becomes visible.
        .onChange(of: tabSelection.pendingAIQuery) { _, newValue in
            guard newValue != nil else { return }
            dismiss()
        }
    }

    private func collectionsSection(kind: SavedCollectionKind) -> some View {
        VStack(spacing: 12) {
            if showingNewCollectionField {
                HStack(spacing: 10) {
                    TextField(String(localized: "saved.collections.namePlaceholder"), text: $newCollectionName)
                        .textFieldStyle(.plain)
                        .onSubmit { createCollection(kind: kind) }
                    Button("common.done") { createCollection(kind: kind) }
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
                        Text(kind == .plan ? "saved.plan.new" : "saved.collections.new")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }

            if kind == .plan, !showingNewCollectionField {
                Button {
                    Haptics.light()
                    showingPlanBuilder = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "suitcase.fill").foregroundStyle(Theme.gold)
                        Text("saved.plan.aiBuild")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "sparkles").foregroundStyle(Theme.gold).font(.system(size: 13))
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gold.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.3)))
                }
                .buttonStyle(.plain)
            }

            if currentCollections.isEmpty {
                VStack(spacing: 12) {
                    Text("◈").font(.system(size: 48)).opacity(0.25)
                    Text(kind == .plan ? "saved.plan.noPlansTitle" : "saved.collections.noListsTitle")
                        .font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
                    Text(kind == .plan ? "saved.plan.noPlansBody" : "saved.collections.noListsBody")
                        .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(currentCollections) { collection in
                    Button {
                        selectedCollection = collection
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind == .plan ? "point.topleft.down.curvedto.point.bottomright.up" : "list.bullet")
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

    private func createCollection(kind: SavedCollectionKind) {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        savedPlacesStore.createCollection(name: trimmed, kind: kind)
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
                if tab == .visited, !visited.isEmpty {
                    Button("common.clear") { recentlyViewedStore.clearHistory() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(spacing: 3) {
                segmentButton(.saved, label: String(localized: "saved.tabs.favorites"), count: savedLists.count)
                segmentButton(.plan, label: String(localized: "saved.tabs.plan"), count: plans.count)
                segmentButton(.visited, label: String(localized: "saved.tabs.visited"), count: visited.count)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .piriGlassSurface()
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("◎").font(.system(size: 48)).opacity(0.25)
            Text("saved.empty.visitedTitle").font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
            Text("saved.empty.visitedBody").font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}
