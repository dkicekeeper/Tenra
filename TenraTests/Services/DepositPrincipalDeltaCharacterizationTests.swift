//
//  DepositPrincipalDeltaCharacterizationTests.swift
//  TenraTests
//
//  M-1 (HIGH RISK): `DepositInterestService.principalDelta` is a SECOND definition
//  of "how a tx moves a deposit", separate from `BalanceCalculationEngine.contribution`.
//  This file CHARACTERIZES the CURRENT behavior of `principalDelta` so any future
//  attempt to unify the two can prove (or disprove) behavior-identity.
//
//  ⚠️ These tests PIN existing behavior — they are NOT assertions that the current
//  behavior is "correct". principalDelta feeds interest-accrual math; changing it
//  corrupts accrued interest. See the divergence notes in docs/domains/deposits.md
//  and the TODO in DepositInterestService.principalDelta. DO NOT "fix" these to
//  match `contribution` without a deliberate, separately-reviewed decision.
//

import Testing
import Foundation
@testable import Tenra

@Suite("DepositInterestService.principalDelta characterization (M-1)")
struct DepositPrincipalDeltaCharacterizationTests {

    private let depositId = "dep-1"
    private let otherId = "other-1"

    private func tx(
        amount: Double,
        currency: String = "KZT",
        convertedAmount: Double? = nil,
        targetAmount: Double? = nil,
        targetCurrency: String? = nil,
        type: TransactionType,
        accountId: String?,
        targetAccountId: String? = nil
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: "2026-01-01",
            description: "char",
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmount,
            type: type,
            category: "",
            subcategory: nil,
            accountId: accountId,
            targetAccountId: targetAccountId,
            accountName: nil,
            targetCurrency: targetCurrency,
            targetAmount: targetAmount
        )
    }

    private func delta(_ t: Transaction, capitalization: Bool = false) -> Decimal {
        DepositInterestService.principalDelta(for: t, accountId: depositId, capitalizationEnabled: capitalization)
    }

    // MARK: - depositTopUp / income (inflow when deposit is source/account)

    @Test("depositTopUp on deposit adds amount")
    func depositTopUpAdds() {
        #expect(delta(tx(amount: 5_000, type: .depositTopUp, accountId: depositId)) == Decimal(5_000))
    }

    @Test("income tagged to deposit adds amount (principalDelta treats income as inflow)")
    func incomeAddsToPrincipal() {
        #expect(delta(tx(amount: 3_000, type: .income, accountId: depositId)) == Decimal(3_000))
    }

    @Test("inflow uses convertedAmount when present (NOT targetAmount)")
    func inflowPrefersConvertedAmount() {
        // principalDelta uses `convertedAmount ?? amount` — it ignores targetAmount.
        let t = tx(amount: 100, currency: "USD", convertedAmount: 44_250, targetAmount: 99_999,
                   type: .depositTopUp, accountId: depositId)
        #expect(delta(t) == Decimal(44_250))
    }

    @Test("inflow falls back to amount when convertedAmount is nil")
    func inflowFallsBackToAmount() {
        let t = tx(amount: 7_777, type: .depositTopUp, accountId: depositId)
        #expect(delta(t) == Decimal(7_777))
    }

    @Test("income on a DIFFERENT account contributes 0")
    func incomeOnOtherAccountZero() {
        #expect(delta(tx(amount: 3_000, type: .income, accountId: otherId)) == 0)
    }

    // MARK: - depositWithdrawal / expense (outflow)

    @Test("depositWithdrawal on deposit subtracts amount")
    func withdrawalSubtracts() {
        #expect(delta(tx(amount: 2_000, type: .depositWithdrawal, accountId: depositId)) == Decimal(-2_000))
    }

    @Test("expense tagged to deposit subtracts amount")
    func expenseSubtracts() {
        #expect(delta(tx(amount: 1_500, type: .expense, accountId: depositId)) == Decimal(-1_500))
    }

    // MARK: - depositInterestAccrual (capitalization-gated)

    @Test("interest accrual adds to principal ONLY when capitalization enabled")
    func interestAccrualGatedByCapitalization() {
        let t = tx(amount: 900, type: .depositInterestAccrual, accountId: depositId)
        #expect(delta(t, capitalization: true) == Decimal(900))
        #expect(delta(t, capitalization: false) == 0)
    }

    // MARK: - internalTransfer (asymmetric source/target handling)

    @Test("internalTransfer INTO deposit (target) adds convertedAmount ?? amount")
    func transferIntoDepositAdds() {
        // Target side uses convertedAmount ?? amount.
        let t = tx(amount: 100, currency: "USD", convertedAmount: 44_250,
                   type: .internalTransfer, accountId: otherId, targetAccountId: depositId)
        #expect(delta(t) == Decimal(44_250))
    }

    @Test("internalTransfer OUT of deposit (source) subtracts raw amount, NOT convertedAmount")
    func transferOutOfDepositSubtractsRawAmount() {
        // ⚠️ Source side uses -amount (raw), ignoring convertedAmount — asymmetric
        // with the target side. This is a key divergence from `contribution`, which
        // uses -(convertedAmount ?? amount) on the transfer source leg.
        let t = tx(amount: 5_000, currency: "KZT", convertedAmount: 9_999,
                   type: .internalTransfer, accountId: depositId, targetAccountId: otherId)
        #expect(delta(t) == Decimal(-5_000))
    }

    @Test("internalTransfer not touching deposit contributes 0")
    func transferUnrelatedZero() {
        let t = tx(amount: 5_000, type: .internalTransfer, accountId: otherId, targetAccountId: "third")
        #expect(delta(t) == 0)
    }

    // MARK: - loan types and default (excluded)

    @Test("loanPayment contributes 0 to deposit principal")
    func loanPaymentZero() {
        #expect(delta(tx(amount: 10_000, type: .loanPayment, accountId: depositId)) == 0)
    }

    @Test("loanEarlyRepayment contributes 0 to deposit principal")
    func loanEarlyRepaymentZero() {
        #expect(delta(tx(amount: 10_000, type: .loanEarlyRepayment, accountId: depositId)) == 0)
    }
}
