//
//  InsightFormulaCard.swift
//  Tenra
//
//  Reusable detail card for insights with formula-style breakdown.
//  Mirrors HealthComponentCard's visual language: header → hero value →
//  formula rows → explainer → recommendation.
//

import SwiftUI

struct InsightFormulaCard: View {
    let model: InsightFormulaModel
    /// Hide the hero value row when the metric is already shown above the card
    /// (InsightDetailView renders it in the shared HeroSection header).
    var showsHero: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            headerRow
            if showsHero {
                heroRow
            }
            formulaSection
            explainer
            recommendationBox
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: model.icon)
                .font(.system(size: AppIconSize.md))
                .foregroundStyle(model.color)
                .frame(width: 28)

            // Static "How it's calculated" — the metric name is already the
            // navigation title of the detail screen; repeating it here
            // (model.titleKey) read as a duplicate.
            Text(String(localized: "insights.formula.howCalculated"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()
        }
    }

    // MARK: - Hero value

    private var heroRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(String(localized: String.LocalizationValue(model.heroLabelKey)))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            Text(model.heroValueText)
                .font(AppTypography.h1.bold())
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Formula breakdown

    // No section sub-header here: the card title is already the static
    // "How it's calculated" — `model.formulaHeaderKey` duplicated it in gray.
    private var formulaSection: some View {
        VStack(spacing: AppSpacing.xs) {
            ForEach(model.formulaRows) { row in
                formulaRow(row)
                if row.id != model.formulaRows.last?.id {
                    Divider().opacity(0.4)
                }
            }
        }
    }

    @ViewBuilder
    private func formulaRow(_ row: InsightFormulaRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.labelText ?? String(localized: String.LocalizationValue(row.labelKey)))
                .font(row.isEmphasised ? AppTypography.bodyEmphasis : AppTypography.body)
                .foregroundStyle(row.isEmphasised ? AppColors.textPrimary : AppColors.textSecondary)
            Spacer()
            // Currency rows go through the design-system formatter (FormattedAmountText)
            // so symbol, grouping separators, and decimals match the rest of the app.
            // Non-currency rows render the formatted value as a plain Text.
            if case .currency = row.kind {
                FormattedAmountText(
                    amount: row.value,
                    currency: model.baseCurrency,
                    fontSize: row.isEmphasised ? AppTypography.bodyEmphasis : AppTypography.body,
                    fontWeight: row.isEmphasised ? .bold : .semibold,
                    color: row.isEmphasised ? model.color : AppColors.textPrimary
                )
            } else {
                Text(formattedValue(row))
                    .font(row.isEmphasised ? AppTypography.bodyEmphasis : AppTypography.body)
                    .fontWeight(row.isEmphasised ? .bold : .semibold)
                    .foregroundStyle(row.isEmphasised ? model.color : AppColors.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func formattedValue(_ row: InsightFormulaRow) -> String {
        switch row.kind {
        case .currency:
            return Formatting.formatCurrencySmart(row.value, currency: model.baseCurrency)
        case .months:
            return String(format: String(localized: "insights.formula.value.months"), row.value)
        case .percent:
            return String(format: "%.1f%%", row.value)
        case .days:
            return String(format: String(localized: "insights.formula.value.days"), Int(row.value.rounded()))
        case .rawText(let s):
            return s
        }
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

#Preview("Savings rate") {
    InsightFormulaCard(model: InsightFormulaModel(
        id: "savingsRate",
        titleKey: "insights.formula.savingsRate.title",
        icon: "banknote.fill",
        color: AppColors.success,
        heroValueText: "12.4%",
        heroLabelKey: "insights.formula.savingsRate.heroLabel",
        formulaHeaderKey: "insights.formula.savingsRate.formulaHeader",
        formulaRows: [
            InsightFormulaRow(id: "income", labelKey: "insights.formula.savingsRate.row.income", value: 530_000, kind: .currency),
            InsightFormulaRow(id: "expenses", labelKey: "insights.formula.savingsRate.row.expenses", value: 464_000, kind: .currency),
            InsightFormulaRow(id: "saved", labelKey: "insights.formula.savingsRate.row.saved", value: 66_000, kind: .currency),
            InsightFormulaRow(id: "rate", labelKey: "insights.formula.savingsRate.row.rate", value: 12.4, kind: .percent, isEmphasised: true)
        ],
        explainerKey: "insights.formula.savingsRate.explainer",
        recommendation: "Aim for 20%. Trim recurring subscriptions or one-off splurges to widen the gap.",
        baseCurrency: "KZT"
    ))
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
