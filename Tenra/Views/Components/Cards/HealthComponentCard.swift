//
//  HealthComponentCard.swift
//  Tenra
//
//  One component card on the Financial Health detail screen.
//  Header → score contribution → current/target value → progress bar →
//  explainer → contextual recommendation.
//

import SwiftUI

/// Display-side model — value-type, Sendable, no domain coupling beyond the
/// single string it carries for the recommendation.
struct HealthComponentDisplayModel: Identifiable, Sendable {
    let id: String                // stable id, e.g. "savingsRate"
    let titleKey: String          // "insights.health.component.<name>.title"
    let explainerKey: String      // "insights.health.component.<name>.explainer"
    let icon: String              // SF Symbol name
    let color: Color              // tint for icon + bar accents
    let weight: Int               // 30 / 25 / 20 / 15 / 10
    let componentScore: Int       // 0…100
    let currentValueText: String  // pre-formatted, e.g. "12.4%" or "1.8 mo"
    let targetTextKey: String     // "insights.health.target.<name>"
    let progress: Double          // 0…1, normalised to target
    let recommendation: String    // ready-to-render localized copy
    let isMuted: Bool             // true when budgetAdherence is disabled
}

struct HealthComponentCard: View {
    let model: HealthComponentDisplayModel

    private var progressColor: Color {
        switch model.progress {
        case ..<0.33: return AppColors.destructive
        case ..<0.66: return AppColors.warning
        default:      return AppColors.success
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            headerRow
            scoreRow
            valueRow
            progressBar
            explainer
            recommendationBox
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        .opacity(model.isMuted ? 0.6 : 1.0)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: model.icon)
                .font(.system(size: AppIconSize.md))
                .foregroundStyle(model.color)
                .frame(width: 28)

            Text(String(localized: String.LocalizationValue(model.titleKey)))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Text(String(format: String(localized: "insights.health.weightLabel"), model.weight))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(AppColors.textSecondary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - Score

    private var scoreRow: some View {
        Text(String(format: String(localized: "insights.health.scoreContribution"), model.componentScore))
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
    }

    // MARK: - Current vs Target

    private var valueRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(String(localized: "insights.health.currentValue"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Text(model.currentValueText)
                    .font(AppTypography.h2.bold())
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                Text(String(localized: "insights.health.target"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Text(String(localized: String.LocalizationValue(model.targetTextKey)))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        BudgetProgressBar(
            percentage: model.progress * 100,
            isOverBudget: false,
            color: progressColor
        )
    }

    // MARK: - Explainer

    private var explainer: some View {
        Text(String(localized: String.LocalizationValue(model.explainerKey)))
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Recommendation

    private var recommendationBox: some View {
        RecommendationBox(text: model.recommendation, color: model.color)
    }
}

// MARK: - Previews

#Preview("Savings — below target") {
    HealthComponentCard(model: HealthComponentDisplayModel(
        id: "savingsRate",
        titleKey: "insights.health.component.savingsRate.title",
        explainerKey: "insights.health.component.savingsRate.explainer",
        icon: "banknote.fill",
        color: AppColors.success,
        weight: 30,
        componentScore: 50,
        currentValueText: "10.0%",
        targetTextKey: "insights.health.target.savingsRate",
        progress: 0.5,
        recommendation: "To reach 20%, cut expenses by ≈ 60 000 ₸/mo or grow income by ≈ 75 000 ₸/mo.",
        isMuted: false
    ))
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Budget — muted (no budgets)") {
    HealthComponentCard(model: HealthComponentDisplayModel(
        id: "budgetAdherence",
        titleKey: "insights.health.component.budgetAdherence.title",
        explainerKey: "insights.health.component.budgetAdherence.explainer",
        icon: "gauge.with.dots.needle.33percent",
        color: AppColors.warning,
        weight: 25,
        componentScore: 0,
        currentValueText: "—",
        targetTextKey: "insights.health.target.budgetAdherence",
        progress: 0,
        recommendation: "Budgets aren't configured. Set them up on your categories — this component will then count toward the score.",
        isMuted: true
    ))
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
