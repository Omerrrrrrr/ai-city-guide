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

    /// Turkish/English/Norwegian keyword → category set, so a themed Ask
    /// Piri question ("sanatsal bir deneyim") can bias the candidate search
    /// toward relevant venues instead of "nearest 24 of anything" — a plain
    /// distance browse has no way to know "sanatsal" means museums/theaters,
    /// not restaurants. Substring match against the raw query; returns `nil`
    /// (not an empty set) when nothing matches so callers can tell "no
    /// theme detected" apart from "detected theme has zero categories."
    private static let queryKeywordCategories: [(keywords: [String], categories: Set<MKPointOfInterestCategory>)] = [
        (["sanat", "sanatsal", "galeri", "art", "gallery", "kunst"], [.museum, .theater, .musicVenue, .library]),
        (["tarih", "tarihi", "tarihsel", "history", "historic", "antik", "historisk"], [.museum, .landmark, .nationalMonument, .castle, .fortress]),
        (["müze", "museum", "museer"], [.museum, .planetarium, .aquarium]),
        (["doğa", "doga", "nature", "natur", "yürüyüş", "yuruyus", "hiking"], [.park, .nationalPark, .campground, .hiking, .zoo]),
        (["eğlence", "eglence", "fun", "entertainment", "underholdning"], [.amusementPark, .bowling, .miniGolf, .goKart, .skatePark, .zoo, .aquarium]),
        (["gece hayatı", "gece", "nightlife", "bar", "natteliv"], [.nightlife, .musicVenue, .brewery, .winery, .distillery]),
        (["yemek", "restoran", "food", "dining", "mat", "kafe", "cafe", "coffee", "kaffe"], [.restaurant, .foodMarket, .bakery, .cafe, .brewery, .winery]),
        (["alışveriş", "alisveris", "shopping", "handel"], [.store]),
        (["spor", "sport", "idman", "gym", "fitness"], [.stadium, .fitnessCenter, .golf, .tennis, .soccer, .swimming]),
        (["aile", "family", "familie", "çocuk", "cocuk", "kids"], [.zoo, .aquarium, .amusementPark, .park]),
        (["macera", "adventure", "eventyr"], [.hiking, .rockClimbing, .kayaking, .surfing, .skiing]),
        (["manzara", "view", "utsikt"], [.park, .landmark, .nationalMonument]),
    ]

    static func inferredCategories(fromQuery query: String) -> Set<MKPointOfInterestCategory>? {
        let normalized = query.lowercased()
        var matched: Set<MKPointOfInterestCategory> = []
        for entry in queryKeywordCategories {
            if entry.keywords.contains(where: { normalized.contains($0) }) {
                matched.formUnion(entry.categories)
            }
        }
        return matched.isEmpty ? nil : matched
    }
}
