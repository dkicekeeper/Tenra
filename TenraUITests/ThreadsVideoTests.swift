//
//  ThreadsVideoTests.swift
//  TenraUITests
//
//  The scenes of the short Threads videos (docs/plan-threads-videos.md), one test per scene, on
//  the screenshot demo's data (-ScreenshotDemo, no RevenueCat) in Russian with tenge. Each step
//  waits 1-1.5 s and more where there is something to read, and scrolls slowly, so the recording
//  can be watched. The screen is recorded outside the test, in the Simulator only (never a phone:
//  the demo wipes the store), by `python3 scripts/threads_video.py record <id>`.
//
//  Each step prints `THREADS-MARK <step> <unix time>`: the cuts in social/videos/<id>.json are
//  "<step>@<seconds>", so they hold when a scene is recorded again. A new step keeps its name in
//  `mark(_:)` (scripts/test_threads_video.py checks the cuts against them).
//

import XCTest

final class ThreadsVideoTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-ScreenshotDemo", "-NoRevenueCat",
            "-AppleLanguages", "(ru)",
            "-AppleLocale", "ru_KZ"
        ]
        app.launchEnvironment["SCREENSHOT_DEMO_CURRENCY"] = "KZT"
        app.launch()

        let historyLink = app.descendants(matching: .any)["home.historyLink"].firstMatch
        XCTAssertTrue(historyLink.waitForExistence(timeout: 90), "Home did not load")
        // The full load: balances, the deposit's interest, the reveal animations.
        sleep(6)
        mark("home")
    }

    // MARK: - v-ten

    /// Ten's tab, "my spending this month" answered with a donut, then an early loan payment
    /// answered with the interest saved and the months sooner (ScreenshotDemoTransport).
    func testTen() throws {
        actionTabButton().tap()
        let presets = app.descendants(matching: .any)["assistant.presets"].firstMatch
        XCTAssertTrue(presets.waitForExistence(timeout: 30), "Ten's home did not load")
        sleep(3)   // Ten greets
        mark("ten-home")

        tapPreset(0, in: presets)
        mark("q-month")
        sleep(9)   // two scripted turns, the cards cascade in
        mark("a-month")
        sleep(4)

        goBack()
        XCTAssertTrue(presets.waitForExistence(timeout: 10), "Ten's home did not come back")
        sleep(1)
        mark("ten-home-2")
        tapPreset(3, in: presets)
        mark("q-loan")
        sleep(9)
        mark("a-loan")
        sleep(5)
        mark("end")
    }

    // MARK: - v-deposit

    /// Finances → deposits → the deposit: its balance, the interest so far this period, the rate
    /// with capitalization, then the monthly interest in its history.
    func testDeposit() throws {
        sleep(1)
        tabBarButton(at: 2).tap()
        let accountsCard = app.descendants(matching: .any)["finances.accountsCard"].firstMatch
        XCTAssertTrue(accountsCard.waitForExistence(timeout: 30), "Finances did not load")
        sleep(2)
        mark("finances")

        let depositsCard = app.descendants(matching: .any)["finances.depositsCard"].firstMatch
        XCTAssertTrue(depositsCard.waitForExistence(timeout: 10), "Deposits card not found")
        depositsCard.tap()
        let deposit = app.descendants(matching: .any)["deposits.card"].firstMatch
        XCTAssertTrue(deposit.waitForExistence(timeout: 10), "Deposit not found")
        sleep(2)
        mark("deposits")

        deposit.tap()
        sleep(4)   // the hero, the accrual, the history
        mark("deposit")

        slowScroll(0.3)
        sleep(4)
        mark("interest")

        slowScroll(0.35)
        sleep(4)
        mark("history")

        slowScroll(0.35)
        sleep(4)
        mark("end")
    }

    // MARK: - Helpers

    private func mark(_ step: String) {
        print("THREADS-MARK \(step) \(String(format: "%.3f", Date().timeIntervalSince1970))")
    }

    /// The demo's questions sit under Ten's card and the composer: a slow scroll brings them up.
    private func tapPreset(_ index: Int, in presets: XCUIElement) {
        let chips = presets.buttons.allElementsBoundByIndex
        XCTAssertTrue(chips.indices.contains(index), "Preset \(index) not found")
        let chip = chips[index]
        let composer = app.descendants(matching: .any)["assistant.composer"].firstMatch
        for _ in 0..<5 {
            let clear = chip.isHittable && (!composer.exists || chip.frame.maxY < composer.frame.minY - 12)
            if clear { break }
            slowScroll(0.25)
            sleep(1)
        }
        sleep(1)
        chip.tap()
    }

    /// A slow drag up by `fraction` of the screen with a hold at the end, so the page moves at a
    /// readable pace and does not fling on.
    private func slowScroll(_ fraction: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78 - fraction))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 350, thenHoldForDuration: 0.4)
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
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        }
        sleep(1)
    }
}
