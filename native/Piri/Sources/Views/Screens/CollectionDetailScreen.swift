import SwiftUI

/// A user-named group of saved places (`SavedCollection`) — rename, remove
/// places, delete the whole list. Presented as a `.sheet` from `SavedScreen`,
/// same pattern as `TripDetailScreen`: a custom header row instead of a
/// `NavigationStack`, since there's no ambient navigation bar to hide here.
///
/// Only `.plan`-kind collections with 2+ places get the AI-optimize/
/// create-route buttons — `.saved`-kind lists are just for keeping places.
struct CollectionDetailScreen: View {
    let collectionId: String

    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(TabSelection.self) private var tabSelection
    @Environment(\.dismiss) private var dismiss

    @State private var isEditingName = false
    @State private var nameInput = ""
    @State private var selectedPOI: POIPlace?
    @State private var resolvingIdentifier: String?

    private var collection: SavedCollection? {
        savedPlacesStore.collections.first { $0.id == collectionId }
    }

    var body: some View {
        Group {
            if let collection {
                content(collection)
            } else {
                VStack(spacing: 16) {
                    Text("saved.collections.notFound").foregroundStyle(.secondary)
                    Button("common.cancel") { dismiss() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func content(_ collection: SavedCollection) -> some View {
        VStack(spacing: 0) {
            header(collection)
            ScrollView {
                VStack(spacing: 12) {
                    if collection.kind == .plan, collection.places.count >= 2 {
                        optimizeButton(collection)
                        createRouteButton(collection)
                    }

                    if collection.places.isEmpty {
                        emptyState
                    } else {
                        ForEach(collection.places) { reference in
                            referenceRow(reference)
                        }
                    }
                }
                .padding(16)
            }
        }
        .sheet(item: $selectedPOI) { poi in POIExplainSheet(poi: poi) }
        .onAppear { nameInput = collection.name }
    }

    private func optimizeButton(_ collection: SavedCollection) -> some View {
        Button {
            let placeNames = collection.places.map(\.name).joined(separator: ", ")
            tabSelection.pendingAIQuery = L("saved.optimize.query", placeNames)
            tabSelection.selection = 3
            // Presented as a `.sheet` (from SavedScreen, itself a `.sheet`
            // from ProfileScreen) — switching `tabSelection.selection` alone
            // changes the tab underneath, invisibly, while these sheets
            // keep covering the whole screen. Dismissing is what actually
            // makes the tab switch to Ask Piri visible.
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text("◈").font(.system(size: 26)).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("saved.optimize.title").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text(LPlural("saved.optimize.sub", count: collection.places.count)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.navy))
        }
        .buttonStyle(.plain)
    }

    private func createRouteButton(_ collection: SavedCollection) -> some View {
        Button {
            // `/routes/directions` caps at 10 coordinates server-side —
            // matched here so a large list doesn't get silently rejected.
            tabSelection.pendingRouteStops = Array(collection.places.prefix(10))
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
    }

    private func header(_ collection: SavedCollection) -> some View {
        HStack {
            Button("common.cancel") { dismiss() }
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            if isEditingName {
                TextField(collection.name, text: $nameInput)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .onSubmit { commitRename(collection) }
            } else {
                Button {
                    nameInput = collection.name
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Text(collection.name).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            Spacer()

            Button {
                savedPlacesStore.deleteCollection(collection.id)
                dismiss()
            } label: {
                Image(systemName: "trash").foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Theme.navy)
    }

    private func commitRename(_ collection: SavedCollection) {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            savedPlacesStore.renameCollection(collection.id, name: trimmed)
        }
        isEditingName = false
    }

    private func referenceRow(_ reference: SavedPOIReference) -> some View {
        HStack(spacing: 12) {
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
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(resolvingIdentifier != nil)

            if resolvingIdentifier != reference.identifier {
                Button {
                    savedPlacesStore.removeFromCollection(collectionId, identifier: reference.identifier)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func open(_ reference: SavedPOIReference) async {
        resolvingIdentifier = reference.identifier
        selectedPOI = await reference.resolve()
        resolvingIdentifier = nil
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("◈").font(.system(size: 48)).opacity(0.25)
            Text("saved.collections.emptyTitle").font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
            Text("saved.collections.emptyBody").font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}
