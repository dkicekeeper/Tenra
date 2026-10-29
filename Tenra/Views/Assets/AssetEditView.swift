//
//  AssetEditView.swift
//  Tenra
//
//  A new asset, or changes to one (docs/domains/assets.md): icon, name, what it is worth today
//  and its currency in the hero; its kind; the purchase price and day (empty for an
//  inheritance or a gift); the person's share and the loan it was bought with. A value changed
//  here is a valuation of today (the sale price, once sold). Changing the currency moves the
//  purchase price and the valuations at today's rate, or keeps the currency without one.
//

import SwiftUI

struct AssetEditView: View {
    let asset: Asset?
    /// Loan accounts the asset can be linked to (a mortgage, a car loan).
    let loanAccounts: [Account]
    let baseCurrency: String
    let onSave: (Asset) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: AssetKind = .apartment
    @State private var iconSource: IconSource? = AssetKind.apartment.defaultIcon
    @State private var valueText = ""
    /// The value as the form opened, so an untouched value is not a new valuation.
    @State private var initialValueText = ""
    @State private var currency = ""
    @State private var purchaseText = ""
    /// The purchase price as the form opened.
    @State private var initialPurchaseText = ""
    @State private var purchaseDate = Date()
    /// 5…100.
    @State private var sharePercent = 100
    /// Empty: no loan.
    @State private var loanAccountId = ""

    var body: some View {
        EditSheetContainer(
            title: asset == nil ? String(localized: "asset.new") : String(localized: "asset.editTitle"),
            isSaveDisabled: !isValid,
            wrapInForm: false,
            onSave: save,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.sm) {
                        EditableHeroSection(
                            iconSource: $iconSource,
                            title: $name,
                            balance: $valueText,
                            currency: $currency,
                            titlePlaceholder: String(localized: "asset.namePlaceholder"),
                            config: .accountHero
                        )
                        Text(asset?.isSold == true ? String(localized: "asset.salePriceHint") : String(localized: "asset.valueHint"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    // The row names the kind: a header with the same word would repeat it.
                    FormSection {
                        UniversalRow(
                            String(localized: "asset.kind"),
                            icon: "square.grid.2x2",
                            accessory: .menu($kind, options: AssetKind.allCases.map { (label: Self.title(of: $0), value: $0) })
                        )
                    }

                    FormSection(
                        header: String(localized: "asset.purchase"),
                        footer: String(localized: "asset.purchase.hint")
                    ) {
                        UniversalRow(
                            String(localized: "asset.purchasePrice"),
                            icon: "cart",
                            accessory: .textField($purchaseText, placeholder: "0", keyboard: .decimalPad)
                        )
                        if purchasePrice != nil {
                            UniversalRow(
                                String(localized: "asset.purchaseDate"),
                                icon: "calendar",
                                accessory: .date($purchaseDate, through: Date())
                            )
                        }
                    }

                    FormSection(
                        header: String(localized: "asset.ownership"),
                        footer: String(localized: "asset.ownership.hint")
                    ) {
                        UniversalRow(
                            String(localized: "asset.share"),
                            icon: "person.2",
                            accessory: .stepper($sharePercent, in: 5...100, step: 5, format: { AssetDetailView.percentText(Double($0) / 100) })
                        )
                        if !loanAccounts.isEmpty {
                            UniversalRow(
                                String(localized: "asset.loan"),
                                icon: "building.columns",
                                accessory: .picker($loanAccountId, options: [(label: String(localized: "asset.loan.none"), value: "")]
                                    + loanAccounts.map { (label: $0.name, value: $0.id) })
                            )
                        }
                    }
                }
                .screenPadding()
                .padding(.top, AppSpacing.md)
                .animation(AppAnimation.smooth, value: purchasePrice != nil)
            }
        }
        .onAppear(perform: fill)
        .onChange(of: kind) { old, new in
            // An icon the person did not pick follows the kind.
            if iconSource == nil || iconSource == old.defaultIcon {
                iconSource = new.defaultIcon
            }
        }
    }

    // MARK: - Values

    private static func amount(_ text: String) -> Double? {
        guard let parsed = AmountFormatter.parse(text), parsed > 0 else { return nil }
        return NSDecimalNumber(decimal: parsed).doubleValue
    }

