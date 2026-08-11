import XCTest

/// One-off interactive verification for `PlanBuilderScreen`, driven through
/// XCTest's own automation rather than host-level Accessibility APIs (this
/// environment has no Accessibility permission for AppleScript/System
/// Events UI scripting, so this is the only way to actually tap through the
/// app from here instead of just asking the user to). Screenshots are
/// attached at each step so a failure partway still leaves visual evidence
/// of how far it got.
final class PlanBuilderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testOpenPlanBuilderFromSavedPlanTab() throws {
        let app = XCUIApplication()
        app.launch()
        attach(app, name: "01-launch")

        let profileTab = app.tabBars.buttons["Profil"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Profil tab bar item not found")
        profileTab.tap()
        attach(app, name: "02-profile")

        // Set an active city first — PlanBuilderScreen has nothing to search
        // around otherwise (its own "önce bir şehir seç" empty state, a
        // separate, already-covered case) and the point of this run is to
        // exercise the actual guided flow.
        let changeCity = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Değiştir")).firstMatch
        if changeCity.waitForExistence(timeout: 5), changeCity.isHittable {
            changeCity.tap()
            attach(app, name: "02b-city-picker")
            let searchField = app.textFields.firstMatch
            if searchField.waitForExistence(timeout: 5) {
                searchField.tap()
                searchField.typeText("Oslo")
                let firstResult = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Oslo")).firstMatch
                if firstResult.waitForExistence(timeout: 8) {
                    firstResult.tap()
                }
            }
            attach(app, name: "02c-city-set")
        }

        let plansStat = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Planlar")).firstMatch
        var scrollAttempts = 0
        while !(plansStat.exists && plansStat.isHittable), scrollAttempts < 10 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(plansStat.waitForExistence(timeout: 5), "Planlar stat button not found")
        plansStat.tap()
        attach(app, name: "03-saved-plan-tab")

        let aiBuildButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "AI ile Planla")).firstMatch
        XCTAssertTrue(aiBuildButton.waitForExistence(timeout: 8), "AI ile Planla button not found")
        aiBuildButton.tap()
        attach(app, name: "04-plan-builder-opened")

        // Let the landmark search (async, network-backed) settle before the
        // final screenshot.
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "05-plan-builder-settled")

        // Tap the first theme chip if one is visible, to exercise the
        // live-updating draft plan section too.
        let artChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sanat")).firstMatch
        if artChip.waitForExistence(timeout: 3), artChip.isHittable {
            artChip.tap()
            Thread.sleep(forTimeInterval: 3)
            attach(app, name: "06-theme-selected")
        }

        // Dismiss back to Saved > Plan tab and open whichever plan already
        // exists there (earlier runs/manual testing leave at least one) to
        // reach CollectionDetailScreen and verify the new date/weather/
        // hours schedule feature — a fresh empty plan has nothing to
        // navigate into, so this reuses existing state rather than
        // fighting SF Symbol accessibility-label guesses to automate the
        // "+" add-to-plan tap here too.
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "07-back-to-plan-tab")

        let firstPlanRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "yer")).firstMatch
        if firstPlanRow.waitForExistence(timeout: 5) {
            firstPlanRow.tap()
            attach(app, name: "08-collection-detail")

            let pickDateRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Tarih")).firstMatch
            if pickDateRow.waitForExistence(timeout: 5) {
                pickDateRow.tap()
                attach(app, name: "09-date-picker-opened")

                let cancelButton = app.navigationBars.buttons.firstMatch
                if cancelButton.waitForExistence(timeout: 3) {
                    cancelButton.tap()
                }
                attach(app, name: "10-date-picker-closed")
            }
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
