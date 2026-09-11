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
    @Environment(AuthStore.self) private var authStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 34
    @ScaledMetric(relativeTo: .title) private var featuredTitleSize = 29

    @State private var weatherQuery = WeatherQuery()
    @State private var holidayQuery = HolidayQuery()
    @State private var goldenHour: GoldenHour?
    @State private var showingHolidayDetail: UpcomingHoliday?
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
    /// Backed by `@AppStorage`, and the same key `MapScreen` uses, so
    /// picking a filter here also shows it pre-selected on Map (and vice
    /// versa) instead of it resetting every time -- see `DietaryFilterButton`.
    @AppStorage("dietaryFilterRawValue") private var dietaryFilterRawValue: String = ""
    private var dietaryFilter: DietTag? {
        get { DietTag(rawValue: dietaryFilterRawValue) }
        nonmutating set { dietaryFilterRawValue = newValue?.rawValue ?? "" }
    }
    @State private var dietaryResults: [DietaryPin] = []
    @State private var dietaryLoading = false
    /// See `ExploreScreen`'s identical field for why an empty string (not
    /// a missing key) means "checked, no photo found".
    @State private var poiPhotos: [String: PhotoBulkResult] = [:]
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
            VStack(alignment: .leading, spacing: 6) {
                header
                categoryChipsRow
                if !Self.useCuratedHomeData, dietaryFilter != nil {
                    dietaryResultsSection
                }

                if let error = placesQuery.errorMessage, !placesQuery.isLoading, Self.useCuratedHomeData {
                    errorBanner(error)
                }

                if !Self.useCuratedHomeData { featuredPOICard }
                aiBanner
                savedShortcuts

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

                if !hasProfile, !poiLoading { profileNudge }
                if soonHoliday != nil || goldenHour?.activeWindow != nil { infoPillsRow }
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
                await weatherQuery.load(lat: lat, lng: lng, cityName: cityStore.cityName)
                await holidayQuery.load(lat: lat, lng: lng, locale: Locale.current.language.languageCode?.identifier)
                goldenHour = try? await SunTimesAPI.fetch(lat: lat, lng: lng)
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
        .sheet(item: $showingHolidayDetail) { holiday in HolidayDetailSheet(holiday: holiday) }
        .sheet(isPresented: $showingWeatherForecast) {
            if let weather = weatherQuery.weather,
               let lat = cityStore.lat ?? locationManager.currentLocation?.latitude,
               let lng = cityStore.lng ?? locationManager.currentLocation?.longitude {
                WeatherForecastSheet(lat: lat, lng: lng, current: weather)
            }
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationBarHidden(true)
    }

    private func localizedCategory(_ poi: POIPlace) -> String {
        guard let category = poi.category,
              let group = POICategoryGroups.all.first(where: { $0.categories?.contains(category) == true }) else { return poi.categoryLabel }
        return String(localized: String.LocalizationValue(group.labelKey))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("PIRI")
                    .font(Theme.editorial(size: 28))
                    .tracking(1.5)
                    .foregroundStyle(Theme.gold)
                    .accessibilityAddTraits(.isHeader)
                Button { showingCityPicker = true } label: {
                    HStack(spacing: 5) {
                        Text(cityStore.cityName ?? String(localized: "common.everywhere"))
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Theme.cardFill, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if let weather = weatherQuery.weather {
                    Button {
                        Haptics.light()
                        showingWeatherForecast = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: weather.condition.icon).foregroundStyle(Theme.gold)
                            Text("\(Int(weather.temp))°").foregroundStyle(.white)
                        }
                        .font(.body)
                        .fixedSize()
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(weather.city), \(Int(weather.temp))°")
                }
            }
            Text(String(localized: "design.home.title"))
                .font(Theme.editorial(size: headlineSize))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            NavigationLink(destination: ExploreScreen()) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.title3)
                    Text("common.searchPlaces").font(.subheadline)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Theme.cardFill, in: Capsule())
                .overlay(Capsule().stroke(Theme.border))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
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
    private var homeCategoryGroups: [POICategoryGroup] {
        let priority = ["mapPoiCategories.cafes", "mapPoiCategories.culture"]
        let groups = POICategoryGroups.all.filter { $0.categories != nil }
        return priority.compactMap { key in groups.first { $0.labelKey == key } }
            + groups.filter { !priority.contains($0.labelKey) }
    }

    private var categoryChipsRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { selectedCategoryGroup = nil } label: {
                        Text("categoryFilters.all")
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(selectedCategoryGroup == nil ? Theme.gold : Theme.cardFill, in: Capsule())
                            .foregroundStyle(selectedCategoryGroup == nil ? Theme.navy : .white)
                            .overlay(Capsule().stroke(selectedCategoryGroup == nil ? .clear : Theme.border))
                    }
                    .accessibilityAddTraits(selectedCategoryGroup == nil ? .isSelected : [])
                    ForEach(homeCategoryGroups) { group in
                        let active = selectedCategoryGroup?.id == group.id
                        Button { selectedCategoryGroup = active ? nil : group } label: {
                            Label(String(localized: String.LocalizationValue(group.labelKey)), systemImage: group.icon)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(active ? Theme.gold : Theme.cardFill, in: Capsule())
                                .foregroundStyle(active ? Theme.navy : .white)
                                .overlay(Capsule().stroke(active ? .clear : Theme.border))
                        }
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
            }
            if !Self.useCuratedHomeData {
                DietaryFilterButton(selection: Binding(get: { dietaryFilter }, set: { dietaryFilter = $0 }))
            }
        }
        .padding(.horizontal, 20)
    }

    private var featuredHomePOI: POIPlace? {
        poiResults.first { poi in
            guard let url = poiPhotos[poi.name]?.photoUrl else { return false }
            return !url.isEmpty
        } ?? poiResults.first
    }

    @ViewBuilder
    private var featuredPOICard: some View {
        if let poi = featuredHomePOI {
            ZStack(alignment: .topTrailing) {
                Button { selectedPOI = poi } label: {
                    VStack {
                        Spacer(minLength: 100)
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("home.sections.nearYou")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Theme.navy.opacity(0.85), in: Capsule())
                                Text(poi.name)
                                    .font(Theme.editorial(size: featuredTitleSize))
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !poi.categoryLabel.isEmpty {
                                    Text(localizedCategory(poi)).font(.subheadline)
                                }
                                personalizedBadge(for: poi)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Theme.navy)
                                .frame(width: 46, height: 46)
                                .background(Theme.gold, in: Circle())
                        }
                        .padding(18)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .background {
                        nearbyTileImage(for: poi, maxPixelSize: 1000)
                            .overlay(LinearGradient(stops: [
                                .init(color: .clear, location: 0.35),
                                .init(color: .black.opacity(0.82), location: 1)
                            ], startPoint: .top, endPoint: .bottom))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("piri.home.featured")
                unsplashBadge(for: poi)
            }
            .padding(.horizontal, 16)
        } else if poiLoading {
            SkeletonBox().frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 16)
        }
    }

    private var savedShortcuts: some View {
        let savedCount = Set(savedPlacesStore.savedLists.flatMap(\.places).map(\.identifier)).count
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                savedShortcut(tab: .saved, count: savedCount)
                savedShortcut(tab: .plan, count: savedPlacesStore.plans.count)
            }
            VStack(spacing: 10) {
                savedShortcut(tab: .saved, count: savedCount)
                savedShortcut(tab: .plan, count: savedPlacesStore.plans.count)
            }
        }
        .padding(.horizontal, 20)
    }

    private func savedShortcut(tab: SavedTab, count: Int) -> some View {
        NavigationLink(destination: SavedScreen(initialTab: tab)) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tab == .saved ? "bookmark" : "calendar")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(tab == .saved ? String(localized: "design.home.saved") : String(localized: "design.home.plans"))
                        .font(.subheadline.weight(.medium))
                    Text(tab == .saved
                         ? LPlural("saved.collections.placesCount", count: count)
                         : LPlural("design.home.planCount", count: count))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(minHeight: 64)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        }
        .buttonStyle(.plain)
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
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardFill))
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
    // already fetching the same `poiPhotos` data ExploreScreen shows at
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
                // `alignment: .top` on each column -- without it, a
                // `GridItem` centers its cell within the row's height
                // (the tallest cell in that row), so a card with a
                // 1-line name would sit vertically centered next to a
                // 2-line-name sibling instead of starting at the same Y
                // -- confirmed live via the accessibility hierarchy: two
                // cards in the same row had card-top Y-origins 39pt
                // apart, tracking exactly with 1-line vs. 2-line names.
                LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .top)] : [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                    ForEach(poiResults.filter { $0.id != featuredHomePOI?.id }) { poi in
                        // The Unsplash attribution badge is a sibling
                        // overlay, not nested inside the Button's own label
                        // — two full-size overlapping tappable controls
                        // (the card's Button, a Link for the photo credit)
                        // don't compose reliably as parent/child in SwiftUI,
                        // so this keeps them as independent hit-targets at
                        // the same level instead.
                        ZStack(alignment: .topTrailing) {
                            Button {
                                selectedPOI = poi
                            } label: {
                                // Photo fills the whole card with name/
                                // category overlaid on a gradient, matching
                                // the same premium photo-first treatment
                                // Saved's collection tiles and Trips' cards
                                // already use, instead of the photo sitting
                                // as a separate strip above a plain-white
                                // text block.
                                ZStack(alignment: .bottomLeading) {
                                    nearbyTileImage(for: poi)
                                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(poi.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                        if !poi.categoryLabel.isEmpty {
                                            Text(poi.categoryLabel).font(.caption).foregroundStyle(.white.opacity(0.75))
                                        }
                                        personalizedBadge(for: poi)
                                    }
                                    .padding(12)
                                    .padding(.top, 65)
                                }
                                .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 240 : 170)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)

                            unsplashBadge(for: poi)
                        }
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
        if selectedCategoryGroup == nil {
            let sightsFirst = POICategoryGroups.prioritizingSights(fetched)
            // sortedForProfile is a no-op stable re-sort when there's no
            // profile match, so this is always safe to call — the
            // sightsFirst order survives untouched until there's a real
            // profession/interest signal to act on.
            poiResults = POICategoryGroups.sortedForProfile(sightsFirst, profile: profile, viewed: recentlyViewedStore.viewed)
        } else {
            poiResults = fetched
        }
        loadNearbyPhotosIfNeeded()
    }

    // A plain `.frame(height: 100).clipped()` on `aspectRatio(.fill)`
    // content turned out unreliable here -- confirmed live via the
    // accessibility hierarchy that a portrait-source photo (e.g. a tall
    // aerial shot) still rendered at 181-271pt instead of 100pt regardless
    // of whether `.frame` came before or after `.clipped()` in the
    // modifier chain, which is what was bleeding down into the name/
    // category text below for any non-landscape source photo. Reading the
    // exact box size from a `GeometryReader` and applying it directly as
    // the image's own `.frame(width:height:)` (rather than letting
    // `aspectRatio(.fill)` infer a size from an ambient proposal) is the
    // standard, unambiguous fix for this SwiftUI sizing gap.
    @ViewBuilder
    private func nearbyTileImage(for poi: POIPlace, maxPixelSize: CGFloat = 400) -> some View {
        let urlString = poiPhotos[poi.name]?.photoUrl
        GeometryReader { geo in
            if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, maxPixelSize: maxPixelSize) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    nearbyIconFallback(for: poi)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            } else {
                nearbyIconFallback(for: poi)
            }
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

    /// Names *why* this card was ranked up, not just that it was — a
    /// personalized ranking with no visible trace of itself reads to the
    /// user as no personalization at all (and can't be corrected if it's
    /// ever wrong). Only the single strongest reason is shown, even if
    /// several matched. See the 2026-08 visual-design research report,
    /// Phase 2, and `POICategoryGroups.personalizationReasons`.
    @ViewBuilder
    private func personalizedBadge(for poi: POIPlace) -> some View {
        if selectedCategoryGroup == nil, let reason = POICategoryGroups.personalizationReasons(for: poi, profile: profile).first {
            Label(L("home.personalized", String(localized: String.LocalizationValue(reason.labelKey))), systemImage: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .lineLimit(1)
        }
    }

    /// Unsplash's API Terms (§9) require attributing Unsplash and the
    /// photographer, linked, every time a photo is displayed — the grid
    /// card has no secondary detail view showing this same photo again, so
    /// unlike `POIPhotoGallery`'s full-screen viewer, this can't defer full
    /// attribution to "somewhere else in the flow." A sibling `Link` (not
    /// nested inside the card's own `Button`, which two overlapping
    /// controls don't handle reliably) opens the photographer's profile.
    @ViewBuilder
    private func unsplashBadge(for poi: POIPlace) -> some View {
        if let photo = poiPhotos[poi.name], photo.source == "unsplash",
           let photographerUrl = photo.photographerUrl, let url = URL(string: photographerUrl) {
            HStack(spacing: 4) {
                Link(destination: url) {
                    Text(photo.photographerName.map { "\($0) · Unsplash" } ?? "Unsplash")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                // Upsell hint only for someone who'd actually benefit from
                // it — a paid account already gets Google's own photos
                // (see /places/explain-poi) wherever it matters, so showing
                // "upgrade for this" to someone who already paid would be
                // wrong, not just redundant.
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

    private func loadNearbyPhotosIfNeeded() {
        let missing = poiResults.filter { poiPhotos[$0.name] == nil }.prefix(20)
        guard !missing.isEmpty else { return }
        let request = PhotoBulkRequest(places: missing.map {
            PhotoBulkPlace(name: $0.name, lat: $0.coordinate.latitude, lng: $0.coordinate.longitude, category: $0.categoryLabel.isEmpty ? nil : $0.categoryLabel)
        })
        Task {
            guard let response = try? await PlacesAPI.photosBulk(request, token: authStore.token) else { return }
            for result in response.results {
                poiPhotos[result.name] = result
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

    /// Priority slot: a profile nudge (unlocks personalization) still
    /// outranks everything else and still takes the full-banner treatment
    /// alone, same reasoning as before. Below that, weather/golden-hour/
    /// holiday no longer fight over one slot — collapsed into small
    /// side-by-side tiles (`infoPillsRow`) light enough to show together
    /// without recreating the original "three competing banners" problem
    /// these were once consolidated to avoid; the evergreen AI-chat banner
    /// keeps its own separate, lowest-priority fallback slot for when none
    /// of the contextual tiles apply at all.
    @ViewBuilder
    private var suggestionCard: some View {
        if !hasProfile, !poiLoading {
            profileNudge
        } else if soonHoliday != nil || goldenHour?.activeWindow != nil {
            infoPillsRow
        } else {
            aiBanner
        }
    }

    // Weather itself doesn't get a pill here anymore -- the header's own
    // weather capsule (top-right, always visible whenever `weatherQuery.weather`
    // exists) already shows it, and showing it again here read as a plain
    // duplicate with no new information. Golden-hour/holiday still don't
    // have a header-level slot of their own, so they keep theirs.
    private var infoPillsRow: some View {
        HStack(spacing: 10) {
            if let window = goldenHour?.activeWindow {
                infoPill(icon: "sun.horizon.fill", title: String(localized: "home.goldenHourPill.title"), subtitle: goldenHourRangeText(window))
            }
            if let holiday = soonHoliday {
                infoPill(icon: "flag.fill", title: holiday.name, subtitle: holidayWhenText(holiday)) {
                    showingHolidayDetail = holiday
                }
            }
            // Without this, a single pill (the common case: golden hour
            // only ever applies for part of the day, and most days have no
            // holiday within a week) stretched to the full row width via
            // its own `maxWidth: .infinity` -- confirmed live, an
            // odd-looking full-width "18° Rainy" slab instead of a compact
            // tile. Capping each tile's width and absorbing the rest here
            // keeps 1-3 pills all reading as the same small tile size.
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private func infoPill(icon: String, title: String, subtitle: String, action: (() -> Void)? = nil) -> some View {
        Group {
            if let action {
                Button {
                    Haptics.light()
                    action()
                } label: { infoPillLabel(icon: icon, title: title, subtitle: subtitle) }
                .buttonStyle(.plain)
            } else {
                infoPillLabel(icon: icon, title: title, subtitle: subtitle)
            }
        }
    }

    private func infoPillLabel(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.gold)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(width: 100)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy.opacity(0.7)))
    }

    private func goldenHourRangeText(_ window: (start: Date, end: Date)) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: window.start))–\(formatter.string(from: window.end))"
    }

    private func holidayWhenText(_ holiday: UpcomingHoliday) -> String {
        let daysUntil = holiday.dateValue.map { Calendar.current.dateComponents([.day], from: .now, to: $0).day ?? 0 } ?? 0
        return daysUntil <= 0
            ? String(localized: "home.holidayBanner.today")
            : LPlural("home.holidayBanner.inDays", count: daysUntil)
    }

    /// Within a week — close enough to be genuinely useful travel context
    /// (closed shops, a parade worth planning around) without this slot
    /// showing a holiday that's still a distant, not-yet-actionable
    /// two months out. `holidayQuery.holidays` is already sorted
    /// soonest-first server-side, so the first match here is the next one.
    private var soonHoliday: UpcomingHoliday? {
        holidayQuery.holidays.first {
            guard let days = $0.dateValue.map({ Calendar.current.dateComponents([.day], from: .now, to: $0).day ?? 999 }) else { return false }
            return days >= 0 && days <= 7
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
        Button { tabSelection.selection = 3 } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.gold)
                    planningLabel
                    Spacer(minLength: 4)
                    planningAction
                }
                VStack(alignment: .leading, spacing: 10) {
                    planningLabel
                    planningAction
                }
            }
            .padding(12)
            .frame(minHeight: 64)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var planningLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "design.home.planTogether"))
                .font(.subheadline.weight(.medium)).foregroundStyle(.white)
            Text(String(localized: "design.home.planSubtitle"))
                .font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var planningAction: some View {
        HStack(spacing: 5) {
            Text(String(localized: "design.home.askPiri"))
            Image(systemName: "arrow.right")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.gold)
        .fixedSize()
    }
}
