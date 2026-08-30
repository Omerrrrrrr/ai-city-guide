import Foundation

/// Base URL resolution. The Expo app derives its dev host from
/// `Constants.expoConfig.hostUri` (the Metro bundler's LAN address) — there's
/// no native equivalent, so Debug builds point at a fixed dev host instead,
/// overridable via the `PIRI_API_BASE_URL` Info.plist entry (set per-scheme
/// in an .xcconfig) without touching code.
enum APIConfig {
    static var baseURL: URL {
        #if !targetEnvironment(simulator)
        // Real device only — a physical iPhone can't reach the Mac via
        // `127.0.0.1`, so this LAN-IP override (project.yml's
        // `PIRI_API_BASE_URL`) is how a Debug build finds the locally
        // running dev server. The Simulator shares the Mac's own network
        // stack, so it never needs this and always falls through to the
        // loopback default below — confirmed live 2026-08-30: this
        // override had gone stale (the Mac's actual LAN IP had changed
        // since it was set) and was silently breaking Simulator runs too,
        // for a reason that had nothing to do with the Simulator itself.
        if let override = Bundle.main.object(forInfoDictionaryKey: "PiriAPIBaseURL") as? String,
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        #endif
        #if DEBUG
        return URL(string: "http://127.0.0.1:4000")!
        #else
        return URL(string: "https://api.getpiri.com")!
        #endif
    }
}
