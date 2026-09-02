import CoreLocation
import SwiftUI

/// Port of `mobile/app/trips.tsx`.
struct TripsScreen: View {
    @Environment(TripsStore.self) private var tripsStore

    var body: some View {
        ScrollView {
            if tripsStore.trips.isEmpty {
                VStack(spacing: 12) {
                    Text("◈").font(.system(size: 48)).foregroundStyle(Theme.gold.opacity(0.6))
                    Text("trips.empty.title").font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
                    Text("trips.empty.body").font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(tripsStore.trips) { trip in
                        NavigationLink(destination: TripDetailScreen(tripId: trip.id)) {
                            TripRowView(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("trips.title")
    }
}

private struct TripRowView: View {
    let trip: Trip

    /// Falls back from breadcrumb → planned route → stop coordinates, in
    /// that order — a trip with real recorded GPS movement uses that (the
    /// actual path walked), but a trip that was started and ended quickly,
    /// or where breadcrumb recording never caught more than one point,
    /// still has a route line or stop pins worth showing. Previously this
    /// only ever used breadcrumb, so any trip without 2+ recorded points
    /// fell back to a plain generic icon even when it clearly had a real
    /// route or stops to draw.
    private var points: [CLLocationCoordinate2D] {
        let breadcrumbPoints = trip.breadcrumb.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        if breadcrumbPoints.count > 1 { return breadcrumbPoints }

        let routePoints = (trip.routeGeometry ?? []).compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        if routePoints.count > 1 { return routePoints }

        return trip.stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    private var dateLabel: String {
        if let name = trip.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        return Date(timeIntervalSince1970: trip.startedAt / 1000).formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Real trip photo takes priority when one exists — a much more
            // premium, editorial treatment than the schematic mini-map ever
            // was. The mini-map (real recorded route/stops) is still a
            // meaningful fallback for a trip with no photos at all, ahead
            // of a plain generic icon.
            Group {
                if let cover = trip.photos.first {
                    CachedAsyncImage(url: URL(string: cover.uri), maxPixelSize: 800) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Theme.navy
                    }
                } else if points.count > 1 {
                    TripMiniMap(points: points)
                } else {
                    ZStack {
                        Theme.navy
                        Text("◈").font(.system(size: 32)).foregroundStyle(Theme.gold)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                if trip.endedAt == nil {
                    Text("trips.inProgress")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.closedRed.opacity(0.9)))
                }
                Text(dateLabel).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(metaText).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
            }
            .padding(14)
        }
        .frame(height: 160)
        .background(Theme.navy)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }

    private var metaText: String {
        var text = LPlural("trips.stopsCount", count: trip.stops.count)
        if !trip.photos.isEmpty {
            text += " · " + LPlural("trips.photosCount", count: trip.photos.count)
        }
        return text
    }
}
