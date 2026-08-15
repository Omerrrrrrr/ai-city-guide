import SwiftUI

/// Lets the user toggle a POI into any of their named lists of the given
/// `kind` (saved or plan), or create a new one on the spot — same
/// tagging-not-filing model favorites/plan already used before both became
/// user-named collections.
struct AddToCollectionSheet: View {
    let poi: POIPlace
    let kind: SavedCollectionKind

    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(\.dismiss) private var dismiss

    @State private var newCollectionName = ""
    @State private var showingNewCollectionField = false

    private var identifier: String { poi.asReference.identifier }
    private var collections: [SavedCollection] {
        kind == .plan ? savedPlacesStore.plans : savedPlacesStore.savedLists
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(collections) { collection in
                    let inCollection = savedPlacesStore.isIn(collection: collection.id, identifier: identifier)
                    Button {
                        Haptics.light()
                        savedPlacesStore.toggle(poi, inCollection: collection.id)
                    } label: {
                        HStack {
                            Text(collection.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: inCollection ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(inCollection ? Theme.gold : .secondary)
                        }
                    }
                }

                if showingNewCollectionField {
                    HStack(spacing: 10) {
                        TextField(String(localized: "saved.collections.namePlaceholder"), text: $newCollectionName)
                            .onSubmit { createAndAdd() }
                        Button("common.done") { createAndAdd() }
                            .font(.system(size: 14, weight: .bold))
                    }
                } else {
                    Button {
                        newCollectionName = ""
                        showingNewCollectionField = true
                    } label: {
                        Label(String(localized: kind == .plan ? "saved.plan.new" : "saved.collections.new"), systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(String(localized: kind == .plan ? "saved.plan.addToPlan" : "saved.collections.addToList"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Every toggle here already saves immediately
                // (`savedPlacesStore.toggle`), so this button has nothing
                // to "confirm" and nothing to "cancel" — it just closes the
                // sheet. It was previously in the leading Cancel slot but
                // labeled "Done", the opposite of every other Cancel/Done
                // pair in the app. "Done" in the trailing slot (matching
                // e.g. Reminders' list pickers) is the closer fit.
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }

    private func createAndAdd() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let id = savedPlacesStore.createCollection(name: trimmed, kind: kind)
        savedPlacesStore.toggle(poi, inCollection: id)
        newCollectionName = ""
        showingNewCollectionField = false
    }
}
