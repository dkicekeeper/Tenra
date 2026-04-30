//
//  BalanceCalculationEngineTests.swift
//  TenraTests
//
//  Verifies that deposit accounts flow through the standard balance pipeline,
//  with no special-case gating on .income/.expense/.internalTransfer.
//

import Testing
import Foundation
@testable import Tenra

@Suite("BalanceCalculationEngine — unified deposit pipeline")
struct BalanceCalculationEngineTests {

    private let engine = BalanceCalculationEngine()

    private func depositAccountBalance(
        id: String = "d1",
        currency: String = "KZT",
        currentBalance: Double = 100_000
    ) -> AccountBalance {
        AccountBalance(
            accountId: id,
            currentBalance: currentBalance,
            initialBalance: currentBalance,
            depositInfo: DepositInfo(
                bankName: "T",
                initialPrincipal: Decimal(currentBalance),
                capitalizationEnabled: false,
                interestRateAnnual: 0,
                interestRateHistory: [RateChange(effectiveFrom: "2020-01-01", annualRate: 0)],
                interestPostingDay: 1,
                lastInterestCalculationDate: "2020-01-01",
                lastInterestPostingMonth: "2020-01-01",
                interestAccruedForCurrentPeriod: 0,
                startDate: "2020-01-01"
            ),
            currency: currency,
            isDeposit: true
        )
    }

    private func nonDepositAccountBalance(
        id: String = "a1",
        currency: String = "KZT",
        currentBalance: Double = 100_000
    ) -> AccountBalance {
        AccountBalance(
            accountId: id,
            currentBalance: currentBalance,
            initialBalance: currentBalance,
            currency: currency,
            isDeposit: false
        )
    }

    private func incomeTx(amount: Double, accountId: String) -> Transaction {
        Transaction(
            id: "i", date: "2026-01-01", description: "",
            amount: amount, currency: "KZT", convertedAmount: nil,
            type: .income, category: "Salary", subcategory: nil,
            accountId: accountId, targetAccountId: nil
        )
    }

    @Test("applyTransaction: .income behaves identically on deposit and regular account")
    func applyIncome_unified() {
        let deposit = depositAccountBalance(currentBalance: 100_000)
        let regular = nonDepositAccountBalance(currentBalance: 100_000)
        let txD = incomeTx(amount: 25_000, accountId: deposit.accountId)
        let txR = incomeTx(amount: 25_000, accountId: regular.accountId)
        #expect(engine.applyTransaction(txD, to: 100_000, for: deposit) == 125_000)
        #expect(engine.applyTransaction(txR, to: 100_000, for: regular) == 125_000)
    }

    @Test("applyTransaction: internal transfer target adds for both deposit and regular")
    func applyTransferTarget_unified() {
        let deposit = depositAccountBalance(currentBalance: 100_000)
        let regular = nonDepositAccountBalance(currentBalance: 100_000)
        let tx = Transaction(
            id: "t", date: "2026-01-01", description: "",
            amount: 30_000, currency: "KZT", convertedAmount: nil,
            type: .internalTransfer, category: "", subcategory: nil,
            accountId: "src", targetAccountId: deposit.accountId,
            targetAmount: 30_000
        )
        #expect(engine.applyTransaction(tx, to: 100_000, for: deposit, isSource: false) == 130_000)
        let txR = Transaction(
            id: "t2", date: "2026-01-01", description: "",
            amount: 30_000, currency: "KZT", convertedAmount: nil,
            type: .internalTransfer, category: "", subcategory: nil,
            accountId: "src", targetAccountId: regular.accountId,
            targetAmount: 30_000
        )
        #expect(engine.applyTransaction(txR, to: 100_000, for: regular, isSource: false) == 130_000)
    }

    @Test("revertTransaction: .income subtracts for both deposit and regular")
    func revertIncome_unified() {
        let deposit = depositAccountBalance(currentBalance: 125_000)
        let regular = nonDepositAccountBalance(currentBalance: 125_000)
        let tx = incomeTx(amount: 25_000, accountId: deposit.accountId)
        #expect(engine.revertTransaction(tx, from: 125_000, for: deposit) == 100_000)
        #expect(engine.revertTransaction(tx, from: 125_000, for: regular) == 100_000)
    }
}
