//
//  MerchantHistory.swift
//  Tenra
//
//  One merchant's transactions and figures for its screen (MerchantDetailView): the
//  selected period, this month and this year, its months for the chart, from every expense
//  and income whose description is that merchant (`CategorySuggestionService.normalizedMerchant`),
//  whatever recorded it. A brand's points count together, and operations linked to the
//  merchant by hand count whatever their description says (MerchantGroupStore.Selection).
//
//  The chart's months are the category screen's (CategoryMonthHistory): the same month a
//  year ago and this month's forecast, and two years of them, so the chart opens with this
//  month in the middle (DesignKit centres the current period of a series longer than its
//  window).
//
//  Money goes through SummaryCalculator (red flag #11: `summaryContribution`, future
//  operations left out, a rate snapshot for the base currency). Pure and
//  `nonisolated`: the screen sweeps the whole history off the main actor with it
//  (red flag #9).
//

import Foundation

nonisolated enum MerchantHistory {

    /// Months the screen's chart shows, this one last.
    static let monthsShown = CategoryMonthHistory.monthsShown

    struct Summary: Sendable, Equatable {
        /// The merchant's expenses and income, newest first.
        var transactions: [Transaction]
        var spentInPeriod: Double
        var visitsInPeriod: Int
        var spentAllTime: Double
        var visitsAllTime: Int
        /// "yyyy-MM-dd" of the latest expense up to today.
        var lastVisit: String?
        /// The category most of its expenses carry.
        var usualCategory: String?
        var spentThisMonth: Double
        var spentThisYear: Double
        /// The last `monthsShown` calendar months, oldest first, with a year ago and this
        /// month's forecast.
        var months: [CategoryMonthHistory.Month]

        static let empty = Summary(
            transactions: [], spentInPeriod: 0, visitsInPeriod: 0,
            spentAllTime: 0, visitsAllTime: 0, lastVisit: nil, usualCategory: nil,
            spentThisMonth: 0, spentThisYear: 0, months: []
        )
    }

    /// - Parameters:
    ///   - merchant: a normalized merchant (`CategorySuggestionService.normalizedMerchant`).
    ///   - periodStart, periodEnd: the screen's period, end exclusive (TimeFilter).
    static func summary(
        merchant: String,
        in transactions: [Transaction],
        periodStart: Date,
        periodEnd: Date,
        baseCurrency: String,
        now: Date = Date()
    ) -> Summary {
        summary(
            of: MerchantGroupStore.Selection(merchants: [merchant], links: [:]),
            in: transactions,
            periodStart: periodStart,
            periodEnd: periodEnd,
            baseCurrency: baseCurrency,
            now: now
        )
    }

    /// The figures of several points at once (a brand) and of the operations linked to them.
    static func summary(
        of selection: MerchantGroupStore.Selection,
        in transactions: [Transaction],
        periodStart: Date,
        periodEnd: Date,
        baseCurrency: String,
        now: Date = Date()
    ) -> Summary {
        let merchants = selection.merchants.filter { $0.count >= CategorySuggestionService.minimumMerchantLength }
        guard !merchants.isEmpty else { return .empty }
        let counted = MerchantGroupStore.Selection(merchants: merchants, links: selection.links)

        let mine = transactions
            .filter { tx in
                (tx.type == .expense || tx.type == .income) && counted.contains(tx)
            }
            .sorted { ($0.date, $0.createdAt, $0.id) > ($1.date, $1.createdAt, $1.id) }

        let inPeriod = SummaryCalculator.compute(
            transactions: mine, filterStart: periodStart, filterEnd: periodEnd,
            baseCurrency: baseCurrency, now: now
        )
        let allTime = SummaryCalculator.compute(
            transactions: mine, filterStart: .distantPast, filterEnd: .distantFuture,
            baseCurrency: baseCurrency, now: now
        )

        let today = Calendar.current.startOfDay(for: now)
        var visitsInPeriod = 0
        var visitsAllTime = 0
        var lastVisit: String?
        var categoryCounts: [String: Int] = [:]
        for tx in mine {
            guard let date = FastDateParser.date(from: tx.date),
                  tx.type.summaryContribution(isFuture: date > today) == .expense else { continue }
            visitsAllTime += 1
            if date >= periodStart, date < periodEnd { visitsInPeriod += 1 }
            if lastVisit.map({ tx.date > $0 }) ?? true { lastVisit = tx.date }
            if !tx.category.isEmpty { categoryCounts[tx.category, default: 0] += 1 }
        }
        let usualCategory = categoryCounts
            .max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?
            .key

        let calendar = Calendar.current
        let months = CategoryMonthHistory.months(of: mine, income: false, baseCurrency: baseCurrency, now: now)
        let year = calendar.dateInterval(of: .year, for: now)
        let spentThisYear = year.map { interval in
            SummaryCalculator.compute(
                transactions: mine, filterStart: interval.start, filterEnd: interval.end,
                baseCurrency: baseCurrency, now: now
            ).totalExpenses
        } ?? 0

        return Summary(
            transactions: mine,
            spentInPeriod: inPeriod.totalExpenses,
            visitsInPeriod: visitsInPeriod,
            spentAllTime: allTime.totalExpenses,
            visitsAllTime: visitsAllTime,
            lastVisit: lastVisit,
            usualCategory: usualCategory,
            spentThisMonth: months.last?.total ?? 0,
            spentThisYear: spentThisYear,
            months: months
        )
    }
}
