//
//  DailyAllowanceCard.swift
//  Tenra
//
//  "For today" on Home: how much can go out a day until the next income (or the month's end)
//  once the subscriptions, loan payments and planned expenses before it are set aside. An
//  adapter over DesignKit's FinanceCard; the figure comes from DailyAllowanceCalculator, the
//  same rule as Ten's forecast_balance.
//

import SwiftUI

struct DailyAllowanceCard: View {
    let amount: Double
    let currency: String
    /// The day the allowance runs to: the next income's date, or nil for the month's end.
    let until: Date?
    /// Set aside before `until`: subscriptions, loan payments, planned expenses.
    let setAside: Double
    let isLoading: Bool

    @Environment(\.amountsHidden) private var amountsHidden

    var body: some View {
        FinanceCard(
            title: String(localized: "home.today.title"),
            isEmpty: false,
            emptyTitle: "",
            subtitle: subtitle
        ) {
            RedactableAmount(amount: amount, currency: currency, isLoading: isLoading)
        } trailing: {
            Icon(
                source: .sfSymbol("sun.max.fill"),
                style: .circle(
                    size: AppIconSize.Tile.md,
                    tint: .monochrome(AppColors.accent),
                    backgroundColor: AppColors.accent.opacity(0.15)
                )
            )
        }
    }

    private var subtitle: String {
        let span: String
        if let until {
            span = String(
                format: String(localized: "home.today.untilIncome"),
                until.formatted(.dateTime.day().month(.abbreviated))
            )
        } else {
            span = String(localized: "home.today.untilMonthEnd")
        }
        guard setAside > 0, !amountsHidden else { return span }
        // The amount never breaks across lines: its group separators become non-breaking.
        let amount = Formatting.formatCurrencySmart(setAside, currency: currency)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
        return span + "\n" + String(format: String(localized: "home.today.setAside"), amount)
    }
}

#Preview {
    VStack {
        DailyAllowanceCard(amount: 8_400, currency: "KZT", until: Date().addingTimeInterval(6 * 86_400), setAside: 23_990, isLoading: false)
        DailyAllowanceCard(amount: 3_150, currency: "KZT", until: nil, setAside: 0, isLoading: false)
    }
    .screenPadding()
}
