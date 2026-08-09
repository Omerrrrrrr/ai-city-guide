import CoreLocation
import MapKit

/// Durable, Codable snapshot of an Apple MapKit POI — replaces bare curated
/// `Place` id strings everywhere a place gets persisted (favorites, plan,
/// recently viewed, trip stops), now that there's no curated database to
/// re-fetch from. The snapshot fields (name/category/coordinate/address) let
/// list rows render immediately with no async call; `identifier` is
/// `MKMapItem.Identifier.rawValue`, used to resolve back to a live
/// `MKMapItem` (for Look Around / Open in Maps / follow-up chat) only when
/// the user actually opens the detail sheet.
struct SavedPOIReference: Codable, Identifiable, Hashable {
    var identifier: String
    var name: String
    var categoryRawValue: String?
    var lat: Double
    var lng: Double
    var address: String?

    var id: String { identifier }

    var category: MKPointOfInterestCategory? {
        categoryRawValue.map { MKPointOfInterestCategory(rawValue: $0) }
    }
}

extension POIPlace {
    /// Never `nil` — `mapItem.identifier` is reported to be missing on some
    /// real devices/search results (confirmed via research), and gating
    /// favoriting/route-stop-picking on its presence made those features
    /// silently do nothing whenever it was absent (live-observed: Route Mode
    /// stop-tapping appeared completely broken). A synthetic fallback
    /// identifier (never mistakable for a real Apple one, which look like
    /// "I63802885C8189B2B") keeps the reference — and therefore the
    /// favorite/stop itself — always capturable. Only `resolve()` (reopening
    /// the live detail sheet later) degrades gracefully when it's synthetic.
    var asReference: SavedPOIReference {
        let identifier = mapItem.identifier?.rawValue
            ?? "local:\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
        return SavedPOIReference(
            identifier: identifier,
            name: name,
            categoryRawValue: category?.rawValue,
            lat: coordinate.latitude,
            lng: coordinate.longitude,
            address: mapItem.placemark.title
        )
    }
}

extension SavedPOIReference {
    /// Re-fetches the live `MKMapItem` for this reference. Returns `nil`
    /// (never throws) if the identifier no longer resolves — same
    /// silent-degrade contract as `POISearchService.search`.
    func resolve() async -> POIPlace? {
        guard let id = MKMapItem.Identifier(rawValue: identifier),
              let mapItem = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem else { return nil }
        return POIPlace(
            name: mapItem.name ?? name,
            category: mapItem.pointOfInterestCategory,
            coordinate: mapItem.placemark.coordinate,
            mapItem: mapItem
        )
    }
}
