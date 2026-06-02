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
        // startDate sits at the open interest-period start (a PAST date), so inherited history
        // dated after it is NOT filtered by the legacy date cutoff. The conversionTimestamp
        // (createdAt-based) cutoff is what correctly excludes it instead.
        let pastStart = Self.pastDate(daysAgo: 30)
        let conversionMoment = Date().timeIntervalSince1970

        // A deposit produced by converting a regular account that held 1,000,000. The
        // snapshot (initialPrincipal / balance) ALREADY includes all prior history; the
        // conversion stamps conversionTimestamp so the cold-launch full recalc excludes any
        // tx that existed at conversion (createdAt <= it) instead of re-summing them.
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
            startDate: pastStart,
            conversionTimestamp: conversionMoment
        )
        let deposit = Account(id: "dep", name: "Dep", currency: "KZT", depositInfo: info,
                              initialBalance: 1_000_000, balance: 1_000_000)
        await coordinator.registerAccounts([deposit])
        await coordinator.setInitialBalance(1_000_000, for: "dep")

        // Inherited pre-conversion income that already built the 1,000,000 snapshot —
        // createdAt is BEFORE the conversion moment, so it's baked in and excluded.
        let inheritedIncome = Transaction(
            id: "inh", date: Self.pastDate(daysAgo: 10), description: "",
            amount: 1_000_000, currency: "KZT", convertedAmount: nil,
            type: .income, category: "Salary", subcategory: nil,
            accountId: "dep", targetAccountId: nil,
            createdAt: conversionMoment - 1_000
        )
        // Post-conversion transfer out (the user's "перевод с депозита на другой счёт"),
        // created AFTER conversion → counts.
        let transferOut = Transaction(
            id: "out", date: today, description: "",
            amount: 491_070.36, currency: "KZT", convertedAmount: nil,
            type: .internalTransfer, category: "", subcategory: nil,
            accountId: "dep", targetAccountId: "other",
            createdAt: conversionMoment + 1_000
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

    /// Reproduces the production corruption: a deposit converted yesterday reads a wildly
    /// wrong balance after a cold relaunch on a NEW calendar day.
    ///
    /// Root cause: the `.preserveImported` mode set by `markAsImported` at conversion lives
    /// ONLY in `BalanceStore.calculationModes` (in-memory, never persisted). On relaunch the
    /// dict is empty, every account defaults to `.fromInitialBalance`, and the day-change
    /// trigger `recalculateLedgerIfDayChanged` runs `recalculateAll`. Because the conversion
    /// sets `startDate` to the open interest-period start (a PAST date) while `initialPrincipal`
    /// snapshots the balance at conversion, inherited history dated AFTER startDate but already
    /// baked into the snapshot is re-applied on top → divergence.
    ///
    /// This test does NOT call `markAsImported` — it models the post-relaunch state directly.
    /// It must equal the snapshot (inherited history is already inside it).
    @Test("Converted deposit reads correct balance after relaunch with mode lost")
    func convertedDepositRecalcCorrectAfterRelaunchModeLost() async {
        let coordinator = Self.makeCoordinator()

        // startDate sits at the open interest-period start — a PAST date, NOT the conversion
        // moment. This is what lets post-startDate inherited history leak past a date cutoff.
        let periodStart = Self.pastDate(daysAgo: 30)
        // The conversion moment: every tx created at/before this is baked into the snapshot.
        let conversionMoment = Date().timeIntervalSince1970

        // Account converted to a deposit yesterday. Snapshot balance (= initialPrincipal =
        // initialBalance) is 1000 and ALREADY reflects every pre-conversion transaction.
        // conversionTimestamp is what the conversion flow now persists.
        let info = DepositInfo(
            bankName: "T",
            initialPrincipal: 1_000,
            capitalizationEnabled: false,
            interestRateAnnual: 0,
            interestRateHistory: [RateChange(effectiveFrom: periodStart, annualRate: 0)],
            interestPostingDay: 1,
            lastInterestCalculationDate: periodStart,
            lastInterestPostingMonth: periodStart,
            interestAccruedForCurrentPeriod: 0,
            startDate: periodStart,
            conversionTimestamp: conversionMoment
        )
        let deposit = Account(id: "dep", name: "Dep", currency: "KZT", depositInfo: info,
                              initialBalance: 1_000, balance: 1_000)

        // Inherited pre-conversion expense, dated AFTER periodStart but already inside the
        // 1000 snapshot. createdAt is BEFORE the conversion moment (it existed at conversion).
        let inheritedExpense = Transaction(
            id: "inh", date: Self.pastDate(daysAgo: 10), description: "",
            amount: 500, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Food", subcategory: nil,
            accountId: "dep", targetAccountId: nil,
            createdAt: conversionMoment - 1_000
        )

        // Cold relaunch: register accounts, mode dict empty (defaults to .fromInitialBalance),
        // day-change trigger fires recalculateAll. NO markAsImported — that state was lost.
        await coordinator.registerAccounts([deposit])
        await coordinator.setInitialBalance(1_000, for: "dep")
        await coordinator.recalculateAll(accounts: [deposit], transactions: [inheritedExpense])
        let rec = coordinator.balances["dep"]

        // The inherited expense is already baked into the 1000 snapshot — recalc must NOT
        // re-subtract it. Pre-fix this yields 500 (double-counted); post-fix it stays 1000.
        #expect(rec == 1_000)
    }

    /// The reason the cutoff keys on `createdAt`, not the calendar day: a post-conversion
    /// event dated the SAME day as the conversion must still count, while a pre-conversion
    /// event on that same day must not. A date-only cutoff cannot tell them apart — which is
    /// exactly why the old fix fell back to `.preserveImported`.
    @Test("Converted deposit separates same-day pre- vs post-conversion events by createdAt")
    func convertedDepositSameDayEventsSeparatedByCreatedAt() async {
        let coordinator = Self.makeCoordinator()
        let today = DateFormatters.dateFormatter.string(from: Date())
        let conversionMoment = Date().timeIntervalSince1970

        let info = DepositInfo(
            bankName: "T",
            initialPrincipal: 1_000,
            capitalizationEnabled: false,
            interestRateAnnual: 0,
            interestRateHistory: [RateChange(effectiveFrom: today, annualRate: 0)],
            interestPostingDay: 1,
            lastInterestCalculationDate: today,
            lastInterestPostingMonth: today,
            interestAccruedForCurrentPeriod: 0,
            startDate: today,
            conversionTimestamp: conversionMoment
        )
        let deposit = Account(id: "dep", name: "Dep", currency: "KZT", depositInfo: info,
                              initialBalance: 1_000, balance: 1_000)

        // Pre-conversion expense, TODAY, already inside the 1000 snapshot (createdAt before).
        let preConversion = Transaction(
            id: "pre", date: today, description: "",
            amount: 200, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Food", subcategory: nil,
            accountId: "dep", targetAccountId: nil,
            createdAt: conversionMoment - 500
        )
        // Post-conversion withdrawal, TODAY, made AFTER converting (createdAt after) → counts.
        let postConversion = Transaction(
            id: "post", date: today, description: "",
            amount: 300, currency: "KZT", convertedAmount: nil,
            type: .depositWithdrawal, category: "", subcategory: nil,
            accountId: "dep", targetAccountId: nil,
            createdAt: conversionMoment + 500
        )

        await coordinator.registerAccounts([deposit])
        await coordinator.setInitialBalance(1_000, for: "dep")
        await coordinator.recalculateAll(
            accounts: [deposit], transactions: [preConversion, postConversion]
        )
        let rec = coordinator.balances["dep"]

        // 1000 snapshot (already includes the pre-conversion 200) minus the post-conversion
        // withdrawal 300 = 700. The pre-conversion expense must NOT be re-applied.
        #expect(rec == 700)
    }

    /// In-session conversion: an account is registered as a NON-deposit, then converted by
    /// `updateDepositInfo` (which sets `depositInfo`). If a recalc fires in the SAME session
    /// (e.g. the day rolls over past midnight while the app is open), the conversionTimestamp
    /// cutoff must already apply — i.e. the stored `AccountBalance.isDeposit` must reflect the
    /// freshly-set `depositInfo`, not the stale pre-conversion `false`. Pins that `isDeposit`
    /// is derived from `depositInfo` rather than a stored flag that goes stale.
    @Test("In-session conversion applies the conversionTimestamp cutoff on a same-session recalc")
    func inSessionConversionAppliesCutoff() async {
        let coordinator = Self.makeCoordinator()

        // Registered as a regular (non-deposit) account, as it exists BEFORE conversion.
        let pre = Account(id: "dep", name: "Dep", currency: "KZT", initialBalance: 1_000, balance: 1_000)
        await coordinator.registerAccounts([pre])
        await coordinator.setInitialBalance(1_000, for: "dep")

        let conversionMoment = Date().timeIntervalSince1970
        // Inherited pre-conversion expense already baked into the 1000 snapshot.
        let inherited = Transaction(
            id: "inh", date: Self.pastDate(daysAgo: 5), description: "",
            amount: 300, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Food", subcategory: nil,
            accountId: "dep", targetAccountId: nil,
            createdAt: conversionMoment - 1_000
        )

        // Simulate the in-session conversion: stamp depositInfo with a conversionTimestamp.
        let periodStart = Self.pastDate(daysAgo: 30)
        let info = DepositInfo(
            bankName: "T", initialPrincipal: 1_000, capitalizationEnabled: false,
            interestRateAnnual: 0,
            interestRateHistory: [RateChange(effectiveFrom: periodStart, annualRate: 0)],
            interestPostingDay: 1, lastInterestCalculationDate: periodStart,
            lastInterestPostingMonth: periodStart, interestAccruedForCurrentPeriod: 0,
            startDate: periodStart, conversionTimestamp: conversionMoment
        )
        let converted = Account(id: "dep", name: "Dep", currency: "KZT", depositInfo: info,
                                initialBalance: 1_000, balance: 1_000)
        await coordinator.updateDepositInfo(converted, depositInfo: info)

        // Same-session recalc must NOT re-subtract the inherited expense (it's pre-conversion).
        await coordinator.recalculateAll(accounts: [converted], transactions: [inherited])

        #expect(coordinator.balances["dep"] == 1_000)
    }
}
