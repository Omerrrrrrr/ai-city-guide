import MapKit
import SwiftUI

/// The user's own alternative to a chat-driven "AI ile Plan Oluştur" flow —
/// a themed city has thousands of Apple POIs, far more than a flat 24-30
/// candidate browse can meaningfully sort through in one shot. Instead of
/// growing that candidate list (or bolting on a multi-step search agent —
/// rejected in favor of this), this screen narrows the search space with a
/// few direct questions (where / what / what pace) *before* searching, and
/// shows the resulting draft plan updating live as those answers change,
/// rather than only after a final submit. Presented as a `.sheet` from
/// `SavedScreen`'s Plan tab, same custom-header-instead-of-NavigationStack
/// pattern as `CollectionDetailScreen`.
struct PlanBuilderScreen: View {
    @Environment(CityStore.self) private var cityStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedThemes: Set<PlanTheme> = []
    @State private var pace: Pace = .balanced
    @State private var allCandidates: [POIPlace] = []
    @State private var addedIdentifiers: Set<String> = []
    /// Grows each time the list scrolls near its end and re-searches at a
    /// wider radius — an actual new search for more real places, not just
    /// revealing more of an already-fetched fixed batch.
    @State private var searchRadius: CLLocationDistance = PlanBuilderScreen.baseSearchRadius
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var searchTask: Task<Void, Never>?
    @State private var landmark: POIPlace?
    @State private var landmarkIncluded = false
    @State private var landmarkDismissed = false
    @State private var selectedPOI: POIPlace?

    private static let baseSearchRadius: CLLocationDistance = 6000
    private static let maxSearchRadius: CLLocationDistance = 20000

    private var themeOptions: [ProfileOption<PlanTheme>] {
        PlanThemes.all.map { ProfileOption(value: $0, labelKey: $0.labelKey, icon: $0.icon) }
    }

    private var addedPlaces: [POIPlace] {
        allCandidates.filter { addedIdentifiers.contains($0.asReference.identifier) }
    }

