//
//  AssetValuationEditView.swift
//  Tenra
//
//  Changes to one valuation of an asset (docs/domains/assets.md, plan 2.1): its value, its day
//  and its note, in the asset's currency; the sale's price and day once sold. A tap on a row of
//  the asset's valuations opens it; deleting stays in the row's menu. The purchase is the
//  asset's own price and day, changed in its form.
//

import SwiftUI

struct AssetValuationEditView: View {
    let valuation: AssetValuation
    let currency: String
    let onSave: (AssetValuation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var valueText = ""
    @State private var date = Date()
    @State private var note = ""

    private var isSale: Bool { valuation.source == .sale }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "asset.valuation.editTitle"),
            isSaveDisabled: value == nil,
            wrapInForm: false,
            onSave: save,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection {
                        UniversalRow(
                            isSale ? String(localized: "asset.source.sale") : String(localized: "asset.chart.value"),
                            icon: isSale ? "tag" : "chart.line.uptrend.xyaxis",
                            hint: currency,
                            accessory: .textField($valueText, placeholder: "0", keyboard: .decimalPad)
                        )
                        UniversalRow(
                            isSale ? String(localized: "asset.soldDate") : String(localized: "asset.valuation.day"),
                            icon: "calendar",
                            accessory: .date($date, through: Date())
                        )
                        UniversalRow(
                            String(localized: "asset.note"),
                            icon: "text.alignleft",
                            accessory: .textField($note, placeholder: String(localized: "moneyEntry.notePlaceholder"))
                        )
                    }
                }
                .screenPadding()
                .padding(.top, AppSpacing.md)
            }
        }
        .onAppear(perform: fill)
    }

    private var value: Double? {
        guard let parsed = AmountFormatter.parse(valueText), parsed > 0 else { return nil }
        return NSDecimalNumber(decimal: parsed).doubleValue
    }

    private func fill() {
        valueText = AmountInputFormatting.bindingString(for: valuation.value)
        date = valuation.date
        note = valuation.note ?? ""
    }

    private func save() {
        guard let value else { return }
        var updated = valuation
        // The range of an estimate from listings belongs to the value it was found for.
        if abs(updated.value - value) >= PersonalDebt.centTolerance {
            updated.listings = nil
        }
        updated.value = value
        updated.date = date
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.note = trimmed.isEmpty ? nil : trimmed
        HapticManager.success()
        onSave(updated)
        dismiss()
    }
}
