import CoreLocation
import MapKit
import SwiftUI

/// Port of `mobile/app/trip/[id].tsx`.
struct TripDetailScreen: View {
    let tripId: String

    @Environment(TripsStore.self) private var tripsStore
    @Environment(\.dismiss) private var dismiss

    @State private var isPlaying = false
    @State private var playbackPosition: CLLocationCoordinate2D?
    @State private var playbackTask: Task<Void, Never>?
    @State private var isEditingName = false
    @State private var nameInput = ""
    @State private var showDeleteConfirm = false
    /// `TripSummarySheet` also auto-opens once, right when a trip ends
    /// (`MapScreen.lastEndedTrip`) — this is the way back to it afterward,
    /// for whoever dismissed that without sharing/screenshotting and wants
    /// it again later. Same sheet, just a second entry point.
    @State private var showingSummary = false
    @State private var viewerIndex: Int?
    @State private var selectedPOI: POIPlace?
    @State private var resolvingStopIdentifier: String?
    /// Keyed by stop name, same empty-string-sentinel contract
    /// `ExploreScreen`/`HomeScreen` already use for their own photo grids —
    /// an empty string means "checked, no photo found," not "not asked yet."
    @State private var photoURLs: [String: String] = [:]

    private let playbackStepMs = 50.0
    private let playbackSegmentMs = 450.0

    private var trip: Trip? {
        tripsStore.trips.first { $0.id == tripId }
    }

    var body: some View {
        Group {
            if let trip {
                content(trip)
            } else {
                VStack(spacing: 16) {
                    Text("trips.notFound").foregroundStyle(.secondary)
                    Button("common.cancel") { dismiss() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
        .onDisappear { playbackTask?.cancel() }
    }

    @ViewBuilder
    private func content(_ trip: Trip) -> some View {
        let stops = trip.stops
        let breadcrumbCoordinates = trip.breadcrumb.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        let routeCoordinates = (trip.routeGeometry ?? []).compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        let allCoordinates = routeCoordinates + breadcrumbCoordinates + stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }

        VStack(spacing: 0) {
            header(trip)

            ZStack(alignment: .bottom) {
                TripMapView(
                    routeCoordinates: routeCoordinates,
                    breadcrumbCoordinates: breadcrumbCoordinates,
                    stops: Array(stops.enumerated()).map { index, stop in
                        (index, CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng))
                    },
                    playbackPosition: playbackPosition,
                    initialRegion: averageRegion(allCoordinates)
                )

                if trip.breadcrumb.count > 1 {
                    Button {
                        if isPlaying { stopPlayback() } else { startPlayback(trip) }
                    } label: {
                        Text(isPlaying ? "⏸ " + String(localized: "trips.pause") : "▶ " + String(localized: "trips.play"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(Capsule().fill(Theme.navy))
                    }
                    .padding(.bottom, 14)
                }
            }
            .frame(height: 280)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    statsRow(trip)
                        .padding(.bottom, 6)

                    Text("trips.stopsLabel").font(.system(size: 12, weight: .bold)).opacity(0.45).textCase(.uppercase)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(stops.enumerated()), id: \.element.identifier) { index, stop in
                            timelineStopRow(index, stop, isLast: index == stops.count - 1)
                        }
                    }
                    .onAppear { loadPhotosIfNeeded(for: stops) }

                    if !trip.photos.isEmpty {
                        Text("trips.photosLabel").font(.system(size: 12, weight: .bold)).opacity(0.45).textCase(.uppercase).padding(.top, 8)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(trip.photos.enumerated()), id: \.element.id) { index, photo in
                                    Button {
                                        viewerIndex = index
                                    } label: {
                                        CachedAsyncImage(url: URL(string: photo.uri), maxPixelSize: 300) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemBackground) }
                                            .frame(width: 90, height: 90)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: Binding(get: { viewerIndex.map(PhotoViewerIndex.init) }, set: { viewerIndex = $0?.value })) { wrapped in
            PhotoViewer(photos: trip.photos, index: wrapped.value)
        }
        .sheet(item: $selectedPOI) { poi in POIExplainSheet(poi: poi) }
        .sheet(isPresented: $showingSummary) { TripSummarySheet(trip: trip) }
        .onAppear { nameInput = trip.name ?? "" }
    }

    private func openStop(_ stop: SavedPOIReference) async {
        resolvingStopIdentifier = stop.identifier
        selectedPOI = await stop.resolve()
        resolvingStopIdentifier = nil
    }

    /// Distance/duration/stop-count summary — data `Trip` has carried since
    /// the very first route-mode trip, but this screen never actually
    /// showed any of it. Same three-stat-card language Polarsteps and
    /// nearly every trip-tracking app use for a journey's headline numbers.
    private func statsRow(_ trip: Trip) -> some View {
        HStack(spacing: 0) {
            statItem(value: trip.formattedDistance, label: String(localized: "trips.stat.distance"))
            Divider().frame(height: 30)
            statItem(value: trip.formattedDuration, label: String(localized: "trips.stat.duration"))
            Divider().frame(height: 30)
            statItem(value: "\(trip.stops.count)", label: String(localized: "trips.stat.stops"))
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 17, weight: .bold))
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    /// A continuous vertical line behind the step badges, connecting each
    /// stop to the next — the one visual element that turns "a list of
    /// places" into "a journey," the same device Polarsteps' own step
    /// timeline is built around.
    private func timelineStopRow(_ index: Int, _ stop: SavedPOIReference, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Theme.navy)
                    Text("\(index + 1)").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.gold)
                }
                .frame(width: 26, height: 26)

