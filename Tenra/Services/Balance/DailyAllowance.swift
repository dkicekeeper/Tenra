//
//  DailyAllowance.swift
//  Tenra
//
//  "For today" on Home (DailyAllowanceCard): how much can go out a day until the next income,
//  once what is known to go out before it is set aside. The number is Ten's forecast_balance
//  (FinanceToolkit.forecast: the everyday accounts' realized balance, less every subscription
//  and recurring payment, loan payment and planned expense before that day), so Home and the
//  assistant never disagree. Only the horizon is chosen here: the next occurrence of an active
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
        let everyday = store.accounts.filter { !$0.isLoan && !$0.isDeposit && $0.includeInBalance }
        guard !everyday.isEmpty else { return nil }
        let calendar = FastDateParser.calendar
        let incomeCategories = Set(store.categories.filter { $0.type == .income }.map(\.name))
        guard let horizon = horizon(series: store.recurringSeries, incomeCategories: incomeCategories, today: now, calendar: calendar) else {
            return nil
        }
        let toolkit = FinanceToolkit(store: store, now: { now })
        guard let forecast = try? await toolkit.forecast(until: FastDateParser.string(from: horizon.date)) else {
            return nil
        }
        return Value(
            amount: forecast.dailyAllowance,
            currency: forecast.currency,
            income: horizon.isIncome ? horizon.date : nil,
            setAside: forecast.outflowTotal
        )
    }
}
