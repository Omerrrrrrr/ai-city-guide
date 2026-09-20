import XCTest
@testable import Piri

/// Port of `mobile/src/store/__tests__/trips.test.ts`. Each test uses its
/// own `TripsStore` instance (backed by a unique UserDefaults suite) instead
/// of resetting shared global state between tests, since `TripsStore` isn't
/// a singleton here.
final class TripsStoreTests: XCTestCase {
    private func makeStore() -> TripsStore {
        let suiteName = "TripsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TripsStore(defaults: defaults)
    }

    private func stop(_ identifier: String, lat: Double = 58.1, lng: Double = 7.9) -> SavedPOIReference {
        SavedPOIReference(identifier: identifier, name: identifier, categoryRawValue: nil, lat: lat, lng: lng, address: nil)
    }

    func testStartTripMarksItActiveWithGivenStopsAndRoute() {
        let store = makeStore()
        let routeGeometry: [[Double]] = [[58.1, 7.9], [58.11, 7.91]]
        let stops = [stop("posebyen"), stop("kunstsilo")]
        let id = store.startTrip(stops: stops, route: RouteInfo(routeGeometry: routeGeometry, distanceMeters: 1200, durationSeconds: 900))

        XCTAssertEqual(store.activeTripId, id)
        XCTAssertEqual(store.trips.count, 1)
        let trip = store.trips[0]
        XCTAssertEqual(trip.id, id)
        XCTAssertEqual(trip.stops, stops)
        XCTAssertEqual(trip.routeGeometry ?? [], routeGeometry)
        XCTAssertEqual(trip.distanceMeters, 1200)
        XCTAssertEqual(trip.durationSeconds, 900)
        XCTAssertEqual(trip.breadcrumb, [])
        XCTAssertEqual(trip.photos, [])
        XCTAssertNil(trip.endedAt)
    }

    func testRenameTrip() {
        let store = makeStore()
        let id = store.startTrip(stops: [stop("posebyen")])
        store.renameTrip(id, name: "Sunday walk")

        XCTAssertEqual(store.trips.first { $0.id == id }?.name, "Sunday walk")
    }

    func testUpdateTripStopsWithoutTouchingBreadcrumbOrPhotos() {
        let store = makeStore()
        let id = store.startTrip(stops: [stop("posebyen")])
        store.addBreadcrumb(id, point: TripWaypoint(lat: 58.1, lng: 7.9, timestamp: 1000))

        let newRoute: [[Double]] = [[58.2, 8.0], [58.21, 8.01]]
        let newStops = [stop("posebyen"), stop("kunstsilo")]
        store.updateTripStops(id, stops: newStops, route: RouteInfo(routeGeometry: newRoute, distanceMeters: 2000, durationSeconds: 1500))

        let trip = store.trips.first { $0.id == id }
        XCTAssertEqual(trip?.stops, newStops)
        XCTAssertEqual(trip?.routeGeometry ?? [], newRoute)
        XCTAssertEqual(trip?.distanceMeters, 2000)
        XCTAssertEqual(trip?.breadcrumb, [TripWaypoint(lat: 58.1, lng: 7.9, timestamp: 1000)])
    }

    func testAppendsBreadcrumbPointsToTheRightTripOnly() {
        let store = makeStore()
        let id = store.startTrip(stops: [stop("posebyen")])
        store.addBreadcrumb(id, point: TripWaypoint(lat: 58.1, lng: 7.9, timestamp: 1000))
        store.addBreadcrumb(id, point: TripWaypoint(lat: 58.11, lng: 7.91, timestamp: 2000))

        let trip = store.trips.first { $0.id == id }
        XCTAssertEqual(trip?.breadcrumb, [
            TripWaypoint(lat: 58.1, lng: 7.9, timestamp: 1000),
            TripWaypoint(lat: 58.11, lng: 7.91, timestamp: 2000),
        ])
    }

    func testAppendsPhotosToATrip() {
        let store = makeStore()
        let id = store.startTrip(stops: [stop("posebyen")])
        store.addPhoto(id, photo: TripPhoto(uri: "file:///photo.jpg", timestamp: 5000, lat: nil, lng: nil))

        let trip = store.trips.first { $0.id == id }
        XCTAssertEqual(trip?.photos, [TripPhoto(uri: "file:///photo.jpg", timestamp: 5000, lat: nil, lng: nil)])
    }

    func testEndTripStampsEndedAtAndClearsActiveTripId() {
        let store = makeStore()
        let id = store.startTrip(stops: [stop("posebyen")])
        store.endTrip(id)

        XCTAssertNil(store.activeTripId)
        XCTAssertNotNil(store.trips.first { $0.id == id }?.endedAt)
    }

    /// A trip started from Home has no stops and no planned route, so
    /// distance/duration must be measured from what was actually recorded --
    /// the recap video's stat tiles read exactly these fields.
    func testEndingAStoplessTripMeasuresDistanceAndDurationFromBreadcrumb() {
        let store = makeStore()
        let id = store.startTrip(stops: [])
        let start = store.trips[0].startedAt
        // ~1.11 km apart (0.01 degrees of latitude).
        store.addBreadcrumb(id, point: TripWaypoint(lat: 58.10, lng: 7.9, timestamp: start))
        store.addBreadcrumb(id, point: TripWaypoint(lat: 58.11, lng: 7.9, timestamp: start + 60_000))
        store.endTrip(id)

        let trip = store.trips[0]
        XCTAssertNotNil(trip.endedAt)
        XCTAssertEqual(trip.distanceMeters ?? 0, 1112, accuracy: 15)
        XCTAssertNotNil(trip.durationSeconds)
        XCTAssertGreaterThanOrEqual(trip.durationSeconds ?? -1, 0)
    }

    func testEndingAPlannedTripKeepsItsRouteDistanceAndDuration() {
        let store = makeStore()
        let id = store.startTrip(stops: [stop("a"), stop("b")], route: RouteInfo(routeGeometry: nil, distanceMeters: 1200, durationSeconds: 900))
        store.addBreadcrumb(id, point: TripWaypoint(lat: 58.10, lng: 7.9, timestamp: 0))
        store.addBreadcrumb(id, point: TripWaypoint(lat: 58.20, lng: 7.9, timestamp: 1))
        store.endTrip(id)

        XCTAssertEqual(store.trips[0].distanceMeters, 1200)
        XCTAssertEqual(store.trips[0].durationSeconds, 900)
    }

    func testMeasuredDistanceIgnoresInvalidPointsAndShortPaths() {
        XCTAssertEqual(TripsStore.measuredDistance(of: []), 0)
        XCTAssertEqual(TripsStore.measuredDistance(of: [TripWaypoint(lat: 58, lng: 7, timestamp: 0)]), 0)
        let withGlitch = [
            TripWaypoint(lat: 58.10, lng: 7.9, timestamp: 0),
            TripWaypoint(lat: .nan, lng: 7.9, timestamp: 1),
            TripWaypoint(lat: 58.11, lng: 7.9, timestamp: 2),
        ]
        XCTAssertEqual(TripsStore.measuredDistance(of: withGlitch), 1112, accuracy: 15)
    }

    func testDeleteTripClearsActiveTripIdIfItWasActive() {
        let store = makeStore()
        let id = store.startTrip(stops: [stop("posebyen")])
        store.deleteTrip(id)

        XCTAssertEqual(store.trips.count, 0)
        XCTAssertNil(store.activeTripId)
    }
}
