//
//  DepositCrossCurrencyTransferTests.swift
//  TenraTests
//
//  M-1 (targeted fix): when a deposit is topped up by an internal transfer FROM an
//  account in a DIFFERENT currency, the amount credited to the deposit's running
//  principal must be the target-side amount (in the deposit's currency), not the
//  source-side `convertedAmount` (in the source account's currency). Otherwise
//  interest accrues on a wrong-currency principal.
//

import Testing
import Foundation
@testable import Tenra

@Suite("DepositInterestService.principalDelta — cross-currency transfer inflow")
struct DepositCrossCurrencyTransferTests {

    private let depositId = "dep-1"
    private let bankId = "bank-1"

    private func delta(_ t: Transaction, capitalization: Bool = false) -> Decimal {
        DepositInterestService.principalDelta(for: t, accountId: depositId, capitalizationEnabled: capitalization)
    }

    @Test("cross-currency transfer INTO deposit credits targetAmount (deposit currency)")
    func crossCurrencyInflowUsesTargetAmount() {
        // Deposit is USD. Transfer 100_000 KZT from a KZT bank → 220 USD into the deposit.
        // Principal must grow by 220 (USD), NOT 100_000 (the KZT source amount).
        let t = Transaction(
            id: UUID().uuidString, date: "2026-01-01", description: "topup",
            amount: 100_000, currency: "KZT", convertedAmount: 100_000,
            type: .internalTransfer, category: "", subcategory: nil,
            accountId: bankId, targetAccountId: depositId,
            accountName: nil, targetCurrency: "USD", targetAmount: 220
        )
        #expect(delta(t) == Decimal(220))
    }

    @Test("same-currency transfer INTO deposit still credits the amount")
    func sameCurrencyInflowUnchanged() {
        // No targetAmount → falls back to convertedAmount ?? amount (existing behavior).
        let t = Transaction(
            id: UUID().uuidString, date: "2026-01-01", description: "topup",
            amount: 5_000, currency: "KZT", convertedAmount: nil,
            type: .internalTransfer, category: "", subcategory: nil,
            accountId: bankId, targetAccountId: depositId,
            accountName: nil, targetCurrency: nil, targetAmount: nil
        )
        #expect(delta(t) == Decimal(5_000))
    }
}
