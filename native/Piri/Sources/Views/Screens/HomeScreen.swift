import MapKit
import SwiftUI

/// Port of `mobile/app/(tabs)/index.tsx`.
struct HomeScreen: View {
    // Reversible, same pattern as `MapScreen.useCuratedMapData` — curated
    // place sections (Featured/Recently Viewed/Nearby/etc.) are hidden while
    // testing Apple's own POI data instead; not a decision to delete the
    // curated-data feature.
    private static let useCuratedHomeData = false

    @Environment(PlacesQuery.self) private var placesQuery
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(CityStore.self) private var cityStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(TabSelection.self) private var tabSelection

    @State private var weatherQuery = WeatherQuery()
    @State private var locationManager = LocationManager()
    @State private var nearbyUser: [PlaceWithDistance] = []
    @State private var showingCityPicker = false
    @State private var showingWeatherForecast = false
    @State private var selectedCategoryGroup: POICategoryGroup?
    @State private var poiResults: [POIPlace] = []
    @State private var poiLoading = false
    /// Halal/Kosher/Vegetarian/Vegan — orthogonal to `selectedCategoryGroup`
    /// (Apple's own POI taxonomy has no dietary tags at all), sourced from
    /// OpenStreetMap via the same `/places/dietary` endpoint the map screen
    /// uses. Kept as a separate result list, not merged into `poiResults`,
    /// since these are lightweight OSM pins with no `MKMapItem` behind them.
    @State private var dietaryFilter: DietTag?
    @State private var dietaryResults: [DietaryPin] = []
    @State private var dietaryLoading = false
    /// See `ExploreScreen`'s identical field for why an empty string (not
    /// a missing key) means "checked, no photo found".
    @State private var poiPhotoURLs: [String: String] = [:]
    @State private var selectedPOI: POIPlace?

    private var profile: UserProfile { userProfileStore.profile }
    private var hasProfile: Bool {
        profile.profession != nil || !profile.interests.isEmpty || profile.faith != nil
            || profile.budget != nil || profile.groupType != nil || profile.pace != nil
    }

    // Dormant with the rest of the `useCuratedHomeData == false` branch —
    // `RecentlyViewedStore` now stores Apple POI references, which don't
    // correspond to curated place ids, so this can no longer find matches.
    private var recentlyViewedPlaces: [Place] {
        recentlyViewedStore.viewed.map(\.identifier).compactMap(placesQuery.place)
    }

    private var ranked: [Place] {
        hasProfile || !recentlyViewedPlaces.isEmpty
            ? PlaceFilters.sortedForProfile(placesQuery.places, profile: profile, viewed: recentlyViewedPlaces)
            : PlaceFilters.sortedForBrowse(placesQuery.places)
    }

