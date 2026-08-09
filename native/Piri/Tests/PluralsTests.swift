import XCTest
@testable import Piri

/// Port of `mobile/src/i18n/__tests__/plurals.test.ts` — regression test for
/// a real production bug in the RN app: Turkish CLDR pluralization
/// distinguishes "one" vs "other" same as English (Turkish nouns don't
/// inflect for plural, but the CLDR rule still applies), and a locale
/// missing an explicit "one" variant silently fell back to the English
/// string. `LPlural` (see `Localization.swift`) sidesteps ICU plural-rule
/// lookup entirely by picking the suffix itself from `count`, so unlike the
/// RN test this doesn't need to force a specific language to check — it
/// verifies that *whatever* the active language is, both the "one" and
/// "other" catalog entries genuinely exist and resolve to real, distinct,
/// correctly-substituted text rather than silently falling through to the
/// raw lookup key (which is Foundation's fallback when nothing matches —
/// this exact failure mode was hit and fixed while writing this test, see
/// `Localization.swift`'s `LPlural`).
final class PluralsTests: XCTestCase {
    private let pluralizedKeys = ["explore.placesFound", "map.placesCount", "cityPicker.placeCount"]

    func testBothPluralFormsResolveToRealSubstitutedText() {
        for key in pluralizedKeys {
            let singular = LPlural(key, count: 1)
            let plural = LPlural(key, count: 5)

            XCTAssertFalse(singular.isEmpty)
            XCTAssertFalse(plural.isEmpty)
            // Foundation's fallback for an unresolved key is the raw lookup
            // string itself — catch a silent miss for either variant.
            XCTAssertNotEqual(singular, "\(key).one")
            XCTAssertNotEqual(plural, "\(key).other")
            // The count must actually be substituted into the template, not
            // left as a literal "%lld" (would indicate `String(format:)`
            // never matched the template's positional specifier).
            XCTAssertTrue(singular.contains("1"), "\(key) singular should contain the substituted count: \(singular)")
            XCTAssertTrue(plural.contains("5"), "\(key) plural should contain the substituted count: \(plural)")
        }
    }
}
