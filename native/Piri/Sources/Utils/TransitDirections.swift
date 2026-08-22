import CoreLocation
import MapKit

enum TransitDirectionsError: Error {
    /// A real "no transit route exists between these stops" outcome from
    /// MapKit, not an infra failure -- unlike ORS's straight-line fallback
    /// (used when OPENROUTESERVICE_API_KEY is missing or ORS itself is
    /// down), there's nothing honest to draw here, so this is surfaced as
    /// its own error rather than silently faked with a direct line.
    case noRouteFound
}

/// Public transit has no OpenRouteService profile at all (confirmed against
/// their docs), so unlike walking/driving/cycling this never goes through
/// `/routes/directions` -- it's computed entirely on-device via
/// `MKDirections`, free and keyless, the same async MapKit request pattern
/// already used for `MKLookAroundSceneRequest` elsewhere in the app.
/// `MKDirections` only computes one origin→destination leg at a time (ORS's
/// single call handles a whole multi-stop route), so this fetches leg by
/// leg and stitches the results into the same `DirectionsResult` shape ORS
/// returns -- route rendering, `Trip.routeGeometry`, etc. need no knowledge
/// of which source produced it.
enum TransitDirections {
    static func fetchMultiLeg(stops: [PlaceCoordinate]) async throws -> DirectionsResult {
        var routeGeometry: [[Double]] = []
        var totalDistance: Double = 0
        var totalDuration: Double = 0
        var steps: [RouteStep] = []

        for i in 0..<(stops.count - 1) {
            let leg = try await fetchLeg(from: stops[i], to: stops[i + 1])
            routeGeometry += leg.route
            totalDistance += leg.distanceMeters ?? 0
            totalDuration += leg.durationSeconds ?? 0
            steps += leg.steps
        }

        return DirectionsResult(route: routeGeometry, distanceMeters: totalDistance, durationSeconds: totalDuration, steps: steps)
    }

    private static func fetchLeg(from: PlaceCoordinate, to: PlaceCoordinate) async throws -> DirectionsResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: from.lat, longitude: from.lng)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: to.lat, longitude: to.lng)))
        request.transportType = .transit

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw TransitDirectionsError.noRouteFound }

        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: route.polyline.pointCount)
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: route.polyline.pointCount))

        let steps = route.steps
            .filter { !$0.instructions.isEmpty }
            .map { RouteStep(instruction: $0.instructions, distanceMeters: $0.distance) }

        return DirectionsResult(
            route: coordinates.map { [$0.latitude, $0.longitude] },
            distanceMeters: route.distance,
            durationSeconds: route.expectedTravelTime,
            steps: steps
        )
    }
}
