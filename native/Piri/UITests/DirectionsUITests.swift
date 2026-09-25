import XCTest

/// Verifies the "Piri Haritası" (in-app) maps-provider's "Yol Tarifi" hand-off
/// actually draws a route in Route Mode -- previously (see `PlaceDirections`
/// and `MapScreen+RouteMode.previewRoute`'s single-stop guard) this just
/// recentered the map with no route line, distance, or duration at all.
///
/// Requires the simulator to have a simulated location set before running
/// (same requirement `TripFlowUITests` documents on itself), e.g.:
///   xcrun simctl location <device> set 59.9139,10.7522
/// Without one, `previewRoute()` has nothing to route from and this test
/// fails on the "Konumun alınamadı." assertion below rather than silently
/// passing on a route that was never actually computed.
final class DirectionsUITests: XCTestCase {
    func testInAppDirectionsDrawsARoute() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // This test asserts on Turkish copy below (no accessibility
        // identifier exists for most of the maps-provider picker or the
        // route summary sheet's text) -- force Turkish regardless of the
        // simulator's own system language/region so the test doesn't
        // silently depend on that being pre-configured outside this run.
        app.launchArguments += ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]

        // XCTest's own default interruption handler picks the alert's
        // "cancel"-role button, which for a location prompt is "Don't
        // Allow" -- exactly the answer that makes this whole flow (and
        // `previewRoute()`'s own real behavior for a user who declines)
        // fail on "Konumun alınamadı." instead of testing the route this
        // test actually exists to check. Registered before `launch()` so
        // it's in place for the just-uninstalled app's first prompt below.
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            let allowWhileUsing = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Uygulamayı")).firstMatch
            let allowOnce = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bir Kez")).firstMatch
            if allowWhileUsing.exists {
                allowWhileUsing.tap()
                return true
            } else if allowOnce.exists {
                allowOnce.tap()
                return true
            }
            return false
        }

        app.launch()
        // No dummy tap needed to "wake" the interruption monitor -- XCTest
        // already checks for a blocking alert as part of synthesizing the
        // very first real tap below (`profileTab.tap()`), same as it did
        // for the *default* handler before this monitor existed.

        // Switch the maps-provider preference to "Piri Haritası" so
        // `PlaceDirections.openInMaps` takes the in-app route path instead
        // of handing off to an external maps app.
        let profileTab = app.buttons["piri.tab.4"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 15))
        profileTab.tap()
        let settings = app.buttons["piri.profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        // Matches `AppSmokeUITests.testProfileSettingsAndCity` -- Profile's
        // own content needs a beat to settle before this button reliably
        // registers a tap.
        Thread.sleep(forTimeInterval: 5)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5))
        let piriProvider = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Piri Haritası")).firstMatch
        XCTAssertTrue(piriProvider.waitForExistence(timeout: 5), "'Piri Haritası' maps-provider option not found in Settings")
        if piriProvider.isHittable { piriProvider.tap() }
        attach(app, "01-settings-piri-provider")
        app.buttons["Bitti"].tap()

        // Open a POI's detail card from Home -- `POIExplainSheet`, the same
        // card `PlaceDirections`'s doc comment lists as a call site.
        let homeTab = app.buttons["piri.tab.0"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        homeTab.tap()
        let featured = app.buttons["piri.home.featured"]
        XCTAssertTrue(featured.waitForExistence(timeout: 30), "Home featured POI card not found")
        featured.tap()

        let directions = app.buttons["piri.detail.directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 20), "'Yol Tarifi' button not found on POI detail card")
        attach(app, "02-poi-detail-before-tap")
        directions.tap()

        // Should land on Map in Route Mode with a real route fetched --
        // "Rotayı Kaydet" only renders once `routeModeSheet` is up at all,
        // and a "X km" summary only renders once `previewRoute()` actually
        // got a real result back (`routeSummaryText`).
        let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Rotayı Kaydet")).firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10), "Route Mode summary sheet did not appear after tapping Yol Tarifi -- still just recentering, not routing")

        let distanceSummary = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", " km")).firstMatch
        let noLocationError = app.staticTexts["Konumun alınamadı."]
        let routeFailedError = app.staticTexts["Rota hesaplanamadı. Bağlantını kontrol et."]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !distanceSummary.exists, !noLocationError.exists, !routeFailedError.exists {
            Thread.sleep(forTimeInterval: 1)
        }
        attach(app, "03-directions-route-result")

        XCTAssertFalse(noLocationError.exists, "No simulated location set -- run with `xcrun simctl location <device> set <lat,lng>` before this test")
        XCTAssertFalse(routeFailedError.exists, "Route request failed")
        XCTAssertTrue(distanceSummary.exists, "Expected a real 'X km' route summary after tapping Yol Tarifi, got none -- Yol Tarifi still isn't drawing a route")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
