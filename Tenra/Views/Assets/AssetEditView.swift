//
//  AssetEditView.swift
//  Tenra
//
//  A new asset, or changes to one (docs/domains/assets.md): icon, name, what it is worth today
//  and its currency in the hero; its kind; the purchase price and day (empty for an
//  inheritance or a gift); the person's share and the loan it was bought with; the categories of
//  its rent and its upkeep, each with an optional subcategory, never the transactions another
//  asset already counts; for transport and other things, the depreciation a year (off by
//  default: the person sets it). A value changed here is a valuation of today (the sale price,
//  once sold). Changing the currency moves the purchase price and the valuations at today's rate, or
//  keeps the currency without one.
//

import SwiftUI

struct AssetEditView: View {
    let asset: Asset?
    /// Loan accounts the asset can be linked to (a mortgage, a car loan).
    let loanAccounts: [Account]
    let baseCurrency: String
    /// The categories rent and upkeep can come from, and the links other assets hold.
    var linkOptions: AssetLinkOptions = .empty
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
    /// 0 (off)…50; only for transport and other things.
    @State private var depreciationPercent = 0
    /// Empty: no loan.
    @State private var loanAccountId = ""
    /// Empty: no link; a subcategory left empty takes the whole category.
    @State private var incomeCategoryId = ""
    @State private var incomeSubcategoryId = ""
    @State private var expenseCategoryId = ""
    @State private var expenseSubcategoryId = ""

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

                    if hasDepreciation {
                        FormSection(
                            header: String(localized: "asset.depreciation"),
                            footer: String(localized: "asset.depreciation.hint")
                        ) {
                            UniversalRow(
                                String(localized: "asset.depreciationRow"),
                                icon: "chart.line.downtrend.xyaxis",
                                accessory: .stepper($depreciationPercent, in: 0...50, step: 1, format: Self.depreciationText)
                            )
                        }
                    }

