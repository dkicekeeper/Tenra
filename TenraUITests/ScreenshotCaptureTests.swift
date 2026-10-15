//
//  ScreenshotCaptureTests.swift
//  TenraUITests
//
//  Automated App Store screenshot capture. Launches the app in ScreenshotDemo
//  mode (seeded dataset, Pro unlocked, offline FX, Ten on a scripted transport)
//  with the language/locale passed via TEST_RUNNER_* environment variables,
//  walks the marketing screens (01-08 and 13-16 for the default product page,
//  09-12 for the custom product pages: subscriptions, a deposit, loans) and
//  stores full-resolution screenshots as keepAlways attachments.
//
//  1.6 frames: 13 Ten answers "My spending this month" on cards, 14 Ten drafts
//  what was said in its voice sheet (07) with Save, 15 a goal's detail with the
//  monthly amount, 16 the debts list with one overdue.
//
//  Run via scripts/capture_screenshots.sh — it loops all storefront locales
//  and exports the attachments from the .xcresult bundles.
//
//  Environment (set with TEST_RUNNER_ prefix on xcodebuild):
//    SCREENSHOT_FRAMES         — "cpp" captures 02 and 09-12 (custom product pages); default all
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

        if env["SCREENSHOT_FRAMES"] == "cpp" {
            // Only the custom product page frames: the default ones are already composed.
            // The first locale of a CI run starts cold: a tab tap can land before the tab bar
            // responds, so tap again until Finances shows.
            let accountsCard = app.descendants(matching: .any)["finances.accountsCard"].firstMatch
            for _ in 0..<3 where !accountsCard.exists {
                tabBarButton(at: 2).tap()
                _ = accountsCard.waitForExistence(timeout: 40)
            }
            XCTAssertTrue(accountsCard.exists, "Finances did not load")
            sleep(2)
            snap("02-finances")   // the custom pages reuse it
            captureCustomPageFrames()
            return
        }

        snap("01-home")

        // ── 6. History (from Home) ───────────────────────────────────────────
        historyLink.tap()
        sleep(3)
        snap("06-history")
        goBack()

        // ── 3. Analytics / Insights ──────────────────────────────────────────
        tabBarButton(at: 1).tap()
        let healthBadge = app.descendants(matching: .any)["insights.healthScore"].firstMatch
        // A slow CI simulator needs minutes for the first Insights pass over the demo data.
        XCTAssertTrue(healthBadge.waitForExistence(timeout: 180), "Insights did not load")
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
        // The current month is partial (one rent payment dominates early in the
        // month), so show the previous, complete month.
        let previousPeriod = app.buttons["insightDetail.previousPeriod"].firstMatch
        if previousPeriod.waitForExistence(timeout: 5) && previousPeriod.isEnabled {
            previousPeriod.tap()
            sleep(2)
        }
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

        captureCustomPageFrames()
        capturePlanFrames()
        captureTenFrames()
    }

    // MARK: - Goals and debts

    /// 15-16: a goal's detail (the first goal: money added by hand, a deadline, what to put aside
    /// each month), then the debts list (one lent and overdue). Starts and ends on Finances.
    private func capturePlanFrames() {
        // ── 15. A savings goal ───────────────────────────────────────────────
        let goalsCard = app.descendants(matching: .any)["finances.goalsCard"].firstMatch
        scrollUntilHittable(goalsCard)
        XCTAssertTrue(goalsCard.exists, "Goals card not found")
        goalsCard.tap()
        let firstGoal = app.descendants(matching: .any).matching(identifier: "goals.row").firstMatch
        XCTAssertTrue(firstGoal.waitForExistence(timeout: 20), "Goals list did not load")
        sleep(1)
        firstGoal.tap()
        sleep(3)   // the hero's progress settles
        snap("15-goal")
        goBack(until: goalsCard)

        // ── 16. Debts, one overdue ───────────────────────────────────────────
        let debtsCard = app.descendants(matching: .any)["finances.debtsCard"].firstMatch
        scrollUntilHittable(debtsCard)
        XCTAssertTrue(debtsCard.exists, "Debts card not found")
        debtsCard.tap()
        let firstDebt = app.descendants(matching: .any).matching(identifier: "debts.row").firstMatch
        XCTAssertTrue(firstDebt.waitForExistence(timeout: 20), "Debts list did not load")
        sleep(2)
        snap("16-debts")
        goBack(until: debtsCard)
    }

    // MARK: - Ten

    /// 13, 07, 14: Ten answers its first ready-made question on cards; its voice sheet hears the
    /// demo phrase; Ten drafts it with Save. The transport is scripted (ScreenshotDemoTransport),
    /// the cards are the seeded data.
    private func captureTenFrames() {
        // ── 13. Ten answers on cards ─────────────────────────────────────────
        tabBarButton(at: 3).tap()   // Ten takes the action tab in demo mode
        let presets = app.descendants(matching: .any)["assistant.presets"].firstMatch
        XCTAssertTrue(presets.waitForExistence(timeout: 20), "Ten's home did not load")
        sleep(2)
        presets.buttons.firstMatch.tap()   // "My spending this month"
        let reply = app.descendants(matching: .any)["assistant.reply"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 60), "Ten did not answer")
        sleep(4)   // the cards cascade in, Ten settles
        snap("13-ten-answers")
        goBack()

        // ── 7. Ten's voice sheet, hearing the demo phrase ────────────────────
        let composer = app.descendants(matching: .any)["assistant.composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "Ten's composer not found")
        let buttons = composer.buttons
        XCTAssertGreaterThan(buttons.count, 0, "Ten's composer has no buttons")
        buttons.element(boundBy: buttons.count - 1).tap()   // the microphone, last in the field
        let stop = app.descendants(matching: .any)["assistant.voice.stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 20), "Ten's voice sheet did not open")
        sleep(3)
        snap("07-voice")

        // ── 14. Ten drafts what was said ─────────────────────────────────────
        stop.tap()
        let send = app.descendants(matching: .any)["assistant.voice.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "\"Ask Ten\" did not show")
        sleep(1)
        send.tap()
        let save = app.descendants(matching: .any)["assistant.draft.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 60), "Ten did not draft the phrase")
        sleep(3)
        snap("14-ten-drafts")
    }

    // MARK: - Custom product page frames

    /// 09-12, for the custom product pages: subscriptions, a deposit, loans. Starts and ends on
    /// the Finances tab.
    private func captureCustomPageFrames() {
        // ── 9-10. Subscriptions: calendar and cards, then one subscription ──
        let subscriptionsCard = app.descendants(matching: .any)["finances.subscriptionsCard"].firstMatch
        XCTAssertTrue(subscriptionsCard.waitForExistence(timeout: 10), "Subscriptions card not found")
        subscriptionsCard.tap()
        sleep(3)   // logos load and the calendar settles
        snap("09-subscriptions")
        let firstSubscription = app.descendants(matching: .any)["subscriptions.card"].firstMatch
        if firstSubscription.waitForExistence(timeout: 10) {
            firstSubscription.tap()
            sleep(3)
            snap("10-subscription-detail")
        }
        backToFinances()

        // ── 11. A deposit ────────────────────────────────────────────────────
        let depositsCard = app.descendants(matching: .any)["finances.depositsCard"].firstMatch
        XCTAssertTrue(depositsCard.waitForExistence(timeout: 10), "Deposits card not found")
        depositsCard.tap()
        let firstDeposit = app.cells.firstMatch
        if firstDeposit.waitForExistence(timeout: 10) {
            firstDeposit.tap()
            sleep(3)
            snap("11-deposit")
        }
        backToFinances()

        // ── 12. Loans (this month's payment status) ──────────────────────────
        let loansCard = app.descendants(matching: .any)["finances.loansCard"].firstMatch
        scrollUntilHittable(loansCard)
        if loansCard.exists {
            loansCard.tap()
            sleep(3)
            snap("12-loans")
            goBack()
        }
    }

    // MARK: - Helpers

    /// Swipes the page up until the card can be tapped (four swipes at most).
    private func scrollUntilHittable(_ element: XCUIElement) {
        var scrolls = 0
        while !(element.exists && element.isHittable) && scrolls < 4 {
            app.swipeUp()
            scrolls += 1
        }
    }

    /// Steps back until the Finances root shows again: a zoom-transition detail can swallow one
    /// back gesture, which left the next card out of reach on a slow simulator.
    private func backToFinances() {
        goBack(until: app.descendants(matching: .any)["finances.accountsCard"].firstMatch)
    }

    /// Steps back until `element` (a card on the Finances root, where the page was scrolled to)
    /// can be tapped again.
    private func goBack(until element: XCUIElement) {
        for _ in 0..<4 {
            if element.waitForExistence(timeout: 2) && element.isHittable { return }
            goBack()
        }
    }

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
