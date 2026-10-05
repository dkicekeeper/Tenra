//
//  PeriodComparisonCard.swift
//  Tenra
//
//  Period-over-period comparison card (current vs previous). Adapter over DesignKit's
//  `ComparisonCard`: keeps the expense / income wording.
//

import SwiftUI

/// Glass card comparing two adjacent time periods.
/// Shows: previous amount | direction arrow + change% | current amount.
///
/// - Parameter isExpenseContext: if true, an increase is shown in red (costs more = bad).
///   If false (income), an increase is shown in green (earns more = good).
struct PeriodComparisonCard: View {
    let currentLabel: String
    let currentAmount: Double
    let previousLabel: String
    let previousAmount: Double
    let currency: String
    var isExpenseContext: Bool = true

    var body: some View {
        ComparisonCard(
            previousLabel: previousLabel,
            previousAmount: previousAmount,
            currentLabel: currentLabel,
            currentAmount: currentAmount,
            currency: currency,
            increaseIsGood: !isExpenseContext
        )
    }
}

// MARK: - Previews

#Preview("Expense increase (bad)") {
    PeriodComparisonCard(
        currentLabel: "Feb 2026", currentAmount: 120_000,
        previousLabel: "Jan 2026", previousAmount: 95_000,
        currency: "KZT", isExpenseContext: true
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Expense decrease (good)") {
    PeriodComparisonCard(
        currentLabel: "Feb 2026", currentAmount: 75_000,
        previousLabel: "Jan 2026", previousAmount: 95_000,
        currency: "KZT", isExpenseContext: true
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Income increase (good)") {
    PeriodComparisonCard(
        currentLabel: "Feb 2026", currentAmount: 620_000,
        previousLabel: "Jan 2026", previousAmount: 530_000,
        currency: "KZT", isExpenseContext: false
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
