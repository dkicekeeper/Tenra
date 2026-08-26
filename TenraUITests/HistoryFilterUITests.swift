//
//  HistoryFilterUITests.swift
//  TenraUITests
//
//  Regression guard: the History filter chips live in a `.safeAreaInset(.top)`
//  bar that competes with the navigation-bar search drawer for touches. Two
//  real bugs shipped here: (1) the default collapsible drawer claimed taps
//  over the bar unless the list was scrolled to the very top; (2) the
//  `displayMode: .always` fix for (1) made the chips untappable everywhere.
//  This test pins the contract: tapping the account chip opens its sheet.
//

import XCTest

final class HistoryFilterUITests: XCTestCase {

    private var app: XCUIApplication!

    private func launchToHistory() {
        app = XCUIApplication()
        // NO_DEMO=1 (TEST_RUNNER_NO_DEMO on xcodebuild) runs against the real app
        // data — for on-device repros. ScreenshotDemo must NEVER run on a personal
        // device: it overwrites UserDefaults and seeds the real CoreData store.
        if ProcessInfo.processInfo.environment["NO_DEMO"] != "1" {
            app.launchArguments += ["-ScreenshotDemo"]
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let historyLink = app.descendants(matching: .any)["home.historyLink"].firstMatch
        XCTAssertTrue(historyLink.waitForExistence(timeout: 90), "Home did not load")
        historyLink.tap()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertAccountSheetOpens(context: String) {
        let accountChip = app.buttons["All Accounts"].firstMatch
        XCTAssertTrue(accountChip.waitForExistence(timeout: 10), "Account filter chip not found (\(context))")
        snap("before-tap-\(context)")
        accountChip.tap()
        let sheetTitle = app.staticTexts["Accounts"].firstMatch
        let opened = sheetTitle.waitForExistence(timeout: 5)
        snap("after-tap-\(context)")
        XCTAssertTrue(opened, "Account filter sheet did not open (\(context)) — chip tap was swallowed")
        // Dismiss the sheet so callers can continue.
        if opened {
            app.swipeDown()
        }
    }

    func testAccountFilterChipOpensSheetAtTop() throws {
        launchToHistory()
        assertAccountSheetOpens(context: "at-top")
    }


    func testAccountFilterChipOpensSheetAfterScrollingDown() throws {
        launchToHistory()
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "History list not found")
        list.swipeUp()
        list.swipeUp()
        assertAccountSheetOpens(context: "scrolled-down")
    }

    // Search is a magnifying-glass toolbar button (`.searchToolbarBehavior(.minimize)`);
    // tapping it must expand the search field.
    func testSearchToolbarButtonExpandsField() throws {
        launchToHistory()
        let searchButton = app.buttons["Search"].firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10), "Search toolbar button not found")
        snap("before-search-tap")
        searchButton.tap()
        let field = app.searchFields.firstMatch
        let expanded = field.waitForExistence(timeout: 5)
        snap("after-search-tap")
        XCTAssertTrue(expanded, "Search field did not expand from the toolbar button")
    }
}
