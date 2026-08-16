import MapKit
import SwiftUI

private final class RoutePolyline: MKPolyline {}
private final class BreadcrumbPolyline: MKPolyline {}

private final class StopAnnotation: NSObject, MKAnnotation {
    let index: Int
    let coordinate: CLLocationCoordinate2D
    init(index: Int, coordinate: CLLocationCoordinate2D) {
        self.index = index
        self.coordinate = coordinate
    }
}

private final class PlaybackAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

/// Port of the `MapView` in `mobile/app/trip/[id].tsx`: planned route
/// (gold) + GPS breadcrumb (navy) polylines, numbered stop pins, and an
/// animated playback marker.
struct TripMapView: UIViewRepresentable {
    var routeCoordinates: [CLLocationCoordinate2D]
    var breadcrumbCoordinates: [CLLocationCoordinate2D]
    var stops: [(index: Int, coordinate: CLLocationCoordinate2D)]
    var playbackPosition: CLLocationCoordinate2D?
    var initialRegion: MKCoordinateRegion?
    /// Off by default to preserve `TripDetailScreen`'s read-only playback use;
    /// `MapScreen`'s live route-tracking mode turns this on so the user can
    /// see their own position alongside the growing breadcrumb.
    var showsUserLocation: Bool = false
    /// Defaulted, not required — `TripDetailScreen`'s read-only playback use
    /// doesn't have (or need) a map-style picker of its own. `MapScreen`'s
    /// live route-tracking mode passes its own `mapType` through so the
    /// Standard/Hybrid/Satellite picker still has an effect once a trip is
    /// active and this view (not `PiriMapView`) is what's on screen — it
    /// used to be silently ignored here, so switching styles mid-trip did
    /// nothing.
    var mapType: MKMapType = .standard

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        mapView.mapType = mapType
        if let initialRegion {
            mapView.setRegion(initialRegion, animated: false)
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }
        mapView.removeOverlays(mapView.overlays)
        if routeCoordinates.count > 1 {
            mapView.addOverlay(RoutePolyline(coordinates: routeCoordinates, count: routeCoordinates.count))
        }
        if breadcrumbCoordinates.count > 1 {
            mapView.addOverlay(BreadcrumbPolyline(coordinates: breadcrumbCoordinates, count: breadcrumbCoordinates.count))
        }

        let existingStops = mapView.annotations.compactMap { $0 as? StopAnnotation }
        mapView.removeAnnotations(existingStops)
        mapView.addAnnotations(stops.map { StopAnnotation(index: $0.index, coordinate: $0.coordinate) })

        let existingPlayback = mapView.annotations.compactMap { $0 as? PlaybackAnnotation }
        if let playbackPosition {
            if let annotation = existingPlayback.first {
                annotation.coordinate = playbackPosition
                mapView.view(for: annotation)?.setNeedsLayout()
            } else {
                mapView.addAnnotation(PlaybackAnnotation(coordinate: playbackPosition))
            }
        } else {
            mapView.removeAnnotations(existingPlayback)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let stop = annotation as? StopAnnotation {
                let identifier = "stop"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: stop, reuseIdentifier: identifier)
                view.annotation = stop
                view.markerTintColor = UIColor(Theme.gold)
                view.glyphText = "\(stop.index + 1)"
                return view
            }
            if let playback = annotation as? PlaybackAnnotation {
                let identifier = "playback"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKAnnotationView
                    ?? MKAnnotationView(annotation: playback, reuseIdentifier: identifier)
                view.annotation = playback
                view.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
                view.backgroundColor = .systemRed
                view.layer.cornerRadius = 8
                view.layer.borderWidth = 2
                view.layer.borderColor = UIColor.white.cgColor
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let route = overlay as? RoutePolyline {
                let renderer = MKPolylineRenderer(polyline: route)
                renderer.strokeColor = UIColor(Theme.gold)
                renderer.lineWidth = 4
                return renderer
            }
            if let breadcrumb = overlay as? BreadcrumbPolyline {
                let renderer = MKPolylineRenderer(polyline: breadcrumb)
                renderer.strokeColor = UIColor(Theme.navy)
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
