import Foundation
import Observation

/// The traveler's own ("home") currency — distinct from a city's/country's
/// currency, which `CityStore.countryInfo` already carries. Used to convert
/// "what does this destination's currency cost me" into a number that
/// actually means something to this specific person, instead of always
/// showing a fixed USD conversion regardless of who's looking.
@Observable
final class PreferredCurrencyStore {
    private(set) var code: String

    private static let defaultsKey = "preferred-currency-code"

    init() {
        // `Locale.current.currency` was tried as a "smart" first guess from
        // the device's region, but confirmed live on Simulator: it resolved
        // to AFN (Afghan Afghani) on a device with no explicit region set,
        // not a currency that had anything to do with the person testing
        // it -- an unreliable signal not worth the surprise. USD is at
        // least a known, unsurprising starting point; always overridable
        // via `CurrencyPickerSheet`.
        code = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "USD"
    }

    func setCode(_ code: String) {
        self.code = code
        UserDefaults.standard.set(code, forKey: Self.defaultsKey)
    }
}
