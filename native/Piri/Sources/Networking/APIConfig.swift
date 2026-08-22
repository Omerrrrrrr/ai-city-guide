import Foundation

/// Base URL resolution. The Expo app derives its dev host from
/// `Constants.expoConfig.hostUri` (the Metro bundler's LAN address) — there's
/// no native equivalent, so Debug builds point at a fixed dev host instead,
/// overridable via the `PIRI_API_BASE_URL` Info.plist entry (set per-scheme
/// in an .xcconfig) without touching code.
enum APIConfig {
    static var baseURL: URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "PiriAPIBaseURL") as? String,
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://127.0.0.1:4000")!
        #else
        return URL(string: "https://api.getpiri.com")!
        #endif
    }
}
