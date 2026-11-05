//
//  FormatsUITests.swift
//  TenraUITests
//
//  Settings › Formats (docs/plan-formats.md §7, check 1): a format chosen on the open page
//  keeps the page (the stack is not reset to its root), Home writes the new format once the
//  person goes back, without a relaunch, and a page left open in another tab (Analytics'
//  health score) is still open. Then "Use the region's format" brings the region's back.
//
//  Simulator only: `-ScreenshotDemo` seeds the store and starts from the region's formats.
//  It must never run on a personal device (it overwrites UserDefaults and the store).
//

import XCTest

final class FormatsUITests: XCTestCase {

    private var app: XCUIApplication!

    /// "1,234": a comma between thousands, which Kazakhstan's region does not write.
    private let commaGrouped = NSPredicate(format: "label MATCHES %@", ".*\\d,\\d{3}.*")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testChosenSeparatorsKeepThePagesAndReachHome() throws {
        app = XCUIApplication()
        // English text in Kazakhstan's region: amounts read "1 234,56 $" to begin with.
        app.launchArguments += [
            "-ScreenshotDemo", "-NoRevenueCat",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_KZ"
        ]
        app.launch()

        let settingsButton = app.descendants(matching: .any)["home.settingsButton"].firstMatch
        let historyLink = app.descendants(matching: .any)["home.historyLink"].firstMatch
        XCTAssertTrue(historyLink.waitForExistence(timeout: 90), "Home did not load")
        snap("home-before")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(commaGrouped).firstMatch.exists,
            "Home already writes 1,234 in the region's format"
        )

        // A page open in Analytics: the health score.
        tab("Analytics").tap()
        let healthCard = app.descendants(matching: .any)["insights.healthScore"].firstMatch
        XCTAssertTrue(healthCard.waitForExistence(timeout: 60), "No health score card in Analytics")
        scrollIntoView(healthCard)
        healthCard.tap()
        let healthBar = app.navigationBars["Finance"]
        XCTAssertTrue(healthBar.waitForExistence(timeout: 10), "The health score page did not open")
        snap("analytics-health-before")

        // Home → the gear → Formats → Separators → 1,234.56
        tab("Home").tap()
        XCTAssertTrue(waitUntilHittable(settingsButton), "Not on Home")
        settingsButton.tap()
        let formatsRow = app.descendants(matching: .any)["settings.formats"].firstMatch
        XCTAssertTrue(formatsRow.waitForExistence(timeout: 15), "No Formats row in Settings")
        scrollIntoView(formatsRow)
        formatsRow.tap()

        let formatsBar = app.navigationBars["Formats"]
        XCTAssertTrue(formatsBar.waitForExistence(timeout: 10), "The Formats page did not open")
        let separatorsRow = app.descendants(matching: .any)["formats.separators"].firstMatch
        XCTAssertTrue(separatorsRow.waitForExistence(timeout: 5), "No Separators row")
        snap("formats-before")
        separatorsRow.tap()

        XCTAssertTrue(app.navigationBars["Separators"].waitForExistence(timeout: 5), "No Separators options page")
        let commaDot = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "1,234.56")).firstMatch
        XCTAssertTrue(commaDot.waitForExistence(timeout: 5), "No 1,234.56 option")
        snap("separators-options")
        commaDot.tap()

        // The choice takes the person back to Formats, and Formats stays: the tab roots
        // rebuild for the new format, their stacks do not. Settled once the preview writes
        // the new format.
        XCTAssertTrue(formatsBar.waitForExistence(timeout: 5), "Back from the options, Formats is gone")
        XCTAssertTrue(app.navigationBars["Separators"].waitForNonExistence(timeout: 5), "The options page stays")
        let previewChanged = app.descendants(matching: .any).matching(commaGrouped).firstMatch
        XCTAssertTrue(previewChanged.waitForExistence(timeout: 10), "The preview does not write 1,234")
        snap("formats-after")
        XCTAssertTrue(formatsBar.exists, "The new format reset the stack: Formats was closed")
        XCTAssertTrue(separatorsRow.label.contains("1,234.56"), "Separators does not show the choice: \(separatorsRow.label)")

        // Back twice: Settings, then Home, in the new format.
        goBack(until: formatsRow)
        goBack(until: settingsButton)
        let grouped = app.descendants(matching: .any).matching(commaGrouped).firstMatch
        let homeChanged = grouped.waitForExistence(timeout: 10)
        snap("home-after")
        XCTAssertTrue(homeChanged, "Home does not write 1,234 after the change")

        // Analytics: the health score page is where it was.
        tab("Analytics").tap()
        XCTAssertTrue(healthBar.waitForExistence(timeout: 10), "The format change closed the page open in Analytics")
        // Still there once the tab has rebuilt its feed (counted polls).
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            XCTAssertTrue(healthBar.exists, "The page open in Analytics closed after the tab showed")
        }
        snap("analytics-health-after")

        // The region's format again: the reset button shows while a choice differs from it.
        tab("Home").tap()
        XCTAssertTrue(waitUntilHittable(settingsButton), "Not on Home")
        settingsButton.tap()
        XCTAssertTrue(formatsRow.waitForExistence(timeout: 15), "No Formats row in Settings")
        scrollIntoView(formatsRow)
        formatsRow.tap()
        XCTAssertTrue(formatsBar.waitForExistence(timeout: 10), "The Formats page did not open again")
        let reset = app.buttons["Use the region's format"].firstMatch
        scrollIntoView(reset)
        XCTAssertTrue(reset.exists, "No reset button while the format differs from the region's")
        reset.tap()
        XCTAssertTrue(reset.waitForNonExistence(timeout: 5), "The reset button stays after the reset")
        XCTAssertFalse(separatorsRow.label.contains("1,234.56"), "The reset kept 1,234.56")
        snap("formats-reset")
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A tab of the bar, by its title.
    private func tab(_ title: String) -> XCUIElement {
        let button = app.tabBars.buttons[title].firstMatch
        return button.waitForExistence(timeout: 5) ? button : app.buttons[title].firstMatch
    }

    /// Counted polls (never a wall-clock deadline): true once `element` can be tapped.
    @discardableResult
    private func waitUntilHittable(_ element: XCUIElement, polls: Int = 50) -> Bool {
        for _ in 0..<polls {
            if element.exists && element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.exists && element.isHittable
    }

    /// The system back button (else a swipe from the left edge), until `screen` shows.
    private func goBack(until screen: XCUIElement) {
        for _ in 0..<3 {
            let back = app.buttons["BackButton"].firstMatch
            if back.exists && back.isHittable {
                back.tap()
            } else {
                let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
                edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            }
            if waitUntilHittable(screen, polls: 15) { return }
        }
        XCTFail("Going back did not reach \(screen)")
    }

    /// Slow swipes until `element` is on screen.
    private func scrollIntoView(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
    }
}