                if !isLast {
                    Rectangle().fill(Theme.gold.opacity(0.3)).frame(width: 2)
                }
            }
            .frame(width: 26)

            Button {
                Task { await openStop(stop) }
            } label: {
                HStack(spacing: 12) {
                    timelinePhoto(for: stop)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stop.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        if let category = stop.category {
                            Text(category.rawValue.replacingOccurrences(of: "MKPOICategory", with: ""))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if resolvingStopIdentifier == stop.identifier {
                        ProgressView()
                    }
                }
                .padding(.bottom, isLast ? 4 : 20)
            }
            .buttonStyle(.plain)
            .disabled(resolvingStopIdentifier != nil)
        }
    }

    /// See `HomeScreen`'s `nearbyTileImage` (identical bug) for why this
    /// doesn't just use `.frame(width:height:).clipped()` directly --
    /// unreliable for portrait-source photos. Not user-visible here since
    /// the caller's own `.clipShape` was already re-cropping correctly,
    /// but fixing the same latent bug at its source rather than relying on
    /// that.
    @ViewBuilder
    private func timelinePhoto(for stop: SavedPOIReference) -> some View {
        let urlString = photoURLs[stop.name]
        if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
            CachedAsyncImage(url: url, maxPixelSize: 200) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                categoryFallback(stop)
            }
            .frame(width: 64, height: 64)
            .clipped()
        } else {
            categoryFallback(stop).frame(width: 64, height: 64)
        }
    }

    private func categoryFallback(_ stop: SavedPOIReference) -> some View {
        ZStack {
            POICategoryGroups.gradient(for: stop.category)
            Image(systemName: POICategoryGroups.icon(for: stop.category))
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private func loadPhotosIfNeeded(for stops: [SavedPOIReference]) {
        let missing = stops.filter { photoURLs[$0.name] == nil }.prefix(20)
        guard !missing.isEmpty else { return }
        let request = PhotoBulkRequest(places: missing.map {
            PhotoBulkPlace(name: $0.name, lat: $0.lat, lng: $0.lng, category: $0.category.map { $0.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") })
        })
        Task {
            guard let response = try? await PlacesAPI.photosBulk(request) else { return }
            for result in response.results {
                photoURLs[result.name] = result.photoUrl ?? ""
            }
        }
    }

    private func header(_ trip: Trip) -> some View {
        HStack {
            Button("common.cancel") { dismiss() }
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            if isEditingName {
                TextField(trip.dateLabel, text: $nameInput)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .onSubmit { tripsStore.renameTrip(trip.id, name: nameInput.trimmingCharacters(in: .whitespaces)); isEditingName = false }
                    // A swipe-down dismiss (rather than the Return key)
                    // used to lose whatever was typed with no warning —
                    // commit it on disappear too, same as any other
                    // "close the sheet" path.
                    .onDisappear {
                        guard isEditingName else { return }
                        tripsStore.renameTrip(trip.id, name: nameInput.trimmingCharacters(in: .whitespaces))
                    }
            } else {
                Button {
                    nameInput = trip.name ?? ""
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Text(trip.displayTitle).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            Spacer()

            HStack(spacing: 14) {
                Button {
                    showingSummary = true
                } label: {
                    Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.7))
                }
                ShareLink(item: shareText(trip)) {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(.white.opacity(0.7))
                }
                Button("common.clear") {
                    showDeleteConfirm = true
                }
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .piriGlassSurface()
        .alert(String(localized: "trip.delete.title"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "common.clear"), role: .destructive) {
                tripsStore.deleteTrip(trip.id)
                dismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text("trip.delete.message")
        }
    }

    private func shareText(_ trip: Trip) -> String {
        let stopNames = trip.stops.map(\.name).joined(separator: " → ")
        let distanceLine = trip.distanceMeters.map { L("trips.share.distance", String(format: "%.1f", $0 / 1000)) } ?? ""
        return L(
            "trips.share.message",
            trip.displayTitle,
            trip.dateLabel,
            stopNames.isEmpty ? String(localized: "trips.share.noStops") : stopNames,
            distanceLine
        )
    }

    /// Bounding-box fit, not just a centroid with a fixed span — a fixed
    /// 0.05° span silently clips stops on any trip that actually covers more
    /// ground than that (same bug already fixed for `MapScreen`'s live route
    /// tracking; this screen's post-trip summary map had the identical gap).
    private func averageRegion(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.02),
            longitudeDelta: max((maxLng - minLng) * 1.6, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func startPlayback(_ trip: Trip) {
        guard trip.breadcrumb.count > 1 else { return }
        playbackTask?.cancel()
        isPlaying = true

        playbackTask = Task {
            var segment = 0
            var t = 0.0
            playbackPosition = CLLocationCoordinate2D(latitude: trip.breadcrumb[0].lat, longitude: trip.breadcrumb[0].lng)

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(playbackStepMs)))
                guard !Task.isCancelled else { return }

                t += playbackStepMs / playbackSegmentMs
                let a = trip.breadcrumb[segment]
                let b = trip.breadcrumb[segment + 1]

                if t >= 1 {
                    let nextSegment = segment + 1
                    if nextSegment >= trip.breadcrumb.count - 1 {
                        playbackPosition = CLLocationCoordinate2D(latitude: b.lat, longitude: b.lng)
                        isPlaying = false
                        return
                    }
                    segment = nextSegment
                    t = 0
                    playbackPosition = CLLocationCoordinate2D(latitude: b.lat, longitude: b.lng)
                } else {
                    playbackPosition = CLLocationCoordinate2D(
                        latitude: a.lat + (b.lat - a.lat) * t,
                        longitude: a.lng + (b.lng - a.lng) * t
                    )
                }
            }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        playbackPosition = nil
    }
}

private struct PhotoViewerIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

private struct PhotoViewer: View {
    let photos: [TripPhoto]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { photoIndex, photo in
                    CachedAsyncImage(url: URL(string: photo.uri), maxPixelSize: 1600) { $0.resizable().aspectRatio(contentMode: .fit) } placeholder: { Color.clear }
                        .tag(photoIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Text("\(index + 1) / \(photos.count)").foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}
