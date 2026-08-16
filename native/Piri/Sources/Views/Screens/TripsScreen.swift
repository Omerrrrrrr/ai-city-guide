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
        HStack(spacing: 0) {
            Group {
                if points.count > 1 {
                    TripMiniMap(points: points)
                } else {
                    ZStack {
                        Color(.secondarySystemBackground)
                        Text("◈").font(.system(size: 24)).foregroundStyle(Theme.gold)
                    }
                }
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 5) {
                Text(dateLabel).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text(metaText).font(.system(size: 13)).foregroundStyle(.secondary)
                if trip.endedAt == nil {
                    Text("trips.inProgress")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.closedRed)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.closedRed.opacity(0.08)))
                }
            }
            .padding(12)
            Spacer()
            Text("›").font(.system(size: 22)).foregroundStyle(.secondary.opacity(0.5)).padding(.trailing, 14)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var metaText: String {
        var text = LPlural("trips.stopsCount", count: trip.stops.count)
        if !trip.photos.isEmpty {
            text += " · " + LPlural("trips.photosCount", count: trip.photos.count)
        }
        return text
    }
}
