import XCTest

/// Produces the App Store screenshots. Not a regression test -- it only
/// attaches screenshots, exported afterwards with
/// `xcresulttool export attachments`.
///
/// Run on an iPhone 16 Pro Max simulator (PNGs come out 1320x2868, ASC's 6.9"
/// size), against a *Release* build (Debug points at a local dev API on
/// 127.0.0.1:4000, so no place photos ever load), in English, with a seeded
/// profile and the status bar override set. `testHomeAndPlace` wants a fixed
/// simulator location; `testTripRecording` wants a moving one
/// (`xcrun simctl location <dev> start ...`).
final class StoreScreenshotsUITests: XCTestCase {
    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func attachText(_ text: String, _ name: String) {
        let a = XCTAttachment(string: text)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testHomeAndPlace() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["piri.home.startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        // Let the nearby list and its photos load.
        Thread.sleep(forTimeInterval: 20)
        attach(app, "01-home")

        let card = app.staticTexts["Kristiansand Cathedral"].firstMatch
        if card.waitForExistence(timeout: 5) {
            card.tap()
            Thread.sleep(forTimeInterval: 15)
            attach(app, "02-place-a")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 2)
            attach(app, "02-place-b")
        }
        let buttons = app.buttons.allElementsBoundByIndex.prefix(40).map { "B: \($0.label) [\($0.identifier)]" }
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(40).map { "T: \($0.label)" }
        attachText((buttons + texts).joined(separator: "\n"), "elements-place")
    }








    /// Home "Start a Trip" -> record while the simulator location moves ->
    /// Map -> "End Trip" -> recap video frames.
    func testTripRecording() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["piri.home.startTrip"]
        let end = app.buttons["piri.home.endTrip"]
        if start.waitForExistence(timeout: 20) {
            Thread.sleep(forTimeInterval: 6)
            start.tap()
        }
        XCTAssertTrue(end.waitForExistence(timeout: 10), "Trip did not start")
        Thread.sleep(forTimeInterval: 30)
        attach(app, "03-home-recording")

        app.buttons["piri.tab.2"].tap()
        Thread.sleep(forTimeInterval: 8)
        attach(app, "04-map-recording")
        // Route mode shows the live trail and the recording status card.
        let flag = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "flag")).firstMatch
        if flag.waitForExistence(timeout: 3) {
            flag.tap()
            Thread.sleep(forTimeInterval: 6)
            attach(app, "04-map-route")
        }

        app.buttons["piri.tab.0"].tap()
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 15)
        end.tap()
        Thread.sleep(forTimeInterval: 2)
        attach(app, "04b-after-end-tap")
        attachText("alerts=\(app.alerts.count) endExists=\(end.exists) endHittable=\(end.isHittable)", "end-tap-state")
        let confirm = app.alerts.firstMatch.buttons["End Trip"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 120), "Recap video never became ready")
        for i in 1...18 {
            attach(app, "05-recap-\(String(format: "%02d", i))")
            Thread.sleep(forTimeInterval: 0.6)
        }
    }
}