                    if !linkOptions.incomeCategories.isEmpty {
                        linkSection(
                            header: String(localized: "asset.rent"),
                            footer: String(localized: "asset.rent.hint"),
                            icon: "arrow.down.circle",
                            categories: linkOptions.incomeCategories,
                            categoryId: $incomeCategoryId,
                            subcategoryId: $incomeSubcategoryId,
                            overlaps: incomeOverlaps
                        )
                    }
                    if !linkOptions.expenseCategories.isEmpty {
                        linkSection(
                            header: String(localized: "asset.upkeep"),
                            footer: String(localized: "asset.upkeep.hint"),
                            icon: "wrench.and.screwdriver",
                            categories: linkOptions.expenseCategories,
                            categoryId: $expenseCategoryId,
                            subcategoryId: $expenseSubcategoryId,
                            overlaps: expenseOverlaps
                        )
                    }
                }
                .screenPadding()
                .padding(.top, AppSpacing.md)
                .animation(AppAnimation.smooth, value: purchasePrice != nil)
                .animation(AppAnimation.smooth, value: hasDepreciation)
                .animation(AppAnimation.smooth, value: incomeCategoryId)
                .animation(AppAnimation.smooth, value: expenseCategoryId)
            }
        }
        .onAppear(perform: fill)
        .onChange(of: kind) { old, new in
            // An icon the person did not pick follows the kind.
            if iconSource == nil || iconSource == old.defaultIcon {
                iconSource = new.defaultIcon
            }
        }
        // A subcategory belongs to its category: another category takes the whole of it.
        .onChange(of: incomeCategoryId) {
            if !linkOptions.has(subcategory: incomeSubcategoryId, in: incomeCategoryId) { incomeSubcategoryId = "" }
        }
        .onChange(of: expenseCategoryId) {
            if !linkOptions.has(subcategory: expenseSubcategoryId, in: expenseCategoryId) { expenseSubcategoryId = "" }
        }
    }

    /// A category and, when it has any, one of its subcategories; under them, what is wrong when
    /// another asset already counts these transactions.
    @ViewBuilder
    private func linkSection(
        header: String,
        footer: String,
        icon: String,
        categories: [AssetLinkOptions.Item],
        categoryId: Binding<String>,
        subcategoryId: Binding<String>,
        overlaps: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormSection(header: header, footer: footer) {
                UniversalRow(
                    String(localized: "asset.link.category"),
                    icon: icon,
                    accessory: .picker(categoryId, options: [(label: String(localized: "asset.link.none"), value: "")]
                        + categories.map { (label: $0.name, value: $0.id) })
                )
                if let subcategories = linkOptions.subcategories[categoryId.wrappedValue], !subcategories.isEmpty {
                    UniversalRow(
                        String(localized: "asset.link.subcategory"),
                        icon: "list.bullet.indent",
                        accessory: .picker(subcategoryId, options: [(label: String(localized: "asset.link.wholeCategory"), value: "")]
                            + subcategories.map { (label: $0.name, value: $0.id) })
                    )
                }
            }
            if overlaps {
                InlineStatusText(message: String(localized: "asset.link.taken"), type: .error)
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

    /// Homes and land keep their last valuation (archive/plans/plan-assets.md §4); a car or a thing may lose
    /// value by a rule.
    private var hasDepreciation: Bool { kind.group != .realEstate }

    /// "Off", or "15% a year".
    private static func depreciationText(_ percent: Int) -> String {
        percent == 0
            ? String(localized: "asset.depreciation.off")
            : String(format: String(localized: "asset.depreciationValue"), AssetDetailView.percentText(Double(percent) / 100))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (value != nil || purchasePrice != nil)
            && !incomeOverlaps && !expenseOverlaps
    }

    private var incomeLink: AssetCategoryLink? {
        Self.link(incomeCategoryId, incomeSubcategoryId)
    }

    private var expenseLink: AssetCategoryLink? {
        Self.link(expenseCategoryId, expenseSubcategoryId)
    }

    private static func link(_ categoryId: String, _ subcategoryId: String) -> AssetCategoryLink? {
        categoryId.isEmpty ? nil : AssetCategoryLink(categoryId: categoryId, subcategoryId: subcategoryId.isEmpty ? nil : subcategoryId)
    }

    /// Another asset counts these transactions already (AssetValuationMath.overlaps).
    private var incomeOverlaps: Bool {
        incomeLink.map { link in linkOptions.takenIncome.contains { AssetValuationMath.overlaps($0, link) } } ?? false
    }

    private var expenseOverlaps: Bool {
        expenseLink.map { link in linkOptions.takenExpense.contains { AssetValuationMath.overlaps($0, link) } } ?? false
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
        // What it is worth today: the depreciation estimate, when it has a rule.
        if AssetValuationMath.currentValue(of: asset) != nil {
            valueText = AmountInputFormatting.bindingString(for: AssetValuationMath.summary(of: asset).value)
        }
        initialValueText = valueText
        currency = asset.currency
        purchaseText = asset.purchasePrice.map { AmountInputFormatting.bindingString(for: $0) } ?? ""
        initialPurchaseText = purchaseText
        purchaseDate = asset.purchaseDate ?? Date()
        sharePercent = min(100, max(5, Int((asset.ownershipShare * 100).rounded())))
        depreciationPercent = min(50, max(0, Int(((asset.depreciationPerYear ?? 0) * 100).rounded())))
        loanAccountId = asset.linkedLoanAccountId ?? ""
        incomeCategoryId = asset.incomeLink?.categoryId ?? ""
        incomeSubcategoryId = asset.incomeLink?.subcategoryId ?? ""
        expenseCategoryId = asset.expenseLink?.categoryId ?? ""
        expenseSubcategoryId = asset.expenseLink?.subcategoryId ?? ""
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
        result.depreciationPerYear = hasDepreciation && depreciationPercent > 0 ? Double(depreciationPercent) / 100 : nil
        result.linkedLoanAccountId = loanAccountId.isEmpty ? nil : loanAccountId
        result.incomeLink = incomeLink
        result.expenseLink = expenseLink

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

/// What the asset form offers for rent and upkeep: the income and expense categories, their
/// subcategories, and the links the other assets hold (a link may not overlap one of them).
struct AssetLinkOptions {
    struct Item: Hashable {
        let id: String
        let name: String
    }

    var incomeCategories: [Item] = []
    var expenseCategories: [Item] = []
    /// By category id, in the category's own order.
    var subcategories: [String: [Item]] = [:]
    var takenIncome: [AssetCategoryLink] = []
    var takenExpense: [AssetCategoryLink] = []

    static let empty = AssetLinkOptions()

    /// `subcategoryId` is one of the category's (an empty one, the whole category, always is).
    func has(subcategory subcategoryId: String, in categoryId: String) -> Bool {
        subcategoryId.isEmpty || subcategories[categoryId]?.contains { $0.id == subcategoryId } == true
    }

    static func make(store: TransactionStore, assets: AssetStore, excluding assetId: String?) -> AssetLinkOptions {
        func items(_ type: TransactionType) -> [Item] {
            store.categories.filter { $0.type == type }.map { Item(id: $0.id, name: $0.name) }
        }
        var subcategories: [String: [Item]] = [:]
        for category in store.categories {
            let list = (store.subcategoryIdsByCategoryId[category.id] ?? [])
                .compactMap { store.subcategoryById[$0] }
                .map { Item(id: $0.id, name: $0.name) }
            if !list.isEmpty { subcategories[category.id] = list }
        }
        let taken = assets.takenLinks(excluding: assetId)
        return AssetLinkOptions(
            incomeCategories: items(.income),
            expenseCategories: items(.expense),
            subcategories: subcategories,
            takenIncome: taken.income,
            takenExpense: taken.expense
        )
    }
}
