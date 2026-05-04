//
//  HealthScoreWeightingCard.swift
//  Tenra
//
//  Educational card explaining the 5-component weighting of the health score.
//  When budgets are absent the bar/legend collapses to 4 segments with
//  redistributed weights.
//

import SwiftUI

struct HealthScoreWeightingCard: View {
    let isBudgetComponentActive: Bool

    private struct Segment: Identifiable {
        let id: String
        let titleKey: String   // "insights.health.component.<name>.short"
        let icon: String
        let color: Color
        let weight: Double     // 0…100
    }

    private var segments: [Segment] {
        if isBudgetComponentActive {
            return [
                Segment(id: "savingsRate",      titleKey: "insights.health.component.savingsRate.short",      icon: "banknote.fill",                       color: AppColors.success,     weight: 30),
                Segment(id: "budgetAdherence",  titleKey: "insights.health.component.budgetAdherence.short",  icon: "gauge.with.dots.needle.33percent",    color: AppColors.warning,     weight: 25),
                Segment(id: "recurringRatio",   titleKey: "insights.health.component.recurringRatio.short",   icon: "repeat.circle",                       color: AppColors.accent,      weight: 20),
                Segment(id: "emergencyFund",    titleKey: "insights.health.component.emergencyFund.short",    icon: "shield.lefthalf.filled",              color: AppColors.income,      weight: 15),
                Segment(id: "cashFlow",         titleKey: "insights.health.component.cashFlow.short",         icon: "chart.line.uptrend.xyaxis",           color: AppColors.destructive, weight: 10),
            ]
        } else {
            // Redistributed weights from computeHealthScore (40 / 26.7 / 20 / 13.3)
            return [
                Segment(id: "savingsRate",      titleKey: "insights.health.component.savingsRate.short",      icon: "banknote.fill",                       color: AppColors.success,     weight: 40),
                Segment(id: "recurringRatio",   titleKey: "insights.health.component.recurringRatio.short",   icon: "repeat.circle",                       color: AppColors.accent,      weight: 26.7),
                Segment(id: "emergencyFund",    titleKey: "insights.health.component.emergencyFund.short",    icon: "shield.lefthalf.filled",              color: AppColors.income,      weight: 20),
                Segment(id: "cashFlow",         titleKey: "insights.health.component.cashFlow.short",         icon: "chart.line.uptrend.xyaxis",           color: AppColors.destructive, weight: 13.3),
            ]
        }
    }

    var body: some View {
        let resolvedSegments = segments
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "insights.health.howItWorks"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)

            Text(String(localized: "insights.health.explainer"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            stackBar(resolvedSegments)
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(spacing: AppSpacing.sm) {
                ForEach(resolvedSegments) { segment in
                    legendRow(segment)
                }
            }

            if !isBudgetComponentActive {
                Text(String(localized: "insights.health.weights.redistributed"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    private func stackBar(_ resolvedSegments: [Segment]) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(resolvedSegments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: proxy.size.width * segment.weight / 100.0)
                }
            }
        }
    }

    private func legendRow(_ segment: Segment) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: segment.icon)
                .font(.system(size: AppIconSize.sm))
                .foregroundStyle(segment.color)
                .frame(width: 24)

            Text(String(localized: String.LocalizationValue(segment.titleKey)))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Text(String(format: String(localized: "insights.health.weightLabel"), Int(segment.weight.rounded())))
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

// MARK: - Previews

#Preview("With budgets") {
    HealthScoreWeightingCard(isBudgetComponentActive: true)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Without budgets — 4 segments") {
    HealthScoreWeightingCard(isBudgetComponentActive: false)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}
