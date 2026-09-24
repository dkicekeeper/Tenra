//
//  ImportDuplicateDetectorTests.swift
//  TenraTests
//
//  Pins which statement rows the review screen flags as already in Tenra:
//  plain duplicates (same account/type/currency/amount within a day) and
//  auto-generated subscription occurrences (±3 days, ±5%).
//

import Testing
import Foundation
@testable import Tenra

struct ImportDuplicateDetectorTests {

    private func row(_ id: String, _ amount: Double, _ date: String, type: TransactionType = .expense, currency: String = "KZT") -> Transaction {
        Transaction(id: id, date: date, description: "BANK ROW", amount: amount, currency: currency,
                    type: type, category: "", accountId: nil)
    }

    private func saved(_ id: String, _ amount: Double, _ date: String, account: String = "a1",
                       type: TransactionType = .expense, series: String? = nil) -> Transaction {
        Transaction(id: id, date: date, description: "manual", amount: amount, currency: "KZT",
                    type: type, category: "Food", accountId: account, recurringSeriesId: series)
    }

    private func detect(_ imported: [Transaction], _ existing: [Transaction], account: String? = "a1") -> [String: ImportDuplicateDetector.Reason] {
        var accounts: [String: String] = [:]
        if let account { for r in imported { accounts[r.id] = account } }
        return ImportDuplicateDetector.detect(imported: imported, importedAccounts: accounts, existing: existing)
    }

    @Test func sameAmountNextDayIsAlreadyAdded() {
        let result = detect([row("r1", 2500, "2026-09-02")], [saved("e1", 2500, "2026-09-01")])
        #expect(result["r1"] == .alreadyAdded(existingId: "e1"))
    }

    @Test func twoDaysApartIsNotFlagged() {
        #expect(detect([row("r1", 2500, "2026-09-03")], [saved("e1", 2500, "2026-09-01")]).isEmpty)
    }

    @Test func differentAccountIsNotFlagged() {
        #expect(detect([row("r1", 2500, "2026-09-01")], [saved("e1", 2500, "2026-09-01", account: "a2")]).isEmpty)
    }

    @Test func subscriptionOccurrenceWithinToleranceIsFlagged() {
        let result = detect([row("r1", 5140, "2026-09-03")], [saved("occ", 4990, "2026-09-05", series: "netflix")])
        #expect(result["r1"] == .subscriptionOccurrence(existingId: "occ", seriesId: "netflix"))
    }

    @Test func subscriptionOccurrenceOutsideToleranceIsNotFlagged() {
        #expect(detect([row("r1", 5500, "2026-09-05")], [saved("occ", 4990, "2026-09-05", series: "netflix")]).isEmpty)
    }

    @Test func oneExistingTransactionIsClaimedOnce() {
        let result = detect(
            [row("r1", 2500, "2026-09-01"), row("r2", 2500, "2026-09-01")],
            [saved("e1", 2500, "2026-09-01")]
        )
        #expect(result.count == 1)
    }

    @Test func rowWithoutAccountIsNeverFlagged() {
        #expect(detect([row("r1", 2500, "2026-09-01")], [saved("e1", 2500, "2026-09-01")], account: nil).isEmpty)
    }

    @Test func subscriptionMatchWinsOverPlainMatch() {
        let result = detect(
            [row("r1", 4990, "2026-09-05")],
            [saved("plain", 4990, "2026-09-05"), saved("occ", 4990, "2026-09-05", series: "netflix")]
        )
        #expect(result["r1"] == .subscriptionOccurrence(existingId: "occ", seriesId: "netflix"))
    }

    @Test func differentTypeIsNotFlagged() {
        #expect(detect([row("r1", 2500, "2026-09-01", type: .income)], [saved("e1", 2500, "2026-09-01")]).isEmpty)
    }
}
