//
//  FinancialHealthDetailView.swift
//  Tenra
//
//  Educational + diagnostic detail screen for the composite Financial
//  Health score. Hero, weighting explainer, five inline component cards.
//

import SwiftUI

struct FinancialHealthDetailView: View {
    let score: FinancialHealthScore

    private var isAvailable: Bool {
        score.totalIncomeWindow > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                HealthScoreHeroCard(score: score, isAvailable: isAvailable)
                    .screenPadding()

                HealthScoreWeightingCard(
                    isBudgetComponentActive: score.isBudgetComponentActive,
                    monthsInWindow: score.monthsInWindow
                )
                .screenPadding()

                if isAvailable {
                    componentsSection
                } else {
                    EmptyStateView(
                        icon: "chart.bar.doc.horizontal",
                        title: String(localized: "insights.health.unavailable.title"),
                        description: String(localized: "insights.health.unavailable.message")
                    )
                    .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(String(localized: "insights.healthScore"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Components

    private var componentsSection: some View {
        VStack(spacing: AppSpacing.lg) {
            HealthComponentCard(model: makeSavingsRateModel())
            HealthComponentCard(model: makeBudgetAdherenceModel())
            HealthComponentCard(model: makeRecurringRatioModel())
            HealthComponentCard(model: makeEmergencyFundModel())
            HealthComponentCard(model: makeCashFlowModel())
        }
        .screenPadding()
    }

    // MARK: - Component model builders

    private func makeSavingsRateModel() -> HealthComponentDisplayModel {
        HealthComponentDisplayModel(
            id: "savingsRate",
            titleKey: "insights.health.component.savingsRate.title",
            explainerKey: "insights.health.component.savingsRate.explainer",
            icon: "banknote.fill",
            color: AppColors.success,
            weight: 30,
            componentScore: score.savingsRateScore,
            currentValueText: String(format: "%.1f%%", score.savingsRatePercent),
            targetTextKey: "insights.health.target.savingsRate",
            progress: min(max(score.savingsRatePercent, 0) / 20.0, 1),
            recommendation: HealthRecommendationBuilder.savingsRateRecommendation(score),
            isMuted: false
        )
    }

    private func makeBudgetAdherenceModel() -> HealthComponentDisplayModel {
        let muted = !score.isBudgetComponentActive
        let progress: Double = score.budgetsTotal > 0
            ? Double(score.budgetsOnTrack) / Double(score.budgetsTotal)
            : 0
        let valueText = score.budgetsTotal > 0
            ? "\(score.budgetsOnTrack)/\(score.budgetsTotal)"
            : "—"
        return HealthComponentDisplayModel(
            id: "budgetAdherence",
            titleKey: "insights.health.component.budgetAdherence.title",
            explainerKey: "insights.health.component.budgetAdherence.explainer",
            icon: "gauge.with.dots.needle.33percent",
            color: AppColors.warning,
            weight: 25,
            componentScore: score.budgetAdherenceScore,
            currentValueText: valueText,
            targetTextKey: "insights.health.target.budgetAdherence",
            progress: progress,
            recommendation: HealthRecommendationBuilder.budgetAdherenceRecommendation(score),
            isMuted: muted
        )
    }

    private func makeRecurringRatioModel() -> HealthComponentDisplayModel {
        // Bar fills as the recurring share *decreases*. 0% recurring → bar full.
        let progress = max(0, min(1, 1.0 - (score.recurringPercentOfIncome / 100.0)))
        return HealthComponentDisplayModel(
            id: "recurringRatio",
            titleKey: "insights.health.component.recurringRatio.title",
            explainerKey: "insights.health.component.recurringRatio.explainer",
            icon: "repeat.circle",
            color: AppColors.accent,
            weight: 20,
            componentScore: score.recurringRatioScore,
            currentValueText: String(format: "%.0f%%", score.recurringPercentOfIncome),
            targetTextKey: "insights.health.target.recurringRatio",
            progress: progress,
            recommendation: HealthRecommendationBuilder.recurringRatioRecommendation(score),
            isMuted: false
        )
    }

    private func makeEmergencyFundModel() -> HealthComponentDisplayModel {
        let progress = min(max(score.monthsCovered, 0) / 3.0, 1)
        let valueText: String
        if score.avgMonthlyExpenses == 0 {
            valueText = "12+"  // unbounded: cap display
        } else {
            valueText = String(format: "%.1f", score.monthsCovered)
        }
        return HealthComponentDisplayModel(
            id: "emergencyFund",
            titleKey: "insights.health.component.emergencyFund.title",
            explainerKey: "insights.health.component.emergencyFund.explainer",
            icon: "shield.lefthalf.filled",
            color: AppColors.income,
            weight: 15,
            componentScore: score.emergencyFundScore,
            currentValueText: valueText,
            targetTextKey: "insights.health.target.emergencyFund",
            progress: progress,
            recommendation: HealthRecommendationBuilder.emergencyFundRecommendation(score),
            isMuted: false
        )
    }

    private func makeCashFlowModel() -> HealthComponentDisplayModel {
        // Map -20% … +20% → 0 … 1, matching the formula's normalisation.
        let progress = max(0, min(1, (score.netFlowPercent + 20) / 40.0))
        return HealthComponentDisplayModel(
            id: "cashFlow",
            titleKey: "insights.health.component.cashFlow.title",
            explainerKey: "insights.health.component.cashFlow.explainer",
            icon: "chart.line.uptrend.xyaxis",
            color: AppColors.destructive,
            weight: 10,
            componentScore: score.cashflowScore,
            currentValueText: String(format: "%+.1f%%", score.netFlowPercent),
            targetTextKey: "insights.health.target.cashFlow",
            progress: progress,
            recommendation: HealthRecommendationBuilder.cashFlowRecommendation(score),
            isMuted: false
        )
    }
}

// MARK: - Previews

#Preview("Good") {
    NavigationStack {
        FinancialHealthDetailView(score: .mockGood())
    }
}

#Preview("Needs attention") {
    NavigationStack {
        FinancialHealthDetailView(score: .mockNeedsAttention())
    }
}

#Preview("Unavailable") {
    NavigationStack {
        FinancialHealthDetailView(score: .unavailable())
    }
}
