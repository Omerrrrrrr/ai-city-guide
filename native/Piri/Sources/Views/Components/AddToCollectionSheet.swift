import SwiftUI

/// Lets the user toggle a POI into any number of their named collections
/// (`SavedPlacesStore.collections`), or create a new one on the spot — same
/// tagging-not-filing model favorites/plan already use.
struct AddToCollectionSheet: View {
    let poi: POIPlace

    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(\.dismiss) private var dismiss

    @State private var newCollectionName = ""
    @State private var showingNewCollectionField = false

    private var identifier: String { poi.asReference.identifier }

    var body: some View {
        NavigationStack {
            List {
                ForEach(savedPlacesStore.collections) { collection in
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
                        Label(String(localized: "saved.collections.new"), systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(String(localized: "saved.collections.addToList"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }

    private func createAndAdd() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let id = savedPlacesStore.createCollection(name: trimmed)
        savedPlacesStore.toggle(poi, inCollection: id)
        newCollectionName = ""
        showingNewCollectionField = false
    }
}
