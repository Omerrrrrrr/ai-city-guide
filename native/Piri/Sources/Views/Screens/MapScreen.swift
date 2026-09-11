import Charts
import MapKit
import SwiftUI

/// XP is derived, not logged (see `Gamification.swift`), so a per-trip XP
/// delta only exists if it's snapshotted right at the moment a trip ends --
/// `endRoute()` in `MapScreen+RouteMode.swift` does exactly that and hands
/// the result here as a one-shot sheet-presentation payload.
struct PendingTripRecap: Identifiable {
    let id = UUID()
    let trip: Trip
    let xpBefore: Int
    let xpAfter: Int
    let levelBefore: Int
    let levelAfter: Int
    let myLifetimeTripCount: Int
}

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
    @Environment(SavedPlacesStore.self) var savedPlacesStore
    @Environment(UserProfileStore.self) var userProfileStore
    @Environment(TripsStore.self) var tripsStore
    @Environment(TabSelection.self) private var tabSelection
    @Environment(AuthStore.self) private var authStore
    @Environment(RecentlyViewedStore.self) var recentlyViewedStore
    @Environment(MyReviewsStore.self) var myReviewsStore

    @State var locationManager = LocationManager()
    @State private var places: [Place] = []
    @State private var livePins: [LivePin] = []
    @State private var selectedCategoryGroup: POICategoryGroup?
    @State private var mapType: MKMapType = .standard
    /// A filter for anyone with a dietary need, not one faith — see
    /// `DietTag`. Orthogonal to `selectedCategoryGroup`: this drives a
    /// separate live pin layer (`dietaryPins`, sourced from OpenStreetMap),
    /// not Apple's own `pointOfInterestFilter`, since Apple's POI data
    /// carries no dietary tags at all. Backed by `@AppStorage`, same key
    /// `HomeScreen` uses, so the choice is shared and remembered across
    /// both screens instead of resetting every visit — see
    /// `DietaryFilterButton`.
    @AppStorage("dietaryFilterRawValue") private var dietaryFilterRawValue: String = ""
    private var dietaryFilter: DietTag? {
        get { DietTag(rawValue: dietaryFilterRawValue) }
        nonmutating set { dietaryFilterRawValue = newValue?.rawValue ?? "" }
    }
    @State private var dietaryPins: [DietaryPin] = []
    @State private var dietaryFetchTask: Task<Void, Never>?
    @State private var selectedDietaryPin: DietaryPin?
    @State private var trailPins: [Trail] = []
    @State private var trailFetchTask: Task<Void, Never>?
    @State private var selectedTrail: Trail?
    @State private var trailGeometryPoints: [CLLocationCoordinate2D] = []
    @State private var trailRouteType: TrailRouteType?
    @State private var trailElevationProfile: [TrailElevationPoint] = []
    @State private var loadingTrailGeometry = false
    /// Drives `TrailReviewsSheet` -- separate from `selectedTrail` (which
    /// keeps driving the compact map card underneath) so dismissing the
    /// reviews sheet doesn't also lose the selected pin/route.
    @State private var trailForReviews: Trail?
    /// Updated on every `handleRegionChange` call (unlike `initialRegion`,
    /// which is set once and deliberately not kept in sync with panning) so
    /// toggling `dietaryFilter` can immediately fetch against wherever the
    /// map currently is, without waiting for the next pan/zoom.
    @State private var currentRegion: MKCoordinateRegion?
    @State private var selectedPlace: Place?
    @State private var selectedLivePin: LivePin?
    @State private var selectedMapFeature: MKMapFeatureAnnotation?
    /// Resolved by `explainMapFeature`/`explainDietaryPin` so `mapFeatureCard`
    /// can build a real `POIPlace` to hand to `POIExplainContent` -- that
    /// type owns everything downstream of having a `POIPlace` (explanation
    /// fetch/cache, photos, weather, chat, etc.) itself now.
    @State private var resolvedMapFeatureItem: MKMapItem?
    /// Set by `explainMapFeature` when `MKMapItemRequest` itself fails (a
    /// real network request, unlike `explainDietaryPin`'s local synthesis) --
    /// drives a retry affordance in `mapFeatureCard`'s loading state instead
    /// of leaving it stuck on a skeleton forever.
    @State private var resolveFailed = false
    @State private var mapFeatureExpanded = false
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
    /// Real turn-by-turn instructions for the current route, when
    /// available — see `RouteStep`'s own doc comment for when this is empty.
    @State var routeSteps: [RouteStep] = []
    @State var showingRouteSteps = false
    @State var isFetchingRoute = false
    @State var routeError: String?
    /// Which profile the *next* `previewRoute()`/`startRoute()`/
    /// `updateRoute()` call fetches — the route used to always be fetched
    /// walking-only with no way to tell from the UI, and no way to ask for
    /// a driving route at all.
    @State var routeProfile: RouteProfile = .footWalking
    /// True whenever `routeProfile` has been changed since the active
    /// trip's route was last persisted — not stored on `Trip` itself (that
    /// would need a schema/sync change for a purely local preview concern),
    /// just enough state to know the freshly-refetched preview geometry
    /// should be drawn instead of the trip's stale persisted one until
    /// "Güncelle" is tapped. Mirrors `stopsChangedFromActiveTrip`.
    @State var routeProfileDirty = false
    /// Set by `endRoute()` right after ending a trip — presenting
    /// `TripRecapView` as a `.sheet(item:)` this drives. `nil` the rest
    /// of the time, so the animated recap only ever plays once, right when
    /// a trip actually finishes, not on every future visit to this screen
    /// (revisiting an old trip later shows the static `TripSummarySheet`
    /// instead, from `TripDetailScreen`).
    @State var pendingTripRecap: PendingTripRecap?
    /// "Rotayı Kaydet" — saves the currently-planned stops (in their
    /// current order) as a new Plan collection, without starting a live
    /// trip. Previously the only way out of route mode was "Rotayı Başlat"
    /// (commit to live tracking) or discard the whole plan.
    @State var showingSaveRouteAlert = false
    @State var saveRouteName = ""
    @State var showingSaveConfirmation = false
    @State var saveConfirmationTask: Task<Void, Never>?
    /// Collapsed by default — the full editable stop list used to always
    /// take up roughly half the screen over the map itself. Expanding is a
    /// deliberate tap, not automatic, so picking stops on the map still
    /// leaves most of the map visible.
    @State var stopsExpanded = false
    @State var showTripPhotoCapture = false
    /// Confirms before `routeModeToggleButton` discards a non-empty,
    /// not-yet-started `plannedStops` — see the 2026-08 usability audit.
    @State var showDiscardStopsConfirm = false
    /// Guards against re-running rehydration/re-starting breadcrumb recording
    /// every time this view re-evaluates its body while a trip is active.
    @State var hydratedTripId: String?

    /// Matches `LIVE_PINS_MAX_LATITUDE_DELTA` in the RN app — live pins only
    /// make sense at city/district zoom, not zoomed out to country level.
    private let maxLiveFetchLatitudeDelta = 0.04

    /// Selecting the "Yürüyüş" category chip drives both Apple's own
    /// `.hiking` POI filter (`pointOfInterestCategories` below, unrelated
    /// code) AND the Overpass trail layer (`fetchTrailsIfNeeded` etc.) —
    /// one control instead of two separate "hiking" toggles a real person
    /// can't tell apart. See `POICategoryGroups.hikingLabelKey`'s comment.
    private var hikingLayerActive: Bool {
        selectedCategoryGroup?.labelKey == POICategoryGroups.hikingLabelKey
    }

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
                if routeMode, let activeTrip = tripsStore.activeTrip {
                    // While the stop list has been edited past what the
                    // active trip last persisted, draw the freshly-previewed
                    // route (kept live by the `onChange(of: plannedStops)`
                    // preview fetch below) instead of the stale persisted
                    // one — otherwise the map didn't visibly react to
                    // adding/removing/reordering a stop until "Güncelle"
                    // was tapped.
                    let liveGeometry = (stopsChangedFromActiveTrip || routeProfileDirty) ? routeGeometry : nil
                    TripMapView(
                        routeCoordinates: (liveGeometry ?? activeTrip.routeGeometry ?? routeGeometry ?? []).compactMap(coordinate(fromPair:)),
                        breadcrumbCoordinates: activeTrip.breadcrumb.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
                        stops: routeStopAnnotations,
                        initialRegion: activeTripDisplayRegion(for: activeTrip) ?? initialRegion,
                        showsUserLocation: true,
                        mapType: mapType
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
                        trailPins: routeMode ? [] : trailPins,
                        trailCoordinates: routeMode ? [] : trailGeometryPoints,
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
                        onSelectTrailPin: { selectTrail($0) },
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
                }
                // Route mode has its own dedicated `routeError` line inside
                // `routeModeSheet` -- this shared banner (search/directions/
                // live pins) used to render on top of it regardless, so a
                // stale unrelated error could linger over route mode, or a
                // route error could look like it came from something else
                // once the user left route mode. Scope it to non-route-mode.
                if !routeMode, let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    Spacer()
                    mapTypeButton
                    routeModeToggleButton
                        .environment(\.colorScheme, .dark)
                        .accessibilityLabel(String(localized: "design.map.plan"))
                    locationButton
                }
                if routeMode {
                    routeModeSheet
                } else if let selectedPlace {
                    placeCard(for: selectedPlace)
                } else if let selectedLivePin {
                    livePinCard(for: selectedLivePin)
                } else if let selectedDietaryPin {
                    mapFeatureCard(for: MapFeatureIdentity(
                        title: selectedDietaryPin.name,
                        coordinate: CLLocationCoordinate2D(latitude: selectedDietaryPin.lat, longitude: selectedDietaryPin.lng)
                    ))
                } else if let selectedTrail {
                    trailCard(for: selectedTrail)
                } else if let visibleMapFeatureIdentity {
                    mapFeatureCard(for: visibleMapFeatureIdentity)
                } else if hikingLayerActive, !trailPins.isEmpty {
                    // Nearest-first (backend already sorts by
                    // `approxDistanceFromQueryKm`) so this doubles as "what's
                    // closest to where I'm looking", not just "what's on
                    // screen" -- lets someone browse trails without having to
                    // find and tap each pin individually.
                    trailListStrip
                }
            }
            .padding()
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
        // "Piri Haritası" maps-provider hand-off (see `PlaceDirections`) --
        // same `.task(id:)`-not-`.onChange` reasoning as `pendingRouteStops`
        // above. Fires even when already on this tab (tapping "Open in
        // Maps" on this screen's own card): `MapFocusRequest`'s fresh
        // `trigger` UUID each time still changes the task's `id`, so it
        // reruns and recenters instead of being treated as a no-op.
        .task(id: tabSelection.pendingMapFocus) {
            guard let focus = tabSelection.pendingMapFocus else { return }
            initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: focus.lat, longitude: focus.lng),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            recenterTrigger = focus.trigger
            tabSelection.pendingMapFocus = nil
        }
        .onChange(of: locationManager.breadcrumb) { _, points in
            guard let activeTripId = tripsStore.activeTripId, let last = points.last else { return }
            tripsStore.addBreadcrumb(activeTripId, point: last)
        }
        // Live preview as stops are picked/reordered/removed — previously
        // the route line (and its distance) only appeared after explicitly
        // starting or updating the trip, so picking stops showed nothing
        // but straight guesses between pins the whole time.
        .onChange(of: plannedStops) { oldStops, newStops in
            if oldStops.isEmpty, !newStops.isEmpty {
                stopsExpanded = true
            }
            guard newStops.count >= 2 else {
                routeGeometry = nil
                routeDistanceMeters = nil
                routeDurationSeconds = nil
                routeSteps = []
                return
            }
            Task { await previewRoute() }
        }
        .onChange(of: routeProfile) { _, _ in
            routeProfileDirty = true
            guard plannedStops.count >= 2 else { return }
            Task { await previewRoute() }
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
        .onChange(of: hikingLayerActive) { _, active in
            // `currentRegion` only gets set once MapKit's own
            // `regionDidChangeAnimated` delegate has fired at least once
            // (see `handleRegionChange`) -- falling back to `initialRegion`
            // covers the edge case of picking this chip before that first
            // callback lands, which otherwise silently did nothing at all
            // (the `if let` failed, so this fell straight to the `else`
            // branch and never fetched anything).
            if active, let region = currentRegion ?? initialRegion {
                fetchTrailsIfNeeded(for: region)
            } else {
                trailPins = []
                selectedTrail = nil
                trailGeometryPoints = []
                trailRouteType = nil
                trailElevationProfile = []
            }
        }
        .sheet(isPresented: $showTripPhotoCapture) {
            TripPhotoCaptureSheet { data in
                Task { await attachTripPhoto(data) }
            }
        }
        .sheet(item: $trailForReviews) { trail in
            TrailReviewsSheet(trail: trail)
        }
        .sheet(item: $pendingTripRecap) { pending in
            TripRecapView(
                trip: pending.trip,
                xpBefore: pending.xpBefore,
                xpAfter: pending.xpAfter,
                levelBefore: pending.levelBefore,
                levelAfter: pending.levelAfter,
                myLifetimeTripCount: pending.myLifetimeTripCount
            )
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
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.navy, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
        }
        .accessibilityLabel(String(localized: "design.map.appearance"))
    }

    /// Re-centers on the user's live GPS position -- distinct from
    /// `initialRegion`'s own one-time snapshot (set once at launch from the
    /// saved city or an early GPS fix, then never updated), so panning away
    /// and tapping this later actually returns to *now*, not to wherever
    /// the map happened to open. Reuses the same `initialRegion` +
    /// `recenterTrigger` plumbing `performSearch` already re-centers with
    /// (see below), rather than adding a second recenter mechanism.
    private var locationButton: some View {
        Button {
            guard let location = locationManager.currentLocation else { return }
            initialRegion = MKCoordinateRegion(center: location, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
            recenterTrigger = UUID()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.navy, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
        }
        .accessibilityLabel(String(localized: "design.map.recenter"))
    }

    private var mapTypeIconName: String {
        switch mapType {
        case .satellite, .satelliteFlyover: return "globe.americas.fill"
        case .hybrid, .hybridFlyover: return "square.stack.3d.up.fill"
        default: return "map"
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField(
                "",
                text: $searchQuery,
                prompt: Text(String(localized: "design.map.search"))
                    .foregroundStyle(Theme.secondaryText)
            )
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(Theme.gold)
            .textFieldStyle(.plain)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .accessibilityLabel(String(localized: "design.map.search"))
            .onSubmit {
                searchTask?.cancel()
                searchTask = Task { await searchAndCenterMap(searchQuery) }
            }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 32, height: 36)
                }
                .accessibilityLabel(String(localized: "design.map.clearSearch"))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(Theme.navy, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.secondaryText.opacity(0.65), lineWidth: 1))
        .shadow(color: Theme.navy.opacity(0.16), radius: 8, y: 3)
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

    private var mapCategoryGroups: [POICategoryGroup] {
        let leadingKeys = ["all", "cafes", "food", "nature", "culture"]
            .map { "mapPoiCategories.\($0)" }
        let leading = leadingKeys.compactMap { key in
            POICategoryGroups.all.first { $0.labelKey == key }
        }
        return leading + POICategoryGroups.all.filter { !leadingKeys.contains($0.labelKey) }
    }

    private var categoryChips: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(mapCategoryGroups) { group in
                        let active = selectedCategoryGroup?.id == group.id || (selectedCategoryGroup == nil && group.categories == nil)
                        Button {
                            selectedCategoryGroup = active ? nil : group
                        } label: {
                            HStack(spacing: 6) {
                                if group.categories != nil {
                                    Image(systemName: group.icon)
                                }
                                Text(String(localized: String.LocalizationValue(group.labelKey)))
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(active ? Theme.gold : Theme.navy, in: Capsule())
                        .overlay(Capsule().strokeBorder(active ? Theme.gold : Theme.border, lineWidth: 1))
                        .foregroundStyle(active ? Theme.navy : .white)
                        .accessibilityAddTraits(active ? [.isSelected] : [])
                    }
                }
            }
            // Keep the shared dietary selection and toggle semantics,
            // with a locally styled menu to match the map overlay.
            Menu {
                ForEach(DietTag.allCases) { tag in
                    Button {
                        dietaryFilter = dietaryFilter == tag ? nil : tag
                    } label: {
                        let label = String(localized: String.LocalizationValue("diet.\(tag.rawValue)"))
                        if dietaryFilter == tag {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17))
                    .foregroundStyle(dietaryFilter == nil ? .white : Theme.navy)
                    .frame(width: 44, height: 44)
                    .background(dietaryFilter == nil ? Theme.navy : Theme.gold, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 1))
            }
            .accessibilityLabel(String(localized: "dietaryFilter.button"))
            .accessibilityValue(dietaryFilter.map { String(localized: String.LocalizationValue("diet.\($0.rawValue)")) } ?? String(localized: "design.common.all"))
        }
    }

    private func selectPlace(_ place: Place) {
        selectedPlace = place
        selectedLivePin = nil
        selectedMapFeature = nil
        selectedDietaryPin = nil
        selectedTrail = nil
        trailGeometryPoints = []
        trailRouteType = nil
        trailElevationProfile = []
        poiExplainTask?.cancel()
    }

    private func selectLivePin(_ pin: LivePin) {
        selectedLivePin = pin
        selectedPlace = nil
        selectedMapFeature = nil
        selectedDietaryPin = nil
        selectedTrail = nil
        trailGeometryPoints = []
        trailRouteType = nil
        trailElevationProfile = []
        poiExplainTask?.cancel()
    }

    private func selectDietaryPin(_ pin: DietaryPin) {
        mapFeatureExpanded = false
        selectedDietaryPin = pin
        selectedPlace = nil
        selectedLivePin = nil
        selectedMapFeature = nil
        selectedTrail = nil
        trailGeometryPoints = []
        trailRouteType = nil
        trailElevationProfile = []
        resolvedMapFeatureItem = nil
        resolveFailed = false
        poiExplainTask?.cancel()
        poiExplainTask = Task { await explainDietaryPin(pin) }
    }

    private func selectMapFeature(_ feature: MKMapFeatureAnnotation) {
        mapFeatureExpanded = false
        selectedMapFeature = feature
        selectedPlace = nil
        selectedLivePin = nil
        selectedDietaryPin = nil
        selectedTrail = nil
        trailGeometryPoints = []
        trailRouteType = nil
        trailElevationProfile = []
        resolvedMapFeatureItem = nil
        resolveFailed = false
        poiExplainTask?.cancel()
        poiExplainTask = Task { await explainMapFeature(feature) }
    }

    private func dismissMapFeature() {
        mapFeatureExpanded = false
        selectedMapFeature = nil
        selectedDietaryPin = nil
        resolvedMapFeatureItem = nil
        resolveFailed = false
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

    /// Horizontal browse strip shown whenever the trail layer is on and
    /// nothing else is selected -- discovery without hunting for pins on
    /// the map, same list backing `trailPins` (map annotations) already has.
    private var trailListStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(trailPins) { trail in
                    Button {
                        Haptics.light()
                        selectTrail(trail)
                    } label: {
                        trailListItem(trail)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private func trailListItem(_ trail: Trail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trail.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                if let distanceKm = trail.distanceKm {
                    Text(formattedKm(distanceKm))
                }
                if let difficulty = trail.difficulty {
                    Text(difficultyLabel(difficulty))
                        .foregroundStyle(difficultyColor(difficulty))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 180, alignment: .leading)
        .piriGlassCard(cornerRadius: 14)
    }

    /// No AI-explain call, unlike every other pin card on this screen — a
    /// trail's name/operator/distance already came fully formed from
    /// `/trails/nearby` (real OSM tags, not something to elaborate on), so
    /// this just offers to draw its line.
    private func trailCard(for trail: Trail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trail.name).font(.headline)
                    HStack(spacing: 6) {
                        if let operatorName = trail.operatorName {
                            Text(operatorName)
                        }
                        if trail.operatorName != nil, trail.distanceKm != nil {
                            Text("·")
                        }
                        if let distanceKm = trail.distanceKm {
                            Text(formattedKm(distanceKm))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectedTrail = nil
                    trailGeometryPoints = []
                    trailRouteType = nil
                    trailElevationProfile = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .font(.title3)
            }
            if trail.difficulty != nil || trail.dogsAllowed == true || trail.surface != nil || trailRouteType != nil {
                HStack(spacing: 6) {
                    if let difficulty = trail.difficulty {
                        trailBadge(difficultyLabel(difficulty), color: difficultyColor(difficulty))
                    }
                    // `false`/untagged aren't shown -- OSM's `dog` tag is
                    // rarely set either way, so silence isn't "not allowed".
                    if trail.dogsAllowed == true {
                        trailBadge(String(localized: "map.trails.dogFriendly"), icon: "pawprint.fill")
                    }
                    if let surface = trail.surface {
                        trailBadge(surface.capitalized)
                    }
                    // Only known once the route's geometry has loaded (this
                    // trail's own line, not the nearby-list response) --
                    // absent while `loadingTrailGeometry` is still running.
                    if let trailRouteType {
                        trailBadge(
                            trailRouteType == .loop
                                ? String(localized: "map.trails.routeType.loop")
                                : String(localized: "map.trails.routeType.linear"),
                            icon: trailRouteType == .loop ? "arrow.trianglehead.2.clockwise" : "arrow.left.and.right"
                        )
                    }
                }
            }
            if loadingTrailGeometry {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("map.trails.loadingRoute").font(.footnote).foregroundStyle(.secondary)
                }
            } else if !trailElevationProfile.isEmpty {
                elevationChart(trailElevationProfile)
            }
            Button {
                Haptics.light()
                trailForReviews = trail
            } label: {
                Label(String(localized: "map.trails.reviews"), systemImage: "text.bubble")
                    .font(.footnote.weight(.semibold))
            }
            .padding(.top, 2)
        }
        .padding()
        .piriGlassCard(cornerRadius: 16)
    }

    /// `nil` (no chart shown at all) when Open-Elevation timed out server-side
    /// -- see `TrailGeometry.elevationProfile`'s doc comment. Height kept
    /// small (56pt): this is a glance-level shape, not a standalone screen.
    private func elevationChart(_ profile: [TrailElevationPoint]) -> some View {
        let gainM = zip(profile, profile.dropFirst())
            .reduce(0.0) { total, pair in total + max(0, pair.1.elevationM - pair.0.elevationM) }
        return VStack(alignment: .leading, spacing: 4) {
            Chart(profile, id: \.distanceKm) { point in
                AreaMark(x: .value("km", point.distanceKm), y: .value("m", point.elevationM))
                    .foregroundStyle(Theme.gold.opacity(0.18))
                LineMark(x: .value("km", point.distanceKm), y: .value("m", point.elevationM))
                    .foregroundStyle(Theme.gold)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 56)
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right").font(.caption2)
                Text("+\(Int(gainM.rounded())) m")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private func formattedKm(_ km: Double) -> String {
        "\(km.formatted(.number.precision(.fractionLength(0...1)))) km"
    }

    private func trailBadge(_ text: String, color: Color = .secondary, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9))
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private func difficultyLabel(_ difficulty: TrailDifficulty) -> String {
        switch difficulty {
        case .easy: String(localized: "map.trails.difficulty.easy")
        case .moderate: String(localized: "map.trails.difficulty.moderate")
        case .hard: String(localized: "map.trails.difficulty.hard")
        case .extreme: String(localized: "map.trails.difficulty.extreme")
        }
    }

    // Mirrors AllTrails' green/yellow/red-ish easy→hard ramp; "extreme" goes
    // to the same red as "hard" rather than inventing a fifth color for OSM's
    // rarely-seen top rung.
    private func difficultyColor(_ difficulty: TrailDifficulty) -> Color {
        switch difficulty {
        case .easy: Theme.openGreen
        case .moderate: Theme.gold
        case .hard, .extreme: Theme.closedRed
        }
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
    /// Common identity for anything `mapFeatureCard` can render — Apple's own
    /// `MKMapFeatureAnnotation` for base-tile POIs, or a tapped `DietaryPin`
    /// (an OSM node, not an Apple feature annotation, so it has no
    /// `MKMapFeatureAnnotation` of its own to reuse). Folding dietary-pin
    /// taps into this same rich, interactive card — instead of the old
    /// separate, non-tappable `dietaryPinCard` — was the user's explicit
    /// request: one system instead of two, and dietary awareness on every
    /// restaurant tap, not just pins already surfaced by the filter.
    private struct MapFeatureIdentity {
        let title: String?
        let coordinate: CLLocationCoordinate2D
    }

    private var visibleMapFeatureIdentity: MapFeatureIdentity? {
        return selectedMapFeature.map { MapFeatureIdentity(title: $0.title, coordinate: $0.coordinate) }
    }

    private func resolvedMapFeaturePOI(for identity: MapFeatureIdentity) -> POIPlace? {
        guard let resolvedMapFeatureItem else { return nil }
        return POIPlace(
            name: resolvedMapFeatureItem.name ?? identity.title ?? "",
            category: resolvedMapFeatureItem.pointOfInterestCategory,
            coordinate: identity.coordinate,
            mapItem: resolvedMapFeatureItem
        )
    }

    /// Details mount only after an explicit expansion; the first tap leaves
    /// room to browse the map and start planning a route.
    private func mapFeatureCard(for identity: MapFeatureIdentity) -> some View {
        let poi = resolvedMapFeaturePOI(for: identity)
        return VStack(alignment: .leading, spacing: 0) {
            if mapFeatureExpanded, let poi {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mapFeatureExpanded = false }
                } label: {
                    Label(String(localized: "design.map.collapse"), systemImage: "chevron.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                POIExplainContent(poi: poi, onClose: dismissMapFeature)
                    .id(poi.asReference.id)
                    .environment(\.colorScheme, .dark)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        MapPreviewThumbnail(poi: poi)
                            .id(poi?.asReference.id ?? "resolving")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(poi?.name ?? identity.title ?? "")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .accessibilityIdentifier("map.poi.name")
                            Text(mapFeatureSubtitle(poi))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(2)
                            if poi != nil {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { mapFeatureExpanded = true }
                                } label: {
                                    Label(String(localized: "design.map.details"), systemImage: "arrow.right")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Theme.gold)
                                        .frame(minHeight: 36)
                                }
                                .accessibilityIdentifier("map.poi.expand")
                            } else if resolveFailed {
                                Button("common.retry") {
                                    poiExplainTask?.cancel()
                                    resolveFailed = false
                                    if let selectedDietaryPin {
                                        poiExplainTask = Task { await explainDietaryPin(selectedDietaryPin) }
                                    } else if let selectedMapFeature {
                                        poiExplainTask = Task { await explainMapFeature(selectedMapFeature) }
                                    }
                                }
                                .tint(Theme.gold)
                                .frame(minHeight: 36)
                            } else {
                                ProgressView().tint(Theme.gold).frame(height: 36)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: dismissMapFeature) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 32, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(String(localized: "design.common.close"))
                    }
                    if resolveFailed {
                        Text("map.live.error")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Button {
                        guard let poi else { return }
                        Haptics.light()
                        var stops = plannedStops
                        if !stops.contains(where: { $0.id == poi.asReference.id }) {
                            stops.append(poi.asReference)
                        }
                        Task { await startPendingRoute(stops) }
                    } label: {
                        Label(String(localized: "design.map.createRoute"), systemImage: "location.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.navy)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.gold.opacity(poi == nil ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(poi == nil)
                    .accessibilityIdentifier("map.poi.createRoute")
                }
                .padding(12)
                .accessibilityIdentifier("map.poi.compactCard")
            }
        }
        .buttonStyle(.plain)
        .background(Theme.navy, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Theme.navy.opacity(0.2), radius: 12, y: 4)
        .frame(maxHeight: mapFeatureExpanded ? UIScreen.main.bounds.height * 0.6 : nil)
    }

    private func mapFeatureSubtitle(_ poi: POIPlace?) -> String {
        let category = (poi?.category).flatMap { category in
            POICategoryGroups.all.first { $0.categories?.contains(category) == true }
        }.map { String(localized: String.LocalizationValue($0.labelKey)) }
        let locality = poi?.mapItem.placemark.locality ?? cityStore.cityName ?? ""
        return [category ?? String(localized: "design.common.place"), locality]
            .filter { !$0.isEmpty }.joined(separator: " · ")
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
        fetchTrailsIfNeeded(for: region)

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

    /// Mirrors `fetchDietaryPinsIfNeeded` -- same debounce, same
    /// no-error-banner treatment (Overpass is a best-effort free service;
    /// an empty result here is an unremarkable outcome, not an app error).
    /// Unlike the dietary/live fetches, this isn't bbox-shaped -- Overpass's
    /// `around:radius` query takes a center + radius, so the region's span
    /// is converted to an equivalent radius instead.
    private func fetchTrailsIfNeeded(for region: MKCoordinateRegion) {
        trailFetchTask?.cancel()
        guard hikingLayerActive else {
            trailPins = []
            return
        }

        trailFetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let radiusMeters = Int(max(region.span.latitudeDelta, region.span.longitudeDelta) * 111_000 / 2)
            let pins = (try? await TrailsAPI.nearby(lat: region.center.latitude, lng: region.center.longitude, radiusMeters: max(radiusMeters, 2000))) ?? []
            guard !Task.isCancelled else { return }
            trailPins = pins
        }
    }

    private func selectTrail(_ trail: Trail) {
        selectedTrail = trail
        trailGeometryPoints = []
        trailRouteType = nil
        trailElevationProfile = []
        selectedPlace = nil
        selectedLivePin = nil
        selectedMapFeature = nil
        selectedDietaryPin = nil
        poiExplainTask?.cancel()
        // Drawn right away, not behind a second "Show Route" tap -- tapping
        // a pin is already the explicit request to see this trail, a
        // follow-up button just added a redundant step.
        Task { await showTrailRoute(trail) }
    }

    private func showTrailRoute(_ trail: Trail) async {
        loadingTrailGeometry = true
        defer { loadingTrailGeometry = false }
        // Best-effort, matching `fetchTrailsIfNeeded` -- a trail whose
        // geometry fails to load just doesn't draw a line; the card itself
        // (name/operator/distance) already came from `fetchNearbyTrails`
        // and stays showing either way.
        guard let geometry = try? await TrailsAPI.geometry(id: trail.id) else { return }
        trailGeometryPoints = geometry.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        trailRouteType = geometry.routeType
        trailElevationProfile = geometry.elevationProfile ?? []
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

    /// Resolves the real `MKMapItem` behind a tapped base-tile POI -- the
    /// annotation alone only has a title and coordinate. Once this lands,
    /// `mapFeatureCard` can build a real `POIPlace` and mount
    /// `POIExplainContent`, which fetches/caches its own explanation --
    /// this used to also drive that fetch itself (with its own cache), but
    /// duplicated everything `POIExplainContent` already does now that the
    /// two cards share it (see that type's own doc comment).
    private func explainMapFeature(_ feature: MKMapFeatureAnnotation) async {
        let mapItem = try? await MKMapItemRequest(mapFeatureAnnotation: feature).mapItem
        guard !Task.isCancelled else { return }
        resolvedMapFeatureItem = mapItem
        // Unlike `explainDietaryPin` (a local synthesis that can't fail),
        // this is a real network request -- without tracking a failure here,
        // a bad connection left the card stuck on its skeleton forever, with
        // no retry and no fallback (POIExplainContent needs a full POIPlace,
        // which needs a resolved MKMapItem to exist at all).
        resolveFailed = mapItem == nil
    }

    /// Mirrors `explainMapFeature`, but a `DietaryPin` is an OSM node we
    /// already have full name/coordinate data for — not an Apple feature
    /// annotation — so there's no `MKMapItemRequest` resolution step. The
    /// synthesized `MKMapItem` exists only so `resolvedMapFeaturePOI` can
    /// build a real `POIPlace`, matching what a resolved Apple POI gets.
    private func explainDietaryPin(_ pin: DietaryPin) async {
        let coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = pin.name
        resolvedMapFeatureItem = mapItem
    }
}

/// Reuses `PiriReviewsSection` as-is for a trail -- it only ever reads
/// `poi.name`/`poi.coordinate` (never `poi.category`/`poi.mapItem`), so a
/// trail's centroid stands in for a real `POIPlace` without needing a
/// separate review pipeline. `/poi/reviews` is already keyed by
/// name+lat/lng (`poiKey` in `apps/api/src/index.ts`), not a POI-source
/// type, so this needed zero backend changes -- trails, Apple MapKit POIs,
/// and Piri's own curated places already share the exact same review table.
private struct TrailReviewsSheet: View {
    let trail: Trail
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var languageStore
    /// `nil` while loading/on failure -- `PiriReviewsSection` already treats
    /// a `nil` summary / empty highlights as "nothing grounded to say", the
    /// same state a fresh trail with no reviews yet is genuinely in, so no
    /// separate loading placeholder is needed here.
    @State private var summary: TrailSummaryResponse?

    private var poiPlace: POIPlace {
        let coordinate = CLLocationCoordinate2D(latitude: trail.centerLat, longitude: trail.centerLng)
        return POIPlace(
            name: trail.name,
            category: nil,
            coordinate: coordinate,
            mapItem: MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                PiriReviewsSection(
                    poi: poiPlace,
                    tripAdvisorRating: nil,
                    googleRating: nil,
                    initialPiriRating: nil,
                    reviewsSummary: summary?.summary,
                    aspectHighlights: summary?.aspectHighlights ?? []
                )
                .padding()
            }
            .navigationTitle(trail.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .task {
            let locale = languageStore.code ?? Locale.current.language.languageCode?.identifier
            summary = try? await TrailsAPI.summary(for: trail, locale: locale)
        }
    }
}

private struct MapPreviewThumbnail: View {
    let poi: POIPlace?
    @State private var photo: PhotoBulkResult?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo, let urlString = photo.photoUrl, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, maxPixelSize: 300) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    fallback
                }
                .frame(width: 94, height: 94)
                .clipped()
                if let attribution = photo.attributionUrl, let url = URL(string: attribution) {
                    Link(photo.source?.capitalized ?? "Photo", destination: url)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(4)
                }
            } else {
                fallback
            }
        }
        .frame(width: 94, height: 94)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: poi?.asReference.id) {
            photo = nil
            guard let poi else { return }
            let request = PhotoBulkRequest(places: [PhotoBulkPlace(
                name: poi.name, lat: poi.coordinate.latitude, lng: poi.coordinate.longitude,
                category: poi.categoryLabel.isEmpty ? nil : poi.categoryLabel
            )])
            // Same free preview path as POIExplainContent; expanding details
            // remains the only request that can consume paid photo quota.
            guard let result = try? await PlacesAPI.photosBulk(request).results.first,
                  !Task.isCancelled,
                  ["wikipedia", "tripadvisor", "google"].contains(result.source ?? "") else { return }
            // Category stock photos aren't presented as a photo of this POI.
            photo = result
        }
    }

    private var fallback: some View {
        ZStack {
            Theme.navyLight
            Image(systemName: POICategoryGroups.icon(for: poi?.category))
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.gold)
        }
        .frame(width: 94, height: 94)
        .accessibilityHidden(true)
    }
}
