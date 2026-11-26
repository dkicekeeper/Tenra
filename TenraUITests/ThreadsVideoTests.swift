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

    // MARK: - v-loan

    /// The loan and its schedule, then an early repayment: the amount on the keypad, "reduce the
    /// term" with its result, "reduce the payment" with its, saved; then the schedule again, with
    /// the lower payment.
    func testLoan() throws {
        sleep(1)
        tabBarButton(at: 2).tap()
        let accountsCard = app.descendants(matching: .any)["finances.accountsCard"].firstMatch
        XCTAssertTrue(accountsCard.waitForExistence(timeout: 30), "Finances did not load")
        sleep(1)
        let loansCard = app.descendants(matching: .any)["finances.loansCard"].firstMatch
        for _ in 0..<5 where !(loansCard.exists && loansCard.isHittable) {
            slowScroll(0.3)
            sleep(1)
        }
        mark("finances")
        loansCard.tap()
        let loan = app.descendants(matching: .any)["loans.card"].firstMatch
        XCTAssertTrue(loan.waitForExistence(timeout: 10), "Loan not found")
        sleep(2)
        mark("loans")

        loan.tap()
        sleep(4)   // the hero, this month's payment, the statistics
        mark("loan")

        let schedule = app.descendants(matching: .any)["График платежей"].firstMatch
        scrollUp(until: schedule, nearTop: 0.3)
        sleep(4)
        mark("schedule")

        let early = app.buttons["Досрочное погашение"].firstMatch
        for _ in 0..<6 where !(early.exists && early.isHittable) {
            drag(from: 0.3, to: 0.75)
            sleep(1)
        }
        sleep(1)
        mark("actions")
        early.tap()
        sleep(2)
        mark("sheet")

        for digit in ["5", "0", "0", "0", "0", "0"] {
            app.buttons[digit].firstMatch.tap()
            usleep(350_000)
        }
        sleep(1)
        mark("amount")

        // The result sits under the strategy; the date buttons and the keypad cover the bottom
        // half (XCUITest still calls what is under them hittable), so up until it clears them.
        let dateButtons = app.buttons["Сегодня"].firstMatch
        scroll(until: label("Новая дата окончания"), above: dateButtons)
        sleep(3)
        mark("term")

        // Back up to the strategy, the other one, and its result.
        let reducePayment = app.buttons["Уменьшить платёж"].firstMatch
        for _ in 0..<4 where !(reducePayment.isHittable && reducePayment.frame.minY > app.frame.height * 0.18) {
            drag(from: 0.2, to: 0.42)
            sleep(1)
        }
        sleep(1)
        mark("strategy")
        reducePayment.tap()
        sleep(2)
        scroll(until: label("Новый ежемесячный платёж"), above: dateButtons)
        sleep(3)
        mark("payment")

        app.buttons["Сохранить"].firstMatch.tap()
        sleep(3)
        mark("saved")

        // The whole schedule, down to the payments after today: lower now.
        let showAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Показать все")).firstMatch
        for _ in 0..<8 where !(showAll.exists && showAll.isHittable) {
            slowScroll(0.3)
            sleep(1)
        }
        sleep(1)
        mark("schedule-2")
        showAll.tap()
        sleep(2)
        scrollUp(until: label("#7"), nearTop: 0.3)
        sleep(5)
        mark("end")
    }

    // MARK: - Helpers

    /// Slow drags up until `element` shows in the top `nearTop` of the screen.
    private func scrollUp(until element: XCUIElement, nearTop: CGFloat) {
        for _ in 0..<8 {
            if element.exists && element.isHittable && element.frame.minY < app.frame.height * nearTop { return }
            slowScroll(0.3)
            sleep(1)
        }
    }

    /// Any element with this text: a row's title may sit inside a combined element.
    private func label(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", text, text + ",")).firstMatch
    }

    /// Slow drags up until `element` shows above `limit` (what covers the bottom of the screen).
    private func scroll(until element: XCUIElement, above limit: XCUIElement) {
        for _ in 0..<5 {
            if element.exists && limit.exists && element.frame.maxY < limit.frame.minY - 8 { return }
            drag(from: 0.42, to: 0.2)
            sleep(1)
        }
    }

    /// A slow drag between two heights (fractions of the screen), held at the end so it does not fling.
    private func drag(from start: CGFloat, to end: CGFloat) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: 350, thenHoldForDuration: 0.4)
    }

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