    private var totalDraftCount: Int {
        addedPlaces.count + (landmarkIncluded ? 1 : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if cityStore.lat == nil || cityStore.lng == nil {
                noCityState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        whereSection
                        themesSection
                        paceSection
                        if let landmark, !landmarkDismissed {
                            landmarkCard(landmark)
                        }
                        draftSection
                    }
                    .padding(20)
                    .padding(.bottom, 90)
                }
                .safeAreaInset(edge: .bottom) { createButton }
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedPOI) { poi in POIExplainSheet(poi: poi) }
        .task { await loadLandmark() }
        .onChange(of: selectedThemes) { _, _ in scheduleSearch() }
    }

    private var header: some View {
        HStack {
            Button("common.cancel") { dismiss() }
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text("planBuilder.title").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            Spacer()
            // Balances the cancel button so the title stays visually
            // centered — matches `CollectionDetailScreen`'s header, which
            // has a real trailing action (delete) instead of this spacer.
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Theme.navy)
    }

    private var noCityState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("planBuilder.noCityTitle").font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
            Text("planBuilder.noCityBody").font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("planBuilder.whereLabel").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).tracking(0.6)
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.gold).font(.system(size: 22))
                Text(L("planBuilder.whereBody", cityStore.cityName ?? ""))
                    .font(.system(size: 16, weight: .semibold))
            }
        }
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("planBuilder.themesLabel").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).tracking(0.6)
            Text("planBuilder.themesSubtitle").font(.system(size: 13)).foregroundStyle(.secondary).padding(.bottom, 4)
            ChipGrid(options: themeOptions, isSelected: { selectedThemes.contains($0) }) { theme in
                Haptics.light()
                if selectedThemes.contains(theme) {
                    selectedThemes.remove(theme)
                } else {
                    selectedThemes.insert(theme)
                }
            }
        }
    }

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("planBuilder.paceLabel").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).tracking(0.6)
            ChipGrid(options: ProfileOptions.paces, isSelected: { pace == $0 }) { value in
                Haptics.light()
                pace = value
            }
        }
    }

    private func landmarkCard(_ poi: POIPlace) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "star.circle.fill").font(.system(size: 30)).foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("planBuilder.landmarkBody", poi.name)).font(.system(size: 15, weight: .semibold))
                Text("planBuilder.landmarkSubtitle").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Haptics.light()
                        landmarkIncluded = true
                        landmarkDismissed = true
                    } label: {
                        Text("planBuilder.landmarkAdd").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.navy)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.gold))
                    }
                    Button {
                        Haptics.light()
                        landmarkDismissed = true
                    } label: {
                        Text("planBuilder.landmarkSkip").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.gold.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.gold.opacity(0.3)))
    }

    @ViewBuilder
    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("planBuilder.draftLabel").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).tracking(0.6)
                Spacer()
                if !addedPlaces.isEmpty {
                    Text(LPlural("planBuilder.addedCount", count: addedPlaces.count))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
            }

            if selectedThemes.isEmpty {
                Text("planBuilder.draftEmpty").font(.system(size: 14)).foregroundStyle(.secondary)
            } else if isSearching && allCandidates.isEmpty {
                VStack(spacing: 8) {
                    SkeletonBox().frame(height: 60)
                    SkeletonBox().frame(height: 60)
                }
            } else if allCandidates.isEmpty {
                Text("planBuilder.draftNoResults").font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                ForEach(allCandidates) { poi in
                    candidateRow(poi)
                        // Reaching the last row (well before the max search
                        // radius is hit) triggers a real new search at a
                        // wider radius — an infinite-scroll feed the system
                        // keeps extending, not a button that just reveals
                        // more of a fixed batch.
                        .onAppear { loadMoreIfNeeded(after: poi) }
                }
                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().tint(Theme.gold)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func candidateRow(_ poi: POIPlace) -> some View {
        let added = addedIdentifiers.contains(poi.asReference.identifier)
        return HStack(spacing: 12) {
            Button {
                selectedPOI = poi
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: POICategoryGroups.icon(for: poi.category))
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.gold.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(poi.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        if !poi.categoryLabel.isEmpty {
                            Text(poi.categoryLabel).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.light()
                if added {
                    addedIdentifiers.remove(poi.asReference.identifier)
                } else {
                    addedIdentifiers.insert(poi.asReference.identifier)
                }
            } label: {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(added ? Theme.gold : .secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(added ? Theme.gold.opacity(0.08) : Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(added ? Theme.gold.opacity(0.35) : .clear, lineWidth: 1.5))
    }

    private var createButton: some View {
        Button {
            createPlan()
        } label: {
            Text(LPlural("planBuilder.createButton", count: totalDraftCount))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy))
        }
        .buttonStyle(.plain)
        .disabled(totalDraftCount == 0)
        .opacity(totalDraftCount == 0 ? 0.5 : 1)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.regularMaterial)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchRadius = Self.baseSearchRadius
        guard let lat = cityStore.lat, let lng = cityStore.lng, !selectedThemes.isEmpty else {
            allCandidates = []
            return
        }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let categories = selectedThemes.reduce(into: Set<MKPointOfInterestCategory>()) { $0.formUnion($1.categories) }
        isSearching = true
        searchTask = Task {
            // Wider than the default 4km — this is meant to sweep a whole
            // city for a themed plan, not just "what's nearby right now".
            let results = await POISearchService.search(near: coordinate, categories: categories, radiusMeters: searchRadius)
            guard !Task.isCancelled else { return }
            allCandidates = results.sorted {
                geoDistanceKm($0.coordinate.latitude, $0.coordinate.longitude, coordinate.latitude, coordinate.longitude)
                    < geoDistanceKm($1.coordinate.latitude, $1.coordinate.longitude, coordinate.latitude, coordinate.longitude)
            }
            isSearching = false
        }
    }

    /// Triggered by the last visible row's `.onAppear` — re-searches at a
    /// wider radius and merges in only the genuinely new places, so
    /// scrolling to the bottom keeps extending the list with real results
    /// instead of just paginating through what was already fetched.
    private func loadMoreIfNeeded(after poi: POIPlace) {
        guard poi.id == allCandidates.last?.id else { return }
        guard !isSearching, !isLoadingMore, searchRadius < Self.maxSearchRadius else { return }
        guard let lat = cityStore.lat, let lng = cityStore.lng, !selectedThemes.isEmpty else { return }

        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let categories = selectedThemes.reduce(into: Set<MKPointOfInterestCategory>()) { $0.formUnion($1.categories) }
        searchRadius = min(searchRadius * 1.7, Self.maxSearchRadius)
        isLoadingMore = true

        Task {
            defer { isLoadingMore = false }
            let results = await POISearchService.search(near: coordinate, categories: categories, radiusMeters: searchRadius)
            let existingIdentifiers = Set(allCandidates.map { $0.asReference.identifier })
            let newOnes = results.filter { !existingIdentifiers.contains($0.asReference.identifier) }
            guard !newOnes.isEmpty else { return }
            allCandidates = (allCandidates + newOnes).sorted {
                geoDistanceKm($0.coordinate.latitude, $0.coordinate.longitude, coordinate.latitude, coordinate.longitude)
                    < geoDistanceKm($1.coordinate.latitude, $1.coordinate.longitude, coordinate.latitude, coordinate.longitude)
            }
        }
    }

    private func loadLandmark() async {
        guard let lat = cityStore.lat, let lng = cityStore.lng else { return }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let results = await POISearchService.search(
            near: coordinate,
            categories: [.landmark, .nationalMonument, .castle, .fortress],
            radiusMeters: 8000
        )
        landmark = results.sorted {
            geoDistanceKm($0.coordinate.latitude, $0.coordinate.longitude, coordinate.latitude, coordinate.longitude)
                < geoDistanceKm($1.coordinate.latitude, $1.coordinate.longitude, coordinate.latitude, coordinate.longitude)
        }.first
    }

    private func createPlan() {
        Haptics.medium()
        let name = cityStore.cityName.map { L("ai.savedPlan.name", $0) } ?? String(localized: "ai.savedPlan.nameFallback")
        let collectionId = savedPlacesStore.createCollection(name: name, kind: .plan)
        for poi in addedPlaces {
            savedPlacesStore.toggle(poi, inCollection: collectionId)
        }
        if landmarkIncluded, let landmark {
            savedPlacesStore.toggle(landmark, inCollection: collectionId)
        }
        dismiss()
    }
}
