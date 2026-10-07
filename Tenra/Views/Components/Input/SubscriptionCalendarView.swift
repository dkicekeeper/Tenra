//
//  SubscriptionCalendarView.swift
//  Tenra
//
//  Created on 2024
//
//  The calendar itself (week strip ↔ month grid, day cells, markers) is DesignKit's
//  MonthCalendar since DesignKit 0.7.0. Tenra keeps what it puts on it: subscription logos
//  on their billing days and the period total in the base currency.
//

import SwiftUI

struct SubscriptionCalendarView: View {
    let subscriptions: [RecurringSeries]
    let baseCurrency: String

    @State private var range = CalendarRange()
    /// Subscriptions keyed by the start of each billing day across the whole range.
    @State private var subscriptionsByDay: [Date: [RecurringSeries]] = [:]
    /// Total due in each week and month, in the base currency.
    @State private var totals: [CalendarPeriod: Decimal] = [:]

    var body: some View {
        MonthCalendar(range: range, itemsByDay: subscriptionsByDay, itemName: { $0.description }) { sub in
            Icon(source: sub.iconSource, size: AppIconSize.md)
        } accessory: { period in
            if let total = totals[period], total > 0 {
                FormattedAmountText(
                    amount: NSDecimalNumber(decimal: total).doubleValue,
                    currency: baseCurrency,
                    fontSize: AppTypography.h4,
                    color: AppColors.textPrimary
                )
            }
        }
        .onAppear { rebuildSubscriptionsByDay() }
        .task { await refreshTotals() }
        .onChange(of: subscriptions.count) { _, _ in
            rebuildSubscriptionsByDay()
            Task { await refreshTotals() }
        }
        .onChange(of: baseCurrency) { _, _ in
            Task { await refreshTotals() }
        }
    }

    private func rebuildSubscriptionsByDay() {
        subscriptionsByDay = range.itemsByDay(subscriptions) { sub, interval in
            sub.occurrences(in: interval)
        }
    }

    /// `occurrences(in:)` includes the interval's end, so each period ends a second before
    /// the next one starts.
    private func refreshTotals() async {
        var result: [CalendarPeriod: Decimal] = [:]
        for period in range.months + range.weeks {
            var total: Decimal = 0
            for subscription in subscriptions {
                let count = subscription.occurrences(in: period.closedInterval).count
                guard count > 0 else { continue }
                let amount = NSDecimalNumber(decimal: subscription.amount).doubleValue
                let converted = await CurrencyConverter.convert(
                    amount: amount, from: subscription.currency, to: baseCurrency
                ) ?? amount
                total += Decimal(converted) * Decimal(count)
            }
            result[period] = total
        }
        totals = result
    }
}

// MARK: - Previews

#Preview("With Subscriptions") {
    let calendar = Calendar.current
    let today = Date()
    let formatter = ISO8601DateFormatter()

    let mockSubscriptions = [
        RecurringSeries(
            amount: 9.99,
            currency: "USD",
            category: "Развлечения",
            description: "Netflix",
            frequency: .monthly,
            startDate: formatter.string(from: calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: today))!),
            iconSource: .brandService("netflix")
        ),
        RecurringSeries(
            amount: 14.99,
            currency: "USD",
            category: "Развлечения",
            description: "Spotify",
            frequency: .monthly,
            startDate: formatter.string(from: calendar.date(byAdding: .day, value: 12, to: calendar.startOfDay(for: today))!),
            iconSource: .brandService("spotify")
        ),
        RecurringSeries(
            amount: 299,
            currency: "RUB",
            category: "Коммуналка",
            description: "Интернет",
            frequency: .monthly,
            startDate: formatter.string(from: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!)
        ),
        RecurringSeries(
            amount: 4.99,
            currency: "USD",
            category: "Облако",
            description: "iCloud Storage",
            frequency: .monthly,
            startDate: formatter.string(from: today),
            iconSource: .brandService("icloud")
        )
    ]

    SubscriptionCalendarView(subscriptions: mockSubscriptions, baseCurrency: "USD")
        .padding()
}

#Preview("Empty Calendar") {
    SubscriptionCalendarView(subscriptions: [], baseCurrency: "USD")
        .padding()
}
