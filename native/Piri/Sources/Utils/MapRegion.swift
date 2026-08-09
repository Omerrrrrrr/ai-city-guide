import MapKit

/// Port of `regionForPoints` in `mobile/app/trips.tsx` — a bounding region
/// around a set of points, padded by 1.6x so the polyline isn't flush with
/// the map edges.
func regionForPoints(_ points: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
    guard !points.isEmpty else { return nil }
    let lats = points.map(\.latitude)
    let lngs = points.map(\.longitude)
    guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }

    return MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
        span: MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.6),
            longitudeDelta: max(0.01, (maxLng - minLng) * 1.6)
        )
    )
}
