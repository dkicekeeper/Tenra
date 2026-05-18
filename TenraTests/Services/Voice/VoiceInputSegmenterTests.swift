//
//  VoiceInputSegmenterTests.swift
//  TenraTests
//
//  Tests for VoiceInputSegmenter — clause splitting heuristics.
//

import XCTest
@testable import Tenra

final class VoiceInputSegmenterTests: XCTestCase {

    // MARK: - No split cases

    func testEmpty() {
        XCTAssertEqual(VoiceInputSegmenter.segment(""), [])
        XCTAssertEqual(VoiceInputSegmenter.segment("   "), [])
    }

    func testSingleClauseStaysIntact() {
        XCTAssertEqual(
            VoiceInputSegmenter.segment("500 тенге на такси"),
            ["500 тенге на такси"]
        )
    }

    func testConjunctionWithoutAmountOnBothSidesDoesNotSplit() {
        // "и" sits inside a single shopping list — only one amount in the text.
        XCTAssertEqual(
            VoiceInputSegmenter.segment("500 тенге на молоко и хлеб"),
            ["500 тенге на молоко и хлеб"]
        )
    }

    func testCommaInsideSingleAmountFragmentDoesNotSplit() {
        // No second amount → no split, even with a comma.
        XCTAssertEqual(
            VoiceInputSegmenter.segment("купил продукты, пошёл домой"),
            ["купил продукты, пошёл домой"]
        )
    }

    // MARK: - Split cases

    func testSplitOnAndWithTwoAmounts() {
        let clauses = VoiceInputSegmenter.segment("500 тенге на такси и 3000 тенге на продукты")
        XCTAssertEqual(clauses.count, 2)
        XCTAssertEqual(clauses[0], "500 тенге на такси")
        XCTAssertEqual(clauses[1], "3000 тенге на продукты")
    }

    func testSplitOnPotomWithTwoAmounts() {
        let clauses = VoiceInputSegmenter.segment("250 за кофе потом 1500 за обед")
        XCTAssertEqual(clauses.count, 2)
        XCTAssertEqual(clauses[0], "250 за кофе")
        XCTAssertEqual(clauses[1], "1500 за обед")
    }

    func testSplitOnPlusWithTwoAmounts() {
        let clauses = VoiceInputSegmenter.segment("100 рублей такси плюс 200 рублей метро")
        XCTAssertEqual(clauses.count, 2)
        XCTAssertEqual(clauses[0], "100 рублей такси")
        XCTAssertEqual(clauses[1], "200 рублей метро")
    }

    func testSplitOnAlsoVariants() {
        let clauses = VoiceInputSegmenter.segment("500 на хлеб а также 700 на молоко")
        XCTAssertEqual(clauses.count, 2)
        XCTAssertEqual(clauses[0], "500 на хлеб")
        XCTAssertEqual(clauses[1], "700 на молоко")
    }

    func testThreeClauses() {
        let clauses = VoiceInputSegmenter.segment("500 такси и 1000 продукты и 200 кофе")
        XCTAssertEqual(clauses.count, 3)
        XCTAssertEqual(clauses[0], "500 такси")
        XCTAssertEqual(clauses[1], "1000 продукты")
        XCTAssertEqual(clauses[2], "200 кофе")
    }

    func testSplitOnCommaSeparator() {
        let clauses = VoiceInputSegmenter.segment("500 на такси, 3000 на продукты")
        XCTAssertEqual(clauses.count, 2)
        XCTAssertEqual(clauses[0], "500 на такси")
        XCTAssertEqual(clauses[1], "3000 на продукты")
    }

    func testWordAmountsTriggerSplit() {
        // Words like "тысяча", "пятьсот" count as amount markers.
        let clauses = VoiceInputSegmenter.segment("пятьсот тенге такси и тысяча тенге продукты")
        XCTAssertEqual(clauses.count, 2)
        XCTAssertEqual(clauses[0], "пятьсот тенге такси")
        XCTAssertEqual(clauses[1], "тысяча тенге продукты")
    }

    // MARK: - Trimming and edge cases

    func testTrailingConjunctionDropped() {
        // "и" at the end with no following amount → no split, whole text returned.
        let clauses = VoiceInputSegmenter.segment("500 на такси и")
        XCTAssertEqual(clauses, ["500 на такси и"])
    }

    func testInputIsTrimmed() {
        let clauses = VoiceInputSegmenter.segment("   500 на такси и 3000 на продукты   ")
        XCTAssertEqual(clauses.count, 2)
        XCTAssertEqual(clauses[0], "500 на такси")
        XCTAssertEqual(clauses[1], "3000 на продукты")
    }
}
