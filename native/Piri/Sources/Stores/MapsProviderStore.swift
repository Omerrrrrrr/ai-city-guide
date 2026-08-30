import Foundation
import Observation

/// Which app "Open in Maps" hands a place off to — three external apps
/// plus `.piri`, which instead jumps to Map (this app's own tab) and
/// centers on the place, never leaving the app. `PlaceDirections` reads
/// the same `UserDefaults` key directly (not through this store) since
/// it's a stateless utility, not a view needing reactivity — this store
/// exists purely so `ProfileScreen`'s picker can observe and update the
/// choice.
enum MapsProvider: String, CaseIterable, Identifiable {
    case piri, apple, google, yandex
    var id: Self { self }

    var labelKey: String {
        switch self {
        case .piri: return "settings.mapsProvider.piri"
        case .apple: return "settings.mapsProvider.apple"
        case .google: return "settings.mapsProvider.google"
        case .yandex: return "settings.mapsProvider.yandex"
        }
    }

    var icon: String {
        switch self {
        case .piri: return "location.circle.fill"
        case .apple: return "map"
        case .google: return "globe.americas"
        case .yandex: return "globe.europe.africa"
        }
    }
}

/// Same shape as `AppearanceStore`/`LanguageStore`.
@Observable
final class MapsProviderStore {
    private(set) var provider: MapsProvider

    // Shared with `PlaceDirections.preferredProvider` -- keep in sync if
    // this ever changes.
    static let defaultsKey = "maps-provider-preference"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey), let provider = MapsProvider(rawValue: raw) {
            self.provider = provider
        } else {
            self.provider = .apple
        }
    }

    func setProvider(_ provider: MapsProvider) {
        self.provider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Self.defaultsKey)
    }
}
