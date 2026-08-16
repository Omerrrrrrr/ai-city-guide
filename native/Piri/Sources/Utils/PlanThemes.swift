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
        // Same 4 category groups the Map screen's own chips already cover
        // (POICategoryGroups.all) that had no equivalent theme here yet —
        // confirmed live: someone who wants a worship-site, beach, sports,
        // or amusement-park-heavy day had no chip that matched. Reusing
        // those chips' own labelKey/icon rather than duplicating new ones.
        PlanTheme(labelKey: "mapPoiCategories.worship", icon: "building.2.fill", categories: [.religiousSite]),
        PlanTheme(labelKey: "mapPoiCategories.beaches", icon: "beach.umbrella.fill", categories: [.beach, .marina, .surfing, .kayaking]),
        PlanTheme(labelKey: "mapPoiCategories.sports", icon: "sportscourt.fill", categories: [.stadium, .fitnessCenter, .golf, .tennis, .soccer, .swimming]),
        PlanTheme(labelKey: "mapPoiCategories.activities", icon: "gamecontroller.fill", categories: [.amusementPark, .bowling, .miniGolf, .goKart, .skatePark, .rockClimbing, .skiing]),
    ]
}
