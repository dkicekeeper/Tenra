//
//  CategoryBudgetService.swift
//  Tenra
//
//  Read-time service for category budget progress.
//
//  Pre-aggregated totals live in `TransactionStore.categoryAggregatesByKey`
//  (maintained incrementally by TransactionStore+CategoryIndex). At read time
//  we lookup ≤31 hashmap buckets — bounded constant work regardless of how
//  many transactions exist.
//
//  See docs/domains/categories.md for the full read/write contract.
//

import Foundation

/// Service responsible for budget calculations and period management.
struct CategoryBudgetService {

    // MARK: - Dependencies

    /// The pre-aggregation store. Required for O(1) reads — without it the
    /// service returns nil/0 (safer than silently falling back to the old
    /// O(N_tx) scan, which is what caused the original lag).
    let store: TransactionStore?

    // MARK: - Initialization

    init(store: TransactionStore? = nil) {
        self.store = store
    }

    // MARK: - Public Methods

    /// Calculate budget progress for a category.
    /// O(≤31) hashmap lookups; returns nil if the category has no budget or
    /// is not an expense category.
    func budgetProgress(for category: CustomCategory) -> BudgetProgress? {
        guard let budgetAmount = category.budgetAmount,
              budgetAmount > 0,
              category.type == .expense,
              let store = store else { return nil }

        let spent = calculateSpent(for: category, store: store)
        return BudgetProgress(budgetAmount: budgetAmount, spent: spent)
    }

    /// Calculate spent amount for a category in the current budget period.
    /// O(≤31) hashmap lookups (1 for yearly, 1 for monthly with resetDay=1,
    /// ≤7 for weekly, ≤31 for monthly with custom resetDay).
    func calculateSpent(for category: CustomCategory, store: TransactionStore) -> Double {
        let cal = Calendar.current
        let now = Date()

        switch category.budgetPeriod {
        case .yearly:
            let y = Int16(cal.component(.year, from: now))
            return readBucket(category: category.name, y: y, m: 0, d: 0, store: store)

        case .monthly where category.budgetResetDay == 1:
            let y = Int16(cal.component(.year, from: now))
            let m = Int16(cal.component(.month, from: now))
            return readBucket(category: category.name, y: y, m: m, d: 0, store: store)

        case .monthly:
            return sumDailyBuckets(in: monthlyPeriod(resetDay: category.budgetResetDay, now: now),
                                   category: category.name,
                                   store: store)

        case .weekly:
            return sumDailyBuckets(in: weeklyPeriod(now: now),
                                   category: category.name,
                                   store: store)
        }
    }

    /// Budget period start date. Kept for back-compat with callers that need
    /// to display the period boundaries (e.g. BudgetSettingsSection preview).
    func budgetPeriodStart(for category: CustomCategory) -> Date {
        let now = Date()
        switch category.budgetPeriod {
        case .weekly:  return weeklyPeriod(now: now).start
        case .monthly: return monthlyPeriod(resetDay: category.budgetResetDay, now: now).start
        case .yearly:  return Calendar.current.dateInterval(of: .year, for: now)?.start ?? now
        }
    }

    // MARK: - Private — period boundaries

    private func weeklyPeriod(now: Date) -> DateInterval {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return DateInterval(start: start, end: now)
    }

