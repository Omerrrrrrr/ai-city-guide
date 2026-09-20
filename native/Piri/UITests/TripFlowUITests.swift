import XCTest

/// Home "Start a Trip" -> record -> "End Trip" -> recap video, driven with
/// real taps. Run with the simulator's location moving (see the
/// `simctl location ... start` line in the commit that added this) --
/// a static location gives the recap only one route point and it fails to
/// render by design.
final class TripFlowUITests: XCTestCase {
    func testStartRecordEndTripFromHomeLeadsToRecap() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let start = app.buttons["piri.home.startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "Home 'Start a Trip' card missing")
        attach(app, "01-home-before")
        start.tap()

        let end = app.buttons["piri.home.endTrip"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "Active-trip card with 'End Trip' did not appear")
        XCTAssertFalse(start.exists, "Start card should be replaced while a trip is active")
        attach(app, "02-home-recording")

        // Let the (simulated) GPS produce a few breadcrumb points.
        Thread.sleep(forTimeInterval: 30)
        attach(app, "03-home-recording-later")

        end.tap()
        let confirm = app.alerts.firstMatch.buttons["End Trip"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Confirm alert missing")
        confirm.tap()

        // The recap sheet takes over: generating -> ready/failed.
        let generating = app.staticTexts["Creating your recap…"]
        let anyRecapText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "recap", "video")).firstMatch
        XCTAssertTrue(generating.waitForExistence(timeout: 10) || anyRecapText.waitForExistence(timeout: 10), "Recap sheet did not appear after ending the trip")
        attach(app, "04-recap")

        // Wait for the video itself: either the finished player (Save/Share
        // toolbar) or the explicit failure text.
        let failed = app.staticTexts["Couldn't create the recap video. You can try again later."]
        // Exact labels -- a CONTAINS match on "save" also hits Home's
        // "Saved places" button sitting behind the sheet and passes instantly.
        let saveButton = app.buttons["Save"]
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline, !failed.exists, !saveButton.exists {
            Thread.sleep(forTimeInterval: 2)
        }
        attach(app, "05-recap-result")
        XCTAssertFalse(failed.exists, "Recap video generation failed")
        XCTAssertTrue(saveButton.exists, "Recap video never became ready within 120s")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
