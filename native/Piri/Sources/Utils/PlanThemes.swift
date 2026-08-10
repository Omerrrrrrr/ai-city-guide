import MapKit

/// Curated theme chips for `PlanBuilderScreen` — a small, UI-facing picker
/// list (one clear label + icon each), distinct from
/// `POICategoryGroups.inferredCategories`'s much larger free-text keyword
/// map used to infer a theme from an arbitrary chat message. Some category
/// overlap between the two is fine; they solve different problems (a fixed
/// picker vs. guessing intent from open text).
struct PlanTheme: Identifiable, Hashable {
    let labelKey: String
    let icon: String
    let categories: Set<MKPointOfInterestCategory>
    var id: String { labelKey }
}

enum PlanThemes {
    static let all: [PlanTheme] = [
        PlanTheme(labelKey: "planThemes.art", icon: "paintpalette.fill", categories: [.museum, .theater, .musicVenue, .library]),
        PlanTheme(labelKey: "planThemes.history", icon: "building.columns.fill", categories: [.museum, .landmark, .nationalMonument, .castle, .fortress]),
        PlanTheme(labelKey: "planThemes.nature", icon: "leaf.fill", categories: [.park, .nationalPark, .campground, .hiking, .zoo]),
        PlanTheme(labelKey: "planThemes.food", icon: "fork.knife", categories: [.restaurant, .foodMarket, .bakery, .cafe]),
        PlanTheme(labelKey: "planThemes.nightlife", icon: "wineglass.fill", categories: [.nightlife, .musicVenue, .brewery, .winery, .distillery]),
        PlanTheme(labelKey: "planThemes.shopping", icon: "bag.fill", categories: [.store]),
        PlanTheme(labelKey: "planThemes.family", icon: "figure.2.and.child.holdinghands", categories: [.zoo, .aquarium, .amusementPark, .park]),
        PlanTheme(labelKey: "planThemes.views", icon: "sun.horizon.fill", categories: [.landmark, .nationalMonument, .park]),
    ]
}
