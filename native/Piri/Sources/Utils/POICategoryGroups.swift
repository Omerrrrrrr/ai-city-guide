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
    let icon: String
    var id: String { labelKey }
}

enum POICategoryGroups {
    static let all: [POICategoryGroup] = [
        POICategoryGroup(labelKey: "mapPoiCategories.all", categories: nil, icon: "mappin.circle.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.museums", categories: [.museum], icon: "building.columns.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.nature", categories: [.park, .nationalPark, .campground], icon: "leaf.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.culture", categories: [.theater, .movieTheater], icon: "theatermasks.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.beaches", categories: [.beach, .marina], icon: "beach.umbrella.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.cafes", categories: [.cafe, .bakery], icon: "cup.and.saucer.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.food", categories: [.restaurant, .brewery, .winery, .foodMarket], icon: "fork.knife"),
        POICategoryGroup(labelKey: "mapPoiCategories.shopping", categories: [.store], icon: "bag.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.nightlife", categories: [.nightlife], icon: "wineglass.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.sports", categories: [.stadium, .fitnessCenter], icon: "sportscourt.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.lodging", categories: [.hotel], icon: "bed.double.fill"),
    ]

    /// Falls back to the generic pin icon for any Apple category not covered
    /// by one of the groups above (Apple exposes ~100 fine-grained
    /// categories; the groups only cover the ones meaningfully distinct for
    /// this app's UI).
    static func icon(for category: MKPointOfInterestCategory?) -> String {
        guard let category else { return "mappin.circle.fill" }
        return all.first { $0.categories?.contains(category) == true }?.icon ?? "mappin.circle.fill"
    }
}
