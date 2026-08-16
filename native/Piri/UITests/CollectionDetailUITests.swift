import XCTest

/// Live verification for the `CollectionDetailScreen` usability fixes from
/// commit `b0359d7` (native `List`/`.onMove` drag reorder, and real
/// network-failure vs. empty-state distinction with a retry button on the
/// weather/hours banners) — the earlier session couldn't drive this because
/// synthetic host-level keystrokes (AppleScript/System Events) don't reach
/// SwiftUI text fields here. XCTest's own automation (used throughout the
/// rest of this UITests target, e.g. `AccountUITests`/`PlanBuilderUITests`)
/// does reach them, so this reuses that same approach instead.
///
/// Run twice against the two intended network conditions:
///   1. with the local `apps/api` dev server stopped, to see the real
///      failure banners + retry button
///   2. with it running, to confirm the same screen recovers
final class CollectionDetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testReorderAndDateTriggeredWeatherHours() throws {
        let app = XCUIApplication()
        app.launch()
        attach(app, name: "01-launch")

        let profileTab = app.tabBars.buttons["Profil"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Profil tab bar item not found")
        profileTab.tap()
        attach(app, name: "02-profile")

        let plansStat = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Planlar")).firstMatch
        var scrollAttempts = 0
        while !(plansStat.exists && plansStat.isHittable), scrollAttempts < 10 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(plansStat.waitForExistence(timeout: 5), "Planlar stat button not found")
        plansStat.tap()
        attach(app, name: "03-plan-tab")

        // "Test 2" (5 places, already has a targetDate from earlier manual
        // testing) is reused rather than creating a fresh collection --
        // reorder needs 2+ places to be meaningful, and this one already
        // has plenty, without fighting the search-to-add field's layout.
        let testPlanRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Test 2")).firstMatch
        let anyPlanRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "yer")).firstMatch
        let planRow = testPlanRow.waitForExistence(timeout: 5) ? testPlanRow : anyPlanRow
        guard planRow.waitForExistence(timeout: 5) else {
            XCTFail("No existing plan found to open -- create one manually first (e.g. via PlanBuilderUITests) so this test has a collection to drive.")
            return
        }
        planRow.tap()
        // A targetDate persisted from before triggers the weather/hours
        // fetch immediately on appear -- give it real time before the
        // first screenshot so the failure/success banners are already
        // settled, not caught mid-flight.
        Thread.sleep(forTimeInterval: 5)
        attach(app, name: "04-collection-opened")

        // Reorder: drag the first row down past the second one. Using a
        // coordinate-based long-press + drag on the row itself (not
        // guessing the system reorder handle's accessibility path) --
        // `List`/`.onMove` accepts a drag starting anywhere on the row on
        // iOS 26 as long as edit mode is active, which this screen forces
        // via `.environment(\.editMode, .constant(.active))`.
        let firstRow = app.cells.firstMatch
        if firstRow.waitForExistence(timeout: 5) {
            let start = firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 2.2))
            start.press(forDuration: 0.6, thenDragTo: end)
            Thread.sleep(forTimeInterval: 1)
        }
        attach(app, name: "06-after-reorder-drag")

        // Set the plan's start time -- default (now) is fine, just confirm
        // -- this is what actually triggers the weather/hours fetch this
        // test is here to observe.
        let pickDateRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Başlangıç")).firstMatch
        if pickDateRow.waitForExistence(timeout: 5) {
            pickDateRow.tap()
            attach(app, name: "07-date-picker-opened")
            let doneButton = app.buttons["Bitti"]
            if doneButton.waitForExistence(timeout: 3) {
                doneButton.tap()
            }
        }

        // Real network round-trip (weather forecast + /places/hours-check)
        // -- give it real time to either succeed or fail.
        Thread.sleep(forTimeInterval: 6)
        attach(app, name: "08-after-date-set")

        let retryButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Tekrar dene"))
        if retryButtons.count > 0 {
            attach(app, name: "09-retry-banners-visible")
            retryButtons.firstMatch.tap()
            Thread.sleep(forTimeInterval: 4)
            attach(app, name: "10-after-retry-tap")
        } else {
            attach(app, name: "09-no-failure-banners-success-state")
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
