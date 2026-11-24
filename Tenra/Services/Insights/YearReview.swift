//
//  YearReview.swift
//  Tenra
//
//  The year in review (docs/plan-release-1.9.md §3): what a calendar year looked like in Tenra,
//  page by page. Built off the main actor from plain values, by the same money rules as
//  Analytics: only realized rows, in the base currency through a pinned `RateSnapshot`
//  (a cross-currency row without a rate is skipped and flagged, never blended), income and
//  expenses by `InsightsService.moneyBucket` (CLAUDE.md, rules 6, 8, 9, 11).
//
//  Shown from 15 December to 31 January (`YearReviewWindow`): in December for the year that
//  is ending, in January for the one just ended. Nothing for someone with fewer than
//  `minimumRecords` records in the year or less than `minimumHistoryDays` of history.
//

import Foundation

nonisolated struct YearReview: Sendable, Equatable {

    nonisolated struct CategoryTotal: Sendable, Equatable, Identifiable {
        /// `InsightsService.categoryKey`: a user category's name or a synthetic key.
        let key: String
        let label: String
        let amount: Double
        /// Of the year's expenses, 0...1.
        let share: Double
        var id: String { key }
    }

    nonisolated struct MerchantTotal: Sendable, Equatable, Identifiable {
        /// The normalized merchant (or brand) key.
        let key: String
        let name: String
        let amount: Double
        let visits: Int
        /// The category key the merchant was most often recorded under, for its icon.
        let usualCategory: String
        var id: String { key }
    }

    nonisolated struct BiggestExpense: Sendable, Equatable {
        let amount: Double
        let title: String
        let categoryKey: String
        /// "yyyy-MM-dd".
        let date: String
    }

    nonisolated struct Habit: Sendable, Equatable {
        /// Records the person made in the year (generated recurring charges and deposit
        /// interest left out).
        let records: Int
        /// Days with at least one such record.
        let days: Int
        /// The longest run of consecutive days with a record.
        let longestStreak: Int
    }

    let year: Int
    let currency: String
    let expenses: Double
    let income: Double
    /// Expenses per month, January first, one entry per month up to the last one with data
    /// in reach (the current month in the current year).
    let monthlyExpenses: [Double]
    /// The last month whose expenses are final: in the current year the month before the
    /// current one, so a month still running is never "the calmest".
    let lastCompleteMonth: Int
    /// Up to `YearReviewBuilder.topCategoryCount`, largest first.
    let topCategories: [CategoryTotal]
    /// Up to `YearReviewBuilder.topMerchantCount`, largest first; empty below
    /// `YearReviewBuilder.minimumMerchants` merchants.
    let topMerchants: [MerchantTotal]
    let subscriptionsTotal: Double
    /// Subscriptions that charged in the year.
    let subscriptionsCount: Int
    let habit: Habit
    let biggestExpense: BiggestExpense?
    /// A cross-currency row had no rate and was left out: recompute when rates arrive.
    let usedStaleFallback: Bool

    var saved: Double { income - expenses }

    /// What was left of the income, as a share of it; nil without income.
    var savingsRate: Double? { income > 0 ? (income - expenses) / income : nil }

    /// The month (1...12) with the most expenses.
    var busiestMonth: Int? {
        monthlyExpenses.indices
            .filter { monthlyExpenses[$0] > 0 }
            .max { monthlyExpenses[$0] < monthlyExpenses[$1] }
            .map { $0 + 1 }
    }

    /// The complete month (1...12) with the least expenses, among those with any.
    var calmestMonth: Int? {
        let complete = monthlyExpenses.indices.filter { $0 < lastCompleteMonth && monthlyExpenses[$0] > 0 }
        guard complete.count >= 2 else { return nil }
        return complete.min { monthlyExpenses[$0] < monthlyExpenses[$1] }.map { $0 + 1 }
    }
}

/// When the year in review is offered.
nonisolated enum YearReviewWindow {
    /// The first December day it shows.
    static let firstDecemberDay = 15

    /// The year whose review shows on `now`: from 15 December the year that is ending, in
    /// January the one just ended, nil the rest of the year.
    static func year(on now: Date, calendar: Calendar = .current) -> Int? {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        if month == 12, day >= firstDecemberDay { return year }
        if month == 1 { return year - 1 }
        return nil
    }
}

