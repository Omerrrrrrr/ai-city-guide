import Foundation
import Observation

private struct TripsState: Codable {
    var trips: [Trip] = []
    var activeTripId: String?
}

/// Port of `mobile/src/store/trips.ts`.
@Observable
final class TripsStore {
    private(set) var trips: [Trip] = []
    private(set) var activeTripId: String?

    private let persistence: UserDefaultsStore<TripsState>

    init(defaults: UserDefaults = .standard) {
        persistence = UserDefaultsStore<TripsState>(key: "piri.trips", defaults: defaults)
        if let saved = persistence.load() {
            trips = saved.trips
            activeTripId = saved.activeTripId
        }
    }

    @discardableResult
    func startTrip(stops: [SavedPOIReference], route: RouteInfo? = nil) -> String {
        let id = "trip-\(Int(Date().timeIntervalSince1970 * 1000))"
        let trip = Trip(
            id: id,
            name: nil,
            stops: stops,
            routeGeometry: route?.routeGeometry,
            distanceMeters: route?.distanceMeters,
            durationSeconds: route?.durationSeconds,
            breadcrumb: [],
            photos: [],
            startedAt: Date().timeIntervalSince1970 * 1000,
            endedAt: nil
        )
        trips.insert(trip, at: 0)
        activeTripId = id
        persist()
        return id
    }

    func endTrip(_ id: String) {
        if let index = trips.firstIndex(where: { $0.id == id }) {
            trips[index].endedAt = Date().timeIntervalSince1970 * 1000
        }
        if activeTripId == id {
            activeTripId = nil
        }
        persist()
    }

    func addBreadcrumb(_ id: String, point: TripWaypoint) {
        guard let index = trips.firstIndex(where: { $0.id == id }) else { return }
        trips[index].breadcrumb.append(point)
        persist()
    }

    func addPhoto(_ id: String, photo: TripPhoto) {
        guard let index = trips.firstIndex(where: { $0.id == id }) else { return }
        trips[index].photos.append(photo)
        persist()
    }

    func deleteTrip(_ id: String) {
        trips.removeAll { $0.id == id }
        if activeTripId == id {
            activeTripId = nil
        }
        persist()
    }

    func renameTrip(_ id: String, name: String) {
        guard let index = trips.firstIndex(where: { $0.id == id }) else { return }
        trips[index].name = name
        persist()
    }

    func updateTripStops(_ id: String, stops: [SavedPOIReference], route: RouteInfo? = nil) {
        guard let index = trips.firstIndex(where: { $0.id == id }) else { return }
        trips[index].stops = stops
        if let route {
            trips[index].routeGeometry = route.routeGeometry
            trips[index].distanceMeters = route.distanceMeters
            trips[index].durationSeconds = route.durationSeconds
        }
        persist()
    }

    /// Overwrites local state with a pulled server copy (account sync only).
    /// `activeTripId` deliberately isn't part of this -- an in-progress trip
    /// is a single-device, in-the-moment session concept, not something
    /// meaningful to carry across devices.
    func replaceTrips(_ newTrips: [Trip]) {
        trips = newTrips
        persist()
    }

    private func persist() {
        persistence.save(TripsState(trips: trips, activeTripId: activeTripId))
    }
}
