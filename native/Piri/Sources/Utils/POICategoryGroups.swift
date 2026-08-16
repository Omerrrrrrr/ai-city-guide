import MapKit
import SwiftUI

extension MKPointOfInterestCategory {
    /// Missing from the public SDK header (`MKPointOfInterestCategory.h`
    /// only goes up to what Apple's documented as of this SDK) despite
    /// being a real, live category MKLocalSearch actually returns —
    /// confirmed live, Kristiansand's own cathedral came back tagged
    /// exactly `MKPOICategoryReligiousSite`. Safe to construct from the raw
    /// string Apple's own API already uses: this type is just a string
    /// wrapper (`NS_TYPED_ENUM`), not a closed Swift enum, so an
    /// unrecognized-by-the-header value still round-trips correctly.
    static let religiousSite = MKPointOfInterestCategory(rawValue: "MKPOICategoryReligiousSite")
}

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
        // Nothing above covered `.religiousSite`/`.landmark`/etc at all
        // before this group existed -- confirmed live, Kristiansand's own
        // cathedral (`.religiousSite`) had no chip that could ever surface
        // it, on top of Apple's plain nearby-browse already burying it below
        // the ~25-result cap (see `AIScreen.coreSightCategories`).
        POICategoryGroup(labelKey: "mapPoiCategories.landmarks", categories: [.landmark, .nationalMonument, .castle, .fortress, .library], icon: "star.circle.fill"),
        // Split out from the landmarks group -- lumped in with castles and
        // monuments, a mosque/church/synagogue/temple had no chip of its
        // own even though it's a distinct, common thing someone wants to
        // find (see the 2026-08 conversation on faith-relevant features).
        // Apple's single `.religiousSite` category doesn't distinguish which
        // religion a given place belongs to, so this can't be split further
        // than "places of worship" as one group.
        POICategoryGroup(labelKey: "mapPoiCategories.worship", categories: [.religiousSite], icon: "building.2.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.nature", categories: [.park, .nationalPark, .campground, .hiking, .zoo], icon: "leaf.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.culture", categories: [.theater, .movieTheater, .musicVenue, .planetarium, .aquarium], icon: "theatermasks.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.beaches", categories: [.beach, .marina, .surfing, .kayaking], icon: "beach.umbrella.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.cafes", categories: [.cafe, .bakery], icon: "cup.and.saucer.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.food", categories: [.restaurant, .brewery, .winery, .foodMarket, .distillery], icon: "fork.knife"),
        POICategoryGroup(labelKey: "mapPoiCategories.shopping", categories: [.store], icon: "bag.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.nightlife", categories: [.nightlife], icon: "wineglass.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.sports", categories: [.stadium, .fitnessCenter, .golf, .tennis, .soccer, .swimming], icon: "sportscourt.fill"),
        POICategoryGroup(labelKey: "mapPoiCategories.lodging", categories: [.hotel], icon: "bed.double.fill"),
        // The remaining categories referenced by `queryKeywordCategories`
        // below (amusement parks, adventure sports, etc.) previously had no
        // chip at all -- confirmed no visible way to filter the map down to
        // them even though an Ask Piri query like "eğlence" already knew to
        // search for them.
        POICategoryGroup(labelKey: "mapPoiCategories.activities", categories: [.amusementPark, .bowling, .miniGolf, .goKart, .skatePark, .rockClimbing, .skiing], icon: "gamecontroller.fill"),
    ]

    /// Falls back to the generic pin icon for any Apple category not covered
    /// by one of the groups above (Apple exposes ~100 fine-grained
    /// categories; the groups only cover the ones meaningfully distinct for
    /// this app's UI).
    static func icon(for category: MKPointOfInterestCategory?) -> String {
        guard let category else { return "mappin.circle.fill" }
        return all.first { $0.categories?.contains(category) == true }?.icon ?? "mappin.circle.fill"
    }

    /// Deterministic per-category gradient, not a flat grey fill — the
    /// pragmatic middle ground when there's no real photo: no image-
    /// generation tool available here to produce actual per-category
    /// illustrations (the visual-identity report's Finding B), so this is
    /// the code-only version of the same idea — generated once per
    /// *category*, not per place, and never dressed up to look like a real
    /// photo of anything specific.
    static func gradient(for category: MKPointOfInterestCategory?) -> LinearGradient {
        let colors: [Color]
        switch category {
        case .museum, .landmark, .nationalMonument, .castle, .fortress, .library:
            colors = [Color(red: 0.55, green: 0.42, blue: 0.20), Color(red: 0.82, green: 0.68, blue: 0.38)]
        case .religiousSite:
            colors = [Color(red: 0.32, green: 0.28, blue: 0.48), Color(red: 0.58, green: 0.52, blue: 0.76)]
        case .park, .nationalPark, .campground, .hiking, .zoo:
            colors = [Color(red: 0.14, green: 0.36, blue: 0.24), Color(red: 0.38, green: 0.58, blue: 0.36)]
        case .theater, .movieTheater, .musicVenue, .planetarium, .aquarium:
            colors = [Color(red: 0.38, green: 0.16, blue: 0.42), Color(red: 0.62, green: 0.32, blue: 0.58)]
        case .beach, .marina, .surfing, .kayaking:
            colors = [Color(red: 0.09, green: 0.36, blue: 0.48), Color(red: 0.32, green: 0.66, blue: 0.72)]
        case .cafe, .bakery:
            colors = [Color(red: 0.42, green: 0.28, blue: 0.16), Color(red: 0.68, green: 0.48, blue: 0.30)]
        case .restaurant, .brewery, .winery, .foodMarket, .distillery:
            colors = [Color(red: 0.55, green: 0.22, blue: 0.16), Color(red: 0.82, green: 0.44, blue: 0.24)]
        case .store:
            colors = [Color(red: 0.16, green: 0.30, blue: 0.46), Color(red: 0.34, green: 0.52, blue: 0.68)]
        case .nightlife:
            colors = [Color(red: 0.24, green: 0.14, blue: 0.42), Color(red: 0.46, green: 0.28, blue: 0.68)]
        case .stadium, .fitnessCenter, .golf, .tennis, .soccer, .swimming:
            colors = [Color(red: 0.10, green: 0.40, blue: 0.34), Color(red: 0.28, green: 0.62, blue: 0.50)]
        case .hotel:
            colors = [Color(red: 0.17, green: 0.20, blue: 0.36), Color(red: 0.32, green: 0.36, blue: 0.56)]
        case .amusementPark, .bowling, .miniGolf, .goKart, .skatePark, .rockClimbing, .skiing:
            colors = [Color(red: 0.55, green: 0.12, blue: 0.32), Color(red: 0.85, green: 0.32, blue: 0.52)]
        default:
            colors = [Color(red: 0.30, green: 0.30, blue: 0.34), Color(red: 0.52, green: 0.52, blue: 0.56)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
        (["tarih", "tarihi", "tarihsel", "history", "historic", "antik", "historisk"], [.museum, .landmark, .nationalMonument, .castle, .fortress, .religiousSite]),
        (["kilise", "katedral", "cami", "sinagog", "tapınak", "tapinak", "church", "cathedral", "mosque", "synagogue", "temple", "kirke", "domkirke"], [.religiousSite]),
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

    /// Excluded from the default, no-filter "Tümü" browse — real Apple POI
    /// categories, just not what anyone opens a *travel guide* to find:
    /// fuel/parking/EV charging, banks/ATMs, pharmacies, hospitals,
    /// schools/universities, civic/emergency services, and plain grocery
    /// stores. Confirmed live: Kristiansand's unfiltered "Yakınında" browse
    /// surfaced a gas station, two supermarkets, and a school ahead of any
    /// actual sight. Never applied to an explicit category chip (a
    /// grocery-store chip, if one ever existed, should still show
    /// groceries) or to a text search (typing "eczane" should still find a
    /// pharmacy) — only to the ambient "show me what's around" browse.
    static let nonTouristyCategories: Set<MKPointOfInterestCategory> = [
        .animalService, .airport, .atm, .automotiveRepair, .bank, .carRental,
        .evCharger, .fireStation, .foodMarket, .gasStation, .hospital,
        .laundry, .mailbox, .parking, .pharmacy, .police, .postOffice,
        .publicTransport, .restroom, .rvPark, .school, .university,
    ]

    /// A city's headline sights — shared with `AIScreen`, which searches
    /// this set directly so a generic "plan my day" request always has a
    /// city's landmarks as candidates (see its own doc comment for why:
    /// Apple's plain nearby-browse can bury a city's own cathedral below
    /// the ~25-result cap entirely). Explore/Home reuse the same set here
    /// for a lighter purpose — reordering, not searching.
    ///
    /// Widened beyond just museums/landmarks/monuments/castles to the rest
    /// of what someone means by "müzeler ve bunun gibi yerler" (museums and
    /// places like that) when they want a nearby-browse to lead with things
    /// worth actually seeing — aquariums, zoos, theaters, and planetariums
    /// are the same kind of "visit and look at something" venue, just not
    /// literally a museum. Deliberately still excludes parks/beaches/nature
    /// (their own "Doğa" category chip already covers those, and they're
    /// more "spend time outdoors" than "come see this specific thing").
    static let coreSightCategories: Set<MKPointOfInterestCategory> = [
        .museum, .landmark, .nationalMonument, .castle, .fortress, .religiousSite,
        .aquarium, .zoo, .theater, .planetarium,
    ]

    /// Moves sight-category places (museum, landmark, monument, ...) ahead
    /// of everything else, without disturbing the relative order within
    /// either group -- so Apple's own relevance/distance ordering still
    /// decides *which* sights come first among themselves, and which
    /// cafes/shops/etc. come first among themselves.
    ///
    /// Same principle the accuracy report already established for
    /// `/places/recommend-poi`'s enrichment order (see the SIGNAL RULE):
    /// comparing a landmark against a restaurant on a single popularity
    /// score is comparing two different things, since Tripadvisor's review
    /// volume structurally favors hospitality. Category-priority ordering
    /// sidesteps that without needing any rating data at all -- useful here
    /// specifically because Explore/Home's plain browse has none in hand
    /// for what's on screen (only fetched lazily, per-card, for photos).
    static func prioritizingSights(_ items: [POIPlace]) -> [POIPlace] {
        let sights = items.filter { $0.category.map(coreSightCategories.contains) ?? false }
        guard !sights.isEmpty, sights.count < items.count else { return items }
        let sightIdentifiers = Set(sights.map(\.id))
        let rest = items.filter { !sightIdentifiers.contains($0.id) }
        return sights + rest
    }
}
