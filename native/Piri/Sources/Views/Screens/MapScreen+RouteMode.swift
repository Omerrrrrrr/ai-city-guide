import CoreLocation
import MapKit
import PhotosUI
import SwiftUI

/// Route/trip creation, port of the `routeMode` parts of
/// `mobile/app/(tabs)/map.tsx`: pick ≥2 stops by tapping Apple POI features
/// on the map, fetch a walking route, start a trip, record a GPS breadcrumb
/// while it's active, optionally attach photos, then end it. Split into its
/// own file (still the same `MapScreen` type — extensions can't add stored
/// properties, so the `@State` itself stays declared on the struct in
/// `MapScreen.swift`) purely to keep that file from growing unmanageably.
extension MapScreen {
    var stopsChangedFromActiveTrip: Bool {
        guard let activeTrip = tripsStore.trips.first(where: { $0.id == tripsStore.activeTripId }) else { return false }
        return activeTrip.stops != plannedStops
    }

    var routeStopAnnotations: [(index: Int, coordinate: CLLocationCoordinate2D)] {
        Array(plannedStops.enumerated()).map { index, stop in
            (index, CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng))
        }
    }

    /// Region that fits every coordinate belonging to the active trip (route
    /// line + breadcrumb + all stops), not just `MapScreen`'s own
    /// general-purpose `initialRegion` (city/GPS center with a fixed small
    /// span). `TripMapView` only applies `initialRegion` once on first
    /// render, so this has to already be correct as soon as route-mode
    /// tracking starts — otherwise only whichever stop happens to sit inside
    /// the general region's small span is visible, and the rest (and often
    /// the route line itself) render off-screen.
    func activeTripDisplayRegion(for trip: Trip) -> MKCoordinateRegion? {
        let routeCoords = (trip.routeGeometry ?? routeGeometry ?? []).compactMap(coordinate(fromPair:))
        let breadcrumbCoords = trip.breadcrumb.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        let stopCoords = trip.stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        let all = routeCoords + breadcrumbCoords + stopCoords
        let lats = all.map(\.latitude)
        let lngs = all.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return initialRegion }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        // Pad the bounding box so stops near the edge aren't clipped against
        // the map view's frame, with a floor so a single-stop or
        // very-close-together trip doesn't zoom in to street level.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.02),
            longitudeDelta: max((maxLng - minLng) * 1.6, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    func coordinate(fromPair pair: [Double]) -> CLLocationCoordinate2D? {
        guard pair.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
    }

    var routeModeToggleButton: some View {
        Button {
            if tripsStore.activeTripId != nil {
                routeMode = true
                return
            }
            // Leaving route mode with picked-but-not-yet-started stops used
            // to discard them on this single tap with no way back — confirm
            // first instead, matching the same "started" invariant used
            // everywhere else here (a *started* trip is only ever left via
            // the explicit "Bitir" button, never this toggle).
            if routeMode && !plannedStops.isEmpty {
                showDiscardStopsConfirm = true
                return
            }
            routeMode.toggle()
        } label: {
            Image(systemName: "flag.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(routeMode ? Theme.navy : .primary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(routeMode ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(.thinMaterial)))
                .shadow(radius: 3)
        }
        .alert(String(localized: "routeMode.discardStops.title"), isPresented: $showDiscardStopsConfirm) {
            Button(String(localized: "common.clear"), role: .destructive) {
                routeMode = false
                plannedStops = []
                routeGeometry = nil
                routeDistanceMeters = nil
                routeDurationSeconds = nil
                routeError = nil
                stopsExpanded = false
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text("routeMode.discardStops.message")
        }
    }

    /// Mirrors `map.tsx`'s hydration effect: resync local planning state from
    /// a trip that's already active (e.g. the user left the Map tab mid-trip
    /// and came back), and make sure breadcrumb recording is running.
    func rehydrateActiveTripIfNeeded() {
        guard let activeTripId = tripsStore.activeTripId, hydratedTripId != activeTripId,
              let activeTrip = tripsStore.trips.first(where: { $0.id == activeTripId }) else { return }
        plannedStops = activeTrip.stops
        routeGeometry = activeTrip.routeGeometry
        routeDistanceMeters = activeTrip.distanceMeters
        routeDurationSeconds = activeTrip.durationSeconds
        hydratedTripId = activeTripId
        routeProfileDirty = false
        if !locationManager.isRecordingBreadcrumb {
            locationManager.startBreadcrumbRecording()
        }
    }

    /// Resolves a tapped Apple base-map POI feature (same path
    /// `explainMapFeature` uses) and toggles it as a route stop.
    func toggleStop(fromFeature feature: MKMapFeatureAnnotation) async {
        guard let mapItem = try? await MKMapItemRequest(mapFeatureAnnotation: feature).mapItem else { return }
        let poi = POIPlace(
            name: mapItem.name ?? feature.title ?? "",
            category: mapItem.pointOfInterestCategory,
            coordinate: feature.coordinate,
            mapItem: mapItem
        )
        let reference = poi.asReference
        if let index = plannedStops.firstIndex(where: { $0.identifier == reference.identifier }) {
            plannedStops.remove(at: index)
        } else {
            plannedStops.append(reference)
        }
    }

    func moveStops(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        plannedStops.move(fromOffsets: offsets, toOffset: destination)
    }

    func removeStop(_ identifier: String) {
        plannedStops.removeAll { $0.identifier == identifier }
    }

    private func stopCoordinates() -> [PlaceCoordinate] {
        plannedStops.map { PlaceCoordinate(lat: $0.lat, lng: $0.lng) }
    }

    /// Entry point for "Haritada Rota Oluştur" (SavedScreen's Plan tab) —
    /// hands off a set of stops from another tab and shows the calculated
    /// route as a preview, instead of requiring the user to re-tap each
    /// place on the map one by one. Previously called `startRoute()`
    /// directly, which immediately committed to a live, breadcrumb-
    /// recording trip the instant a plan's route was opened — now it only
    /// previews the path; the existing "Rotayı Başlat" button in
    /// `routeModeSheet` (already shown whenever there's no active trip and
    /// 2+ stops) is what actually starts it.
    func startPendingRoute(_ stops: [SavedPOIReference]) async {
        guard tripsStore.activeTripId == nil else {
            // Already mid-trip — don't silently overwrite it. Same
            // invariant `routeModeToggleButton` already enforces: only ever
            // show the existing active trip until it's ended. Surface *why*
            // the hand-off's stops didn't take effect instead of just
            // dropping them with no explanation.
            routeMode = true
            routeError = String(localized: "map.route.activeTripConflict")
            return
        }
        plannedStops = stops
        routeMode = true
        await previewRoute()
    }

    /// Fetches and displays the route line for the current `plannedStops`
    /// without starting a live trip — `startRoute()` is the separate,
    /// explicit "commit" step (creates the `Trip`, starts breadcrumb
    /// recording) triggered by the user actually tapping "Rotayı Başlat".
    func previewRoute() async {
        guard plannedStops.count >= 2 else { return }
        isFetchingRoute = true
        routeError = nil
        defer { isFetchingRoute = false }
        do {
            let result = try await RoutesAPI.directions(coordinates: stopCoordinates(), profile: routeProfile)
            routeGeometry = result.route
            routeDistanceMeters = result.distanceMeters
            routeDurationSeconds = result.durationSeconds
        } catch {
            routeError = String(localized: "map.route.failed")
        }
    }

    func startRoute() async {
        guard plannedStops.count >= 2 else { return }
        isFetchingRoute = true
        routeError = nil
        defer { isFetchingRoute = false }
        do {
            let result = try await RoutesAPI.directions(coordinates: stopCoordinates(), profile: routeProfile)
            routeGeometry = result.route
            routeDistanceMeters = result.distanceMeters
            routeDurationSeconds = result.durationSeconds
            let tripId = tripsStore.startTrip(
                stops: plannedStops,
                route: RouteInfo(routeGeometry: result.route, distanceMeters: result.distanceMeters, durationSeconds: result.durationSeconds)
            )
            hydratedTripId = tripId
            routeProfileDirty = false
            locationManager.startBreadcrumbRecording()
        } catch {
            routeError = String(localized: "map.route.failed")
        }
    }

    func updateRoute() async {
        guard let activeTripId = tripsStore.activeTripId, plannedStops.count >= 2 else { return }
        isFetchingRoute = true
        routeError = nil
        defer { isFetchingRoute = false }
        do {
            let result = try await RoutesAPI.directions(coordinates: stopCoordinates(), profile: routeProfile)
            routeGeometry = result.route
            routeDistanceMeters = result.distanceMeters
            routeDurationSeconds = result.durationSeconds
            tripsStore.updateTripStops(
                activeTripId,
                stops: plannedStops,
                route: RouteInfo(routeGeometry: result.route, distanceMeters: result.distanceMeters, durationSeconds: result.durationSeconds)
            )
            routeProfileDirty = false
        } catch {
            routeError = String(localized: "map.route.failed")
        }
    }

    func endRoute() {
        if let activeTripId = tripsStore.activeTripId {
            tripsStore.endTrip(activeTripId)
            // Snapshot after endTrip() so distanceMeters/durationSeconds and
            // endedAt are already final -- endTrip() keeps the trip in
            // tripsStore.trips (just clears activeTripId), it doesn't
            // delete it, so this lookup is safe.
            lastEndedTrip = tripsStore.trips.first { $0.id == activeTripId }
        }
        locationManager.stopBreadcrumbRecording()
        hydratedTripId = nil
        plannedStops = []
        routeGeometry = nil
        routeDistanceMeters = nil
        routeDurationSeconds = nil
        routeMode = false
        stopsExpanded = false
        routeProfileDirty = false
        routeProfile = .footWalking
    }

    /// Best-effort location tag, matching RN's `attachTripPhoto`: reads
    /// whatever position is already available without prompting for
    /// permission (the map screen already requested it on appear).
    func attachTripPhoto(_ data: Data) async {
        guard let activeTripId = tripsStore.activeTripId, let url = TripPhotoStore.save(data) else { return }
        let location = locationManager.currentLocation
        tripsStore.addPhoto(activeTripId, photo: TripPhoto(
            uri: url.absoluteString,
            timestamp: Date().timeIntervalSince1970 * 1000,
            lat: location?.latitude,
            lng: location?.longitude
        ))
    }

    @ViewBuilder
    var routeModeSheet: some View {
        let activeTrip = tripsStore.trips.first(where: { $0.id == tripsStore.activeTripId })

        VStack(alignment: .leading, spacing: 12) {
            if let routeError {
                Text(routeError).font(.footnote).foregroundStyle(Theme.closedRed)
            }

            if let activeTrip {
                HStack(spacing: 8) {
                    Circle().fill(Theme.closedRed).frame(width: 8, height: 8)
                    Text(LPlural("map.route.tracking", count: activeTrip.breadcrumb.count)).font(.footnote.weight(.semibold))
                }
            }

            if !plannedStops.isEmpty {
                // Was always fetched walking-only with nothing in the UI
                // saying so — indistinguishable from a driving route at a
                // glance. Picking a mode here refetches immediately (see
                // `onChange(of: routeProfile)`), so the map/summary reflect
                // it right away instead of only after "Güncelle".
                Picker("", selection: $routeProfile) {
                    Label(String(localized: "map.route.walking"), systemImage: "figure.walk").tag(RouteProfile.footWalking)
                    Label(String(localized: "map.route.driving"), systemImage: "car.fill").tag(RouteProfile.drivingCar)
                }
                .pickerStyle(.segmented)
            }

            if plannedStops.isEmpty {
                Text("map.route.hint").font(.footnote).foregroundStyle(.secondary)
            } else {
                // Collapsed by default to a single summary row (stop count +
                // real distance/duration) — the full editable list used to
                // always take up roughly half the screen over the map
                // itself, with no way to shrink it back down to actually
                // look at the route. Tapping the summary expands it back to
                // the same draggable/removable rows as before.
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.2)) { stopsExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: routeProfile == .drivingCar ? "car.fill" : "figure.walk")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(LPlural("map.route.stopsCount", count: plannedStops.count))
                            .font(.footnote.weight(.semibold))
                        if let summary = routeSummaryText(activeTrip: activeTrip) {
                            Text("·").foregroundStyle(.secondary)
                            Text(summary).font(.footnote).foregroundStyle(.secondary)
                        } else if isFetchingRoute {
                            ProgressView().controlSize(.mini)
                        }
                        Spacer()
                        Image(systemName: stopsExpanded ? "chevron.down" : "chevron.up")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if stopsExpanded {
                    // Stacked rows with a native drag handle (`.onMove`), not
                    // the old horizontal row of chips with up/down chevron
                    // buttons — full-width rows read each stop's name
                    // without truncation, and dragging a row to any position
                    // is a single gesture instead of repeated adjacent-swap
                    // taps.
                    List {
                        ForEach(Array(plannedStops.enumerated()), id: \.element.identifier) { index, stop in
                            stopRow(index: index, stop: stop)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .onMove(perform: moveStops)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
                    .frame(height: min(CGFloat(plannedStops.count), 4) * 52)
                }
            }

            if let activeTrip, !activeTrip.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeTrip.photos) { photo in
                            CachedAsyncImage(url: URL(string: photo.uri), maxPixelSize: 200) {
                                $0.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color(.secondarySystemBackground)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                if activeTrip != nil {
                    Button {
                        showTripPhotoCapture = true
                    } label: {
                        Text("map.route.addPhoto")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
                    }
                }

                primaryRouteButton(activeTrip: activeTrip)
            }
        }
        .padding(16)
        .piriGlassCard(cornerRadius: 18)
    }

    @ViewBuilder
    private func primaryRouteButton(activeTrip: Trip?) -> some View {
        if activeTrip == nil {
            Button {
                Task { await startRoute() }
            } label: {
                HStack {
                    if isFetchingRoute { ProgressView().tint(.white) }
                    Text("map.route.start")
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.navy))
            }
            .disabled(plannedStops.count < 2 || isFetchingRoute)
            .opacity(plannedStops.count < 2 ? 0.5 : 1)
        } else {
            HStack(spacing: 10) {
                // Shown whenever stops differ from the active trip's saved
                // ones, not just when there happen to be ≥2 left — removing
                // stops down to 0-1 used to hide this button entirely, so
                // the removal was reflected in the UI but never actually
                // persisted to the trip. Keeping it visible (disabled +
                // dimmed, same convention `startRoute`'s button already
                // uses below `count >= 2`) makes that state visible and
                // gives the user something to act on instead of a removal
                // that silently didn't take.
                if stopsChangedFromActiveTrip {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button {
                            Task { await updateRoute() }
                        } label: {
                            Text("map.route.update")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.navy))
                        }
                        .disabled(isFetchingRoute || plannedStops.count < 2)
                        .opacity(plannedStops.count < 2 ? 0.5 : 1)

                        if plannedStops.count < 2 {
                            Text("map.route.updateNeedsTwoStops")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    endRoute()
                } label: {
                    Text("map.route.end")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.closedRed))
                }
            }
        }
    }

    /// Prefers the live-previewed values (kept fresh by
    /// `onChange(of: plannedStops)`) over the active trip's last-persisted
    /// ones, so an edited-but-not-yet-"Güncelle"d stop list still shows its
    /// own real distance instead of a stale one.
    private func routeSummaryText(activeTrip: Trip?) -> String? {
        guard let distanceMeters = routeDistanceMeters ?? activeTrip?.distanceMeters,
              let durationSeconds = routeDurationSeconds ?? activeTrip?.durationSeconds else { return nil }
        let km = String(format: "%.1f", distanceMeters / 1000)
        let minutes = String(Int((durationSeconds / 60).rounded()))
        return "\(L("map.route.distanceKm", km)) · \(L("map.route.durationMinutes", minutes))"
    }

    private func stopRow(index: Int, stop: SavedPOIReference) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.gold.opacity(0.15))
                Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
            }
            .frame(width: 24, height: 24)

            Text(stop.name).font(.subheadline.weight(.semibold)).lineLimit(1)

            Spacer()

            Button { removeStop(stop.identifier) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }
}

