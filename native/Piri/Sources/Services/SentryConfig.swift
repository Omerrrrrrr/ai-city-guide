import Sentry

/// Port of `mobile/src/sentry.ts` — same DSN, native Cocoa SDK instead of
/// `@sentry/react-native`. No Expo-Go-style gate needed here since there's
/// no equivalent constrained runtime.
enum SentryConfig {
    static func start() {
        SentrySDK.start { options in
            options.dsn = "https://e77498086d6aca108fe6f3e2b925851b@o4511846233407488.ingest.de.sentry.io/4511846289834064"
            options.tracesSampleRate = 0
        }
    }
}
