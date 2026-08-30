import CoreLocation
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

    /// Single source of truth for "is there really a trip in progress right
    /// now" — every call site used to re-derive this inline as
    /// `trips.first(where: { $0.id == activeTripId })`, which trusts
    /// `activeTripId` alone. Also requiring `endedAt == nil` here means a
    /// trip that's already been ended can never be treated as active again
    /// just because something left `activeTripId` pointing at it.
    var activeTrip: Trip? {
        guard let activeTripId else { return nil }
        return trips.first { $0.id == activeTripId && $0.endedAt == nil }
    }

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

    private static let verifiedVisitRadiusMeters: CLLocationDistance = 150

    /// Whether this device has real evidence of a physical visit near
    /// `lat`/`lng` -- either GPS breadcrumb from a trip that actually
    /// passed within range (recorded live during an in-progress trip, not
    /// just planned), or a stop on a trip that was *completed* (not just
    /// started). A stop on a still-active or abandoned trip doesn't count
    /// -- planning to go somewhere isn't evidence of having gone. Backs
    /// the "verified visit" flag sent with a new review (see
    /// `WriteReviewSheet`) -- self-reported to the server, which has no
    /// way to check GPS itself, but grounded in real location data the
    /// app already collected rather than a bare checkbox.
    func hasVisited(lat: Double, lng: Double, radiusMeters: CLLocationDistance = verifiedVisitRadiusMeters) -> Bool {
        let target = CLLocation(latitude: lat, longitude: lng)
        for trip in trips {
            if trip.breadcrumb.contains(where: { CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: target) <= radiusMeters }) {
                return true
            }
            if trip.endedAt != nil, trip.stops.contains(where: { CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: target) <= radiusMeters }) {
                return true
            }
        }
        return false
    }
}
