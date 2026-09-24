//
//  LegacyDepositDiagnosticsTests.swift
//  TenraTests
//
//  The read-only diagnostic flags deposits without a conversion marker that
//  carry inherited plain rows after startDate or negative accrued interest.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct LegacyDepositDiagnosticsTests {

    private func deposit(id: String, accrued: Decimal = 0, converted: Bool = false) -> Account {
        var info = DepositInfo(
            bankName: "T",
            initialPrincipal: 100_000,
            capitalizationEnabled: false,
            interestRateAnnual: 12,
            interestRateHistory: [RateChange(effectiveFrom: "2026-01-01", annualRate: 12)],
            interestPostingDay: 1,
            lastInterestCalculationDate: "2026-01-01",
            lastInterestPostingMonth: "2026-01-01",
            interestAccruedForCurrentPeriod: accrued,
            startDate: "2026-01-01"
        )
        if converted { info.conversionTimestamp = 1_780_000_000 }
        return Account(id: id, name: id, currency: "KZT", depositInfo: info, initialBalance: 100_000)
    }

    private func row(_ account: String, _ type: TransactionType, _ date: String) -> Transaction {
        Transaction(id: UUID().uuidString, date: date, description: "", amount: 1000, currency: "KZT",
                    type: type, category: "", accountId: account)
    }

    @Test func freshDepositWithOnlyDepositRowsIsClean() {
        let reports = LegacyDepositDiagnostics.inspect(
            accounts: [deposit(id: "fresh")],
            transactions: [row("fresh", .depositTopUp, "2026-02-01"), row("fresh", .depositInterestAccrual, "2026-03-01")]
        )
        #expect(reports.first?.isSuspicious == false)
    }

    @Test func inheritedPlainRowsAreFlagged() {
        let reports = LegacyDepositDiagnostics.inspect(
            accounts: [deposit(id: "legacy")],
            transactions: [row("legacy", .expense, "2026-02-01"), row("legacy", .income, "2025-12-01")]
        )
        #expect(reports.first?.plainRowsAfterStart == 1)
        #expect(reports.first?.isSuspicious == true)
    }

    @Test func negativeAccruedInterestIsFlagged() {
        let reports = LegacyDepositDiagnostics.inspect(accounts: [deposit(id: "neg", accrued: -12_817)], transactions: [])
        #expect(reports.first?.isSuspicious == true)
    }

    @Test func depositsWithConversionMarkerAreSkipped() {
        #expect(LegacyDepositDiagnostics.inspect(accounts: [deposit(id: "new", converted: true)], transactions: []).isEmpty)
    }
}
