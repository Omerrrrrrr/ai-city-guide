import XCTest

/// One-off interactive verification for ProfileScreen's new "Hesap" (account)
/// card and SignInScreen, driven the same way PlanBuilderUITests already
/// does -- real taps through XCTest's own automation, screenshots attached
/// at each step. Requires the API dev server running locally with
/// AUTH_JWT_SECRET set (see accounts.ts/auth.ts) -- this exercises real
/// register -> sign-in -> sync -> sign-out against it, not a mock.
final class AccountUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testSignUpAndSignOutFromProfileAccountCard() throws {
        let app = XCUIApplication()
        app.launch()
        attach(app, name: "01-launch")

        completeOnboardingIfNeeded(app)

        let profileTab = app.tabBars.buttons["Profil"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Profil tab bar item not found")
        profileTab.tap()
        attach(app, name: "02-profile")

        // A previous run's session persists in Keychain across app
        // launches (by design) -- reset to signed-out first so this test
        // starts from a known state regardless of what ran before it.
        signOutIfNeeded(app)

        let signInButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Giriş Yap")).firstMatch
        var scrollAttempts = 0
        while !(signInButton.exists && signInButton.isHittable), scrollAttempts < 10 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5), "'Giriş Yap' button not found in the signed-out account card")
        attach(app, name: "03-signed-out-account-card")
        signInButton.tap()
        attach(app, name: "04-sign-in-sheet")

        // Start in "log in" mode by default -- switch to "register" since
        // this run needs a brand-new account every time.
        let switchToRegister = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Oluştur")).firstMatch
        XCTAssertTrue(switchToRegister.waitForExistence(timeout: 5), "Switch-to-register link not found")
        switchToRegister.tap()
        attach(app, name: "05-register-mode")

        // Not `.firstMatch` -- register mode shows the (optional) display
        // name field above the email field, so the first text field isn't
        // reliably the email one.
        let emailField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "E-posta")).firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Email field not found")
        emailField.tap()
        let uniqueEmail = "uitest-\(Int(Date().timeIntervalSince1970))@example.com"
        emailField.typeText(uniqueEmail)

        let passwordField = app.secureTextFields.firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "Password field not found")
        passwordField.tap()
        passwordField.typeText("correcthorsebattery")
        attach(app, name: "06-register-form-filled")

        let submitButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Hesap Oluştur")).firstMatch
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5), "Submit button not found")
        submitButton.tap()

        // Real network round-trip (register -> session token -> initial
        // sync pull/push) before the sheet dismisses.
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "07-after-submit")

        // iOS's own "Save Password?" prompt covers the whole screen after a
        // SecureField submit -- not an app UI element, just needs dismissing
        // before anything underneath is tappable again.
        let notNowButton = app.buttons["Sonra"]
        if notNowButton.waitForExistence(timeout: 3) {
            notNowButton.tap()
            attach(app, name: "07b-dismissed-save-password-prompt")
        }

        let signOutButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Çıkış Yap")).firstMatch
        scrollAttempts = 0
        while !(signOutButton.exists && signOutButton.isHittable), scrollAttempts < 10 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 8), "'Çıkış Yap' button not found -- sign-in likely failed or sheet didn't dismiss")

        let emailLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", uniqueEmail)).firstMatch
        XCTAssertTrue(emailLabel.exists, "Signed-in email not shown on the account card")
        attach(app, name: "08-signed-in-account-card")

        signOutButton.tap()
        attach(app, name: "09-after-sign-out")

        let signInButtonAgain = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Giriş Yap")).firstMatch
        XCTAssertTrue(signInButtonAgain.waitForExistence(timeout: 5), "Account card did not return to the signed-out state after sign-out")
        attach(app, name: "10-signed-out-again")
    }

    /// A fresh simulator/app install lands on OnboardingScreen, not the main
    /// tabs -- the other UITests in this target only pass because their
    /// simulator already had onboarding completed from earlier manual runs.
    /// Taps through it (welcome "Başla", then "Devam et"/"Bitti" on each
    /// wizard step) so this test works from a truly clean install too.
    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        guard !app.tabBars.buttons["Profil"].waitForExistence(timeout: 2) else { return }

        let start = app.buttons["Başla"]
        if start.waitForExistence(timeout: 3) {
            start.tap()
        }

        var attempts = 0
        while !app.tabBars.buttons["Profil"].exists, attempts < 12 {
            let advance = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Devam et", "Bitti")).firstMatch
            if advance.waitForExistence(timeout: 3), advance.isHittable {
                advance.tap()
            } else {
                break
            }
            attempts += 1
        }
        attach(app, name: "01b-onboarding-completed")
    }

    private func signOutIfNeeded(_ app: XCUIApplication) {
        let signOutButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Çıkış Yap")).firstMatch
        var scrollAttempts = 0
        while !(signOutButton.exists && signOutButton.isHittable), scrollAttempts < 10 {
            app.swipeUp()
            scrollAttempts += 1
        }
        guard signOutButton.exists, signOutButton.isHittable else { return }
        signOutButton.tap()
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
