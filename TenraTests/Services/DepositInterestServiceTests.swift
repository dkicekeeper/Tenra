//
//  DepositInterestServiceTests.swift
//  TenraTests
//
//  Unit tests for DepositInterestService.calculateInterestToToday (pure, no CoreData).
//  TEST-01
//

import Testing
import Foundation
@testable import Tenra

@Suite("DepositInterestService")
struct DepositInterestServiceTests {

    // MARK: - Helpers

    private func today() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func dateString(offsetDays: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offsetDays, to: today())!
        return DateFormatters.dateFormatter.string(from: date)
    }

    /// Builds a minimal DepositInfo for testing.
    /// - Parameters:
    ///   - principal: Deposit principal balance
    ///   - annualRate: Annual interest rate in percent (e.g. 12 for 12%)
    ///   - lastCalcDateOffset: Days from today (-1 = yesterday, 0 = today, -5 = 5 days ago)
    ///   - accruedForPeriod: Pre-existing accrued interest for the current period
    ///   - rateHistory: Custom rate history; if nil, a single entry is auto-created
    private func makeDepositInfo(
        principal: Decimal = 100_000,
        annualRate: Decimal = 12,
        lastCalcDateOffset: Int = -1,
        accruedForPeriod: Decimal = 0,
        rateHistory: [RateChange]? = nil
    ) -> DepositInfo {
        let lastCalcDateStr = dateString(offsetDays: lastCalcDateOffset)

        // Build rate history: one entry effective from the last calculation date
        let history: [RateChange]
        if let rateHistory {
            history = rateHistory
        } else {
            history = [RateChange(effectiveFrom: lastCalcDateStr, annualRate: annualRate)]
        }

        return DepositInfo(
            bankName: "TestBank",
            initialPrincipal: principal,
            capitalizationEnabled: false,
            interestRateAnnual: annualRate,
            interestRateHistory: history,
            interestPostingDay: 1,
            lastInterestCalculationDate: lastCalcDateStr,
            lastInterestPostingMonth: "2020-01-01",
            interestAccruedForCurrentPeriod: accruedForPeriod
        )
    }

    // MARK: - Test A: Single-day accrual

    @Test("Single-day accrual returns principal * rate/100 / 365")
    func testSingleDayAccrual() {
        let principal: Decimal = 100_000
        let rate: Decimal = 12
        let info = makeDepositInfo(principal: principal, annualRate: rate, lastCalcDateOffset: -1)

        let result = DepositInterestService.calculateInterestToToday(depositInfo: info, accountId: "d1", allTransactions: [])

        // Loop runs once (today), adding principal * rate/100 / 365
        let expected: Decimal = principal * (rate / 100) / 365
        // Allow tolerance of 0.001 for Decimal rounding
        let diff = abs(result - expected)
        #expect(diff < Decimal(string: "0.001")!, "Expected ~\(expected), got \(result)")
    }

    // MARK: - Test B: Multi-day accrual

    @Test("5-day accrual returns 5 × daily interest")
    func testMultiDayAccrual() {
        let principal: Decimal = 100_000
        let rate: Decimal = 12
        let info = makeDepositInfo(principal: principal, annualRate: rate, lastCalcDateOffset: -5, accruedForPeriod: 0)

        let result = DepositInterestService.calculateInterestToToday(depositInfo: info, accountId: "d1", allTransactions: [])

        // Loop runs 5 times (today - 4, ..., today)
        let dailyInterest: Decimal = principal * (rate / 100) / 365
        let expected: Decimal = dailyInterest * 5
        let diff = abs(result - expected)
        #expect(diff < Decimal(string: "0.01")!, "Expected ~\(expected), got \(result)")
    }

    // MARK: - Test C: Current period is recomputed (persisted accrual NOT added)

    @Test("Persisted interestAccruedForCurrentPeriod is recomputed, not added on top")
    func testAccruedRecomputedNotAdded() {
        // The current period is always recomputed fresh from its start, so a stale
        // `interestAccruedForCurrentPeriod` value must NOT be added to the result
        // (the old incremental model added it — the source of the backdated-principal
        // bug). startDate defaults to lastCalc (yesterday), so this is a 1-day period.
        let principal: Decimal = 100_000
        let rate: Decimal = 12
        let priorAccrued: Decimal = 50
        let info = makeDepositInfo(
            principal: principal,
            annualRate: rate,
            lastCalcDateOffset: -1,
            accruedForPeriod: priorAccrued
        )

        let result = DepositInterestService.calculateInterestToToday(depositInfo: info, accountId: "d1", allTransactions: [])

        let dailyInterest: Decimal = principal * (rate / 100) / 365
        let diff = abs(result - dailyInterest)
        #expect(diff < Decimal(string: "0.001")!, "Expected ~\(dailyInterest) (1 day, stored 50 ignored), got \(result)")
    }

    // MARK: - Test D: Rate history selection

    @Test("Rate history: most recent applicable rate is used (20%, not 10%)")
    func testRateHistorySelection() {
        let principal: Decimal = 100_000

        // Two rate changes: 10% from 2024-01-01, 20% from 2025-01-01
        let history = [
            RateChange(effectiveFrom: "2024-01-01", annualRate: 10),
            RateChange(effectiveFrom: "2025-01-01", annualRate: 20)
        ]

        // lastCalcDate = yesterday — the loop iterates for today only
        let info = makeDepositInfo(
            principal: principal,
            annualRate: 20,  // current rate; history overrides inside calculation
            lastCalcDateOffset: -1,
            accruedForPeriod: 0,
            rateHistory: history
        )

        let result = DepositInterestService.calculateInterestToToday(depositInfo: info, accountId: "d1", allTransactions: [])

        // Today is in 2026; rate effective from 2025-01-01 (20%) applies
        let expectedAt20Percent: Decimal = principal * (Decimal(20) / 100) / 365
        let unexpectedAt10Percent: Decimal = principal * (Decimal(10) / 100) / 365

        // Result must be closer to 20% daily interest than 10%
        let diffTo20 = abs(result - expectedAt20Percent)
        let diffTo10 = abs(result - unexpectedAt10Percent)
        #expect(diffTo20 < diffTo10, "Should use 20% rate, not 10%")
        #expect(diffTo20 < Decimal(string: "0.001")!, "Result \(result) should match 20% daily (\(expectedAt20Percent))")
    }

    // MARK: - Test E: Leap year / February boundary

    @Test("Leap year February accrual: crossing Feb 29 accumulates interest without crash")
    func testLeapYearFebruaryBoundary() {
        // Set lastCalcDate to 2024-02-28 (day before Feb 29 in leap year 2024)
        // Since today is well past Feb 29 2024, the loop will iterate through Feb 29 and beyond
        let history = [RateChange(effectiveFrom: "2024-01-01", annualRate: 12)]
        var info = DepositInfo(
            bankName: "TestBank",
            initialPrincipal: 100_000,
            capitalizationEnabled: false,
            interestRateAnnual: 12,
            interestRateHistory: history,
            interestPostingDay: 31,   // posting day = 31 (clamped to last day of month)
            lastInterestCalculationDate: "2024-02-28",
            lastInterestPostingMonth: "2020-01-01",
            interestAccruedForCurrentPeriod: 0
        )

        // The function must not crash and must return a positive accumulated value
        let result = DepositInterestService.calculateInterestToToday(depositInfo: info, accountId: "d1", allTransactions: [])
        #expect(result > 0, "Expected positive interest when crossing Feb 29, got \(result)")

        // Also verify that adding a RateChange with addRateChange doesn't crash
        DepositInterestService.addRateChange(depositInfo: &info, effectiveFrom: "2024-03-01", annualRate: 15)
        let resultAfterRateChange = DepositInterestService.calculateInterestToToday(depositInfo: info, accountId: "d1", allTransactions: [])
        #expect(resultAfterRateChange > 0, "Still positive after rate change added")
    }

    // MARK: - Test F: Period starts today → zero accrual

    @Test("Deposit whose current period starts today accrues 0 (recompute, stored value ignored)")
    func testUpToDateDeposit() {
        let priorAccrued: Decimal = 42
        let info = makeDepositInfo(
            principal: 100_000,
            annualRate: 12,
            lastCalcDateOffset: 0,   // startDate defaults to today → period starts today
            accruedForPeriod: priorAccrued
        )

        let result = DepositInterestService.calculateInterestToToday(depositInfo: info, accountId: "d1", allTransactions: [])

        // periodStart == today → no completed days → fresh recompute returns 0
        // (the stored 42 is intentionally not surfaced anymore).
        #expect(result == 0, "Expected 0, got \(result)")
    }

    // MARK: - principalDelta tests (Task 2)

    @Test("principalDelta: income adds amount")
    func principalDelta_income_addsAmount() {
        let tx = Transaction(
            id: "t1", date: dateString(offsetDays: -1), description: "",
            amount: 1_000, currency: "KZT", convertedAmount: nil,
            type: .income, category: "Salary", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )
        let delta = DepositInterestService.principalDelta(for: tx, accountId: "d1", capitalizationEnabled: true)
        #expect(delta == Decimal(1_000))
    }

    @Test("principalDelta: expense subtracts amount")
    func principalDelta_expense_subtractsAmount() {
        let tx = Transaction(
            id: "t2", date: dateString(offsetDays: -1), description: "",
            amount: 500, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Other", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )
        let delta = DepositInterestService.principalDelta(for: tx, accountId: "d1", capitalizationEnabled: true)
        #expect(delta == Decimal(-500))
    }

    @Test("principalDelta: income prefers convertedAmount when present")
    func principalDelta_income_usesConvertedAmount() {
        // Source amount is in USD; convertedAmount is the value already in deposit currency.
        let tx = Transaction(
            id: "t3", date: dateString(offsetDays: -1), description: "",
            amount: 100, currency: "USD", convertedAmount: 47_000,
            type: .income, category: "Salary", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )
        let delta = DepositInterestService.principalDelta(for: tx, accountId: "d1", capitalizationEnabled: true)
        #expect(delta == Decimal(47_000))
    }

    @Test("principalDelta: expense prefers convertedAmount when present")
    func principalDelta_expense_usesConvertedAmount() {
        let tx = Transaction(
            id: "t4", date: dateString(offsetDays: -1), description: "",
            amount: 100, currency: "USD", convertedAmount: 47_000,
            type: .expense, category: "Other", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )
        let delta = DepositInterestService.principalDelta(for: tx, accountId: "d1", capitalizationEnabled: true)
        #expect(delta == Decimal(-47_000))
    }

    // MARK: - reconcileDepositInterest tests (Task 3)

    /// Constructs a deposit-bearing Account for tests.
    private func makeDepositAccount(
        id: String = "d1",
        currency: String = "KZT",
        depositInfo: DepositInfo
    ) -> Account {
        Account(
            id: id,
            name: "Deposit",
            currency: currency,
            iconSource: nil,
            depositInfo: depositInfo,
            initialBalance: NSDecimalNumber(decimal: depositInfo.initialPrincipal).doubleValue
        )
    }

    private func makeIncomeTx(
        id: String = "i1",
        amount: Double,
        currency: String = "KZT",
        convertedAmount: Double? = nil,
        date: String,
        accountId: String = "d1"
    ) -> Transaction {
        Transaction(
            id: id, date: date, description: "Salary",
            amount: amount, currency: currency, convertedAmount: convertedAmount,
            type: .income, category: "Salary", subcategory: nil,
            accountId: accountId, targetAccountId: nil
        )
    }

    /// Helper: drive the engine over the given events and return the deposit's resulting balance.
    private func depositBalance(account: Account, events: [Transaction]) -> Double {
        let info = account.depositInfo
        let bal = AccountBalance(
            accountId: account.id,
            currentBalance: 0,
            initialBalance: NSDecimalNumber(decimal: info?.initialPrincipal ?? 0).doubleValue,
            depositInfo: info,
            currency: account.currency
        )
        return BalanceCalculationEngine().calculateBalance(
            account: bal, transactions: events
        )
    }

    @Test("balance walks .income on deposit (unified pipeline)")
    func reconcile_incomeAddsToPrincipal() {
        var info = makeDepositInfo(
            principal: 100_000, annualRate: 0, lastCalcDateOffset: -1, accruedForPeriod: 0
        )
        info.startDate = dateString(offsetDays: -5)

        let account = makeDepositAccount(depositInfo: info)
        let income = makeIncomeTx(amount: 25_000, date: dateString(offsetDays: -3))

        #expect(depositBalance(account: account, events: [income]) == 125_000)
    }

    @Test("balance walks .expense on deposit (unified pipeline)")
    func reconcile_expenseSubtractsFromPrincipal() {
        var info = makeDepositInfo(principal: 100_000, annualRate: 0, lastCalcDateOffset: -1)
        info.startDate = dateString(offsetDays: -5)

        let account = makeDepositAccount(depositInfo: info)
        let expense = Transaction(
            id: "e1", date: dateString(offsetDays: -3), description: "",
            amount: 10_000, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Other", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )

        #expect(depositBalance(account: account, events: [expense]) == 90_000)
    }

    @Test("balance uses convertedAmount when income currency differs")
    func reconcile_incomeUsesConvertedAmount() {
        var info = makeDepositInfo(principal: 100_000, annualRate: 0, lastCalcDateOffset: -1)
        info.startDate = dateString(offsetDays: -5)

        let account = makeDepositAccount(currency: "KZT", depositInfo: info)
        let income = makeIncomeTx(
            amount: 100, currency: "USD", convertedAmount: 47_000,
            date: dateString(offsetDays: -2)
        )

        #expect(depositBalance(account: account, events: [income]) == 147_000)
    }

    @Test("balance reflects same-day events without separate principal recompute")
    func reconcile_sameDayPrincipalRecompute() {
        var info = makeDepositInfo(principal: 100_000, annualRate: 0, lastCalcDateOffset: -1)
        info.startDate = dateString(offsetDays: -5)

        let account = makeDepositAccount(depositInfo: info)
        #expect(depositBalance(account: account, events: []) == 100_000)
        let todayIncome = makeIncomeTx(amount: 30_000, date: dateString(offsetDays: 0))
        #expect(depositBalance(account: account, events: [todayIncome]) == 130_000)
    }

    @Test("balance includes .internalTransfer target-side amount on deposit (regression)")
    func reconcile_internalTransferTargetCounts() {
        var info = makeDepositInfo(principal: 100_000, annualRate: 0, lastCalcDateOffset: -1)
        info.startDate = dateString(offsetDays: -5)

        let account = makeDepositAccount(depositInfo: info)
        let transferIn = Transaction(
            id: "t1", date: dateString(offsetDays: -2), description: "",
            amount: 50_000, currency: "KZT", convertedAmount: 50_000,
            type: .internalTransfer, category: TransactionType.transferCategoryName,
            subcategory: nil, accountId: "src", targetAccountId: "d1",
            targetAmount: 50_000
        )
        // The whole point of unification: transfer to deposit is reflected in balance.
        #expect(depositBalance(account: account, events: [transferIn]) == 150_000)
    }

    // MARK: - calculateInterestToToday(allTransactions:) tests (Task 4)

    @Test("calculateInterestToToday(allTransactions:) accrues on principal grown by .income")
    func calculateInterestToToday_walksIncome() {
        // Deposit at 100k, 12% APR, .income of 100k applied 3 days ago doubles the
        // running principal from that day. Validate that the historical walk picks
        // up the .income event.
        var info = makeDepositInfo(
            principal: 100_000,
            annualRate: 12,
            lastCalcDateOffset: -5,
            accruedForPeriod: 0
        )
        info.initialPrincipal = 100_000
        info.startDate = dateString(offsetDays: -10)

        let income = makeIncomeTx(
            id: "i1", amount: 100_000,
            date: dateString(offsetDays: -3),
            accountId: "d1"
        )

        let walked = DepositInterestService.calculateInterestToToday(
            depositInfo: info, accountId: "d1", allTransactions: [income]
        )
        let baseline = DepositInterestService.calculateInterestToToday(
            depositInfo: info, accountId: "d1", allTransactions: []
        )

        // Walked variant must accrue strictly more because principal doubled mid-period.
        #expect(walked > baseline)
    }

    @Test("reconcile with capitalization+posting creates a transaction that the engine folds into balance")
    func reconcile_capitalizedPostingDuringWalk_principalIncludesPosting() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -35, to: today)!
        let startDateStr = DateFormatters.dateFormatter.string(from: startDate)

        let postingDay = 1
        let monthBeforeStart = calendar.date(byAdding: .month, value: -1, to: startDate)!
        let monthBeforeStartComps = calendar.dateComponents([.year, .month], from: monthBeforeStart)
        let monthBeforeStartFloor = calendar.date(from: monthBeforeStartComps)!
        let monthBeforeStartStr = DateFormatters.dateFormatter.string(from: monthBeforeStartFloor)

        let info = DepositInfo(
            bankName: "T",
            initialPrincipal: 100_000,
            capitalizationEnabled: true,
            interestRateAnnual: 12,
            interestRateHistory: [RateChange(effectiveFrom: startDateStr, annualRate: 12)],
            interestPostingDay: postingDay,
            lastInterestCalculationDate: startDateStr,
            lastInterestPostingMonth: monthBeforeStartStr,
            interestAccruedForCurrentPeriod: 0,
            startDate: startDateStr
        )
        var account = makeDepositAccount(currency: "KZT", depositInfo: info)

        var posted: [Transaction] = []
        DepositInterestService.reconcileDepositInterest(
            account: &account,
            allTransactions: [],
            onTransactionCreated: { posted.append($0) }
        )

        #expect(posted.count >= 1)
        // The unified pipeline: posted .depositInterestAccrual transactions feed the
        // standard balance engine. Verify the engine folds them into balance.
        let computed = depositBalance(account: account, events: posted)
        #expect(computed > 100_000, "Expected balance > 100k after capitalized posting; got \(computed)")
        let totalPosted = posted.reduce(0.0) { $0 + $1.amount }
        let expected = 100_000.0 + totalPosted
        #expect(abs(computed - expected) < 0.01, "Balance \(computed) should ≈ \(expected)")
    }

    @Test("reconcile posts interest when TODAY is the posting day (new-month / June-1 regression)")
    func reconcile_postsOnTodayWhenTodayIsPostingDay() {
        // Regression: the walk used `currentDate < today`, so when the user opened the
        // app ON the posting day (e.g. June 1) the loop exited before reaching today and
        // the interest transaction for the just-ended period was never created.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let postingDay = calendar.component(.day, from: today)

        // Last posting happened in the previous month → the open period ends today.
        let prevMonth = calendar.date(byAdding: .month, value: -1, to: today)!
        let prevMonthFloor = calendar.date(from: calendar.dateComponents([.year, .month], from: prevMonth))!
        let lastPostingMonthStr = DateFormatters.dateFormatter.string(from: prevMonthFloor)

        let startDate = calendar.date(byAdding: .day, value: -90, to: today)!
        let startDateStr = DateFormatters.dateFormatter.string(from: startDate)

        let info = DepositInfo(
            bankName: "T",
            initialPrincipal: 1_000_000,
            capitalizationEnabled: false,
            interestRateAnnual: 12,
            interestRateHistory: [RateChange(effectiveFrom: startDateStr, annualRate: 12)],
            interestPostingDay: postingDay,
            lastInterestCalculationDate: startDateStr,
            lastInterestPostingMonth: lastPostingMonthStr,
            interestAccruedForCurrentPeriod: 0,
            startDate: startDateStr
        )
        var account = makeDepositAccount(currency: "KZT", depositInfo: info)

        var posted: [Transaction] = []
        DepositInterestService.reconcileDepositInterest(
            account: &account,
            allTransactions: [],
            onTransactionCreated: { posted.append($0) }
        )

        #expect(posted.count == 1, "Interest must be posted on the posting day even when that day is today")
        if let tx = posted.first {
            #expect(tx.date == DateFormatters.dateFormatter.string(from: today))
            #expect(tx.amount > 0)
        }
    }

    @Test("value date T+1: a top-up earns interest only from the day AFTER it arrives")
    func accrual_topUpEarnsFromNextDay() {
        // Deposit funded entirely by a top-up dated `today - 2`. Under T+1 that money
        // earns on `today-1` and `today` = 2 days, NOT 3 (the arrival day earns nothing).
        let principal: Decimal = 100_000
        let rate: Decimal = 12

        let startStr = dateString(offsetDays: -5)
        let info = DepositInfo(
            bankName: "T",
            initialPrincipal: 0,
            capitalizationEnabled: false,
            interestRateAnnual: rate,
            interestRateHistory: [RateChange(effectiveFrom: startStr, annualRate: rate)],
            interestPostingDay: 1,
            lastInterestCalculationDate: startStr,
            lastInterestPostingMonth: "2020-01-01",  // far past → period start clamps to startDate
            interestAccruedForCurrentPeriod: 0,
            startDate: startStr
        )

        let topUp = makeIncomeTx(amount: 100_000, date: dateString(offsetDays: -2))

        let result = DepositInterestService.calculateInterestToToday(
            depositInfo: info, accountId: "d1", allTransactions: [topUp]
        )

        let daily = principal * (rate / 100) / 365
        let expectedTwoDays = daily * 2
        let wrongThreeDays = daily * 3
        #expect(abs(result - expectedTwoDays) < Decimal(string: "0.01")!,
                "Top-up should earn 2 days (T+1), got \(result), expected \(expectedTwoDays)")
        #expect(abs(result - wrongThreeDays) > Decimal(string: "1")!,
                "Must NOT earn from the arrival day (would be \(wrongThreeDays))")
    }
}

@Suite("TransactionType.affectsDepositPrincipal")
struct TransactionTypeDepositPrincipalTests {

    @Test("deposit-principal types return true")
    func depositPrincipalTypesReturnTrue() {
        #expect(TransactionType.depositTopUp.affectsDepositPrincipal)
        #expect(TransactionType.depositWithdrawal.affectsDepositPrincipal)
        #expect(TransactionType.depositInterestAccrual.affectsDepositPrincipal)
    }

    @Test("income and expense return true")
    func incomeAndExpenseReturnTrue() {
        #expect(TransactionType.income.affectsDepositPrincipal)
        #expect(TransactionType.expense.affectsDepositPrincipal)
    }

    @Test("internalTransfer is principal-affecting (deposit may be source or target)")
    func internalTransferReturnsTrue() {
        #expect(TransactionType.internalTransfer.affectsDepositPrincipal)
    }

    @Test("loan types return false")
    func loanReturnsFalse() {
        #expect(!TransactionType.loanPayment.affectsDepositPrincipal)
        #expect(!TransactionType.loanEarlyRepayment.affectsDepositPrincipal)
    }
}
