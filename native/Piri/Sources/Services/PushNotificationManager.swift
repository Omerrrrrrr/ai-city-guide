import Observation
import UIKit
import UserNotifications

struct CityDiscoveryTapPayload: Equatable {
    var cityId: String
    var cityName: String
}

/// Port of `getExpoPushToken`/`useNotificationTapHandler` in
/// `mobile/src/hooks/use-push-notifications.ts`, now talking to APNs
/// directly instead of through Expo's push service (see `apps/api/src/apns.ts`
/// for the corresponding backend side).
@Observable
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    private(set) var deviceTokenHex: String?
    private(set) var registrationFailed = false
    private(set) var pendingTapPayload: CityDiscoveryTapPayload?

    private init() {}

    /// Lazy, on-demand registration matching RN's `getExpoPushToken()`
    /// contract exactly: only ever called from the city-discover flow, never
    /// throws, returns `nil` on denial/failure/timeout. Uses the same
    /// bounded-poll idiom as `LocationManager.currentLocationOnce` rather
    /// than a continuation, since `didRegisterForRemoteNotifications...` can
    /// arrive on a background thread and a continuation resumed twice (once
    /// from a race, once from the timeout) would crash.
    @MainActor
    func deviceToken(timeout: Duration = .seconds(5)) async -> String? {
        if let deviceTokenHex { return deviceTokenHex }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return nil }

        UIApplication.shared.registerForRemoteNotifications()

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let deviceTokenHex { return deviceTokenHex }
            if registrationFailed { return nil }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return deviceTokenHex
    }

    /// Called by `AppDelegate` — UIKit guarantees this delegate callback
    /// lands on the main thread.
    func handleDeviceToken(_ data: Data) {
        deviceTokenHex = data.map { String(format: "%02x", $0) }.joined()
    }

    func handleRegistrationFailure(_ error: Error) {
        registrationFailed = true
    }

    /// Called by `AppDelegate` for both cold-start-via-tap and warm-tap —
    /// unlike RN, which needed `getLastNotificationResponseAsync` plus a
    /// separate live listener, `UNUserNotificationCenterDelegate` covers both
    /// through this one method once it's set as the delegate at launch.
    /// Apple doesn't guarantee this callback lands on the main thread, so the
    /// caller (`AppDelegate`) hops to main before calling in.
    @MainActor
    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        guard userInfo["type"] as? String == "city-discovery",
              let cityId = userInfo["cityId"] as? String,
              let cityName = userInfo["cityName"] as? String else { return }
        pendingTapPayload = CityDiscoveryTapPayload(cityId: cityId, cityName: cityName)
    }

    @MainActor
    func consumeTapPayload() {
        pendingTapPayload = nil
    }
}