    private var value: Double? { Self.amount(valueText) }
    private var purchasePrice: Double? { Self.amount(purchaseText) }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (value != nil || purchasePrice != nil)
    }

    static func title(of kind: AssetKind) -> String {
        switch kind {
        case .apartment: return String(localized: "asset.kind.apartment")
        case .house: return String(localized: "asset.kind.house")
        case .land: return String(localized: "asset.kind.land")
        case .commercial: return String(localized: "asset.kind.commercial")
        case .vehicle: return String(localized: "asset.kind.vehicle")
        case .other: return String(localized: "asset.kind.other")
        }
    }

    private func fill() {
        guard let asset else {
            currency = baseCurrency
            return
        }
        name = asset.name
        kind = asset.kind
        iconSource = asset.displayIcon
        if let current = AssetValuationMath.currentValue(of: asset) {
            valueText = AmountInputFormatting.bindingString(for: current)
        }
        initialValueText = valueText
        currency = asset.currency
        purchaseText = asset.purchasePrice.map { AmountInputFormatting.bindingString(for: $0) } ?? ""
        initialPurchaseText = purchaseText
        purchaseDate = asset.purchaseDate ?? Date()
        sharePercent = min(100, max(5, Int((asset.ownershipShare * 100).rounded())))
        loanAccountId = asset.linkedLoanAccountId ?? ""
    }

    // MARK: - Save

    private func save() {
        guard isValid else { return }
        let today = Date()
        var result = asset ?? Asset(name: "", kind: kind, currency: currency)
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.kind = kind
        // The kind's own icon is not kept: it follows the kind.
        result.iconSource = iconSource == kind.defaultIcon ? nil : iconSource
        result.ownershipShare = Double(sharePercent) / 100
        result.linkedLoanAccountId = loanAccountId.isEmpty ? nil : loanAccountId

        // Kept in the asset's currency: the purchase price and the valuations move to the new
        // one at today's rate, or the currency stays when there is no rate to move them at.
        result.currency = currency
        if let asset, asset.currency != currency {
            if let moved = Self.amounts(of: asset, in: currency) {
                result.valuations = moved.valuations
                result.purchasePrice = moved.purchasePrice
            } else {
                result.currency = asset.currency
            }
        }

        // A field left as it was keeps the stored (and moved) amount.
        if purchaseText != initialPurchaseText {
            result.purchasePrice = purchasePrice
        }
        result.purchaseDate = result.purchasePrice == nil ? nil : Calendar.current.startOfDay(for: purchaseDate)

        if let value, valueText != initialValueText {
            if result.isSold, let index = result.valuations.lastIndex(where: { $0.source == .sale }) {
                // A sold asset's value is its sale price.
                result.valuations[index].value = value
            } else if asset != nil || !isPurchaseToday(value: value, price: result.purchasePrice, date: result.purchaseDate, today: today) {
                result.valuations.append(AssetValuation(date: today, value: value, source: .manual))
            }
        }
        HapticManager.success()
        onSave(result)
        dismiss()
    }

    /// A new asset bought today at the value typed: the purchase is the only point.
    private func isPurchaseToday(value: Double, price: Double?, date: Date?, today: Date) -> Bool {
        guard let price, let date else { return false }
        return abs(price - value) < PersonalDebt.centTolerance && Calendar.current.isDate(date, inSameDayAs: today)
    }

    /// The asset's valuations and purchase price in another currency at today's rate; nil when
    /// one of them has no rate.
    private static func amounts(of asset: Asset, in currency: String) -> (valuations: [AssetValuation], purchasePrice: Double?)? {
        func convert(_ amount: Double) -> Double? {
            CurrencyConverter.convertSync(amount: amount, from: asset.currency, to: currency).map { ($0 * 100).rounded() / 100 }
        }
        var valuations: [AssetValuation] = []
        for valuation in asset.valuations {
            guard let value = convert(valuation.value) else { return nil }
            var copy = valuation
            copy.value = value
            valuations.append(copy)
        }
        var price: Double?
        if let purchase = asset.purchasePrice {
            guard let converted = convert(purchase) else { return nil }
            price = converted
        }
        return (valuations, price)
    }
}

#Preview("Asset Edit - New") {
    AssetEditView(asset: nil, loanAccounts: [], baseCurrency: "KZT", onSave: { _ in })
}
