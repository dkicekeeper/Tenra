//
//  CategoryMonthHistory.swift
//  Tenra
//
//  A category's last 12 calendar months for its screen's chart (CategoryDetailView), each
//  with the same month a year before and, for this month, where it is heading.
//
//  Money goes through SummaryCalculator (red flag #11: `summaryContribution`, future
//  operations left out, a rate snapshot for the base currency), as MerchantHistory does.
//  Pure and `nonisolated`: the screen runs it off the main actor (red flag #9).
//

import Foundation

nonisolated enum CategoryMonthHistory {
    /// Months the chart shows, this one last.
    static let monthsShown = 12

    struct Month: Sendable, Equatable {
        /// "yyyy-MM"
        let key: String
        let start: Date
        /// Spent (an expense category) or received (an income category) in the month.
        let total: Double
        /// The same month a year before; `nil` before the category's first operation.
        let yearAgo: Double?
        /// This month only: what it comes to at the pace of the three months before it.
        let forecast: Double?
        let isCurrent: Bool
    }

    /// - Parameters:
    ///   - transactions: the category's transactions (its index bucket).
    ///   - income: an income category: what came in, else what went out.
    static func months(
        of transactions: [Transaction],
        income: Bool,
        baseCurrency: String,
        now: Date = Date()
    ) -> [Month] {
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        let firstDate = transactions.lazy.compactMap { FastDateParser.date(from: $0.date) }.min()

        // 24 months: the 12 shown and the 12 before them, for "a year ago".
        var totals: [(key: String, start: Date, end: Date, total: Double)] = []
        for offset in stride(from: monthsShown * 2 - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: monthStart),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            let summary = SummaryCalculator.compute(
                transactions: transactions, filterStart: start, filterEnd: end,
                baseCurrency: baseCurrency, now: now
            )
            let parts = calendar.dateComponents([.year, .month], from: start)
            let key = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
            totals.append((key, start, end, income ? summary.totalIncome : summary.totalExpenses))
        }
        guard totals.count == monthsShown * 2 else { return [] }

        return (monthsShown..<totals.count).map { i in
            let month = totals[i]
            let isCurrent = i == totals.count - 1
            // A month before the first operation had nothing to compare with.
            let before = totals[i - monthsShown]
            let yearAgo = firstDate.map { before.end > $0 } == true ? before.total : nil
            var forecast: Double?
            if isCurrent, !income {
                let previous = totals[(i - 3)..<i].map(\.total)
                let typical = previous.reduce(0, +) / Double(previous.count)
                let length = month.end.timeIntervalSince(month.start)
                let elapsed = length > 0 ? min(max(now.timeIntervalSince(month.start) / length, 0), 1) : 1
                forecast = typical > 0 ? month.total + typical * (1 - elapsed) : nil
            }
            return Month(key: month.key, start: month.start, total: month.total,
                         yearAgo: yearAgo, forecast: forecast, isCurrent: isCurrent)
        }
    }
}
