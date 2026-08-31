import Foundation

/// String interpolation into a `String.LocalizationValue`/`Text` key (e.g.
/// `Text("key \(value)")`) makes Swift build the *interpolated* text itself
/// into the lookup key — that only resolves against a catalog Xcode
/// generated from that exact call site. `Localizable.xcstrings` here was
/// generated from the RN app's i18next JSON instead, so every entry is a
/// bare key (`"home.cityPill"`) whose *value* contains `%@`/`%lld`
/// placeholders. Looking it up needs a plain, non-interpolated key lookup
/// followed by classic `String(format:)` substitution — these two helpers
/// are that lookup, used everywhere instead of inline interpolation.
func L(_ key: String, _ args: CVarArg...) -> String {
    let template = String(localized: String.LocalizationValue(key))
    return String(format: template, arguments: args)
}

/// Plural counterpart: every language this app supports (English, Turkish,
/// Norwegian Bokmål, Spanish, German, French, Italian, Brazilian
/// Portuguese) uses just the CLDR "one"/"other" categories, and "one"
/// always means exactly count == 1 in each — see
/// `mobile/src/i18n/__tests__/plurals.test.ts`'s Turkish regression test.
/// So the suffix is picked directly rather than consulting ICU plural rules.
/// A language with a genuinely different plural system (Polish's
/// few/many, Arabic's dual, ...) would need real ICU rules here instead.
func LPlural(_ key: String, count: Int) -> String {
    let suffix = count == 1 ? "one" : "other"
    // Build the full key as a plain `String` *first*. Passing a `"\(...)"`
    // string-interpolation literal straight into `String.LocalizationValue`
    // doesn't concatenate into a lookup key at all — `LocalizationValue`
    // has its own `ExpressibleByStringInterpolation` conformance, so the
    // compiler routes `key`/`suffix` through its interpolation handler as
    // *substitution arguments* instead, and the catalog lookup (searching
    // for something like a literal "%@.%@" entry) always misses — silently
    // falling back to reconstructing the interpolated text itself, which
    // reads exactly like a successful lookup unless you inspect the value.
    let fullKey = key + "." + suffix
    let template = String(localized: String.LocalizationValue(fullKey))
    return String(format: template, count)
}
