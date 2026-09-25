import XCTest

/// Diagnoses a report: opening a POI, asking a question in its inline chat
/// ("Ask about this place"), backgrounds the app into the system Maps app
/// instead of showing the chat reply. Runs entirely through XCUITest (never
/// touches the real mouse/screen) -- safe to run on a shared Mac.
final class POIChatUITests: XCTestCase {
    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testAskingAQuestionInPOIChatDoesNotLeaveTheApp() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()

        let featured = app.buttons["piri.home.featured"]
        XCTAssertTrue(featured.waitForExistence(timeout: 20), "Home featured POI card missing")
        // Let the real photo load -- the bug (if it's the same hit-testing
        // class as the Home trip-card bug) only shows once a real photo is
        // drawn over its box.
        Thread.sleep(forTimeInterval: 20)
        attach(app, "01-home")
        featured.tap()

        let toggle = app.buttons["piri.detail.chat.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "POI detail sheet / chat toggle did not appear")
        Thread.sleep(forTimeInterval: 8)
        attach(app, "02-poi-detail")
        XCTAssertTrue(app.buttons["piri.detail.directions"].exists, "Directions button missing before chat is opened")
        toggle.tap()

        let input = app.textFields["piri.detail.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Chat input did not appear after expanding")
        // The actual fix: the big "Directions" button (which backgrounds
        // the app into Apple Maps by default) must not sit in the chat's
        // hot zone once chat is open.
        XCTAssertFalse(app.buttons["piri.detail.directions"].exists, "Directions button still present while chat is open -- mis-tap hazard not fixed")
        attach(app, "03-chat-expanded")
        input.tap()
        input.typeText("What is this place known for?")
        attach(app, "04-typed")

        let send = app.buttons["piri.detail.chat.send"]
        XCTAssertTrue(send.exists)
        XCTAssertTrue(app.state == .runningForeground, "App not foreground before send")
        send.tap()
        Thread.sleep(forTimeInterval: 2)
        attach(app, "05-after-send-tap")

        // The real bug report: tapping send should never background the app
        // into Maps. Poll briefly since state transitions aren't instant.
        var sawBackground = false
        for _ in 0..<10 {
            if app.state != .runningForeground { sawBackground = true; break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        attach(app, "06-final-state")
        XCTAssertFalse(sawBackground, "App left the foreground (likely opened Maps) after tapping chat send")

        // If it stayed foreground, also confirm we're still looking at the
        // POI sheet, not something else entirely.
        XCTAssertTrue(app.buttons["piri.detail.chat.send"].exists, "No longer on the POI chat sheet after send")
    }
}
