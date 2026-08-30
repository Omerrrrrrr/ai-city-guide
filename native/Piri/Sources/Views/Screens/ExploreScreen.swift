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
    @Environment(AuthStore.self) private var authStore

    @State private var query = ""
    @State private var selectedCategoryGroup: POICategoryGroup?
    @State private var results: [POIPlace] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    /// Halal/Kosher/Vegetarian/Vegan — orthogonal to `selectedCategoryGroup`
    /// (Apple's own POI taxonomy has no dietary tags at all), sourced from
    /// OpenStreetMap via the same `/places/dietary` endpoint the map screen
    /// uses. Kept as a separate result list, not merged into `results`,
    /// since these are lightweight OSM pins with no `MKMapItem` behind them.
    @State private var dietaryFilter: DietTag?
    @State private var dietaryResults: [DietaryPin] = []
    @State private var dietaryLoading = false
    @State private var selectedPOI: POIPlace?
    @State private var locationManager = LocationManager()
    @State private var searchTask: Task<Void, Never>?
    /// `MKLocalSearchRequest` has no result-count/page parameter at all —
    /// confirmed against the actual header, not just docs — so ~25 results
    /// per call is a hard, undocumented Apple cap, not anything tunable
    /// here. Scrolling to the bottom re-searches at a wider radius and
    /// merges in whatever's new, same pattern as `PlanBuilderScreen`, since
    /// that's the only way to surface more than one call's worth at all.
    @State private var searchRadius: CLLocationDistance = 4000
    @State private var searchCoordinate: CLLocationCoordinate2D?
    private static let maxSearchRadius: CLLocationDistance = 20000
    /// Keyed by POI name. The full result (not just the URL) is kept so
    /// Unsplash-sourced photos can show their required photographer
    /// attribution — a present dictionary entry with a `nil` `photoUrl` is
    /// a real, distinct value here ("already checked, no photo found"), not
    /// just "haven't asked yet", so a no-photo place doesn't get
    /// re-requested on every scroll.
    @State private var photos: [String: PhotoBulkResult] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                categoryChips
                dietaryChips
                if dietaryFilter != nil {
                    dietaryResultsSection
                }

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
        // `.task` above only fires once per view identity, not on every
        // re-appear -- switching the selected city elsewhere (e.g.
        // `ProfileScreen`'s city picker) while this tab stays alive in a
        // `TabView` left `results` showing the *previous* city's places
        // (only the `header`'s city-name label re-rendered, since that
        // reads `cityStore` directly), until some unrelated interaction
        // (typing, tapping a category) happened to call `search()` again.
        .onChange(of: cityStore.cityId) { _, _ in
            searchTask?.cancel()
            Task { await search() }
            if let dietaryFilter {
                Task { await loadDietaryResults(dietaryFilter) }
            }
        }
        .onChange(of: dietaryFilter) { _, filter in
            guard let filter else {
                dietaryResults = []
                return
            }
            Task { await loadDietaryResults(filter) }
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

    /// Orthogonal to `categoryChips` — a dietary need, not an Apple POI
    /// category, so it's its own row rather than folded into the same one.
    /// Same single-select-with-toggle-off interaction as the category chips.
    private var dietaryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DietTag.allCases) { tag in
                    let active = dietaryFilter == tag
                    // See `MapScreen.dietaryChips`: `String.LocalizationValue`
                    // treats a directly-interpolated literal as a format
                    // string with the interpolated part as an *argument*,
                    // not part of the lookup key — building the key as a
                    // plain `String` first avoids that.
                    let key: String = "diet.\(tag.rawValue)"
                    Button {
                        dietaryFilter = active ? nil : tag
                    } label: {
                        Text(String(localized: String.LocalizationValue(key)))
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

    /// Shown only while a dietary filter is active — the primary thing the
    /// user is looking for at that point, so it sits ahead of the plain POI
    /// grid. Lightweight rows only (name + which diet tags matched), no tap
    /// action — these are OSM pins with no `MKMapItem` behind them, so
    /// there's nothing to open a full `POIExplainSheet` on, matching the
    /// map screen's `dietaryPinCard`.
    private var dietaryResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("dietaryResults.title").font(.system(size: 17, weight: .bold)).padding(.horizontal, 20)
            if dietaryLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if dietaryResults.isEmpty {
                Text("dietaryResults.empty")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(dietaryResults) { pin in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pin.name).font(.system(size: 15, weight: .semibold))
                            HStack(spacing: 6) {
                                ForEach(pin.dietTags, id: \.self) { tag in
                                    let key: String = "diet.\(tag)"
                                    Text(String(localized: String.LocalizationValue(key)))
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGreen).opacity(0.18), in: Capsule())
                                        .foregroundStyle(Color(.systemGreen))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    /// Same meters-to-degrees approximation used everywhere else a center +
    /// radius needs to become a bbox for `/places/dietary` — good enough at
    /// city scale, doesn't need to be geodesically exact.
    private func dietaryBoundingBox(center: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) -> (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) {
        let latDelta = radiusMeters / 111_000
        let lngDelta = radiusMeters / (111_000 * cos(center.latitude * .pi / 180))
        return (center.latitude - latDelta, center.latitude + latDelta, center.longitude - lngDelta, center.longitude + lngDelta)
    }

    private func loadDietaryResults(_ tag: DietTag) async {
        let coordinate: CLLocationCoordinate2D?
        if let searchCoordinate {
            coordinate = searchCoordinate
        } else if let lat = cityStore.lat, let lng = cityStore.lng {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            coordinate = await locationManager.currentLocationOnce()
        }
        guard let coordinate else { return }
        // A newer tap may have already changed `dietaryFilter` by the time
        // this `await` resolves — don't clobber its result with a stale one.
        guard dietaryFilter == tag else { return }

        dietaryLoading = true
        defer { dietaryLoading = false }
        let box = dietaryBoundingBox(center: coordinate, radiusMeters: searchRadius)
        let fetched = (try? await DietaryPlacesAPI.fetchNearby(minLat: box.minLat, maxLat: box.maxLat, minLng: box.minLng, maxLng: box.maxLng, diet: tag)) ?? []
        guard dietaryFilter == tag else { return }
        dietaryResults = fetched
    }

    private var resultsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LPlural("explore.placesFound", count: results.count)).font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 20)
            // `alignment: .top` -- see HomeScreen's `poiSection`, identical
            // row-centering bug otherwise.
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                ForEach(results) { poi in
                    // Sibling overlay, not nested inside the Button's own
                    // label — see HomeScreen's identical pattern for why.
                    ZStack(alignment: .topTrailing) {
                        Button {
                            selectedPOI = poi
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                tileImage(for: poi)
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
                        .onAppear { loadMoreIfNeeded(after: poi) }

                        unsplashBadge(for: poi)
                    }
                }
            }
            .padding(.horizontal, 16)

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.gold)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    /// Real photo when the cache/live lookup found one; the category icon
    /// tile (today's only option) otherwise — never a broken-image state,
    /// same silent-degrade contract `POISearchService` already uses.
    ///
    /// See `HomeScreen`'s `nearbyTileImage` (identical bug) for why this
    /// reads the exact box size from a `GeometryReader` instead of relying
    /// on `.frame(height:).clipped()`, which turned out unreliable for
    /// portrait-source photos.
    @ViewBuilder
    private func tileImage(for poi: POIPlace) -> some View {
        let urlString = photos[poi.name]?.photoUrl
        GeometryReader { geo in
            if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, maxPixelSize: 300) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    categoryTile(for: poi)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            } else {
                categoryTile(for: poi)
            }
        }
        .frame(height: 100)
    }

    private func categoryTile(for poi: POIPlace) -> some View {
        ZStack {
            POICategoryGroups.gradient(for: poi.category)
            Image(systemName: POICategoryGroups.icon(for: poi.category))
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    /// Unsplash's API Terms (§9) require attributing Unsplash and the
    /// photographer, linked, every time a photo is displayed — see
    /// HomeScreen's identical helper for the full rationale (no secondary
    /// detail view here re-shows this same photo, so the grid card itself
    /// has to carry it).
    @ViewBuilder
    private func unsplashBadge(for poi: POIPlace) -> some View {
        if let photo = photos[poi.name], photo.source == "unsplash",
           let photographerUrl = photo.photographerUrl, let url = URL(string: photographerUrl) {
            HStack(spacing: 4) {
                Link(destination: url) {
                    Text("Unsplash")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                // See HomeScreen's identical badge for why this is
                // tier-gated: a paid account shouldn't see an "upgrade"
                // hint it's already paid for.
                if authStore.user?.isPaidTier != true {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.55), in: Circle())
                }
            }
            .padding(6)
        }
    }

    /// Batches up to 20 places at once (matches `/places/photos-bulk`'s own
    /// cap) and skips anything already resolved — including a confirmed
    /// "no photo" — so scrolling through a long list doesn't re-request the
    /// same names over and over.
    private func loadPhotosIfNeeded(for items: [POIPlace]) {
        let missing = items.filter { photos[$0.name] == nil }.prefix(20)
        guard !missing.isEmpty else { return }
        let request = PhotoBulkRequest(places: missing.map {
            PhotoBulkPlace(name: $0.name, lat: $0.coordinate.latitude, lng: $0.coordinate.longitude, category: $0.categoryLabel.isEmpty ? nil : $0.categoryLabel)
        })
        Task {
            guard let response = try? await PlacesAPI.photosBulk(request, token: authStore.token) else { return }
            for result in response.results {
                photos[result.name] = result
            }
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

        searchCoordinate = coordinate
        searchRadius = 4000

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let fetched = await POISearchService.search(
            near: coordinate,
            categories: selectedCategoryGroup?.categories,
            naturalLanguageQuery: trimmed.isEmpty ? nil : trimmed,
            radiusMeters: searchRadius
        )
        // Only reorder the plain "everything nearby" browse — once a
        // category filter is active the list is already one category, and
        // a text search's own relevance order (what actually matched the
        // words typed) matters more than category grouping.
        results = (selectedCategoryGroup == nil && trimmed.isEmpty) ? POICategoryGroups.prioritizingSights(fetched) : fetched
        loadPhotosIfNeeded(for: results)
    }

    private func loadMoreIfNeeded(after poi: POIPlace) {
        guard poi.id == results.last?.id else { return }
        guard !isLoading, !isLoadingMore, searchRadius < Self.maxSearchRadius else { return }
        guard let coordinate = searchCoordinate else { return }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        searchRadius = min(searchRadius * 1.7, Self.maxSearchRadius)
        isLoadingMore = true

        Task {
            defer { isLoadingMore = false }
            let more = await POISearchService.search(
                near: coordinate,
                categories: selectedCategoryGroup?.categories,
                naturalLanguageQuery: trimmed.isEmpty ? nil : trimmed,
                radiusMeters: searchRadius
            )
            let existingIdentifiers = Set(results.map { $0.asReference.identifier })
            let newOnes = more.filter { !existingIdentifiers.contains($0.asReference.identifier) }
            guard !newOnes.isEmpty else { return }
            results += newOnes
            loadPhotosIfNeeded(for: newOnes)
        }
    }
}
