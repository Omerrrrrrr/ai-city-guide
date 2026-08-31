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

/// Public transit routing, tried in two layers:
///
/// 1. `/routes/directions` with `profile: .transit` -- the backend calls
///    Transitous (transitous.ts), a free/keyless service aggregating GTFS
///    feeds from 60+ countries into one API. Picked over a national transit
///    API (e.g. Norway's Entur) specifically to avoid one bespoke
///    integration per country -- confirmed live that Apple's own transit
///    coverage in Norway is capital-cities-only (Oslo/Bergen), leaving
///    Kristiansand (this app's own dev/test city) with no Apple transit
///    data at all, which is what made this gap visible in the first place.
/// 2. On-device `MKDirections` with `.transportType = .transit`, leg by leg
///    -- kept as a fallback for wherever Transitous's crowd-sourced feed
///    coverage is thinner than Apple's own (the two don't necessarily
///    overlap), and for offline resilience if the backend call fails for
///    an unrelated reason (network, backend down).
///
/// Both return the same `DirectionsResult` shape ORS's walking/driving/
/// cycling profiles already do -- route rendering, `Trip.routeGeometry`,
/// etc. need no knowledge of which of the three sources produced it.
enum TransitDirections {
    static func fetchMultiLeg(stops: [PlaceCoordinate]) async throws -> DirectionsResult {
        if let result = try? await RoutesAPI.directions(coordinates: stops, profile: .transit) {
            return result
        }
        return try await fetchMultiLegOnDevice(stops: stops)
    }

    private static func fetchMultiLegOnDevice(stops: [PlaceCoordinate]) async throws -> DirectionsResult {
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

        // `calculate()` itself throws (rather than returning an empty
        // `routes` array) whenever Apple simply has no transit data for the
        // region at all -- confirmed live: a ferry-only route (Kristiansand
        // to a small island) surfaced the generic "Rota hesaplanamadı.
        // Bağlantını kontrol et." (misleadingly implying a network problem)
        // instead of the accurate, already-written `map.route.transitFailed`
        // copy, because this threw before ever reaching the empty-`routes`
        // check below. Every failure from `calculate()` under `.transit`
        // means the same thing in practice -- no real connectivity check is
        // possible here, so there's no lost information in normalizing it.
        let response: MKDirections.Response
        do {
            response = try await MKDirections(request: request).calculate()
        } catch {
            throw TransitDirectionsError.noRouteFound
        }
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
