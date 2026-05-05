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

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            headerRow
            heroRow
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

            Text(String(localized: String.LocalizationValue(model.titleKey)))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()
        }
    }

    // MARK: - Hero value

    private var heroRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(String(localized: String.LocalizationValue(model.heroLabelKey)))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(model.heroValueText)
                .font(AppTypography.h1.bold())
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    // MARK: - Formula breakdown

    private var formulaSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: String.LocalizationValue(model.formulaHeaderKey)))
                .font(AppTypography.bodySmall)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: AppSpacing.xs) {
                ForEach(model.formulaRows) { row in
                    formulaRow(row)
                    if row.id != model.formulaRows.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formulaRow(_ row: InsightFormulaRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: String.LocalizationValue(row.labelKey)))
                .font(row.isEmphasised ? AppTypography.bodyEmphasis : AppTypography.body)
                .foregroundStyle(row.isEmphasised ? AppColors.textPrimary : AppColors.textSecondary)
            Spacer()
            Text(formattedValue(row))
                .font(row.isEmphasised ? AppTypography.bodyEmphasis : AppTypography.body)
                .fontWeight(row.isEmphasised ? .bold : .semibold)
                .foregroundStyle(row.isEmphasised ? model.color : AppColors.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, AppSpacing.xxs)
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
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: AppIconSize.sm))
                .foregroundStyle(model.color)

            Text(model.recommendation)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .background(model.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
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
