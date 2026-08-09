import MapKit
import SwiftUI

/// UIViewRepresentable wrapping MKMapView, replacing `react-native-maps` in
/// `mobile/app/(tabs)/map.tsx`. Unlike that library — which predates Fabric
/// and forced the RN app into legacy-interop workarounds (manual-tap-only
/// refresh, hard server-side pin caps, custom-View markers because plain
/// pins dropped `onPress`) — MKMapView clusters and re-renders large,
/// frequently-changing annotation sets natively, so none of those
/// workarounds are needed here: annotations update on every region change.
struct PiriMapView: UIViewRepresentable {
    var places: [Place]
    var livePins: [LivePin]
    var routeCoordinates: [CLLocationCoordinate2D]
    var showsUserLocation: Bool
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onSelectPlace: (Place) -> Void
    var onSelectLivePin: (LivePin) -> Void
    /// Apple's own base-map points of interest (restaurants, shops,
    /// landmarks baked into the map tiles themselves) — not our data at
    /// all, but the user still expects every pin on the map to respond to a
    /// tap, not just Piri's own annotations.
    var onSelectMapFeature: (MKMapFeatureAnnotation) -> Void
    /// `nil` shows every Apple POI category; a non-nil set restricts the
    /// *base-map* POI layer to just those categories, tied to the same
    /// category chips that filter Piri's own pins.
    var pointOfInterestCategories: Set<MKPointOfInterestCategory>?
    /// Route-mode stop picking (`MapScreen`) tints a place pin gold once it's
    /// been tapped in as a stop, instead of opening its place card — `nil`/
    /// empty everywhere else, where every place pin stays plain blue.
    var selectedPlaceIds: Set<String> = []
    /// Set once (e.g. on first appearance / "locate me" tap) rather than bound
    /// continuously, so it doesn't fight the user's own pan/zoom gestures.
    var centerOnce: MKCoordinateRegion?
    /// Bump this (e.g. to a fresh `UUID()`) alongside a new `centerOnce`
    /// value to force a re-center after the initial load too — e.g. jumping
    /// to a search result. Without a distinct trigger, a second `centerOnce`
    /// with the same or a new region would otherwise never re-fire once the
    /// initial center-on-load has already happened.
    var recenterTrigger: UUID? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        // Makes Apple's own base-map POI icons (grocery stores, restaurants,
        // landmarks — anything rendered by the map tiles rather than one of
        // our own annotations) individually selectable, delivered to the
        // delegate as `MKMapFeatureAnnotation` in `didSelect`.
        mapView.selectableMapFeatures = .pointsOfInterest
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MapAnnotationReuseID.place)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MapAnnotationReuseID.livePin)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        if let centerOnce {
            mapView.setRegion(centerOnce, animated: false)
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        reconcileAnnotations(on: mapView)
        reconcileRoute(on: mapView, coordinator: context.coordinator)
        reconcileSelection(on: mapView, coordinator: context.coordinator)

        // Re-assigning `pointOfInterestFilter` forces MapKit to reload the
        // base-map POI tile layer, which is expensive now that it can render
        // every one of Apple's POI categories — SwiftUI calls `updateUIView`
        // on every state change (e.g. the AI-explain loading spinner), so
        // without this guard the filter was being reapplied dozens of times
        // a minute even though it hadn't changed, causing visible map lag.
        if !context.coordinator.didApplyPOIFilter || context.coordinator.lastPOICategories != pointOfInterestCategories {
            if let pointOfInterestCategories {
                mapView.pointOfInterestFilter = MKPointOfInterestFilter(including: Array(pointOfInterestCategories))
            } else {
                mapView.pointOfInterestFilter = .includingAll
            }
            context.coordinator.lastPOICategories = pointOfInterestCategories
            context.coordinator.didApplyPOIFilter = true
        }

        if let centerOnce, context.coordinator.lastCenteredRegion == nil || context.coordinator.lastRecenterTrigger != recenterTrigger {
            mapView.setRegion(centerOnce, animated: true)
            context.coordinator.lastCenteredRegion = centerOnce
            context.coordinator.lastRecenterTrigger = recenterTrigger
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func reconcileAnnotations(on mapView: MKMapView) {
        let existingPlace = mapView.annotations.compactMap { $0 as? PlaceAnnotation }
        let existingLivePin = mapView.annotations.compactMap { $0 as? LivePinAnnotation }

        let currentPlaceIds = Set(existingPlace.map(\.place.id))
        let targetPlaceIds = Set(places.map(\.id))
        let currentLiveIds = Set(existingLivePin.map(\.livePin.id))
        let targetLiveIds = Set(livePins.map(\.id))

        guard currentPlaceIds != targetPlaceIds || currentLiveIds != targetLiveIds else { return }

        let toRemovePlace = existingPlace.filter { !targetPlaceIds.contains($0.place.id) }
        let toRemoveLive = existingLivePin.filter { !targetLiveIds.contains($0.livePin.id) }
        mapView.removeAnnotations(toRemovePlace)
        mapView.removeAnnotations(toRemoveLive)

        let toAddPlace = places
            .filter { $0.location != nil && !currentPlaceIds.contains($0.id) }
            .map(PlaceAnnotation.init)
        let toAddLive = livePins
            .filter { !currentLiveIds.contains($0.id) }
            .map(LivePinAnnotation.init)
        mapView.addAnnotations(toAddPlace)
        mapView.addAnnotations(toAddLive)
    }

    /// Tints already-placed place pins gold/blue in place, without touching
    /// annotation identity — `reconcileAnnotations` only diffs by id set, so
    /// toggling a stop (same places, different selection) wouldn't otherwise
    /// re-run `viewFor` at all.
    private func reconcileSelection(on mapView: MKMapView, coordinator: Coordinator) {
        guard coordinator.lastSelectedPlaceIds != selectedPlaceIds else { return }
        coordinator.lastSelectedPlaceIds = selectedPlaceIds
        for annotation in mapView.annotations {
            guard let placeAnnotation = annotation as? PlaceAnnotation,
                  let view = mapView.view(for: placeAnnotation) as? MKMarkerAnnotationView else { continue }
            view.markerTintColor = selectedPlaceIds.contains(placeAnnotation.place.id) ? UIColor(Theme.gold) : .systemBlue
        }
    }

    private func reconcileRoute(on mapView: MKMapView, coordinator: Coordinator) {
        guard coordinator.lastRouteCoordinates.map(\.latitude) != routeCoordinates.map(\.latitude)
            || coordinator.lastRouteCoordinates.map(\.longitude) != routeCoordinates.map(\.longitude) else { return }
        coordinator.lastRouteCoordinates = routeCoordinates
        mapView.removeOverlays(mapView.overlays)
        guard routeCoordinates.count > 1 else { return }
        mapView.addOverlay(MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count))
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: PiriMapView
        var lastCenteredRegion: MKCoordinateRegion?
        var lastRecenterTrigger: UUID?
        var lastPOICategories: Set<MKPointOfInterestCategory>?
        var didApplyPOIFilter = false
        var lastRouteCoordinates: [CLLocationCoordinate2D] = []
        var lastSelectedPlaceIds: Set<String> = []

        init(parent: PiriMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster) as? MKMarkerAnnotationView
                view?.markerTintColor = .systemBlue
                return view
            }

            if let placeAnnotation = annotation as? PlaceAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MapAnnotationReuseID.place, for: placeAnnotation) as? MKMarkerAnnotationView
                view?.clusteringIdentifier = MapAnnotationReuseID.place
                view?.markerTintColor = parent.selectedPlaceIds.contains(placeAnnotation.place.id) ? UIColor(Theme.gold) : .systemBlue
                view?.canShowCallout = true
                return view
            }

            if let liveAnnotation = annotation as? LivePinAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MapAnnotationReuseID.livePin, for: liveAnnotation) as? MKMarkerAnnotationView
                view?.clusteringIdentifier = MapAnnotationReuseID.livePin
                view?.markerTintColor = .systemGray
                view?.canShowCallout = true
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let placeAnnotation = annotation as? PlaceAnnotation {
                parent.onSelectPlace(placeAnnotation.place)
            } else if let liveAnnotation = annotation as? LivePinAnnotation {
                parent.onSelectLivePin(liveAnnotation.livePin)
            } else if let cluster = annotation as? MKClusterAnnotation {
                // Tapping a cluster badge did nothing before this — MapKit
                // doesn't auto-expand clusters on tap, so every clustered pin
                // (i.e. most pins, at anything but full street-level zoom)
                // was effectively untappable. Zoom into the cluster's own
                // member region instead, same as Apple Maps' POI clusters.
                if let region = regionForPoints(cluster.memberAnnotations.map(\.coordinate)) {
                    mapView.setRegion(region, animated: true)
                }
            } else if let feature = annotation as? MKMapFeatureAnnotation {
                parent.onSelectMapFeature(feature)
            }

            // Let every tap re-fire `didSelect`, even on the same annotation
            // twice in a row (e.g. after the place/live-pin card was
            // dismissed) — MapKit otherwise only calls this once until the
            // annotation is deselected.
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 4
            return renderer
        }
    }
}
