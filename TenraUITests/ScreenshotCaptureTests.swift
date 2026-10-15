//
//  ScreenshotCaptureTests.swift
//  TenraUITests
//
//  Automated App Store screenshot capture. Launches the app in ScreenshotDemo
//  mode (seeded dataset, Pro unlocked, offline FX, Ten's answers scripted on the
//  phone) with the language/locale passed via TEST_RUNNER_* environment variables,
//  walks the marketing screens (01-08 and 13-16 on the default product page, 09-12
//  for the custom product pages: subscriptions, a deposit, loans) and stores
//  full-resolution screenshots as keepAlways attachments.
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

        if env["SCREENSHOT_FRAMES"] == "ten" {
            // Only Ten's frames (07, 13, 14): a quick run while they are being worked on.
            captureTen()
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
        captureGoalsAndDebts()
        captureTen()
    }

    // MARK: - Goals and debts

    /// 15-16: a goal with what to put aside each month, then the debts with one overdue. Starts
    /// and ends on the Finances tab.
    private func captureGoalsAndDebts() {
        let goalsCard = app.descendants(matching: .any)["finances.goalsCard"].firstMatch
        scrollUntilHittable(goalsCard)
        XCTAssertTrue(goalsCard.exists, "Goals card not found")
        goalsCard.tap()
        let goal = app.descendants(matching: .any)["goals.card"].firstMatch
        if goal.waitForExistence(timeout: 10) {
            goal.tap()
            sleep(3)   // the hero's progress settles
            snap("15-goal")
        }
        // The Finances root is scrolled down here: its accounts card is out of reach, so
        // waiting for it would step back once too often and tap the root's own toolbar.
        backToFinances(showing: goalsCard)

        let debtsCard = app.descendants(matching: .any)["finances.debtsCard"].firstMatch
        scrollUntilHittable(debtsCard)
        XCTAssertTrue(debtsCard.exists, "Debts card not found")
        debtsCard.tap()
        _ = app.descendants(matching: .any)["debts.card"].firstMatch.waitForExistence(timeout: 10)
        sleep(2)
        snap("16-debts")
        backToFinances(showing: debtsCard)
    }

    // MARK: - Ten

    /// 07, 14, 13 on Ten's tab (the action tab): the voice sheet with the demo phrase as heard,
    /// that phrase drafted on the phone with Save, then a ready-made question answered on cards
    /// (ScreenshotDemoTransport: no network).
    private func captureTen() {
        // The tab bar collapses on scroll down (`tabBarMinimizeBehavior(.onScrollDown)`): scroll
        // Finances back up, then take the action tab, the bar's last button in either state.
        for _ in 0..<3 { app.swipeDown() }
        actionTabButton().tap()
        let presets = app.descendants(matching: .any)["assistant.presets"].firstMatch
        XCTAssertTrue(presets.waitForExistence(timeout: 30), "Ten's home did not load")
        sleep(3)   // Ten greets

        // ── 7. Voice: the composer's microphone (its right-most button while the field is empty) ──
        let composer = app.descendants(matching: .any)["assistant.composer"].firstMatch
        let microphone = composer.buttons.allElementsBoundByIndex.max { $0.frame.maxX < $1.frame.maxX }
        guard let microphone, microphone.isHittable else {
            debugSnapshot("composer")
            return
        }
        microphone.tap()
        let orb = app.descendants(matching: .any)["assistant.voice.orb"].firstMatch
        guard orb.waitForExistence(timeout: 10) else {
            debugSnapshot("voice")
            return
        }
        sleep(2)
        snap("07-voice")
        orb.tap()

        // ── 14. What was said, drafted on the phone ──────────────────────────
        let send = app.descendants(matching: .any)["assistant.voice.send"].firstMatch
        guard send.waitForExistence(timeout: 10) else {
            debugSnapshot("send")
            return
        }
        send.tap()
        sleep(5)
        snap("14-ten-draft")
        goBack()

        // ── 13. A ready-made question answered on cards ──────────────────────
        _ = presets.waitForExistence(timeout: 10)
        guard let preset = presets.buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            debugSnapshot("presets")
            return
        }
        preset.tap()
        sleep(8)   // two scripted turns, the cards cascade in
        snap("13-ten-answer")
    }

    /// When a step of Ten's frames finds nothing: the screen and the accessibility tree, exported
    /// next to the frames as `19-debug-<step>` (the tree is text in a .png-named file).
    private func debugSnapshot(_ step: String) {
        snap("19-debug-\(step)")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "19-debug-\(step)-tree"
        tree.lifetime = .keepAlways
        add(tree)
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
        var loanScrolls = 0
        while !(loansCard.exists && loansCard.isHittable) && loanScrolls < 4 {
            app.swipeUp()
            loanScrolls += 1
        }
        if loansCard.exists {
            loansCard.tap()
            sleep(3)
            snap("12-loans")
            goBack()
        }
    }

    // MARK: - Helpers

    private func scrollUntilHittable(_ element: XCUIElement) {
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
    }

    /// Steps back until the Finances root shows again: a zoom-transition detail can swallow one
    /// back gesture, which left the next card out of reach on a slow simulator. `card` is one
    /// the root shows at its current scroll (the accounts card unless it was scrolled).
    private func backToFinances(showing card: XCUIElement? = nil) {
        let marker = card ?? app.descendants(matching: .any)["finances.accountsCard"].firstMatch
        for _ in 0..<4 {
            if marker.waitForExistence(timeout: 2) && marker.isHittable { return }
            goBack()
        }
    }

    private func actionTabButton() -> XCUIElement {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "Tab bar not found")
        return tabBar.buttons.allElementsBoundByIndex.last ?? tabBar.buttons.firstMatch
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
