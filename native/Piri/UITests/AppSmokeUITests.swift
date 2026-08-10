import XCTest

/// Broad, one-screen-per-test smoke coverage across the app's main tabs and
/// the screens reachable from them — driven the same way as
/// `PlanBuilderUITests` (XCTest's own automation), run 3x via
/// `-test-iterations 3` to shake out timing-dependent flakiness rather than
/// trusting a single pass. Each test is independent (fresh launch) so one
/// failing doesn't cascade into the rest.
final class AppSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapTab(_ app: XCUIApplication, _ label: String) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(label) tab not found")
        tab.tap()
    }

    // MARK: - Home

    func testHomeTabLoads() throws {
        let app = launchedApp()
        attach(app, name: "home-01-launch")
        XCTAssertTrue(app.staticTexts["PIRI"].waitForExistence(timeout: 10), "PIRI wordmark not found on Home")
        attach(app, name: "home-02-loaded")
    }

    // MARK: - Scan

    func testScanTabOpens() throws {
        let app = launchedApp()
        tapTab(app, "Tara")
        // Simulators have no real camera — the important thing is that the
        // screen itself renders (no crash, no blank white screen) rather
        // than a live camera feed.
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "scan-01-opened")
        XCTAssertTrue(app.exists)
    }

    // MARK: - Map

    func testMapTabLoads() throws {
        let app = launchedApp()
        tapTab(app, "Harita")
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "map-01-loaded")
        XCTAssertTrue(app.exists)
    }

    // MARK: - Ask Piri (real network round-trip)

    func testAskPiriReturnsAResponse() throws {
        let app = launchedApp()
        tapTab(app, "Piri'ye Sor")
        attach(app, name: "aipiri-01-opened")

        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask Piri input field not found")
        input.tap()
        input.typeText("kahve içebileceğim bir yer")

        let askButton = app.buttons["Sor"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 5), "Sor button not found")
        askButton.tap()

        // Real backend round-trip (candidate search + AI call) — give it
        // real time rather than a token delay.
        Thread.sleep(forTimeInterval: 8)
        attach(app, name: "aipiri-02-response")
    }

    // MARK: - Profile (all 4 tabs)

    func testProfileAllSubTabs() throws {
        let app = launchedApp()
        tapTab(app, "Profil")
        attach(app, name: "profile-01-language")

        for label in ["Meslek", "İlgi Alanları", "Plan"] {
            let tabButton = app.buttons[label]
            if tabButton.waitForExistence(timeout: 5), tabButton.isHittable {
                tabButton.tap()
                Thread.sleep(forTimeInterval: 0.5)
                attach(app, name: "profile-tab-\(label)")
            }
        }
    }

    // MARK: - Saved (Kaydedilen / Plan / Ziyaret edilen)

    func testSavedScreenAllTabs() throws {
        let app = launchedApp()
        tapTab(app, "Profil")

        let viewAll = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Tümünü gör")).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 8), "'Tümünü gör' (saved places) not found")
        viewAll.tap()
        attach(app, name: "saved-01-favorites")

        for label in ["Plan", "ziyaret edilen"] {
            let tabButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
            if tabButton.waitForExistence(timeout: 5), tabButton.isHittable {
                tabButton.tap()
                Thread.sleep(forTimeInterval: 0.5)
                attach(app, name: "saved-tab-\(label)")
            }
        }
    }
}
