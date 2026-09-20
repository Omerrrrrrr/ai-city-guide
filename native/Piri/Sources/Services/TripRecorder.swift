import CoreLocation
import Foundation
import Observation

/// Owns live trip recording for the whole app. Before this existed, the GPS
/// breadcrumb was recorded by (and only by) `MapScreen`'s own
/// `LocationManager`, so a trip could only be started or ended from Map >
/// Route Mode. Now Home can start a trip with no planned stops ("Geziye
/// Başla") and end it ("Geziyi Sonlandır"), and Map is just another view of
/// the same trip -- both go through here, so there is exactly one recorder
/// writing breadcrumb points into `TripsStore`.
///
/// Ending a trip also produces the `PendingTripRecap` that
/// `MainTabView` presents as `TripRecapView` (the exported recap video), so
/// the video is made the same way no matter which screen ended the trip.
@Observable
@MainActor
final class TripRecorder {
    /// Dedicated to recording -- deliberately not shared with any screen's
    /// own `LocationManager`, so a screen going away can never stop a trip.
    let locationManager = LocationManager()

    /// Set right after a trip ends; `MainTabView` presents the recap for it
    /// and clears it on dismiss.
    var pendingRecap: PendingTripRecap?

    var isRecording: Bool { locationManager.isRecordingBreadcrumb }

    /// Starts a trip with no planned stops. Returns false (and does
    /// nothing) if a trip is already in progress.
    @discardableResult
    func startFreeTrip(tripsStore: TripsStore) -> Bool {
        guard tripsStore.activeTrip == nil else { return false }
        tripsStore.startTrip(stops: [])
        beginRecording(tripsStore: tripsStore)
        return true
    }

    /// Idempotent -- safe to call again for a trip that's already being
    /// recorded (e.g. Map re-hydrating a trip Home started).
    func beginRecording(tripsStore: TripsStore) {
        guard !locationManager.isRecordingBreadcrumb else { return }
        locationManager.onBreadcrumbPoint = { [weak tripsStore] point in
            guard let tripsStore, let id = tripsStore.activeTripId else { return }
            tripsStore.addBreadcrumb(id, point: point)
        }
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startBreadcrumbRecording()
    }

    /// Picks recording back up for a trip that was still active when the
    /// app was last closed -- `TripsStore` persists `activeTripId`, but
    /// the GPS recording itself doesn't survive a relaunch.
    func resumeIfNeeded(tripsStore: TripsStore) {
        guard tripsStore.activeTrip != nil, !isRecording else { return }
        beginRecording(tripsStore: tripsStore)
    }

    func stopRecording() {
        locationManager.stopBreadcrumbRecording()
        locationManager.onBreadcrumbPoint = nil
    }

    /// Ends the active trip, stops recording, and queues the recap. XP is
    /// derived fresh from current counts, not logged (see Gamification.swift)
    /// -- the only way to know what THIS trip was worth is to snapshot
    /// immediately before and after the one thing that changes,
    /// completedTripCount.
    func finishActiveTrip(
        tripsStore: TripsStore,
        userProfileStore: UserProfileStore,
        savedPlacesStore: SavedPlacesStore,
        recentlyViewedStore: RecentlyViewedStore,
        myReviewsStore: MyReviewsStore
    ) {
        defer { stopRecording() }
        guard let activeTripId = tripsStore.activeTripId else { return }

        addClosingPoint(to: activeTripId, tripsStore: tripsStore)

        let profile = userProfileStore.profile
        let savedPlaceCount = savedPlacesStore.collections.reduce(0) { $0 + $1.places.count }
        let completedBefore = tripsStore.trips.filter { $0.endedAt != nil }.count
        let visitedCount = recentlyViewedStore.viewed.count
        let reviewCount = myReviewsStore.count
        let xpBefore = Gamification.xp(profile: profile, savedPlaceCount: savedPlaceCount, completedTripCount: completedBefore, visitedCount: visitedCount, reviewCount: reviewCount)

        tripsStore.endTrip(activeTripId)

        let completedAfter = tripsStore.trips.filter { $0.endedAt != nil }.count
        let xpAfter = Gamification.xp(profile: profile, savedPlaceCount: savedPlaceCount, completedTripCount: completedAfter, visitedCount: visitedCount, reviewCount: reviewCount)

        // Snapshot after endTrip() so distanceMeters/durationSeconds and
        // endedAt are already final -- endTrip() keeps the trip in
        // tripsStore.trips (just clears activeTripId), it doesn't delete it.
        if let endedTrip = tripsStore.trips.first(where: { $0.id == activeTripId }) {
            pendingRecap = PendingTripRecap(
                trip: endedTrip,
                xpBefore: xpBefore,
                xpAfter: xpAfter,
                levelBefore: Gamification.level(forXP: xpBefore),
                levelAfter: Gamification.level(forXP: xpAfter),
                myLifetimeTripCount: completedAfter
            )
        }
    }

    /// The recap video needs at least two route points, and breadcrumb only
    /// samples every ~20s/25m -- a short trip could otherwise end with one
    /// point (or none) and fail to render. Records where the user is right
    /// now as the trip's last point.
    private func addClosingPoint(to tripId: String, tripsStore: TripsStore) {
        guard let current = locationManager.currentLocation,
              let trip = tripsStore.trips.first(where: { $0.id == tripId }) else { return }
        if let last = trip.breadcrumb.last {
            let moved = CLLocation(latitude: last.lat, longitude: last.lng)
                .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            guard moved >= 5 else { return }
        }
        tripsStore.addBreadcrumb(tripId, point: TripWaypoint(
            lat: current.latitude,
            lng: current.longitude,
            timestamp: Date().timeIntervalSince1970 * 1000
        ))
    }
}
