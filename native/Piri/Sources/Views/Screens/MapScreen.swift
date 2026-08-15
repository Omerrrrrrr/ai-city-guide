import MapKit
import SwiftUI

/// Port of `mobile/app/(tabs)/map.tsx`. The RN version had to gate live-pin
/// fetching behind a manual "Discover this area" button and a hard
/// server-side cap (`MAX_LIVE_PINS_RESPONSE = 25`) because bulk marker churn
/// crashed `react-native-maps` under Fabric's legacy-interop bridge. MKMapView
/// has no such ceiling, so here the fetch just runs — debounced — on every
/// settled region change, same as panning any other native maps app.
///
/// 2026-08-08: at the user's request, Piri's own curated/live pin data is
/// switched off here in favor of Apple's native MapKit POI layer (every POI
/// on the map is tappable, category chips filter Apple's own categories via
/// `pointOfInterestFilter`, and tapping any POI gets an ephemeral
/// AI-personalized blurb from `/places/explain-poi` instead of a curated
/// description). This is a deliberate, reversible toggle, not a deletion —
/// the curated fetch/render path below is intact, just gated off. Revisit
/// this decision later; flip `useCuratedMapData` back to `true` to restore it.
struct MapScreen: View {
    private static let useCuratedMapData = false

    // Not `private` — `MapScreen+RouteMode.swift` (an extension, so it can't
    // declare its own stored/environment properties) needs access to these.
    @Environment(CityStore.self) var cityStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(TripsStore.self) var tripsStore
    @Environment(TabSelection.self) private var tabSelection

    @State var locationManager = LocationManager()
    @State private var places: [Place] = []
    @State private var livePins: [LivePin] = []
    @State private var selectedCategoryGroup: POICategoryGroup?
    @State private var mapType: MKMapType = .standard
    /// A filter for anyone with a dietary need, not one faith — see
    /// `DietTag`. Orthogonal to `selectedCategoryGroup`: this drives a
    /// separate live pin layer (`dietaryPins`, sourced from OpenStreetMap),
    /// not Apple's own `pointOfInterestFilter`, since Apple's POI data
    /// carries no dietary tags at all.
    @State private var dietaryFilter: DietTag?
    @State private var dietaryPins: [DietaryPin] = []
    @State private var dietaryFetchTask: Task<Void, Never>?
    @State private var selectedDietaryPin: DietaryPin?
    /// Updated on every `handleRegionChange` call (unlike `initialRegion`,
    /// which is set once and deliberately not kept in sync with panning) so
    /// toggling `dietaryFilter` can immediately fetch against wherever the
    /// map currently is, without waiting for the next pan/zoom.
    @State private var currentRegion: MKCoordinateRegion?
    @State private var selectedPlace: Place?
    @State private var selectedLivePin: LivePin?
    @State private var selectedMapFeature: MKMapFeatureAnnotation?
    @State private var poiExplainResult: ExplainResult?
    @State private var poiExplainLoading = false
    /// Separate from the shared `errorMessage` banner (search/directions/live
    /// pins) so a POI-explain failure shows inline in `mapFeatureCard` with
    /// its own retry button, instead of a disconnected top-of-screen banner
    /// that could also linger after the card that caused it is dismissed.
    @State private var poiExplainError: String?
    /// Fetched alongside (not blocking) the AI explain call — independent of
    /// `poiExplainCache`, since a cache hit on the AI text shouldn't also
    /// serve stale weather. `WeatherQuery` has its own 30-minute cache.
    @State private var mapFeatureWeatherQuery = WeatherQuery()
    /// Resolved alongside the AI explain call so `mapFeatureCard` can show
    /// its plain phone/website fields and offer the full Place Card sheet.
    @State private var resolvedMapFeatureItem: MKMapItem?
    @State private var showingMapItemDetail = false
    @State private var addToCollectionKind: SavedCollectionKind?
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State var initialRegion: MKCoordinateRegion?
    @State private var recenterTrigger: UUID?
    @State private var searchQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var liveFetchTask: Task<Void, Never>?
    @State private var poiExplainTask: Task<Void, Never>?
    @State private var errorMessage: String?

