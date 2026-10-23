//
//  ScreenshotCaptureTests.swift
//  TenraUITests
//
//  Automated App Store screenshot capture. Launches the app in ScreenshotDemo
//  mode (seeded dataset, Pro unlocked, offline FX, Ten's answers scripted on the
//  phone) with the language/locale passed via TEST_RUNNER_* environment variables,
//  walks the marketing screens (01-08, 13-16 and the auto-capture 20-21 for the default
//  product page, 09-12 and Ten's 17-19 for the custom product pages: subscriptions,
//  currencies, a deposit, loans; the auto-capture page takes 20, 21, 09 and 01) and stores
//  full-resolution screenshots as keepAlways attachments.
//
//  Run via scripts/capture_screenshots.sh — it loops all storefront locales
//  and exports the attachments from the .xcresult bundles.
//
//  Environment (set with TEST_RUNNER_ prefix on xcodebuild):
//    SCREENSHOT_FRAMES         — "cpp" captures 02 and 09-12 (custom product pages), "ten"
//                                Ten's 07, 13, 14, 17-19, "autocapture" 20-21; default all
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
            // Only Ten's frames (07, 13, 14, 17-19): a quick run while they are being worked on.
            captureTen()
            return
        }

        if env["SCREENSHOT_FRAMES"] == "autocapture" {
            // Only the auto-capture frames (20-21): a quick run while they are being worked on.
            captureAutoCapture()
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
        // Last: it goes back to Home from Ten's chat, so a step it misses costs no other frame.
        captureAutoCapture()
    }

    // MARK: - Auto-capture

    /// 20-21 in Settings → Wallet, a sheet over Home: the Apple Pay payments the Wallet
    /// automation recorded with a guess (To review), then a merchant's own screen (Merchants →
    /// Starbucks, ScreenshotDemoSeeder). Starts anywhere, ends on Home with the sheet closed.
    private func captureAutoCapture() {
        guard showHome() else {
            debugSnapshot("autocapture-home")
            return
        }
        let settingsButton = app.descendants(matching: .any)["home.settingsButton"].firstMatch
        let toReview = app.descendants(matching: .any)["settings.wallet.toReview"].firstMatch
        let merchants = app.descendants(matching: .any)["settings.wallet.merchants"].firstMatch

        // ── 20. To review: payments that recorded themselves, with logos ─────
        // A cold first locale can drop a tap that lands before Home responds: tap again.
        for _ in 0..<3 where !toReview.exists && settingsButton.isHittable {
            settingsButton.tap()
            _ = toReview.waitForExistence(timeout: 15)
        }
        guard toReview.exists else {
            debugSnapshot("settings")
            closeSettings(showing: toReview)
            return
        }
        scrollIntoView(toReview)
        guard toReview.isHittable else {
            debugSnapshot("settings-wallet")
            closeSettings(showing: toReview)
            return
        }
        toReview.tap()
        // The list shows placeholders until the full load, then the payments; then the logos.
        if app.descendants(matching: .any)["walletReview.payment"].firstMatch.waitForExistence(timeout: 60) {
            sleep(5)
            snap("20-autocapture")
        } else {
            debugSnapshot("to-review")
        }
        backToSettings(showing: toReview)

        // ── 21. A merchant's own screen ──────────────────────────────────────
        scrollIntoView(merchants)
        guard merchants.exists, merchants.isHittable else {
            debugSnapshot("settings-merchants")
            closeSettings(showing: toReview)
            return
        }
        merchants.tap()
        let starbucks = app.descendants(matching: .any)["merchants.row.starbucks"].firstMatch
        let anyMerchant = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "merchants.row.")).firstMatch
        let merchant = starbucks.waitForExistence(timeout: 10) ? starbucks : anyMerchant
        if merchant.exists && merchant.isHittable {
            merchant.tap()
            sleep(5)   // the history sweep, the monthly chart and the logo
            snap("21-merchant")
        } else {
            debugSnapshot("merchants")
        }
        closeSettings(showing: toReview)
    }

    /// Home's root, wherever the run is: Ten's chat (where the default run ends) hides the tab
    /// bar, so step back until it shows, then take its first tab.
    private func showHome() -> Bool {
        let settingsButton = app.descendants(matching: .any)["home.settingsButton"].firstMatch
        for _ in 0..<4 {
            if settingsButton.exists && settingsButton.isHittable { return true }
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists && tabBar.isHittable {
                // A scrolled screen collapses the bar to the current tab and the action tab.
                for _ in 0..<3 where tabBar.buttons.count < 3 {
                    app.swipeDown()
                    sleep(1)
                }
                let homeTab = tabBar.buttons.element(boundBy: 0)
                if homeTab.exists && homeTab.isHittable {
                    homeTab.tap()
                    _ = settingsButton.waitForExistence(timeout: 10)
                }
            } else {
                goBack()
            }
        }
        return settingsButton.exists && settingsButton.isHittable
    }

    /// Scrolls until `element` is on screen: slow swipes, so a long page does not fly past it,
    /// and back down when it went up under the bar.
    private func scrollIntoView(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.maxY < app.frame.midY {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
    }

    /// Back inside the Settings sheet until its list shows `row` again: the system back button
    /// (Home's stack under the sheet is at its root, so the only one is the sheet's), else a swipe
    /// from the sheet's left edge. Not `goBack()`: Home's navigation bar under the sheet can
    /// answer its query first.
    private func backToSettings(showing row: XCUIElement) {
        for _ in 0..<3 {
            if row.exists && row.isHittable { return }
            let back = app.buttons["BackButton"].firstMatch
            if back.exists && back.isHittable {
                back.tap()
            } else {
                let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
                edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            }
            sleep(1)
        }
    }

    /// Closes the Settings sheet, from wherever it is: back to its list, then swipes down until
    /// the list is at its top and the next swipe takes the sheet down.
    private func closeSettings(showing row: XCUIElement) {
        backToSettings(showing: row)
        for _ in 0..<8 where row.exists {
            app.swipeDown()
            sleep(1)
        }
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

    /// 07, 14, 13, 17-19 on Ten's tab (the action tab): the voice sheet with the demo phrase as
    /// heard, that phrase drafted on the phone with Save, then the demo's questions answered on
    /// cards (ScreenshotDemoTransport: no network).
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

        // ── 13, 17-19. The demo's questions answered on cards ────────────────
        // In order: this month's spending, subscriptions, all currencies, an early loan payment
        // (the custom product pages' Ten frames). Each answer opens its own chat.
        let answers = ["13-ten-answer", "17-ten-subscriptions", "18-ten-currencies", "19-ten-loan"]
        for (index, frame) in answers.enumerated() {
            if index > 0 { goBack() }
            _ = presets.waitForExistence(timeout: 10)
            let chips = presets.buttons.allElementsBoundByIndex
            guard chips.indices.contains(index), chips[index].isHittable else {
                debugSnapshot("presets-\(index)")
                return
            }
            chips[index].tap()
            sleep(8)   // two scripted turns, the cards cascade in
            snap(frame)
        }
    }

    /// When a step of Ten's frames finds nothing: the screen and the accessibility tree, exported
    /// next to the frames as `90-debug-<step>` (the tree is text in a .png-named file).
    private func debugSnapshot(_ step: String) {
        snap("90-debug-\(step)")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "90-debug-\(step)-tree"
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
        // A card per deposit (DesignKit's CardList, no table cells).
        let firstDeposit = app.descendants(matching: .any)["deposits.card"].firstMatch
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
        // A scrolled screen collapses the bar to the current tab and the action tab
        // (`tabBarMinimizeBehavior(.onScrollDown)`): scroll back up until the tab is there.
        for _ in 0..<4 where tabBar.buttons.count <= index {
            app.swipeDown()
            sleep(1)
        }
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