    private var featured: [Place] { Array(ranked.filter(PlaceFilters.isHighQuality).prefix(8)) }
    private var openNow: [Place] { Array(ranked.filter { PlaceHours.isOpen(PlaceHours.openStatus(for: $0)) }.prefix(5)) }
    private var localFavorites: [Place] { Array(ranked.filter { $0.tags.contains("local favorite") }.prefix(5)) }
    private var rainyDay: [Place] { Array(ranked.filter { $0.tags.contains("rainy day") }.prefix(4)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                categoryChipsRow
                if !Self.useCuratedHomeData {
                    dietaryChipsRow
                    if dietaryFilter != nil {
                        dietaryResultsSection
                    }
                }

                if let error = placesQuery.errorMessage, !placesQuery.isLoading, Self.useCuratedHomeData {
                    errorBanner(error)
                }

                suggestionCard

                if Self.useCuratedHomeData {
                    if featured.isEmpty, !ranked.isEmpty {
                        section(title: L("home.sections.exploreCity", cityStore.cityName ?? ""), places: Array(ranked.prefix(8)), horizontal: true)
                    } else if !featured.isEmpty {
                        section(title: String(localized: "home.sections.featured"), places: featured, horizontal: true)
                    }

                    if !recentlyViewedPlaces.isEmpty {
                        section(title: String(localized: "home.sections.recentlyViewed"), places: recentlyViewedPlaces, horizontal: true)
                    }

                    if !nearbyUser.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("home.sections.nearYou").font(.system(size: 21, weight: .heavy))
                            ForEach(nearbyUser) { entry in
                                NavigationLink(destination: PlaceDetailScreen(placeId: entry.place.id)) {
                                    PlaceRowView(place: entry.place)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    section(title: String(localized: "home.sections.openRightNow"), places: openNow)
                    section(
                        title: hasProfile ? String(localized: "home.sections.forYou") : String(localized: "home.sections.localFavorites"),
                        places: localFavorites
                    )
                    section(title: String(localized: "home.sections.rainyDay"), places: rainyDay)
                } else {
                    poiSection
                }
            }
            .padding(.bottom, 40)
        }
        .refreshable {
            if Self.useCuratedHomeData {
                await placesQuery.refresh()
            } else {
                await loadPOIs()
            }
        }
        .task {
            locationManager.requestWhenInUseAuthorization()
            if Self.useCuratedHomeData {
                await placesQuery.load(cityName: cityStore.cityName, lat: cityStore.lat, lng: cityStore.lng)
            }
            if let lat = cityStore.lat ?? locationManager.currentLocation?.latitude,
               let lng = cityStore.lng ?? locationManager.currentLocation?.longitude {
                await weatherQuery.load(lat: lat, lng: lng)
            }
            if let location = locationManager.currentLocation {
                nearbyUser = placesQuery.nearbyUser(lat: location.latitude, lng: location.longitude)
            }
            if !Self.useCuratedHomeData {
                await loadPOIs()
            }
        }
        .onChange(of: selectedCategoryGroup?.id) { _, _ in
            guard !Self.useCuratedHomeData else { return }
            Task { await loadPOIs() }
        }
        .onChange(of: dietaryFilter) { _, filter in
            guard let filter else {
                dietaryResults = []
                return
            }
            Task { await loadDietaryResults(filter) }
        }
        .sheet(isPresented: $showingCityPicker) { CityPickerScreen() }
        .sheet(item: $selectedPOI) { poi in POIExplainSheet(poi: poi) }
        .sheet(isPresented: $showingWeatherForecast) {
            if let weather = weatherQuery.weather,
               let lat = cityStore.lat ?? locationManager.currentLocation?.latitude,
               let lng = cityStore.lng ?? locationManager.currentLocation?.longitude {
                WeatherForecastSheet(lat: lat, lng: lng, current: weather)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PIRI").font(.system(size: 26, weight: .heavy)).tracking(6).foregroundStyle(Theme.gold)
                    Text(greeting).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    Button {
                        showingCityPicker = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: cityStore.cityName != nil ? "mappin" : "globe")
                            Text((cityStore.cityName.map { L("home.cityPill", $0) } ?? String(localized: "common.everywhere")) + " ›")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
                if let weather = weatherQuery.weather {
                    Button {
                        Haptics.light()
                        showingWeatherForecast = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: weather.condition.icon).foregroundStyle(.white.opacity(0.9))
                            Text("\(Int(weather.temp))°").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                            Text(weather.city).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            NavigationLink(destination: ExploreScreen()) {
                Text("common.searchPlaces")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .piriGlassSurface()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let key = hour < 12 ? "home.greeting.morning" : hour < 17 ? "home.greeting.afternoon" : "home.greeting.evening"
        let base = String(localized: String.LocalizationValue(key))
        return profile.name.isEmpty ? base : L("home.greeting.withName", base, profile.name)
    }

    // Apple's own POI categories (same grouping as the map screen's category
    // chips) rather than Piri's own tag taxonomy, while curated data is
    // disabled — see `useCuratedHomeData`.
    private var categoryChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(POICategoryGroups.all) { group in
                    let active = selectedCategoryGroup?.id == group.id
                    Button(String(localized: String.LocalizationValue(group.labelKey))) {
                        selectedCategoryGroup = active ? nil : group
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(active ? Theme.gold : Theme.navy.opacity(0.08)))
                    .foregroundStyle(active ? .white : .primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    /// Orthogonal to `categoryChipsRow` — a dietary need, not an Apple POI
    /// category, so it's its own row rather than folded into the same one.
    /// Same single-select-with-toggle-off interaction as the category chips.
    private var dietaryChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DietTag.allCases) { tag in
                    let active = dietaryFilter == tag
                    // See `MapScreen.dietaryChips`: `String.LocalizationValue`
                    // treats a directly-interpolated literal as a format
                    // string with the interpolated part as an *argument*,
                    // not part of the lookup key — building the key as a
                    // plain `String` first avoids that.
                    let key: String = "diet.\(tag.rawValue)"
                    Button(String(localized: String.LocalizationValue(key))) {
                        dietaryFilter = active ? nil : tag
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(active ? Theme.gold : Theme.navy.opacity(0.08)))
                    .foregroundStyle(active ? .white : .primary)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Shown only while a dietary filter is active — the primary thing the
    /// user is looking for at that point, so it sits ahead of the plain POI
    /// list. Lightweight rows only (name + which diet tags matched), no tap
    /// action — these are OSM pins with no `MKMapItem` behind them, so there's
    /// nothing to open a full `POIExplainSheet` on, matching the map
    /// screen's `dietaryPinCard`.
    private var dietaryResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("dietaryResults.title").font(.system(size: 21, weight: .heavy))
                .padding(.horizontal, 20)
            if dietaryLoading {
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonBox().frame(height: 52) }
                }
                .padding(.horizontal, 20)
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
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
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
        if let lat = cityStore.lat, let lng = cityStore.lng {
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
        let box = dietaryBoundingBox(center: coordinate, radiusMeters: 4000)
        let fetched = (try? await DietaryPlacesAPI.fetchNearby(minLat: box.minLat, maxLat: box.maxLat, minLng: box.minLng, maxLng: box.maxLng, diet: tag)) ?? []
        guard dietaryFilter == tag else { return }
        dietaryResults = fetched
    }

    // Photo-forward 2-column grid, mirroring ExploreScreen's `resultsGrid` —
    // this used to be a plain list of 44×44-thumbnail rows, making the
    // first screen a user sees the least visual one in the app despite
    // already fetching the same `poiPhotoURLs` data ExploreScreen shows at
    // full card size. See the 2026-08 visual-design research report,
    // Phase 1: no new data, just the same photos shown bigger.
    private var poiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("home.sections.nearYou").font(.system(size: 21, weight: .heavy))
                .padding(.horizontal, 20)
            if poiLoading {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonBox().frame(height: 140) }
                }
                .padding(.horizontal, 16)
            } else if poiResults.isEmpty {
                Text("home.sections.nearYouEmpty")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(poiResults) { poi in
                        Button {
                            selectedPOI = poi
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                nearbyTileImage(for: poi).frame(height: 100)
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
    }

    private func loadPOIs() async {
        let coordinate: CLLocationCoordinate2D?
        if let lat = cityStore.lat, let lng = cityStore.lng {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            // `.currentLocation` is only populated once CoreLocation's
            // delegate fires, which can be well after this runs on first
            // launch — do a bounded one-shot wait instead of reading it
            // synchronously and silently finding nothing.
            coordinate = await locationManager.currentLocationOnce()
        }
        guard let coordinate else { return }
        poiLoading = true
        defer { poiLoading = false }
        let fetched = await POISearchService.search(near: coordinate, categories: selectedCategoryGroup?.categories)
        // Same principle as ExploreScreen: only reorder the unfiltered
        // "everything nearby" browse, not an already-homogeneous category
        // filter.
        poiResults = selectedCategoryGroup == nil ? POICategoryGroups.prioritizingSights(fetched) : fetched
        loadNearbyPhotosIfNeeded()
    }

    @ViewBuilder
    private func nearbyTileImage(for poi: POIPlace) -> some View {
        let urlString = poiPhotoURLs[poi.name]
        if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
            CachedAsyncImage(url: url, maxPixelSize: 300) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                nearbyIconFallback(for: poi)
            }
            .clipped()
        } else {
            nearbyIconFallback(for: poi)
        }
    }

    private func nearbyIconFallback(for poi: POIPlace) -> some View {
        ZStack {
            POICategoryGroups.gradient(for: poi.category)
            Image(systemName: POICategoryGroups.icon(for: poi.category))
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private func loadNearbyPhotosIfNeeded() {
        let missing = poiResults.filter { poiPhotoURLs[$0.name] == nil }.prefix(20)
        guard !missing.isEmpty else { return }
        let request = PhotoBulkRequest(places: missing.map {
            PhotoBulkPlace(name: $0.name, lat: $0.coordinate.latitude, lng: $0.coordinate.longitude, category: $0.categoryLabel.isEmpty ? nil : $0.categoryLabel)
        })
        Task {
            guard let response = try? await PlacesAPI.photosBulk(request) else { return }
            for result in response.results {
                poiPhotoURLs[result.name] = result.photoUrl ?? ""
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Text(message).font(.system(size: 14)).lineLimit(2)
            Spacer()
            Button("common.retry") { Task { await placesQuery.refresh() } }
                .font(.system(size: 14, weight: .bold))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.closedRed.opacity(0.1)))
        .padding(.horizontal, 20)
    }

    /// Single priority slot replacing three banners that used to stack on
    /// top of each other (profile nudge, weather, "Ask Piri") whenever more
    /// than one applied at once — up to three "please engage with me" cards
    /// competing for attention on the very first screen. Picks the single
    /// most relevant one instead: filling out a profile (unlocks
    /// personalization) outranks a contextual weather tip, which outranks
    /// the evergreen AI-chat fallback. See the 2026-08 visual-design
    /// research report, Phase 1.
    @ViewBuilder
    private var suggestionCard: some View {
        if !hasProfile, !poiLoading {
            profileNudge
        } else if let weather = weatherQuery.weather {
            weatherBanner(weather)
        } else {
            aiBanner
        }
    }

    private var profileNudge: some View {
        NavigationLink(destination: ProfileScreen()) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("home.profileNudge.title").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text("home.profileNudge.body").font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text("›").font(.system(size: 24)).foregroundStyle(Theme.gold)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.navy.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private func weatherBanner(_ weather: Weather) -> some View {
        Button {
            tabSelection.selection = 3
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: weather.condition.icon).font(.system(size: 28)).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text(weatherBannerMessage(weather)).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    Text("home.weatherBanner.cta").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.navy.opacity(0.85)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private func weatherBannerMessage(_ weather: Weather) -> String {
        switch weather.condition {
        case .rainy, .stormy: return String(localized: "home.weatherBanner.rainy")
        case .snowy: return String(localized: "home.weatherBanner.snowy")
        case .sunny where weather.temp > 22: return String(localized: "home.weatherBanner.sunnyHot")
        case .sunny where weather.temp > 16: return String(localized: "home.weatherBanner.sunnyMild")
        case .foggy: return String(localized: "home.weatherBanner.foggy")
        default: return L("home.weatherBanner.fallback", weather.description, weather.city)
        }
    }

    @ViewBuilder
    private func section(title: String, places: [Place], horizontal: Bool = false) -> some View {
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 21, weight: .heavy))
                    .padding(.horizontal, 20)
                if horizontal {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(places) { place in
                                NavigationLink(destination: PlaceDetailScreen(placeId: place.id)) {
                                    FeaturedCardView(place: place)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(places) { place in
                            NavigationLink(destination: PlaceDetailScreen(placeId: place.id)) {
                                PlaceRowView(place: place)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var aiBanner: some View {
        Button {
            tabSelection.selection = 3
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("home.aiBanner.title").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    Text("home.aiBanner.sub").font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text("›").font(.system(size: 28)).foregroundStyle(Theme.gold)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.navy))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}