    // MARK: Route mode (`MapScreen+RouteMode.swift`)
    @State var routeMode = false
    /// Stops are picked by tapping Apple's own base-map POI features (same
    /// resolution path as `explainMapFeature`) — no curated data involved.
    @State var plannedStops: [SavedPOIReference] = []
    @State var routeGeometry: [[Double]]?
    @State var routeDistanceMeters: Double?
    @State var routeDurationSeconds: Double?
    @State var isFetchingRoute = false
    @State var routeError: String?
    @State var showTripPhotoCapture = false
    /// Guards against re-running rehydration/re-starting breadcrumb recording
    /// every time this view re-evaluates its body while a trip is active.
    @State var hydratedTripId: String?

    /// Session-only cache so re-tapping the same POI doesn't re-call the AI
    /// (and re-spend the LLM call) — not persisted, matches the "doesn't
    /// need to be saved, just needs to be fast" requirement. Plain `static`
    /// (not `@State`, which only applies to instance properties) since it's
    /// a shared, non-observed cache rather than view-identity-bound state.
    private static var poiExplainCache: [String: ExplainResult] = [:]

    /// Matches `LIVE_PINS_MAX_LATITUDE_DELTA` in the RN app — live pins only
    /// make sense at city/district zoom, not zoomed out to country level.
    private let maxLiveFetchLatitudeDelta = 0.04

    var filteredPlaces: [Place] {
        guard Self.useCuratedMapData else { return [] }
        guard let selectedCategoryGroup, selectedCategoryGroup.categories != nil else { return places }
        // Curated places use Piri's own category taxonomy, not Apple's
        // MKPointOfInterestCategory — there's no clean mapping between the
        // two, so a POI category chip only filters Apple's own layer while
        // curated data (if re-enabled) stays unfiltered by it.
        return places
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let initialRegion {
                if routeMode, let activeTrip = tripsStore.trips.first(where: { $0.id == tripsStore.activeTripId }) {
                    TripMapView(
                        routeCoordinates: (activeTrip.routeGeometry ?? routeGeometry ?? []).compactMap(coordinate(fromPair:)),
                        breadcrumbCoordinates: activeTrip.breadcrumb.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
                        stops: routeStopAnnotations,
                        initialRegion: activeTripDisplayRegion(for: activeTrip) ?? initialRegion,
                        showsUserLocation: true
                    )
                    .ignoresSafeArea()
                } else {
                    // Route-mode stop-picking reuses this same Apple-POI base
                    // map — tapping a POI feature toggles it as a stop
                    // instead of opening the explain card. There's no way to
                    // tint an already-picked Apple base-tile POI (unlike the
                    // old curated-pin picker), so the stop list in
                    // `routeModeSheet` is the primary "what's selected" UI.
                    PiriMapView(
                        places: filteredPlaces,
                        livePins: Self.useCuratedMapData ? livePins : [],
                        dietaryPins: routeMode ? [] : dietaryPins,
                        // In route mode, a fetched-but-not-yet-started route
                        // (`previewRoute()`) draws here as a preview line —
                        // this is still the plain picking map, not
                        // `TripMapView`, since no trip exists until "Rotayı
                        // Başlat" is actually tapped.
                        routeCoordinates: routeMode ? (routeGeometry ?? []).compactMap(coordinate(fromPair:)) : routeCoordinates,
                        showsUserLocation: true,
                        onRegionChange: handleRegionChange,
                        onSelectPlace: { selectPlace($0) },
                        onSelectLivePin: { selectLivePin($0) },
                        onSelectDietaryPin: { selectDietaryPin($0) },
                        onSelectMapFeature: { feature in
                            if routeMode {
                                Task { await toggleStop(fromFeature: feature) }
                            } else {
                                selectMapFeature(feature)
                            }
                        },
                        pointOfInterestCategories: selectedCategoryGroup?.categories,
                        centerOnce: initialRegion,
                        recenterTrigger: recenterTrigger,
                        mapType: mapType
                    )
                    .ignoresSafeArea()
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 12) {
                if !routeMode {
                    searchBar
                    categoryChips
                    dietaryChips
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
                if routeMode {
                    routeModeSheet
                } else if let selectedPlace {
                    placeCard(for: selectedPlace)
                } else if let selectedLivePin {
                    livePinCard(for: selectedLivePin)
                } else if let selectedDietaryPin {
                    dietaryPinCard(for: selectedDietaryPin)
                } else if let selectedMapFeature {
                    mapFeatureCard(for: selectedMapFeature)
                }
            }
            .padding()
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                mapTypeButton
                routeModeToggleButton
            }
            .padding(20)
        }
        // Not `.navigationTitle` — the system nav bar/large-title reserved a
        // big, unstyled blank band above the map (inconsistent with every
        // other screen's custom `Theme.navy` header, and wasteful here since
        // the map should fill the screen edge-to-edge like Apple's own Maps
        // app, with the search bar floating directly below the status bar).
        .navigationBarHidden(true)
        .task {
            locationManager.requestWhenInUseAuthorization()
            await setInitialRegionIfNeeded()
            if Self.useCuratedMapData {
                await loadCuratedPlaces()
            }
        }
        .task(id: routeMode) {
            guard routeMode else { return }
            rehydrateActiveTripIfNeeded()
        }
        // `.task(id:)`, not `.onChange` — `pendingRouteStops` is very often
        // already set by the time this view first appears (the whole point
        // of the hand-off is jumping here from another tab), and `onChange`
        // only fires on a delta from a baseline observed *while mounted*,
        // so a value that's already non-nil on first appearance never
        // fires it. `.task(id:)` runs immediately on appearance too, not
        // just on subsequent changes. Cleared *after* the work finishes
        // (not before) so re-setting it back to nil doesn't self-cancel
        // this same task mid-flight — `.task(id:)` restarts whenever its id
        // changes, including changes made by its own body.
        .task(id: tabSelection.pendingRouteStops) {
            guard let stops = tabSelection.pendingRouteStops else { return }
            await startPendingRoute(stops)
            tabSelection.pendingRouteStops = nil
        }
        .onChange(of: locationManager.breadcrumb) { _, points in
            guard let activeTripId = tripsStore.activeTripId, let last = points.last else { return }
            tripsStore.addBreadcrumb(activeTripId, point: last)
        }
        // Refetch immediately on filter change, not just on the next pan/
        // zoom -- `currentRegion` is kept in sync by `handleRegionChange` on
        // every region change, unlike `initialRegion`.
        .onChange(of: dietaryFilter) { _, _ in
            if let currentRegion {
                fetchDietaryPinsIfNeeded(for: currentRegion)
            } else {
                dietaryPins = []
            }
        }
        .sheet(isPresented: $showTripPhotoCapture) {
            TripPhotoCaptureSheet { data in
                Task { await attachTripPhoto(data) }
            }
        }
    }