nonisolated enum YearReviewBuilder {
    static let minimumRecords = 30
    static let minimumHistoryDays = 30
    static let topCategoryCount = 5
    static let topMerchantCount = 3
    static let minimumMerchants = 3

    /// The review of `year`, or nil when there is too little to review: fewer than
    /// `minimumRecords` records in the year, or the first record ever less than
    /// `minimumHistoryDays` before `now`.
    static func build(
        year: Int,
        transactions: [Transaction],
        recurringSeries: [RecurringSeries],
        baseCurrency: String,
        rates: RateSnapshot,
        brands: MerchantBrands = .none,
        now: Date,
        calendar: Calendar = FastDateParser.calendar
    ) -> YearReview? {
        let prefix = String(format: "%04d-", year)
        let today = FastDateParser.string(from: now)

        guard let firstEver = transactions.lazy.map(\.date).min(),
              let firstDate = FastDateParser.date(from: firstEver),
              let historyDays = calendar.dateComponents([.day], from: firstDate, to: now).day,
              historyDays >= minimumHistoryDays else { return nil }

        let subscriptionIds = Set(recurringSeries.filter(\.isSubscription).map(\.id))
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let monthsInReach = year < currentYear ? 12 : (year == currentYear ? currentMonth : 0)
        guard monthsInReach > 0 else { return nil }

        var expenses = 0.0
        var income = 0.0
        var monthly = [Double](repeating: 0, count: monthsInReach)
        var byCategory: [String: Double] = [:]
        var stale = false
        var records = 0
        var recordDays = Set<String>()
        var subscriptionsTotal = 0.0
        var chargedSubscriptions = Set<String>()
        var biggest: (amount: Double, tx: Transaction)?

        struct Merchant {
            var total = 0.0
            var visits = 0
            var latestDate = ""
            var latestDescription = ""
            var byCategory: [String: Double] = [:]
        }
        var merchants: [String: Merchant] = [:]
        var keyByDescription: [String: String] = [:]

        for tx in transactions where tx.date.hasPrefix(prefix) && tx.date <= today {
            // The habit: what the person recorded, not what Tenra generated.
            if tx.recurringSeriesId == nil, tx.type != .depositInterestAccrual {
                records += 1
                recordDays.insert(tx.date)
            }

            let bucket = InsightsService.moneyBucket(tx.type)
            guard bucket != .none else { continue }
            let resolved = InsightsService.resolveAmountToBase(tx, baseCurrency: baseCurrency, rates: rates)
            if resolved.usedStaleFallback { stale = true }
            let amount = resolved.amount
            guard amount > 0 else { continue }

            if bucket == .income {
                income += amount
                continue
            }

            expenses += amount
            if let month = Int(tx.date.dropFirst(5).prefix(2)), month >= 1, month <= monthsInReach {
                monthly[month - 1] += amount
            }
            let categoryKey = InsightsService.categoryKey(for: tx)
            byCategory[categoryKey, default: 0] += amount

            if let seriesId = tx.recurringSeriesId, subscriptionIds.contains(seriesId) {
                subscriptionsTotal += amount
                chargedSubscriptions.insert(seriesId)
            }

            guard tx.type == .expense else { continue }
            if tx.recurringSeriesId == nil, amount > (biggest?.amount ?? 0) {
                biggest = (amount, tx)
            }

            // Merchants as the "Top merchant" insight finds them.
            let described: String
            if let cached = keyByDescription[tx.description] {
                described = cached
            } else {
                described = CategorySuggestionService.normalizedMerchant(tx.description)
                keyByDescription[tx.description] = described
            }
            let key = brands.isEmpty ? described : brands.merchant(of: tx, described: described)
            guard key.count >= CategorySuggestionService.minimumMerchantLength,
                  key != CategorySuggestionService.normalizedMerchant(tx.category) else { continue }
            var merchant = merchants[key, default: Merchant()]
            merchant.total += amount
            merchant.visits += 1
            if tx.date >= merchant.latestDate {
                merchant.latestDate = tx.date
                merchant.latestDescription = tx.description
            }
            merchant.byCategory[categoryKey, default: 0] += amount
            merchants[key] = merchant
        }

        guard records >= minimumRecords else { return nil }

        let topCategories = byCategory
            .filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(topCategoryCount)
            .map { entry in
                YearReview.CategoryTotal(
                    key: entry.key,
                    label: InsightsService.categoryLabel(for: entry.key),
                    amount: entry.value,
                    share: expenses > 0 ? entry.value / expenses : 0
                )
            }

        let rankedMerchants = merchants
            .filter { $0.value.total > 0 }
            .sorted { $0.value.total != $1.value.total ? $0.value.total > $1.value.total : $0.key < $1.key }
        let topMerchants: [YearReview.MerchantTotal] = rankedMerchants.count < minimumMerchants
            ? []
            : rankedMerchants.prefix(topMerchantCount).map { entry in
                let usual = entry.value.byCategory
                    .max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?
                    .key ?? ""
                return YearReview.MerchantTotal(
                    key: entry.key,
                    name: brands.brandName(entry.key) ?? MerchantName.displayName(entry.value.latestDescription),
                    amount: entry.value.total,
                    visits: entry.value.visits,
                    usualCategory: usual
                )
            }

        let biggestExpense = biggest.map { found in
            let categoryKey = InsightsService.categoryKey(for: found.tx)
            let described = MerchantName.displayName(found.tx.description)
            return YearReview.BiggestExpense(
                amount: found.amount,
                title: described.isEmpty ? InsightsService.categoryLabel(for: categoryKey) : described,
                categoryKey: categoryKey,
                date: found.tx.date
            )
        }

        return YearReview(
            year: year,
            currency: baseCurrency,
            expenses: expenses,
            income: income,
            monthlyExpenses: monthly,
            lastCompleteMonth: year < currentYear ? 12 : currentMonth - 1,
            topCategories: Array(topCategories),
            topMerchants: topMerchants,
            subscriptionsTotal: subscriptionsTotal,
            subscriptionsCount: chargedSubscriptions.count,
            habit: YearReview.Habit(
                records: records,
                days: recordDays.count,
                longestStreak: longestStreak(recordDays, calendar: calendar)
            ),
            biggestExpense: biggestExpense,
            usedStaleFallback: stale
        )
    }

    /// The longest run of consecutive calendar days among "yyyy-MM-dd" days.
    static func longestStreak(_ days: Set<String>, calendar: Calendar = FastDateParser.calendar) -> Int {
        let dates = days.compactMap(FastDateParser.date(from:)).sorted()
        guard var previous = dates.first else { return 0 }
        var longest = 1
        var run = 1
        for date in dates.dropFirst() {
            let gap = calendar.dateComponents([.day], from: previous, to: date).day ?? 0
            run = gap == 1 ? run + 1 : 1
            longest = max(longest, run)
            previous = date
        }
        return longest
    }
}
