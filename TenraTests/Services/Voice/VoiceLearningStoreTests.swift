//
//  VoiceLearningStoreTests.swift
//  TenraTests
//
//  Covers record/recall + confidence-threshold semantics of the manual
//  correction learning store.
//

import XCTest
@testable import Tenra

final class VoiceLearningStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: VoiceLearningStore!
    private let suiteName = "voice.learning.tests"

    override func setUp() {
        super.setUp()
        // Use an ephemeral suite so production UserDefaults stays untouched.
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
        store = VoiceLearningStore(defaults: defaults)
    }

    override func tearDown() {
        store.reset()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testEmptyStoreReturnsNil() {
        XCTAssertNil(store.preferredAccountID(forCategory: "Transport"))
        XCTAssertNil(store.preferredAccountID(forCategory: nil))
    }

    func testSingleHitIsBelowConfidenceThreshold() {
        // One save isn't enough to override usage-based defaults — guards
        // against an accidental tap locking in the wrong account forever.
        store.recordSave(category: "Transport", accountId: "wallet")
        XCTAssertNil(store.preferredAccountID(forCategory: "Transport"))
    }

    func testTwoHitsCrossThreshold() {
        store.recordSave(category: "Transport", accountId: "wallet")
        store.recordSave(category: "Transport", accountId: "wallet")
        XCTAssertEqual(store.preferredAccountID(forCategory: "Transport"), "wallet")
    }

    func testHigherHitCountWins() {
        store.recordSave(category: "Food", accountId: "card")
        store.recordSave(category: "Food", accountId: "card")
        store.recordSave(category: "Food", accountId: "card")
        store.recordSave(category: "Food", accountId: "cash")
        store.recordSave(category: "Food", accountId: "cash")
        // card has 3 hits, cash has 2 → card wins.
        XCTAssertEqual(store.preferredAccountID(forCategory: "Food"), "card")
    }

    func testFilterExcludesUnusableAccount() {
        store.recordSave(category: "Food", accountId: "deleted")
        store.recordSave(category: "Food", accountId: "deleted")
        store.recordSave(category: "Food", accountId: "active")
        store.recordSave(category: "Food", accountId: "active")
        let result = store.preferredAccountID(forCategory: "Food") { $0 != "deleted" }
        XCTAssertEqual(result, "active")
    }

    func testCategoryNameIsCaseInsensitive() {
        store.recordSave(category: "Транспорт", accountId: "wallet")
        store.recordSave(category: "транспорт", accountId: "wallet")
        XCTAssertEqual(store.preferredAccountID(forCategory: "ТРАНСПОРТ"), "wallet")
    }

    func testNilCategoryShareBucket() {
        // nil and empty string map to the same bucket.
        store.recordSave(category: nil, accountId: "wallet")
        store.recordSave(category: "", accountId: "wallet")
        XCTAssertEqual(store.preferredAccountID(forCategory: nil), "wallet")
        XCTAssertEqual(store.preferredAccountID(forCategory: ""), "wallet")
    }

    func testResetClearsEverything() {
        store.recordSave(category: "Food", accountId: "card")
        store.recordSave(category: "Food", accountId: "card")
        XCTAssertEqual(store.preferredAccountID(forCategory: "Food"), "card")
        store.reset()
        XCTAssertNil(store.preferredAccountID(forCategory: "Food"))
    }

    func testPersistsAcrossInstances() {
        store.recordSave(category: "Transport", accountId: "wallet")
        store.recordSave(category: "Transport", accountId: "wallet")
        // New instance reads from the same UserDefaults suite.
        let fresh = VoiceLearningStore(defaults: defaults)
        XCTAssertEqual(fresh.preferredAccountID(forCategory: "Transport"), "wallet")
    }

    func testEmptyOrMissingAccountIDIsIgnored() {
        store.recordSave(category: "Food", accountId: nil)
        store.recordSave(category: "Food", accountId: "")
        XCTAssertNil(store.preferredAccountID(forCategory: "Food"))
    }
}
