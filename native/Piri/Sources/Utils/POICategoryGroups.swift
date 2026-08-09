import MapKit

/// Groups of Apple's own `MKPointOfInterestCategory` values behind the map's
/// category chips, applied via `MKMapView.pointOfInterestFilter` — this is
/// what makes the *base-map* POI layer (not just Piri's own pins) respond to
/// the same category filtering the rest of the app already has. Apple
/// exposes ~100 fine-grained categories; grouping them keeps the chip row
/// the same rough size as before rather than listing all of them.
struct POICategoryGroup: Identifiable {
    let labelKey: String
    /// `nil` means "no filter" (show every category) — used for the "All" chip.
    let categories: Set<MKPointOfInterestCategory>?
    var id: String { labelKey }
}

enum POICategoryGroups {
    static let all: [POICategoryGroup] = [
        POICategoryGroup(labelKey: "mapPoiCategories.all", categories: nil),
        POICategoryGroup(labelKey: "mapPoiCategories.museums", categories: [.museum]),
        POICategoryGroup(labelKey: "mapPoiCategories.nature", categories: [.park, .nationalPark, .campground]),
        POICategoryGroup(labelKey: "mapPoiCategories.culture", categories: [.theater, .movieTheater]),
        POICategoryGroup(labelKey: "mapPoiCategories.beaches", categories: [.beach, .marina]),
        POICategoryGroup(labelKey: "mapPoiCategories.cafes", categories: [.cafe, .bakery]),
        POICategoryGroup(labelKey: "mapPoiCategories.food", categories: [.restaurant, .brewery, .winery, .foodMarket]),
        POICategoryGroup(labelKey: "mapPoiCategories.shopping", categories: [.store]),
        POICategoryGroup(labelKey: "mapPoiCategories.nightlife", categories: [.nightlife]),
        POICategoryGroup(labelKey: "mapPoiCategories.sports", categories: [.stadium, .fitnessCenter]),
        POICategoryGroup(labelKey: "mapPoiCategories.lodging", categories: [.hotel]),
    ]
}
