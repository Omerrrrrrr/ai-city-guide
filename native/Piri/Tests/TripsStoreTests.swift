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

    func testStartTripMarksItActiveWithGivenStopsAndRoute() {
        let store = makeStore()
        let routeGeometry: [[Double]] = [[58.1, 7.9], [58.11, 7.91]]
        let id = store.startTrip(placeIds: ["posebyen", "kunstsilo"], route: RouteInfo(routeGeometry: routeGeometry, distanceMeters: 1200, durationSeconds: 900))

        XCTAssertEqual(store.activeTripId, id)
        XCTAssertEqual(store.trips.count, 1)
        let trip = store.trips[0]
        XCTAssertEqual(trip.id, id)
        XCTAssertEqual(trip.placeIds, ["posebyen", "kunstsilo"])
        XCTAssertEqual(trip.routeGeometry ?? [], routeGeometry)
        XCTAssertEqual(trip.distanceMeters, 1200)
        XCTAssertEqual(trip.durationSeconds, 900)
        XCTAssertEqual(trip.breadcrumb, [])
        XCTAssertEqual(trip.photos, [])
        XCTAssertNil(trip.endedAt)
    }

    func testRenameTrip() {
        let store = makeStore()
        let id = store.startTrip(placeIds: ["posebyen"])
        store.renameTrip(id, name: "Sunday walk")

        XCTAssertEqual(store.trips.first { $0.id == id }?.name, "Sunday walk")
    }

    func testUpdateTripStopsWithoutTouchingBreadcrumbOrPhotos() {
        let store = makeStore()
        let id = store.startTrip(placeIds: ["posebyen"])
        store.addBreadcrumb(id, point: TripWaypoint(lat: 58.1, lng: 7.9, timestamp: 1000))

        let newRoute: [[Double]] = [[58.2, 8.0], [58.21, 8.01]]
        store.updateTripStops(id, placeIds: ["posebyen", "kunstsilo"], route: RouteInfo(routeGeometry: newRoute, distanceMeters: 2000, durationSeconds: 1500))

        let trip = store.trips.first { $0.id == id }
        XCTAssertEqual(trip?.placeIds, ["posebyen", "kunstsilo"])
        XCTAssertEqual(trip?.routeGeometry ?? [], newRoute)
        XCTAssertEqual(trip?.distanceMeters, 2000)
        XCTAssertEqual(trip?.breadcrumb, [TripWaypoint(lat: 58.1, lng: 7.9, timestamp: 1000)])
    }

    func testAppendsBreadcrumbPointsToTheRightTripOnly() {
        let store = makeStore()
        let id = store.startTrip(placeIds: ["posebyen"])
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
        let id = store.startTrip(placeIds: ["posebyen"])
        store.addPhoto(id, photo: TripPhoto(uri: "file:///photo.jpg", timestamp: 5000, lat: nil, lng: nil))

        let trip = store.trips.first { $0.id == id }
        XCTAssertEqual(trip?.photos, [TripPhoto(uri: "file:///photo.jpg", timestamp: 5000, lat: nil, lng: nil)])
    }

    func testEndTripStampsEndedAtAndClearsActiveTripId() {
        let store = makeStore()
        let id = store.startTrip(placeIds: ["posebyen"])
        store.endTrip(id)

        XCTAssertNil(store.activeTripId)
        XCTAssertNotNil(store.trips.first { $0.id == id }?.endedAt)
    }

    func testDeleteTripClearsActiveTripIdIfItWasActive() {
        let store = makeStore()
        let id = store.startTrip(placeIds: ["posebyen"])
        store.deleteTrip(id)

        XCTAssertEqual(store.trips.count, 0)
        XCTAssertNil(store.activeTripId)
    }
}
