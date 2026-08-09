import Foundation

/// Port of the runtime effect of `mobile/src/store/language.ts` — i18next
/// can switch its active language instantly, independent of the OS setting,
/// because it owns its own string tables outside of UIKit/Foundation's
/// localization system entirely. There is no equivalent for that on iOS:
/// `String(localized:)` and SwiftUI `Text` resolve through Foundation's own
/// bundle-localization machinery, and (confirmed empirically — see
/// `DiagnosticTests`) isa-swizzling `Bundle.main` to redirect it does not
/// affect that resolution path for String Catalogs, only the legacy
/// `NSBundle.localizedString(forKey:...)` entry point some other code might
/// still call directly.
///
/// The actually-supported mechanism is the same one Settings.app's per-app
/// "Language" picker uses under the hood: writing the preferred language to
/// the `AppleLanguages` default. It only takes effect on the *next* launch —
/// there is no public API to change a running app's resolved language
/// in-process. `ProfileScreen` shows a "restart Piri" hint after a change
/// for exactly this reason.
enum LanguageManager {
    private static let key = "AppleLanguages"

    static func apply(_ code: String?) {
        guard let code else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set([code], forKey: key)
    }
}
