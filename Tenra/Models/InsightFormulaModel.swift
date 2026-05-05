//
//  InsightFormulaModel.swift
//  Tenra
//
//  Display model for formula-breakdown detail cards (savingsRate,
//  emergencyFund, spendingForecast, balanceRunway, projectedBalance,
//  yearOverYear). Mirrors the shape of HealthComponentDisplayModel.
//

import SwiftUI

/// One row of the formula breakdown — e.g. "Income: 530 000 ₸".
/// `kind` controls the value formatting (currency / months / percentage / count).
struct InsightFormulaRow: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case currency        // formatted via Formatting.formatCurrencySmart
        case months          // "1.8 months" — value is months count
        case percent         // "12.4%"
        case days            // "12 days"
        case rawText(String) // pre-formatted, render text as-is
    }

    let id: String
    let labelKey: String        // "insights.formula.<insight>.row.<name>"
    /// Optional pre-formatted label that overrides `labelKey` (e.g., "May 2026").
    /// Used when the row label is data-driven (date, category name) rather than fixed copy.
    let labelText: String?
    let value: Double
    let kind: Kind
    /// Optional emphasis (e.g. true for the "= result" row).
    let isEmphasised: Bool

    init(id: String, labelKey: String, labelText: String? = nil, value: Double, kind: Kind, isEmphasised: Bool = false) {
        self.id = id
        self.labelKey = labelKey
        self.labelText = labelText
        self.value = value
        self.kind = kind
        self.isEmphasised = isEmphasised
    }
}

/// Display model for a formula-breakdown detail card — value-type, Sendable.
/// Carries everything needed to render: header, hero value, formula rows, and
/// localized recommendation copy.
struct InsightFormulaModel: Hashable, Sendable {
    let id: String                  // stable id, e.g. "savingsRate"
    let titleKey: String            // "insights.formula.<insight>.title"
    let icon: String                // SF Symbol name
    let color: Color                // tint
    let heroValueText: String       // pre-formatted hero, e.g. "12.4%" / "1.8 mo"
    let heroLabelKey: String        // "insights.formula.<insight>.heroLabel"
    let formulaHeaderKey: String    // "insights.formula.<insight>.formulaHeader"
    let formulaRows: [InsightFormulaRow]
    let explainerKey: String        // "insights.formula.<insight>.explainer"
    let recommendation: String      // ready-to-render localized copy
    let baseCurrency: String        // for currency-kind rows

    // Color is not Hashable; hash and compare by id only.
    static func == (lhs: InsightFormulaModel, rhs: InsightFormulaModel) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
