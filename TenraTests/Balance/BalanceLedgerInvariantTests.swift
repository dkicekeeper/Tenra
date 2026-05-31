//
//  BalanceLedgerInvariantTests.swift
//  TenraTests
//
//  The core invariant for the data-integrity refactor: applying transactions
//  INCREMENTALLY (BalanceCoordinator add/remove) must produce the same balances
//  as a FULL RECALCULATION of the same data. Any divergence is the "same derived
//  fact via two algorithms" bug class. These tests pin the invariant for the two
//  known offenders — loan-payment target legs and the deposit startDate cutoff —
//  so the unified `contribution()` path keeps them in lockstep.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct BalanceLedgerInvariantTests {

    private static func makeCoordinator() -> BalanceCoordinator {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        return BalanceCoordinator(repository: repo)
    }

    private static func pastDate(daysAgo: Int = 10) -> String {
        DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        )
    }

    @Test("Incremental balance equals full recalc for a loan payment (both legs)")
    func loanPaymentLegConsistency() async {
        let coordinator = Self.makeCoordinator()
        let bank = Account(id: "bank", name: "Bank", currency: "KZT", initialBalance: 200_000, balance: 200_000)
        let loan = Account(id: "loan", name: "Loan", currency: "KZT", initialBalance: 500_000, balance: 500_000)
        await coordinator.registerAccounts([bank, loan])
        await coordinator.setInitialBalance(200_000, for: "bank")
        await coordinator.setInitialBalance(500_000, for: "loan")

        let pay = Transaction(
            id: "p1", date: Self.pastDate(), description: "",
            amount: 50_000, currency: "KZT", convertedAmount: nil,
            type: .loanPayment, category: "", subcategory: nil,
            accountId: "bank", targetAccountId: "loan"
        )

        await coordinator.updateForTransaction(pay, operation: .add(pay))
        let incBank = coordinator.balances["bank"]
        let incLoan = coordinator.balances["loan"]

        await coordinator.recalculateAll(accounts: [bank, loan], transactions: [pay])
        let recBank = coordinator.balances["bank"]
        let recLoan = coordinator.balances["loan"]

        #expect(incBank == recBank)
        #expect(incLoan == recLoan)
    }

    @Test("Incremental balance equals full recalc with deposit startDate cutoff")
    func depositStartDateCutoffConsistency() async {
        let coordinator = Self.makeCoordinator()
        let info = DepositInfo(
            bankName: "T",
            initialPrincipal: 1_000_000,
            capitalizationEnabled: false,
            interestRateAnnual: 0,
            interestRateHistory: [RateChange(effectiveFrom: "2026-01-01", annualRate: 0)],
            interestPostingDay: 1,
            lastInterestCalculationDate: "2026-01-01",
            lastInterestPostingMonth: "2026-01-01",
            interestAccruedForCurrentPeriod: 0,
            startDate: "2026-01-01"
        )
        let deposit = Account(id: "dep", name: "Dep", currency: "KZT", depositInfo: info,
                              initialBalance: 1_000_000, balance: 1_000_000)
        await coordinator.registerAccounts([deposit])
        await coordinator.setInitialBalance(1_000_000, for: "dep")

        // A top-up dated on/before the deposit startDate is baked into initialPrincipal —
        // full recalc skips it (cutoff). Incremental must skip it too.
        let preStartTopUp = Transaction(
            id: "t0", date: "2025-12-15", description: "",
            amount: 30_000, currency: "KZT", convertedAmount: nil,
            type: .depositTopUp, category: "", subcategory: nil,
            accountId: "dep", targetAccountId: nil
        )

        await coordinator.updateForTransaction(preStartTopUp, operation: .add(preStartTopUp))
        let inc = coordinator.balances["dep"]

        await coordinator.recalculateAll(accounts: [deposit], transactions: [preStartTopUp])
        let rec = coordinator.balances["dep"]

        #expect(inc == rec)
    }

    @Test("Converting an account with history to a deposit doesn't double-count it on recalc")
    func convertedDepositRecalcDoesNotDoubleCountHistory() async {
        let coordinator = Self.makeCoordinator()

        let today = DateFormatters.dateFormatter.string(from: Date())
        // The conversion sets startDate to the start of the open interest period — a date
        // in the PAST — so inherited history dated after it is NOT filtered by the deposit
        // cutoff. That is exactly what lets the .fromInitialBalance recalc double-count it.
        let pastStart = Self.pastDate(daysAgo: 30)

        // A deposit produced by converting a regular account that held 1,000,000. The
        // snapshot (initialPrincipal / balance) ALREADY includes all prior history. The
        // conversion fix marks the account preserveImported so the cold-launch full recalc
        // keeps the live balance instead of re-summing the inherited transactions on top
        // of the snapshot.
        let info = DepositInfo(
            bankName: "T",
            initialPrincipal: 1_000_000,
            capitalizationEnabled: false,
            interestRateAnnual: 0,
            interestRateHistory: [RateChange(effectiveFrom: pastStart, annualRate: 0)],
            interestPostingDay: 1,
            lastInterestCalculationDate: pastStart,
            lastInterestPostingMonth: pastStart,
            interestAccruedForCurrentPeriod: 0,
            startDate: pastStart
        )
        let deposit = Account(id: "dep", name: "Dep", currency: "KZT", depositInfo: info,
                              initialBalance: 1_000_000, balance: 1_000_000)
        await coordinator.registerAccounts([deposit])
        await coordinator.setInitialBalance(1_000_000, for: "dep")
        await coordinator.markAsImported("dep")

        // Inherited pre-conversion income that already built the 1,000,000 snapshot.
        let inheritedIncome = Transaction(
            id: "inh", date: Self.pastDate(daysAgo: 10), description: "",
            amount: 1_000_000, currency: "KZT", convertedAmount: nil,
            type: .income, category: "Salary", subcategory: nil,
            accountId: "dep", targetAccountId: nil
        )
        // Post-conversion transfer out (the user's "перевод с депозита на другой счёт").
        let transferOut = Transaction(
            id: "out", date: today, description: "",
            amount: 491_070.36, currency: "KZT", convertedAmount: nil,
            type: .internalTransfer, category: "", subcategory: nil,
            accountId: "dep", targetAccountId: "other"
        )

        await coordinator.updateForTransaction(transferOut, operation: .add(transferOut))
        let inc = coordinator.balances["dep"]

        await coordinator.recalculateAll(accounts: [deposit], transactions: [inheritedIncome, transferOut])
        let rec = coordinator.balances["dep"]

        // The invariant: cold recalc must equal the incrementally-maintained balance.
        // Before the fix the recalc re-added the inherited 1,000,000 (and re-applied the
        // transfer), diverging into a large wrong (often negative) balance — the bug the
        // user hit, where a converted deposit showed ≈ -1.5M days after a transfer.
        #expect(inc == rec)
        #expect(rec == 1_000_000 - 491_070.36)
    }
}
