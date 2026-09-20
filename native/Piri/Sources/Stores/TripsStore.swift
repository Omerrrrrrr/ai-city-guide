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

    /// For AI personalization context (see `PlaceSummaryInput`'s siblings in
    /// `AIResponses.swift`) — one compact line per completed trip (an
    /// in-progress trip has no real shape to summarize yet), most recent
    /// first, capped to 5. Plain English regardless of the app's own
    /// language, same as `RecentlyViewedStore`/`SavedPlacesStore`'s
    /// summaries -- this text is for the AI prompt, not shown to the user,
    /// and `languageInstruction(locale)` already tells the model what
    /// language to reply in separately.
    var asPersonalizationSummaries: [String] {
        let completed = trips
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(5)
        let now = Date().timeIntervalSince1970 * 1000
        return completed.map { trip in
            let stopNames = trip.stops.prefix(4).map(\.name).joined(separator: ", ")
            let daysAgo = max(0, Int((now - trip.startedAt) / (1000 * 60 * 60 * 24)))
            let recency = daysAgo == 0 ? "today" : "\(daysAgo)d ago"
            let label = trip.name?.trimmingCharacters(in: .whitespaces).isEmpty == false ? trip.name! : "Trip"
            return stopNames.isEmpty ? "\(label) (\(recency))" : "\(label): \(stopNames) (\(recency))"
        }
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
            let now = Date().timeIntervalSince1970 * 1000
            trips[index].endedAt = now
            // A trip started without a planned route (Home's "Start a Trip")
            // has no distance/duration from a directions call, and the
            // recap video's stat tiles read exactly these two fields --
            // measure what actually happened instead of showing "—".
            // Planned trips keep their route's own numbers.
            if trips[index].distanceMeters == nil {
                let measured = Self.measuredDistance(of: trips[index].breadcrumb)
                trips[index].distanceMeters = measured > 0 ? measured : nil
            }
            if trips[index].durationSeconds == nil {
                trips[index].durationSeconds = max(0, (now - trips[index].startedAt) / 1000)
            }
        }
        if activeTripId == id {
            activeTripId = nil
        }
        persist()
    }

    /// Sum of straight-line hops between consecutive valid GPS samples.
    static func measuredDistance(of breadcrumb: [TripWaypoint]) -> Double {
        let valid = breadcrumb.filter { $0.lat.isFinite && $0.lng.isFinite }
        guard valid.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for (previous, next) in zip(valid, valid.dropFirst()) {
            total += CLLocation(latitude: previous.lat, longitude: previous.lng)
                .distance(from: CLLocation(latitude: next.lat, longitude: next.lng))
        }
        return total
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

    /// Called on sign-out ([[AuthStore.signOut]]) -- unlike `replaceTrips`,
    /// this also clears `activeTripId`. Without this, a different person
    /// signing in afterward on the same device would inherit (and, via
    /// `AuthStore.performInitialSync`'s "push local data to seed the
    /// account" path, permanently upload under their own account) whatever
    /// trip history the previous person left behind.
    func clearAllLocalData() {
        trips = []
        activeTripId = nil
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
