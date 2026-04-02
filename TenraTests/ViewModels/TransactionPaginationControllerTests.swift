//
//  TransactionPaginationControllerTests.swift
//  AIFinanceManagerTests
//
//  Created on 2026-02-23
//  Task 9: Unit tests for TransactionPaginationController supporting types
//
//  Note: TransactionSection tests were removed because TransactionSection now requires
//  a live NSFetchedResultsSectionInfo (from CoreData FRC) and cannot be constructed
//  directly in unit tests. The formatter tests below cover the section key generation logic.
//

import Testing
import Foundation
import CoreData
@testable import AIFinanceManager

// MARK: - TransactionSectionKeyFormatter Tests

struct TransactionSectionKeyFormatterTests {

    @Test("Formatter returns YYYY-MM-DD for a known date")
    func testSectionKeyFormatterKnownDate() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 23
        let date = Calendar.current.date(from: components)!
        let key = TransactionSectionKeyFormatter.string(from: date)
        #expect(key == "2026-02-23")
    }

    @Test("Formatter zero-pads month and day")
    func testSectionKeyFormatterZeroPadding() {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 5
        let date = Calendar.current.date(from: components)!
        let key = TransactionSectionKeyFormatter.string(from: date)
        #expect(key == "2025-01-05")
    }

    @Test("Formatter returns consistent results for same date")
    func testSectionKeyFormatterConsistency() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        let date = Calendar.current.date(from: components)!
        let key1 = TransactionSectionKeyFormatter.string(from: date)
        let key2 = TransactionSectionKeyFormatter.string(from: date)
        #expect(key1 == key2)
    }
}
