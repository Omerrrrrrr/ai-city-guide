import SwiftUI

enum SavedTab: Hashable, Identifiable {
    case lists, visited
    var id: Self { self }
}

/// Port of `mobile/app/(tabs)/saved.tsx`, since generalized: there's no more
/// single "Favorites" or "Plan" bucket — per the user's explicit choice,
/// both became user-named `SavedCollection`s (`.lists` tab), each of which
/// can independently be turned into an AI-optimized suggestion or an actual
/// map route once it has 2+ places (see `CollectionDetailScreen`). `.visited`
/// (recently viewed, automatic history) is unaffected.
struct SavedScreen: View {
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore

    @State private var tab: SavedTab
    @State private var selectedPOI: POIPlace?
    @State private var resolvingIdentifier: String?
    @State private var selectedCollection: SavedCollection?
    @State private var showingNewCollectionField = false
    @State private var newCollectionName = ""

    init(initialTab: SavedTab = .lists) {
        _tab = State(initialValue: initialTab)
    }

    private var visited: [SavedPOIReference] { recentlyViewedStore.viewed }
    private var collections: [SavedCollection] { savedPlacesStore.collections }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if tab == .lists {
                    collectionsSection
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
                if tab == .visited, !visited.isEmpty {
                    Button("common.clear") { recentlyViewedStore.clearHistory() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(spacing: 3) {
                segmentButton(.lists, label: String(localized: "saved.tabs.collections"), count: collections.count)
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
