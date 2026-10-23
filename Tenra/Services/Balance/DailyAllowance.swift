//
//  DailyAllowance.swift
//  Tenra
//
//  "For today" on Analytics and in the widget (DailyAllowanceLink, the For today widget): how
//  much can go out a day until the next income, once what is known to go out before it is set
//  aside. The number is Ten's forecast_balance (FinanceToolkit.forecast: the realized balance of
//  the accounts that count for today, `Account.countsForToday`, less every subscription and
//  recurring payment, loan payment and planned expense before that day, each in the base
//  currency), so the app and the assistant never disagree. Only the horizon is chosen here: the next occurrence of an active
//  income series within `maxHorizonDays`, else the first day of next month.
//

import Foundation

enum DailyAllowance {
    struct Value: Equatable {
        let amount: Double
        let currency: String
        /// The next income's date; nil when the allowance runs to the month's end.
        let income: Date?
        /// Set aside before the horizon: subscriptions, loan payments, planned expenses.
        let setAside: Double
        /// How it is reached (the insight's "How it's calculated"), exact where `amount` and `setAside` are
        /// rounded: today's balance of the everyday accounts, less `outflows`, leaves `free`,
        /// spread over `days`.
        var startBalance: Double = 0
        var free: Double = 0
        var days: Int = 0
        var outflows: [Outflow] = []
        /// Currencies with no rate: their payments are not in `outflows` (the breakdown says so).
        var missingRates: [String] = []
    }

    /// A payment set aside before the horizon, in the base currency, with what it is (for its
    /// icon: the series' or the loan's logo, else the category's).
    struct Outflow: Equatable {
        let date: Date
        let label: String
        let amount: Double
        var seriesId: String? = nil
        var loanAccountId: String? = nil
        var category: String? = nil
    }

    /// An income further away than this is not "your income": the month's end is the horizon.
    static let maxHorizonDays = 45

    /// The day the allowance runs to, and whether it is an income's. Pure, for the tests.
    static func horizon(
        series: [RecurringSeries],
        incomeCategories: Set<String>,
        today: Date,
        calendar: Calendar
    ) -> (date: Date, isIncome: Bool)? {
        let start = calendar.startOfDay(for: today)
        let nextIncome = series
            .filter { $0.isActive && $0.targetAccountId == nil && incomeCategories.contains($0.category) }
            .compactMap { income -> Date? in
                guard let first = FastDateParser.date(from: income.startDate) else { return nil }
                return first > start
                    ? first
                    : RecurringDateMath.firstOccurrence(after: start, start: first, frequency: income.frequency, calendar: calendar)
            }
            .filter { date in
                guard let days = calendar.dateComponents([.day], from: start, to: date).day else { return false }
                return days > 0 && days <= maxHorizonDays
            }
            .min()
        if let nextIncome { return (nextIncome, true) }
        // The first day of next month: the allowance covers the rest of this one.
        guard let interval = calendar.dateInterval(of: .month, for: start) else { return nil }
        return (interval.end, false)
    }

    /// The allowance for today, or nil without an everyday account to spend from.
    @MainActor
    static func value(store: TransactionStore, now: Date = Date()) async -> Value? {
        guard store.accounts.contains(where: \.countsForToday) else { return nil }
        let calendar = FastDateParser.calendar
        let incomeCategories = Set(store.categories.filter { $0.type == .income }.map(\.name))
        guard let horizon = horizon(series: store.recurringSeries, incomeCategories: incomeCategories, today: now, calendar: calendar) else {
            return nil
        }
        let toolkit = FinanceToolkit(store: store, now: { now })
        guard let forecast = try? await toolkit.forecast(until: FastDateParser.string(from: horizon.date)) else {
            return nil
        }
        // Whole units: kopecks in a day's allowance are noise. The allowance rounds down and
        // what is set aside rounds up, so neither promises more than there is.
        return Value(
            amount: forecast.dailyAllowance.rounded(.down),
            currency: forecast.currency,
            income: horizon.isIncome ? horizon.date : nil,
            setAside: forecast.outflowTotal.rounded(.up),
            startBalance: forecast.startBalance,
            free: forecast.free,
            days: forecast.days,
            outflows: forecast.outflows.compactMap { outflow in
                FastDateParser.date(from: outflow.date).map {
                    Outflow(
                        date: $0, label: outflow.label, amount: outflow.amount,
                        seriesId: outflow.seriesId, loanAccountId: outflow.loanAccountId, category: outflow.category
                    )
                }
            },
            missingRates: forecast.missingRates.sorted()
        )
    }
}
