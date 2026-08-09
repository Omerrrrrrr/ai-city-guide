import CoreLocation
import Observation

/// Port of the location parts of `mobile/app/(tabs)/map.tsx` (GPS breadcrumb
/// via `expo-location`'s `watchPositionAsync`) plus the plain
/// `getCurrentPositionAsync` calls in `use-weather.ts` / `use-places.ts`.
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var currentLocation: CLLocationCoordinate2D?
    private(set) var breadcrumb: [TripWaypoint] = []

    private let manager = CLLocationManager()
    private(set) var isRecordingBreadcrumb = false
    /// Matches the RN app's breadcrumb sampling: a new point roughly every
    /// 20s or 25m of movement, whichever comes first (`map.tsx` `watchPositionAsync`).
    private var lastBreadcrumbAt: Date?
    private var lastBreadcrumbLocation: CLLocation?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    func startBreadcrumbRecording() {
        breadcrumb = []
        lastBreadcrumbAt = nil
        lastBreadcrumbLocation = nil
        isRecordingBreadcrumb = true
    }

    func stopBreadcrumbRecording() {
        isRecordingBreadcrumb = false
    }

    /// Port of `getCurrentLocation` in `mobile/src/utils/location.ts` — a
    /// best-effort, one-shot read used by Scan/AI to tag a request with the
    /// user's coordinates, not a continuous subscription.
    func currentLocationOnce(timeout: Duration = .seconds(3)) async -> CLLocationCoordinate2D? {
        if let currentLocation { return currentLocation }

        requestWhenInUseAuthorization()
        startUpdatingLocation()

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let currentLocation { return currentLocation }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return currentLocation
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate

        guard isRecordingBreadcrumb else { return }

        let now = Date()
        let distance = lastBreadcrumbLocation.map { location.distance(from: $0) } ?? .greatestFiniteMagnitude
        let elapsed = lastBreadcrumbAt.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude

        guard distance >= 25 || elapsed >= 20 else { return }

        lastBreadcrumbAt = now
        lastBreadcrumbLocation = location
        breadcrumb.append(TripWaypoint(lat: location.coordinate.latitude, lng: location.coordinate.longitude, timestamp: now.timeIntervalSince1970 * 1000))
    }
}
