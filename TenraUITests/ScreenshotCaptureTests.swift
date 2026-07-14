//
//  ScreenshotCaptureTests.swift
//  TenraUITests
//
//  Automated App Store screenshot capture. Launches the app in ScreenshotDemo
//  mode (seeded dataset, Pro unlocked, offline FX) with the language/locale
//  passed via TEST_RUNNER_* environment variables, walks the 8 marketing
//  screens and stores full-resolution screenshots as keepAlways attachments.
//
//  Run via scripts/capture_screenshots.sh — it loops all storefront locales
//  and exports the attachments from the .xcresult bundles.
//
//  Environment (set with TEST_RUNNER_ prefix on xcodebuild):
//    SCREENSHOT_LANGUAGE       — AppleLanguages value for the app ("de", "es-MX", …)
//    SCREENSHOT_LOCALE         — AppleLocale value ("de_DE", "es_MX", …)
//    SCREENSHOT_DEMO_CURRENCY  — seeded dataset currency ("EUR", "MXN", …)
//

import XCTest

final class ScreenshotCaptureTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureMarketingScreens() throws {
        let env = ProcessInfo.processInfo.environment
        let language = env["SCREENSHOT_LANGUAGE"] ?? "en"
        let locale = env["SCREENSHOT_LOCALE"] ?? "en_US"
        let currency = env["SCREENSHOT_DEMO_CURRENCY"] ?? "USD"

        // The simulator's own UI stays in English — system permission alerts keep
        // English button titles regardless of the app's -AppleLanguages override.
        addUIInterruptionMonitor(withDescription: "System permission alerts") { alert in
            for title in ["Allow", "OK", "Allow While Using App", "Allow Full Access"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app = XCUIApplication()
        app.launchArguments += [
            "-ScreenshotDemo",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        app.launchEnvironment["SCREENSHOT_DEMO_CURRENCY"] = currency
        app.launch()

        // ── 1. Home (budgets) ────────────────────────────────────────────────
        let historyLink = app.descendants(matching: .any)["home.historyLink"].firstMatch
        XCTAssertTrue(historyLink.waitForExistence(timeout: 90), "Home did not load")
        // Let full init finish: balances recalc, deposit interest posting, reveal animations.
        sleep(6)
        snap("01-home")

        // ── 6. History (from Home) ───────────────────────────────────────────
        historyLink.tap()
        sleep(3)
        snap("06-history")
        goBack()

        // ── 3. Analytics / Insights ──────────────────────────────────────────
        tabBarButton(at: 1).tap()
        let healthBadge = app.descendants(matching: .any)["insights.healthScore"].firstMatch
        XCTAssertTrue(healthBadge.waitForExistence(timeout: 60), "Insights did not load")
        sleep(2)
        snap("03-insights")

        // ── 4. Financial health score ────────────────────────────────────────
        healthBadge.tap()
        sleep(2)
        snap("04-health-score")
        goBack()

        // ── 5. Top spending category ─────────────────────────────────────────
        let topCategoryCard = app.descendants(matching: .any)["insights.card.top_spending"].firstMatch
        var scrollAttempts = 0
        while !(topCategoryCard.exists && topCategoryCard.isHittable) && scrollAttempts < 8 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(topCategoryCard.exists, "Top-spending insight card not found")
        topCategoryCard.tap()
        sleep(2)
        snap("05-top-category")
        goBack()

        // ── 2. Finances ──────────────────────────────────────────────────────
        tabBarButton(at: 2).tap()
        let accountsCard = app.descendants(matching: .any)["finances.accountsCard"].firstMatch
        XCTAssertTrue(accountsCard.waitForExistence(timeout: 30), "Finances did not load")
        sleep(2)
        snap("02-finances")

        // ── 8. Accounts / multi-currency total ───────────────────────────────
        accountsCard.tap()
        sleep(2)
        snap("08-multicurrency")
        goBack()

        // ── 7. Voice input (expand the [+] pseudo-tab, then Voice) ───────────
        tabBarButton(at: 3).tap()   // [+] → switches tab bar to expanded mode
        sleep(1)
        tabBarButton(at: 0).tap()   // Voice tab in expanded mode
        sleep(2)
        // Trigger the interruption monitor if a mic/speech alert appeared.
        app.tap()
        sleep(2)
        snap("07-voice")
    }

    // MARK: - Helpers

    private func tabBarButton(at index: Int) -> XCUIElement {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "Tab bar not found")
        return tabBar.buttons.element(boundBy: index)
    }

    private func goBack() {
        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            backButton.tap()
        } else {
            // Zoom-transition detail views sometimes expose no nav bar — swipe from edge.
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        }
        sleep(1)
    }

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
