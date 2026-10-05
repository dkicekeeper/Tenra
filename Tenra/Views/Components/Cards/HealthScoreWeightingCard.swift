//
//  HealthScoreWeightingCard.swift
//  Tenra
//
//  Educational card explaining the 5-component weighting of the health score.
//  When budgets are absent the bar/legend collapses to 4 segments with
//  redistributed weights. Adapter over DesignKit's `WeightBreakdownCard`: the
//  components, weights and copy are Tenra's; the card is DesignKit's.
//

import SwiftUI

struct HealthScoreWeightingCard: View {
    let isBudgetComponentActive: Bool
    let monthsInWindow: Int

    private var periodContextText: String {
        if monthsInWindow <= 1 {
            return String(localized: "insights.health.periodContext.singleMonth")
        }
        let format = String(localized: "insights.health.periodContext.months")
        return String(format: format, monthsInWindow)
    }

    private struct Component {
        let id: String
        let titleKey: String   // "insights.health.component.<name>.short"
        let icon: String
        let color: Color
        let weight: Double     // 0…100
    }

    private var components: [Component] {
        if isBudgetComponentActive {
            return [
                Component(id: "savingsRate",      titleKey: "insights.health.component.savingsRate.short",      icon: "banknote.fill",                       color: AppColors.success,     weight: 30),
                Component(id: "budgetAdherence",  titleKey: "insights.health.component.budgetAdherence.short",  icon: "gauge.with.dots.needle.33percent",    color: AppColors.warning,     weight: 25),
                Component(id: "recurringRatio",   titleKey: "insights.health.component.recurringRatio.short",   icon: "repeat.circle",                       color: AppColors.accent,      weight: 20),
                Component(id: "emergencyFund",    titleKey: "insights.health.component.emergencyFund.short",    icon: "shield.lefthalf.filled",              color: AppColors.income,      weight: 15),
                Component(id: "cashFlow",         titleKey: "insights.health.component.cashFlow.short",         icon: "chart.line.uptrend.xyaxis",           color: AppColors.destructive, weight: 10),
            ]
        } else {
            // Redistributed weights from computeHealthScore (40 / 26.7 / 20 / 13.3)
            return [
                Component(id: "savingsRate",      titleKey: "insights.health.component.savingsRate.short",      icon: "banknote.fill",                       color: AppColors.success,     weight: 40),
                Component(id: "recurringRatio",   titleKey: "insights.health.component.recurringRatio.short",   icon: "repeat.circle",                       color: AppColors.accent,      weight: 26.7),
                Component(id: "emergencyFund",    titleKey: "insights.health.component.emergencyFund.short",    icon: "shield.lefthalf.filled",              color: AppColors.income,      weight: 20),
                Component(id: "cashFlow",         titleKey: "insights.health.component.cashFlow.short",         icon: "chart.line.uptrend.xyaxis",           color: AppColors.destructive, weight: 13.3),
            ]
        }
    }

    var body: some View {
        WeightBreakdownCard(
            title: String(localized: "insights.health.howItWorks"),
            message: String(localized: "insights.health.explainer"),
            caption: periodContextText,
            segments: components.map { component in
                WeightBreakdownCard.Segment(
                    id: component.id,
                    title: String(localized: String.LocalizationValue(component.titleKey)),
                    systemImage: component.icon,
                    color: component.color,
                    weight: component.weight,
                    weightLabel: String(
                        format: String(localized: "insights.health.weightLabel"),
                        Int(component.weight.rounded())
                    )
                )
            },
            footnote: isBudgetComponentActive
                ? nil
                : String(localized: "insights.health.weights.redistributed")
        )
    }
}

// MARK: - Previews

#Preview("With budgets") {
    HealthScoreWeightingCard(isBudgetComponentActive: true, monthsInWindow: 6)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Without budgets — 4 segments") {
    HealthScoreWeightingCard(isBudgetComponentActive: false, monthsInWindow: 1)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}
