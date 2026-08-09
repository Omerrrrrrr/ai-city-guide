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
    @State private var viewerIndex: Int?
    @State private var selectedPOI: POIPlace?
    @State private var resolvingStopIdentifier: String?

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
                    Text("trips.stopsLabel").font(.system(size: 12, weight: .bold)).opacity(0.45).textCase(.uppercase)
                    ForEach(Array(stops.enumerated()), id: \.element.identifier) { index, stop in
                        Button {
                            Task { await openStop(stop) }
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(Theme.gold.opacity(0.15))
                                    Text("\(index + 1)").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.gold)
                                }
                                .frame(width: 22, height: 22)
                                ZStack {
                                    Color(.secondarySystemBackground)
                                    Image(systemName: POICategoryGroups.icon(for: stop.category)).foregroundStyle(Theme.gold)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(stop.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Spacer()
                                if resolvingStopIdentifier == stop.identifier {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(resolvingStopIdentifier != nil)
                    }

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
        .onAppear { nameInput = trip.name ?? "" }
    }

    private func openStop(_ stop: SavedPOIReference) async {
        resolvingStopIdentifier = stop.identifier
        selectedPOI = await stop.resolve()
        resolvingStopIdentifier = nil
    }

    private func header(_ trip: Trip) -> some View {
        HStack {
            Button("common.cancel") { dismiss() }
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            if isEditingName {
                TextField(tripDateLabel(trip), text: $nameInput)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .onSubmit { tripsStore.renameTrip(trip.id, name: nameInput.trimmingCharacters(in: .whitespaces)); isEditingName = false }
            } else {
                Button {
                    nameInput = trip.name ?? ""
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Text(tripTitle(trip)).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        Text("✎").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            Spacer()

            HStack(spacing: 14) {
                ShareLink(item: shareText(trip)) {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(.white.opacity(0.7))
                }
                Button("common.clear") {
                    tripsStore.deleteTrip(trip.id)
                    dismiss()
                }
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Theme.navy)
    }

    private func tripDateLabel(_ trip: Trip) -> String {
        Date(timeIntervalSince1970: trip.startedAt / 1000).formatted(date: .abbreviated, time: .omitted)
    }

    private func tripTitle(_ trip: Trip) -> String {
        let name = trip.name?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? tripDateLabel(trip) : name
    }

    private func shareText(_ trip: Trip) -> String {
        let stopNames = trip.stops.map(\.name).joined(separator: " → ")
        let distanceLine = trip.distanceMeters.map { L("trips.share.distance", String(format: "%.1f", $0 / 1000)) } ?? ""
        return L(
            "trips.share.message",
            tripTitle(trip),
            tripDateLabel(trip),
            stopNames.isEmpty ? String(localized: "trips.share.noStops") : stopNames,
            distanceLine
        )
    }

    /// Bounding-box fit, not just a centroid with a fixed span — a fixed
    /// 0.05° span silently clips stops on any trip that actually covers more
    /// ground than that (same bug already fixed for `MapScreen`'s live route
    /// tracking; this screen's post-trip summary map had the identical gap).
    private func averageRegion(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.02),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.6, 0.02)
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
