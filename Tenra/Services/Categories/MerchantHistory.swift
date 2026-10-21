//
//  MerchantHistory.swift
//  Tenra
//
//  One merchant's transactions and figures for its screen (MerchantDetailView): the
//  selected period, this month and this year, the last 12 months for its chart, from every
//  expense and income whose description is that merchant
//  (`CategorySuggestionService.normalizedMerchant`), whatever recorded it.
//
//  Money goes through SummaryCalculator (red flag #11: `summaryContribution`, future
//  operations left out, a rate snapshot for the base currency). Pure and
//  `nonisolated`: the screen sweeps the whole history off the main actor with it
//  (red flag #9).
//

import Foundation

nonisolated enum MerchantHistory {

    /// Months the screen's chart shows, this one last.
    static let monthsShown = 12

    /// What was spent at the merchant in one calendar month.
    struct MonthTotal: Sendable, Equatable {
        /// "yyyy-MM"
        let key: String
        let start: Date
        let spent: Double
    }

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
        /// The last `monthsShown` calendar months, oldest first.
        var months: [MonthTotal]

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
        guard merchant.count >= CategorySuggestionService.minimumMerchantLength else { return .empty }

        let mine = transactions
            .filter { tx in
                (tx.type == .expense || tx.type == .income)
                    && CategorySuggestionService.normalizedMerchant(tx.description) == merchant
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
        let spent: (Date, Date) -> Double = { start, end in
            SummaryCalculator.compute(
                transactions: mine, filterStart: start, filterEnd: end,
                baseCurrency: baseCurrency, now: now
            ).totalExpenses
        }
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? today
        var months: [MonthTotal] = []
        for offset in stride(from: monthsShown - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: monthStart),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            let parts = calendar.dateComponents([.year, .month], from: start)
            let key = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
            months.append(MonthTotal(key: key, start: start, spent: spent(start, end)))
        }
        let year = calendar.dateInterval(of: .year, for: now)
        let spentThisYear = year.map { spent($0.start, $0.end) } ?? 0

        return Summary(
            transactions: mine,
            spentInPeriod: inPeriod.totalExpenses,
            visitsInPeriod: visitsInPeriod,
            spentAllTime: allTime.totalExpenses,
            visitsAllTime: visitsAllTime,
            lastVisit: lastVisit,
            usualCategory: usualCategory,
            spentThisMonth: months.last?.spent ?? 0,
            spentThisYear: spentThisYear,
            months: months
        )
    }
}
