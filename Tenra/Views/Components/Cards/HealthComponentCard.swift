//
//  HealthComponentCard.swift
//  Tenra
//
//  One component card on the Financial Health detail screen.
//  Header → score contribution → current/target value → progress bar →
//  explainer → contextual recommendation. Adapter over DesignKit's
//  `TargetProgressCard`: resolves the component's copy keys.
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

    var body: some View {
        TargetProgressCard(
            systemImage: model.icon,
            color: model.color,
            title: String(localized: String.LocalizationValue(model.titleKey)),
            badge: String(format: String(localized: "insights.health.weightLabel"), model.weight),
            summary: String(format: String(localized: "insights.health.scoreContribution"), model.componentScore),
            currentLabel: String(localized: "insights.health.currentValue"),
            currentValue: model.currentValueText,
            targetLabel: String(localized: "insights.health.target"),
            targetValue: String(localized: String.LocalizationValue(model.targetTextKey)),
            progress: model.progress,
            explanation: String(localized: String.LocalizationValue(model.explainerKey)),
            recommendation: model.recommendation,
            isMuted: model.isMuted
        )
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