    private func monthlyPeriod(resetDay: Int, now: Date) -> DateInterval {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: now)
        var startComps = comps
        startComps.day = resetDay
        let candidate = cal.date(from: startComps) ?? now
        let start: Date
        if candidate > now {
            // Reset day hasn't happened this month yet — period started last month.
            start = cal.date(byAdding: .month, value: -1, to: candidate) ?? candidate
        } else {
            start = candidate
        }
        return DateInterval(start: start, end: now)
    }

    // MARK: - Private — bucket reads

    private func readBucket(category: String, y: Int16, m: Int16, d: Int16, store: TransactionStore) -> Double {
        let key = CategoryAggregate.makeId(category: category, year: y, month: m, day: d)
        // Budget "spent" is EXPENSE-only (C-6): a non-expense tx tagged to a
        // budgeted expense category must not inflate it. Read `expenseAmount`,
        // not `totalAmount` (which sums all aggregatable types).
        return store.categoryAggregatesByKey[key]?.expenseAmount ?? 0
    }

    /// Sum daily buckets between the two dates, inclusive of start, exclusive of end+1day.
    /// Bounded at ≤31 lookups (monthly) or ≤7 (weekly), so this is effectively O(1).
    private func sumDailyBuckets(in range: DateInterval, category: String, store: TransactionStore) -> Double {
        let cal = Calendar.current
        var total = 0.0
        var cursor = cal.startOfDay(for: range.start)
        let limit = range.end
        while cursor <= limit {
            let comps = cal.dateComponents([.year, .month, .day], from: cursor)
            total += readBucket(
                category: category,
                y: Int16(comps.year ?? 0),
                m: Int16(comps.month ?? 0),
                d: Int16(comps.day ?? 0),
                store: store
            )
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return total
    }
}

// MARK: - Static Helpers

extension CategoryBudgetService {
    /// Create budget service with all dependencies.
    static func create(store: TransactionStore) -> CategoryBudgetService {
        CategoryBudgetService(store: store)
    }

    // MARK: - Legacy array-based API (Insights only)
    //
    // InsightsService runs `nonisolated` on a background actor and cannot read
    // MainActor-isolated TransactionStore indexes. It works on a snapshot
    // `[Transaction]` array passed in from the orchestrator, so we keep an
    // array-scanning path here exclusively for that consumer.
    //
    // DO NOT call from Views / ViewModels — they should use the store-backed
    // instance methods which are O(≤31), not O(N_tx).

    /// O(N_tx) scan of a transactions snapshot.
    nonisolated static func budgetProgress(
        for category: CustomCategory,
        transactions: [Transaction],
        baseCurrency: String?
    ) -> BudgetProgress? {
        guard let budgetAmount = category.budgetAmount,
              budgetAmount > 0,
              category.type == .expense else { return nil }
        let spent = calculateSpentLegacy(for: category, transactions: transactions, baseCurrency: baseCurrency)
        return BudgetProgress(budgetAmount: budgetAmount, spent: spent)
    }

    /// O(N_tx) scan of a transactions snapshot, converting amounts to base currency
    /// via `CategoryBudgetCurrency.toBase`. Kept verbatim from pre-refactor logic
    /// so Insights output is byte-for-byte identical.
    nonisolated static func calculateSpentLegacy(
        for category: CustomCategory,
        transactions: [Transaction],
        baseCurrency: String?
    ) -> Double {
        let periodStart = legacyBudgetPeriodStart(for: category)
        let periodEnd = Date()
        let dateFormatter = DateFormatters.dateFormatter

        return transactions
            .filter { tx in
                guard tx.category == category.name,
                      tx.type == .expense,
                      let d = dateFormatter.date(from: tx.date) else { return false }
                return d >= periodStart && d <= periodEnd
            }
            .reduce(0) { sum, tx in
                guard let base = baseCurrency else { return sum + tx.amount }
                return sum + CategoryBudgetCurrency.toBase(amount: tx.amount, from: tx.currency, base: base).amount
            }
    }

    nonisolated static func legacyBudgetPeriodStart(for category: CustomCategory) -> Date {
        // NB: do NOT short-circuit to `now` when budgetStartDate is nil (legacy data can
        // have a budget without a stored start date). The period is derived from the
        // reset day / calendar like the store path, so the two agree.
        let cal = Calendar.current
        let now = Date()
        switch category.budgetPeriod {
        case .weekly:
            return cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: now)
            var startComps = comps
            startComps.day = category.budgetResetDay
            if let resetDate = cal.date(from: startComps) {
                if resetDate > now {
                    return cal.date(byAdding: .month, value: -1, to: resetDate) ?? resetDate
                }
                return resetDate
            }
            return now
        case .yearly:
            return cal.dateInterval(of: .year, for: now)?.start ?? now
        }
    }
}
