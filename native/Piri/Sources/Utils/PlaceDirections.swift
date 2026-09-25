import MapKit
import UIKit

/// Port of `mobile/src/utils/directions.ts`, adapted to open natively
/// instead of building a Google Maps web URL — the RN app had no native
/// Maps integration to call into, this one does.
///
/// "Open in Maps" now hands off to whichever app the user picked in
/// Settings (`ProfileScreen`'s maps-provider card / `MapsProviderStore`),
/// not always Apple Maps — every call site in the app (`PlaceDetailScreen`,
/// `MapScreen`, `POIExplainSheet`) goes through this one place so they
/// can't drift out of sync with each other.
enum PlaceDirections {
    /// Reads the same `UserDefaults` key `MapsProviderStore` writes to.
    /// A plain read here (not `@Environment(MapsProviderStore.self)`)
    /// because this is a stateless utility called from several unrelated
    /// views, some without easy access to the environment at the call
    /// site — and the choice only ever needs to be read at the moment of
    /// the tap, never observed/reactive.
    private static var preferredProvider: MapsProvider {
        UserDefaults.standard.string(forKey: MapsProviderStore.defaultsKey).flatMap(MapsProvider.init) ?? .apple
    }

    /// Whether "Open in Maps" (with the current preference) stays inside
    /// Piri rather than switching to an external app. Callers presenting
    /// this action from a sheet/pushed screen check this to also call
    /// their own `dismiss()` afterward — switching tabs underneath a
    /// still-presented sheet wouldn't show the user the newly-centered
    /// map until they dismissed it manually anyway.
    static var opensInApp: Bool { preferredProvider == .piri }

    static func openInMaps(_ place: Place, tabSelection: TabSelection) {
        guard let location = place.location else { return }
        openInMaps(name: place.name, coordinate: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng), tabSelection: tabSelection)
    }

    static func canOpenInMaps(_ place: Place) -> Bool {
        place.location != nil
    }

    /// The general entry point — every call site with an `MKMapItem`
    /// (Apple POIs, dietary pins, ...) goes through this instead of
    /// calling `mapItem.openInMaps()` directly, so the provider choice
    /// applies everywhere, not just to Piri's own curated `Place`s.
    /// `tabSelection` is required (not just for `.piri`) so callers can't
    /// forget it and get a silent no-op the one time a user has that
    /// provider selected.
    static func openInMaps(name: String, coordinate: CLLocationCoordinate2D, tabSelection: TabSelection) {
        switch preferredProvider {
        case .piri:
            // Jump to Map, center there, AND hand off a single-stop route
            // request — `pendingRouteStops` is the same hand-off
            // `CollectionDetailScreen`'s "Haritada Rota Oluştur" already
            // uses for a multi-stop plan; MapScreen's existing
            // `startPendingRoute`/`previewRoute` draw the actual route line
            // from the user's current location to this one destination
            // (see `previewRoute`'s own comment on why a single stop is
            // allowed through its guard). A synthetic identifier matches
            // `POIPlace.asReference`'s own fallback convention -- this
            // entry point only ever has a name/coordinate, never a real
            // `MKMapItem` to read `.identifier` from.
            // `selection = 2` is a no-op if already selected, and
            // MapScreen consumes both pending values the same way either
            // way.
            let identifier = "local:\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
            tabSelection.pendingRouteStops = [
                SavedPOIReference(identifier: identifier, name: name, lat: coordinate.latitude, lng: coordinate.longitude)
            ]
            tabSelection.pendingMapFocus = TabSelection.MapFocusRequest(lat: coordinate.latitude, lng: coordinate.longitude)
            tabSelection.selection = 2

        case .apple:
            // `MKLaunchOptionsDirectionsModeKey` is what actually asks Maps
            // for a route from the user's current location to this item --
            // without it, `openInMaps()` just drops a pin and leaves the
            // user to tap "Directions" themselves inside Apple Maps, which
            // read as this button doing nothing.
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            mapItem.name = name
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])

        case .google:
            // `daddr` (destination address) is what triggers turn-by-turn
            // directions from the user's current location -- `q`/`center`
            // (the previous params here) only drop a search pin, same gap
            // as the old bare `openInMaps()` call above.
            // https://developers.google.com/maps/documentation/urls/ios-urlscheme
            // and the api=1 web directions URL (https://developers.google.com/maps/documentation/urls/get-started).
            let query = "\(coordinate.latitude),\(coordinate.longitude)"
            openExternal(
                appURL: URL(string: "comgooglemaps://?daddr=\(query)"),
                webURL: URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(query)")!
            )

        case .yandex:
            // `rtext=~lat,lon` builds a route ending at this point, with the
            // empty segment before `~` telling Yandex to start from the
            // user's current location -- `pt=` (the previous param here)
            // only drops a point marker, same gap as Google's `q=` above.
            // https://yandex.com/dev/mapkit/doc/en/uri/ext/maps.
            let point = "\(coordinate.latitude),\(coordinate.longitude)"
            openExternal(
                appURL: URL(string: "yandexmaps://maps.yandex.ru/?rtext=~\(point)&rtt=auto"),
                webURL: URL(string: "https://yandex.com/maps/?rtext=~\(point)&rtt=auto")!
            )
        }
    }

    /// Opens the app URL if that app is actually installed (`canOpenURL`
    /// needs the scheme declared in `project.yml`'s
    /// `LSApplicationQueriesSchemes`, otherwise it always reports `false`
    /// even when the app is present), falling back to the web URL
    /// otherwise -- so picking Google/Yandex in Settings without having
    /// that app installed still opens *something* usable instead of
    /// silently doing nothing.
    private static func openExternal(appURL: URL?, webURL: URL) {
        if let appURL, UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            UIApplication.shared.open(webURL)
        }
    }
}