    private var mapTypeButton: some View {
        Menu {
            Button {
                mapType = .standard
            } label: {
                Label(String(localized: "map.style.standard"), systemImage: "map")
            }
            Button {
                mapType = .hybrid
            } label: {
                Label(String(localized: "map.style.hybrid"), systemImage: "square.stack.3d.up")
            }
            Button {
                mapType = .satellite
            } label: {
                Label(String(localized: "map.style.satellite"), systemImage: "globe.americas.fill")
            }
        } label: {
            Image(systemName: mapTypeIconName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(.thinMaterial))
                .shadow(radius: 3)
        }
    }

    private var mapTypeIconName: String {
        switch mapType {
        case .satellite, .satelliteFlyover: return "globe.americas.fill"
        case .hybrid, .hybridFlyover: return "square.stack.3d.up.fill"
        default: return "map"
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(String(localized: "common.searchPlaces"), text: $searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onSubmit {
                    searchTask?.cancel()
                    searchTask = Task { await searchAndCenterMap(searchQuery) }
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .piriGlassCard(cornerRadius: 12)
    }

    private func searchAndCenterMap(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let initialRegion {
            request.region = initialRegion
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled, let coordinate = response.mapItems.first?.placemark.coordinate else { return }
            initialRegion = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            recenterTrigger = UUID()
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(POICategoryGroups.all) { group in
                    let active = selectedCategoryGroup?.id == group.id
                    Button(String(localized: String.LocalizationValue(group.labelKey))) {
                        selectedCategoryGroup = active ? nil : group
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(active ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                    .foregroundStyle(active ? .white : .primary)
                }
            }
        }
    }

    /// Orthogonal to `categoryChips` — a dietary need, not an Apple POI
    /// category, so it's its own row rather than folded into the same one.
    private var dietaryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DietTag.allCases) { tag in
                    let active = dietaryFilter == tag
                    // `String.LocalizationValue` conforms to
                    // `ExpressibleByStringInterpolation` for its
                    // parameterized-string-argument feature -- passing an
                    // interpolated literal directly (`"diet.\(x)"`) makes
                    // Swift treat `x` as a *format argument*, not part of
                    // the lookup key, so it silently fails to resolve and
                    // falls back to echoing the raw interpolated text.
                    // Building the key as a plain `String` first (as
                    // `categoryChips` already does with `group.labelKey`)
                    // avoids that entirely.
                    let key: String = "diet.\(tag.rawValue)"
                    Button(String(localized: String.LocalizationValue(key))) {
                        dietaryFilter = active ? nil : tag
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(active ? Color(.systemGreen) : Color(.secondarySystemBackground), in: Capsule())
                    .foregroundStyle(active ? .white : .primary)
                }
            }
        }
    }

    private func selectPlace(_ place: Place) {
        selectedPlace = place
        selectedLivePin = nil
        selectedMapFeature = nil
        selectedDietaryPin = nil
        poiExplainTask?.cancel()
    }

    private func selectLivePin(_ pin: LivePin) {
        selectedLivePin = pin
        selectedPlace = nil
        selectedMapFeature = nil
        selectedDietaryPin = nil
        poiExplainTask?.cancel()
    }

    private func selectDietaryPin(_ pin: DietaryPin) {
        selectedDietaryPin = pin
        selectedPlace = nil
        selectedLivePin = nil
        selectedMapFeature = nil
        poiExplainTask?.cancel()
    }

    private func selectMapFeature(_ feature: MKMapFeatureAnnotation) {
        selectedMapFeature = feature
        selectedPlace = nil
        selectedLivePin = nil
        selectedDietaryPin = nil
        poiExplainResult = nil
        poiExplainError = nil
        lookAroundScene = nil
        resolvedMapFeatureItem = nil
        showingMapItemDetail = false
        addToCollectionKind = nil
        poiExplainTask?.cancel()
        poiExplainTask = Task { await explainMapFeature(feature) }
        Task { lookAroundScene = try? await MKLookAroundSceneRequest(coordinate: feature.coordinate).scene }
    }

    private func dismissMapFeature() {
        selectedMapFeature = nil
        poiExplainResult = nil
        poiExplainError = nil
        lookAroundScene = nil
        showingMapItemDetail = false
        addToCollectionKind = nil
        poiExplainTask?.cancel()
    }

    // Dormant — `filteredPlaces` (curated data) is always empty while
    // `useCuratedMapData` is off, so `selectedPlace` never gets set and this
    // never renders. Kept compiling (favorite/plan removed since
    // `SavedPlacesStore` now only accepts Apple `POIPlace`, not curated
    // `Place`) rather than deleted, matching the rest of this pivot.
    private func placeCard(for place: Place) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading) {
                Text(place.name).font(.headline)
                Text(place.category).font(.subheadline).foregroundStyle(.secondary)
            }
            Button("common.openInMaps") {
                Task { await fetchDirections(to: place) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .piriGlassCard(cornerRadius: 16)
    }

    private func livePinCard(for pin: LivePin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pin.name).font(.headline)
            Text(pin.category).font(.subheadline).foregroundStyle(.secondary)
            Button("common.showAll") {
                Task { await enrichLivePin(pin) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .piriGlassCard(cornerRadius: 16)
    }

    /// No AI enrichment path, unlike `livePinCard`'s "show all" → full curated
    /// place — this pin type is purely a dietary-match indicator, so the
    /// card is just the name and which tags matched.
    private func dietaryPinCard(for pin: DietaryPin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pin.name).font(.headline)
                Spacer()
                Button {
                    selectedDietaryPin = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
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
        .padding()
        .piriGlassCard(cornerRadius: 16)
    }

    /// Card for ANY tapped map POI — Piri's own pins have a stable DB record
    /// to explain, but most pins on the map are Apple's own base-tile POIs
    /// with nothing in our backend at all. This calls `/places/explain-poi`
    /// with just what `MKMapItemRequest` gives us (name/category/coordinate)
    /// and shows the same personalized-blurb UI `PlaceDetailScreen`'s
    /// "Piri's Take" card uses, without ever persisting anything.
    /// `resolvedMapFeatureItem`, packaged as a `POIPlace` for the
    /// bookmark/flag buttons and `AddToCollectionSheet` — `nil` until
    /// `explainMapFeature` resolves it, same as those buttons' visibility.
    private func resolvedMapFeaturePOI(for feature: MKMapFeatureAnnotation) -> POIPlace? {
        guard let resolvedMapFeatureItem else { return nil }
        return POIPlace(
            name: resolvedMapFeatureItem.name ?? feature.title ?? "",
            category: resolvedMapFeatureItem.pointOfInterestCategory,
            coordinate: feature.coordinate,
            mapItem: resolvedMapFeatureItem
        )
    }

    private func mapFeatureCard(for feature: MKMapFeatureAnnotation) -> some View {
        let poi = resolvedMapFeaturePOI(for: feature)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("◈").foregroundStyle(Theme.gold)
                Text(feature.title ?? "").font(.headline).lineLimit(1)
                Spacer()
                // Same bookmark/flag pair as POIExplainSheet — this card
                // floats over the map itself so there was nowhere to save
                // or plan a tapped POI from without leaving the map.
                // Tap targets are widened past the glyph via `.frame` +
                // `.contentShape` (default icon-only buttons here were only
                // as big as the SF Symbol itself, easy to mis-tap on a
                // floating card), and the close button gets extra leading
                // space so it isn't sitting flush against the plan button.
                if let poi {
                    let identifier = poi.asReference.identifier
                    HStack(spacing: 12) {
                        Button {
                            Haptics.light()
                            addToCollectionKind = .saved
                        } label: {
                            Image(systemName: savedPlacesStore.isSaved(identifier) ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(savedPlacesStore.isSaved(identifier) ? Theme.gold : .secondary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        Button {
                            Haptics.light()
                            addToCollectionKind = .plan
                        } label: {
                            // Not "flag" — that's already `routeModeToggleButton`'s
                            // icon on this same screen, and reusing it here for
                            // "add to Plan" made the two concepts (start Route
                            // Mode vs. save this POI into a Plan list) look like
                            // the same action.
                            Image(systemName: savedPlacesStore.isPlanned(identifier) ? "suitcase.fill" : "suitcase")
                                .foregroundStyle(savedPlacesStore.isPlanned(identifier) ? Theme.gold : .secondary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                    }
                    .font(.title3)
                    .padding(.trailing, 10)
                }
                Button {
                    dismissMapFeature()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .font(.title3)
            }

            // AI explanation first — the reason this card is showing at
            // all — before any of Apple's own place data below.
            if poiExplainLoading {
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBox().frame(width: 180, height: 14)
                    SkeletonBox().frame(height: 12)
                    SkeletonBox().frame(width: 220, height: 12)
                }
            } else if let poiExplainResult {
                Text(poiExplainResult.headline).font(.subheadline.bold()).foregroundStyle(Theme.gold)
                if let rating = poiExplainResult.rating {
                    TripAdvisorRatingRow(rating: rating)
                }
                if let curatedInfo = poiExplainResult.curatedInfo {
                    CuratedInfoRow(info: curatedInfo)
                }
                if let weather = mapFeatureWeatherQuery.weather {
                    weatherBadge(weather)
                }
                POIPhotoGallery(photos: poiExplainResult.photos)
                Text(poiExplainResult.body).font(.footnote)
                ForEach(poiExplainResult.highlights, id: \.self) { highlight in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(Theme.gold).frame(width: 5, height: 5).padding(.top, 6)
                        Text(highlight).font(.caption)
                    }
                }
            } else if let poiExplainError {
                HStack(spacing: 8) {
                    Text(poiExplainError).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button("common.retry") {
                        poiExplainTask?.cancel()
                        poiExplainTask = Task { await explainMapFeature(feature) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Phone/website are plain `MKMapItem` properties — shown
            // directly on this card rather than behind Apple's own Place
            // Card sheet/popover, which would open as a second, separate
            // page stacked on top of this one (confirmed broken both ways:
            // an embedded mini map for the selection-accessory callout
            // rendered as a messy duplicate over the real map already
            // behind this card; the sheet/popover is a fine surface but
            // always its own disconnected screen). Hours/ratings/photos
            // have no plain data API (confirmed via research) — "Haritalarda
            // Aç" below is how to reach those from here.
            if let resolvedMapFeatureItem {
                if let phoneNumber = resolvedMapFeatureItem.phoneNumber,
                   let telURL = URL(string: "tel:\(phoneNumber.filter { !$0.isWhitespace })") {
                    Link(phoneNumber, destination: telURL).font(.footnote)
                }
                if let website = resolvedMapFeatureItem.url {
                    Link(website.host ?? website.absoluteString, destination: website).font(.footnote)
                }
                HStack(spacing: 10) {
                    Button {
                        showingMapItemDetail = true
                    } label: {
                        Label("poiExplain.fullDetails", systemImage: "info.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gold)
                    .mapItemDetailSheet(isPresented: $showingMapItemDetail, item: resolvedMapFeatureItem)

                    Button("common.openInMaps") {
                        resolvedMapFeatureItem.openInMaps()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let lookAroundScene {
                LookAroundCard(scene: lookAroundScene, height: 140)
            }
        }
        .padding()
        .piriGlassCard(cornerRadius: 16)
        .sheet(item: $addToCollectionKind) { kind in
            if let poi { AddToCollectionSheet(poi: poi, kind: kind) }
        }
    }

    /// Compact, not a card element — current conditions at this POI, one
    /// line, next to the rating row rather than a section of its own.
    private func weatherBadge(_ weather: Weather) -> some View {
        HStack(spacing: 4) {
            Image(systemName: weather.condition.icon)
            Text("\(Int(weather.temp))°, \(weather.description.capitalized)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func setInitialRegionIfNeeded() async {
        guard initialRegion == nil else { return }

        if let lat = cityStore.lat, let lng = cityStore.lng {
            initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            return
        }

        // No saved city yet — wait briefly for CoreLocation, matching the
        // RN app's fall-through-to-GPS behavior in `use-weather.ts`/`use-places.ts`.
        for _ in 0..<20 {
            if let location = locationManager.currentLocation {
                initialRegion = MKCoordinateRegion(center: location, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        // Last resort so the map always renders something.
        initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }

    private func loadCuratedPlaces() async {
        do {
            places = try await PlacesAPI.fetchPlaces(city: cityStore.cityName, lat: cityStore.lat, lng: cityStore.lng)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleRegionChange(_ region: MKCoordinateRegion) {
        currentRegion = region
        fetchDietaryPinsIfNeeded(for: region)

        guard Self.useCuratedMapData else { return }
        liveFetchTask?.cancel()
        guard region.span.latitudeDelta <= maxLiveFetchLatitudeDelta else {
            livePins = []
            return
        }

        liveFetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let minLat = region.center.latitude - region.span.latitudeDelta / 2
            let maxLat = region.center.latitude + region.span.latitudeDelta / 2
            let minLng = region.center.longitude - region.span.longitudeDelta / 2
            let maxLng = region.center.longitude + region.span.longitudeDelta / 2

            do {
                let pins = try await LivePlacesAPI.fetchNearbyLive(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng)
                guard !Task.isCancelled else { return }
                livePins = pins
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Independent of `Self.useCuratedMapData` — this is a fresh, unrelated
    /// feature (see the 2026-08 conversation on dietary filtering), not part
    /// of the old curated-pins pivot decision. Not `async` since it only
    /// kicks off a debounced background `Task`, matching `handleRegionChange`'s
    /// own live-pin fetch, which this mirrors.
    private func fetchDietaryPinsIfNeeded(for region: MKCoordinateRegion) {
        dietaryFetchTask?.cancel()
        guard let dietaryFilter, region.span.latitudeDelta <= maxLiveFetchLatitudeDelta else {
            dietaryPins = []
            return
        }

        dietaryFetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let minLat = region.center.latitude - region.span.latitudeDelta / 2
            let maxLat = region.center.latitude + region.span.latitudeDelta / 2
            let minLng = region.center.longitude - region.span.longitudeDelta / 2
            let maxLng = region.center.longitude + region.span.longitudeDelta / 2

            // No `errorMessage` on failure, unlike the live-pin fetch this
            // mirrors -- Overpass is a best-effort free service and an empty
            // result (no matches nearby, or a transient Overpass hiccup) is
            // an expected, unremarkable outcome here, not something to
            // surface as an app error banner.
            let pins = (try? await DietaryPlacesAPI.fetchNearby(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng, diet: dietaryFilter)) ?? []
            guard !Task.isCancelled else { return }
            dietaryPins = pins
        }
    }

    private func fetchDirections(to place: Place) async {
        guard let location = place.location, let userLocation = locationManager.currentLocation else { return }
        do {
            let result = try await RoutesAPI.directions(coordinates: [
                PlaceCoordinate(lat: userLocation.latitude, lng: userLocation.longitude),
                PlaceCoordinate(lat: location.lat, lng: location.lng),
            ])
            routeCoordinates = result.route.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enrichLivePin(_ pin: LivePin) async {
        do {
            let place = try await LivePlacesAPI.enrichLive(overtureId: pin.id)
            places.append(place)
            selectedLivePin = nil
            selectedPlace = place
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Includes a fingerprint of the personalization fields actually sent to
    /// `/places/explain-poi` (below), so editing profile/interests/budget/pace
    /// mid-session makes previously-cached blurbs simply stop matching
    /// instead of resurfacing stale, pre-edit personalization.
    private func poiCacheKey(_ feature: MKMapFeatureAnnotation, profile: UserProfile) -> String {
        let fingerprint = [
            profile.name,
            profile.professionText ?? "",
            profile.interestsText.joined(separator: ","),
            profile.faith?.rawValue ?? "",
            profile.budget?.rawValue ?? "",
            profile.groupType?.rawValue ?? "",
            profile.pace?.rawValue ?? "",
        ].joined(separator: ",")
        return "\(feature.title ?? "")|\(String(format: "%.5f", feature.coordinate.latitude))|\(String(format: "%.5f", feature.coordinate.longitude))|\(fingerprint)"
    }

    private func explainMapFeature(_ feature: MKMapFeatureAnnotation) async {
        var category: String?
        var address: String?
        // Best-effort enrichment — the annotation alone only has a title and
        // coordinate, `MKMapItemRequest` gets the rest (category, address,
        // and `resolvedMapFeatureItem` for the phone/website rows and
        // "Detaylı Bilgi" button). Always resolved, even on an AI-cache hit
        // below — this used to sit after the cache's early `return`, so
        // revisiting any previously-explained POI left `resolvedMapFeatureItem`
        // nil (reset by `selectMapFeature`) and silently hid all of that.
        if let mapItem = try? await MKMapItemRequest(mapFeatureAnnotation: feature).mapItem {
            category = mapItem.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
            address = mapItem.placemark.title
            resolvedMapFeatureItem = mapItem
        }

        guard !Task.isCancelled else { return }

        // Fire-and-forget — weather has no dependency on the AI explain
        // call or its cache, so it's not awaited here.
        Task { await mapFeatureWeatherQuery.load(lat: feature.coordinate.latitude, lng: feature.coordinate.longitude) }

        let profile = userProfileStore.profile
        let cacheKey = poiCacheKey(feature, profile: profile)
        if let cached = Self.poiExplainCache[cacheKey] {
            poiExplainResult = cached
            poiExplainError = nil
            return
        }

        poiExplainLoading = true
        poiExplainError = nil
        defer { poiExplainLoading = false }

        let request = ExplainPOIRequest(
            name: feature.title ?? "",
            category: category,
            lat: feature.coordinate.latitude,
            lng: feature.coordinate.longitude,
            address: address,
            locale: Locale.current.language.languageCode?.identifier,
            userProfile: PersonalizationProfile(
                name: profile.name,
                profession: profile.professionText,
                interests: profile.interestsText,
                faith: profile.faith?.rawValue,
                budget: profile.budget?.rawValue,
                groupType: profile.groupType?.rawValue,
                pace: profile.pace?.rawValue
            ),
            recentlyViewedPlaceIds: nil
        )

        do {
            let result = try await PlacesAPI.explainPOI(request)
            guard !Task.isCancelled else { return }
            poiExplainResult = result
            Self.poiExplainCache[cacheKey] = result
        } catch {
            guard !Task.isCancelled else { return }
            poiExplainError = error.localizedDescription
        }
    }
}
