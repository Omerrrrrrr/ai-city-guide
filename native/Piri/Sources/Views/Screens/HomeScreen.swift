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
            VStack(alignment: .leading, spacing: 16) {
                header
                categoryChipsRow
                if !Self.useCuratedHomeData, dietaryFilter != nil {
                    dietaryResultsSection
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
                            Image(systemName: weather.condition.icon).foregroundStyle(Theme.gold)
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
        // Plain fill, not `piriGlassSurface()` -- that material's own edge
        // highlight read as an unwanted rectangular border once the body
        // below went navy too (see `Theme.screenBackground`): with nothing
        // behind it left to blur/tint differently, the glass shape's own
        // bounds became the only visible thing about it. A flat fill reads
        // seamlessly with the (now identically navy) scroll content below.
        .background(Theme.navy)
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
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(POICategoryGroups.all) { group in
                        let active = selectedCategoryGroup?.id == group.id
                        Button {
                            selectedCategoryGroup = active ? nil : group
                        } label: {
                            Label(String(localized: String.LocalizationValue(group.labelKey)), systemImage: group.icon)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(active ? Theme.gold : Theme.navy.opacity(0.08)))
                        .foregroundStyle(active ? .white : .primary)
                    }
                }
                .padding(.leading, 20)
            }
            // Not gated by `useCuratedHomeData` the way `dietaryResultsSection`
            // still is below -- the button itself is harmless to show either
            // way, and keeping it in this always-rendered row (rather than a
            // separate conditional one) is what makes it a persistent,
            // non-scrolling fixture next to the category chips.
            if !Self.useCuratedHomeData {
                DietaryFilterButton(selection: Binding(get: { dietaryFilter }, set: { dietaryFilter = $0 }))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                    ForEach(poiResults) { poi in
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
                                        Text(poi.name).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                                        if !poi.categoryLabel.isEmpty {
                                            Text(poi.categoryLabel).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                                        }
                                        personalizedBadge(for: poi)
                                    }
                                    .padding(12)
                                }
                                .frame(height: 170)
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
    private func nearbyTileImage(for poi: POIPlace) -> some View {
        let urlString = poiPhotos[poi.name]?.photoUrl
        GeometryReader { geo in
            if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, maxPixelSize: 400) { image in
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
                    Text("Unsplash")
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
