import Foundation
import Observation

/// Lets any screen jump to another tab (e.g. the weather banner and AI
/// banner on Home both push to Ask Piri), mirroring `router.push('/ai')`
/// cross-route navigation in the RN app — SwiftUI's `TabView` has no
/// built-in equivalent, so this is shared via the environment instead.
@Observable
final class TabSelection {
    var selection = 0
    /// Set alongside `selection = 3` when a screen wants Ask Piri to open
    /// pre-filled and auto-submitted — mirrors `router.push('/ai', {q})`
    /// carrying a query string across the RN app's route-based navigation,
    /// which a `TabView` switch has no equivalent for on its own. `AIScreen`
    /// consumes and clears this on appearance.
    var pendingAIQuery: String?
    /// Set alongside `selection = 2` when a screen (SavedScreen's "Haritada
    /// Rota Oluştur") wants Map to start Route Mode with these stops already
    /// planned and a real route already fetched. Same cross-tab hand-off
    /// pattern as `pendingAIQuery` — `MapScreen` consumes and clears this.
    var pendingRouteStops: [SavedPOIReference]?
    /// Set alongside `selection = 2` when a screen wants Map to jump to and
    /// center on a single coordinate — the "Piri Haritası" maps-provider
    /// option's hand-off (see `MapsProvider`/`PlaceDirections`), distinct
    /// from `pendingRouteStops`' multi-stop route hand-off. `trigger` is a
    /// fresh `UUID` every time so re-focusing the same coordinate twice in
    /// a row (e.g. two taps on the same POI from Home) still re-fires —
    /// same reasoning as `PiriMapView`'s own `recenterTrigger`.
    struct MapFocusRequest: Equatable {
        var lat: Double
        var lng: Double
        var trigger = UUID()
    }
    var pendingMapFocus: MapFocusRequest?
}
