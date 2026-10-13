//
//  AmountHeroCards.swift
//  Tenra
//
//  The tops of two insight details, edge to edge on the colour of the insight's tone, over
//  DesignKit's `ScoreGaugeCard(amount:)` in the `.hero` style (4.5.0). The amount in the app's
//  amount format (hidden with the other amounts), a gauge and a capsule under it:
//  - LargeTransactionHeroCard: the expense against the usual one (its notch), "13.9× the usual";
//  - BudgetHeadroomHeroCard: what is left against the budgets it is left of, how many
//    categories are on track.
//  Each replaces the detail's header and its half gauge for its insight.
//

import SwiftUI

struct LargeTransactionHeroCard: View {
    /// The expense, in `currency`.
    let amount: Double
    /// The average expense it is compared with (the feed card's gauge norm).
    let usual: Double
    let currency: String
    /// The insight's severity colour.
    let color: Color
    /// What it was and when (the insight's subtitle).
    let subtitle: String
    var entranceDelay: Double = 0

    var body: some View {
        ScoreGaugeCard(
            amount: amount,
            currency: currency,
            maxValue: amount * 1.15,
            norm: usual,
            grade: Self.timesText(amount: amount, usual: usual),
            color: color,
            subtitle: subtitle,
            style: .hero,
            entranceDelay: entranceDelay
        )
    }

    /// "13.9× the usual", the multiple in the app's locale with one decimal.
    static func timesText(amount: Double, usual: Double) -> String {
        let multiple = usual > 0 ? amount / usual : 0
        return String(
            format: String(localized: "insights.largeTransaction.timesUsual"),
            multiple.formatted(.number.precision(.fractionLength(1)))
        )
    }
}

struct BudgetHeadroomHeroCard: View {
    /// What is left of the budgets, in `currency`.
    let headroom: Double
    /// The budgets it is left of (the feed card's gauge norm).
    let budget: Double
    let currency: String
    /// The insight's severity colour.
    let color: Color
    /// How many categories are on track (the insight's subtitle).
    let categoriesText: String
    var entranceDelay: Double = 0

    @Environment(\.amountsHidden) private var amountsHidden

    var body: some View {
        ScoreGaugeCard(
            amount: headroom,
            currency: currency,
            maxValue: max(budget, headroom),
            grade: categoriesText,
            color: color,
            subtitle: String(
                format: String(localized: "insights.budgetHeadroom.leftOf"),
                amountsHidden
                    ? Formatting.hiddenAmount(currency: currency)
                    : Formatting.formatCurrencySmart(budget, currency: currency)
            ),
            style: .hero,
            entranceDelay: entranceDelay
        )
    }
}

// MARK: - Previews

#Preview("Large transaction") {
    ScrollView {
        LargeTransactionHeroCard(amount: 84_900, usual: 6_100, currency: "KZT", color: AppColors.warning,
                                 subtitle: "Furniture, 3 Oct")
    }
}

#Preview("Budget headroom") {
    ScrollView {
        BudgetHeadroomHeroCard(headroom: 145_000, budget: 380_000, currency: "KZT", color: AppColors.success,
                               categoriesText: "3 categories on track")
    }
}