/// Minimal capture UI reusing `ScanScreen`'s camera/gallery idiom, stripped
/// of the identify pipeline — hands raw JPEG data back to `MapScreen` via a
/// closure so it stays free of `TripsStore`/`LocationManager` dependencies.
struct TripPhotoCaptureSheet: View {
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var galleryItem: PhotosPickerItem?
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            if camera.isAuthorized {
                CameraPreviewView(session: camera.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                // Was just a black screen with a permanently-disabled
                // shutter and no explanation — same permission-denied
                // overlay `ScanScreen` already uses for this identical
                // `CameraController`/`isAuthorized` API.
                VStack(spacing: 16) {
                    Text("scan.permission.title").font(.system(size: 24, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    Text("scan.permission.body").foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                    Button {
                        Task { await camera.requestAuthorizationAndStart() }
                    } label: {
                        Text("scan.permission.allow")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.navy)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Theme.gold))
                    }
                }
                .padding(32)
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(.white).padding(10).background(Circle().fill(.black.opacity(0.35)))
                    }
                    Spacer()
                }
                .padding(20)

                Spacer()

                HStack(spacing: 40) {
                    PhotosPicker(selection: $galleryItem, matching: .images) {
                        Text("map.route.photoGallery")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    Button {
                        Task { await capture() }
                    } label: {
                        Circle().fill(.white).frame(width: 60, height: 60)
                            .padding(8)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                    .disabled(isCapturing || !camera.isAuthorized)

                    Text("map.route.photoCamera")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.bottom, 48)
            }
        }
        .task { await camera.requestAuthorizationAndStart() }
        .onDisappear { camera.stop() }
        .onChange(of: galleryItem) { _, newItem in
            Task { await handleGalleryPick(newItem) }
        }
    }

    private func capture() async {
        guard !isCapturing else { return }
        Haptics.medium()
        isCapturing = true
        defer { isCapturing = false }
        guard let data = await camera.capturePhoto() else { return }
        onCapture(data)
        dismiss()
    }

    private func handleGalleryPick(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        galleryItem = nil
        onCapture(data)
        dismiss()
    }
}
