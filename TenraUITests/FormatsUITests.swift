//
//  FormatsUITests.swift
//  TenraUITests
//
//  Settings › Formats (docs/plan-formats.md §7, check 1): a format chosen on the open page
//  keeps the page (the stack is not reset to its root), and Home writes the new format once
//  the person goes back, without a relaunch. Then "Use the region's format" brings the
//  region's back.
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

    func testChosenSeparatorsKeepThePageAndReachHome() throws {
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

        // Home → the gear → Formats → Separators → 1,234.56
        settingsButton.tap()
        let formatsRow = app.descendants(matching: .any)["settings.formats"].firstMatch
        XCTAssertTrue(formatsRow.waitForExistence(timeout: 15), "No Formats row in Settings")
        scrollIntoView(formatsRow)
        formatsRow.tap()

        let formatsBar = app.navigationBars["Formats"]
        XCTAssertTrue(formatsBar.waitForExistence(timeout: 10), "The Formats page did not open")
        let separatorsRow = app.buttons["Separators"].firstMatch
        XCTAssertTrue(separatorsRow.waitForExistence(timeout: 5), "No Separators row")
        snap("formats-before")
        separatorsRow.tap()

        let commaDot = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "1,234.56")).firstMatch
        XCTAssertTrue(commaDot.waitForExistence(timeout: 5), "No 1,234.56 option")
        commaDot.tap()

        // The choice takes the person back to Formats, and Formats stays: the tab roots
        // rebuild for the new format, their stacks do not.
        XCTAssertTrue(formatsBar.waitForExistence(timeout: 5), "Back from the options, Formats is gone")
        sleep(2)
        snap("formats-after")
        XCTAssertTrue(formatsBar.exists, "The new format reset the stack: Formats was closed")
        XCTAssertEqual(separatorsRow.value as? String, "1,234.56", "Separators does not show the choice")

        // Back twice: Settings, then Home, in the new format.
        goBack()
        goBack()
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "Not back on Home")
        let grouped = app.descendants(matching: .any).matching(commaGrouped).firstMatch
        let homeChanged = grouped.waitForExistence(timeout: 10)
        snap("home-after")
        XCTAssertTrue(homeChanged, "Home does not write 1,234 after the change")

        // The region's format again: the reset button shows while a choice differs from it.
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
        XCTAssertNotEqual(separatorsRow.value as? String, "1,234.56", "The reset kept 1,234.56")
        snap("formats-reset")
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The system back button, else a swipe from the left edge.
    private func goBack() {
        let back = app.buttons["BackButton"].firstMatch
        if back.waitForExistence(timeout: 3) && back.isHittable {
            back.tap()
        } else {
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
            edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        }
        sleep(1)
    }

    /// Slow swipes until `element` is on screen.
    private func scrollIntoView(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
    }
}
