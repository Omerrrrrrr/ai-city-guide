import CoreLocation
import MapKit
import SwiftUI

/// Port of `mobile/app/(tabs)/explore.tsx`, rewritten on Apple POI data —
/// same `POISearchService`/`POICategoryGroups` pattern `HomeScreen`'s
/// `useCuratedHomeData == false` branch already established, extended with
/// search-as-you-type (`POISearchService`'s `naturalLanguageQuery` param).
/// No tag chips, "featured"/"rainy day" sections, quality ranking, or
/// open-now filter — none of those have an Apple POI data source (see
/// `PlaceFilters`/`PlaceHours`, left dormant along with the rest of the
/// curated-data screens this pivot replaces).
struct ExploreScreen: View {
    @Environment(CityStore.self) private var cityStore

    @State private var query = ""
    @State private var selectedCategoryGroup: POICategoryGroup?
    @State private var results: [POIPlace] = []
    @State private var isLoading = false
    @State private var selectedPOI: POIPlace?
    @State private var locationManager = LocationManager()
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                categoryChips

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if results.isEmpty {
                    Text("explore.emptyText").foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 20)
                } else {
                    resultsGrid
                }
            }
            .padding(.bottom, 40)
        }
        // See CityPickerScreen: without this, the default `.interactively`
        // keyboard dismissal swallows the first tap on a result card while
        // the search field is still focused, instead of firing it.
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await search() }
        .task { await search() }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: selectedCategoryGroup?.id) { _, _ in
            searchTask?.cancel()
            Task { await search() }
        }
        .sheet(item: $selectedPOI) { poi in POIExplainSheet(poi: poi) }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cityStore.cityName ?? String(localized: "explore.placesFallback"))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
            TextField(text: $query) {
                Text("common.searchPlaces")
            }
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .piriGlassSurface()
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(POICategoryGroups.all) { group in
                    let active = selectedCategoryGroup?.id == group.id
                    Button {
                        selectedCategoryGroup = active ? nil : group
                    } label: {
                        Label(String(localized: String.LocalizationValue(group.labelKey)), systemImage: group.icon)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(active ? Theme.navy : Color(.secondarySystemBackground)))
                            .foregroundStyle(active ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var resultsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LPlural("explore.placesFound", count: results.count)).font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 20)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(results) { poi in
                    Button {
                        selectedPOI = poi
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            ZStack {
                                Color(.secondarySystemBackground)
                                Image(systemName: POICategoryGroups.icon(for: poi.category))
                                    .font(.system(size: 28))
                                    .foregroundStyle(Theme.gold)
                            }
                            .frame(height: 100)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(poi.name).font(.system(size: 15, weight: .bold)).lineLimit(2)
                                if !poi.categoryLabel.isEmpty {
                                    Text(poi.categoryLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                        }
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let coordinate: CLLocationCoordinate2D?
        if let lat = cityStore.lat, let lng = cityStore.lng {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            coordinate = await locationManager.currentLocationOnce()
        }
        guard let coordinate else { return }

        isLoading = true
        defer { isLoading = false }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        results = await POISearchService.search(
            near: coordinate,
            categories: selectedCategoryGroup?.categories,
            naturalLanguageQuery: trimmed.isEmpty ? nil : trimmed
        )
    }
}
