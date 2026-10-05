//
//  InsightFormulaCard.swift
//  Tenra
//
//  Detail card for insights with a formula-style breakdown: header → hero value →
//  formula rows → explainer → recommendation. Adapter over DesignKit's `CalculationCard`:
//  the formula model, its localization keys and value formats are Tenra's; the card is
//  DesignKit's.
//

import SwiftUI

struct InsightFormulaCard: View {
    let model: InsightFormulaModel
    /// Hide the hero value row when the metric is already shown above the card
    /// (InsightDetailView renders it in the shared HeroSection header).
    var showsHero: Bool = true

    var body: some View {
        CalculationCard(
            systemImage: model.icon,
            color: model.color,
            // Static "How it's calculated": the metric name is already the navigation
            // title of the detail screen; repeating it here read as a duplicate.
            title: String(localized: "insights.formula.howCalculated"),
            heroLabel: String(localized: String.LocalizationValue(model.heroLabelKey)),
            heroValue: showsHero ? model.heroValueText : nil,
            rows: model.formulaRows.map { calculationRow($0) },
            explanation: String(localized: String.LocalizationValue(model.explainerKey)),
            recommendation: model.recommendation
        )
    }

    private func calculationRow(_ row: InsightFormulaRow) -> CalculationCard.Row {
        // Currency rows go through FormattedAmountText (inside the card); the other kinds
        // are formatted here.
        let value: CalculationCard.Row.Value
        if case .currency = row.kind {
            value = .amount(row.value, currency: model.baseCurrency)
        } else {
            value = .text(formattedValue(row))
        }
        return CalculationCard.Row(
            id: row.id,
            label: row.labelText ?? String(localized: String.LocalizationValue(row.labelKey)),
            value: value,
            isEmphasised: row.isEmphasised
        )
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
