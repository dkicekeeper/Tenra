//
//  AssetDetailView.swift
//  Tenra
//
//  One asset (docs/domains/assets.md), on EntityDetailScaffold. The hero: its icon, the value
//  (the sale price once sold) with when it was valued and the gain over the purchase price as a
//  trend pill, then its worth over time, the purchase and every valuation, drawing in. Actions:
//  "Update value" (a valuation, MoneyEntrySheet) and "Sell" (the sale price and day), or
//  "Undo sale" once sold. Info rows: the purchase, the gain, the growth a year, the
//  person's share, the linked loan and their own money in it, the rent and upkeep of the last 12
//  months, the yield and the full result. Then the valuations, newest first (a tap changes one,
//  the purchase in the asset's form; a long press deletes one, which breaks into dust), and the
//  rent and upkeep transactions by day; with a rent
//  category and no rent yet, a banner opens the add form in it. A valuation older than its kind
//  allows puts a banner on top that opens "Update value"; with a depreciation rule the value is
//  an estimate ("≈"), and the chart ends on it today. A valuation above the value bursts
//  sparkles over the hero; a sale above the purchase price celebrates. The rent banner's form
//  comes with the link's subcategories. Once Ten's server values
//  assets, "Estimate from listings" (the menu, and the out-of-date banner) opens
//  AssetEstimateSheet.
//

import SwiftUI

struct AssetDetailView: View {
    let assetStore: AssetStore
    let assetId: String

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.amountsHidden) private var amountsHidden
    @State private var showingEdit = false
    @State private var showingValuation = false
    /// "Estimate from listings" (AssetEstimateSheet).
    @State private var showingEstimate = false
    /// "Enter by hand" in the estimate sheet: the money sheet, once that one is gone.
    @State private var valuationAfterEstimate = false
    @State private var showingSale = false
    /// A valuation changed in place (AssetValuationEditView).
    @State private var editingValuation: AssetValuation?
    @State private var showingDelete = false
    /// "Undo sale" asks first: it drops the sale's price, day and note (finding A14).
    @State private var showingUndoSale = false
    /// "Link payments", "Remove payments" or "Removed payments" (the owner's car, 2026-11-02).
    @State private var paymentsScreen: PaymentsScreen?

    private enum PaymentsScreen: Hashable {
        case link, remove, removed
    }
    /// The add form in the rent category.
    @State private var showingRentEntry = false
    /// "Record the money" of a sale: the income category asked first, then the add form in it.
    @State private var choosingSaleCategory = false
    @State private var saleIncomeCategory: String?
    /// The sales whose money the person said is recorded ("Already recorded"): asset ids, one
    /// per line. A hint of this device, like the soft paywall's cap.
    @AppStorage("asset.saleIncome.dismissed") private var dismissedSaleIncome = ""
    /// The linked loan, from the "not paid off" banner of a sold asset.
    @State private var showingLoan = false
    /// Bumped by a valuation above the value: one burst of sparkles over the hero.
    @State private var valuationSparkles = 0
    /// Bumped by a sale above the purchase price: one confetti burst.
    @State private var celebrations = 0
    /// The growth a year depends on the day: moved at midnight.
    @State private var today = Date()
    /// The rent and upkeep and what they come to, gathered once per change rather than on every
    /// pass of the body (finding A6 of the assets audit).
    @State private var linked = Linked()

    struct Linked {
        /// Newest first.
        var transactions: [Transaction] = []
        var income = AssetValuationMath.IncomeSummary(hasRent: false)
        /// A sold asset's money is recorded as an income (`AssetSale`).
        var saleRecorded = true
        /// Gathered at least once: until then the "no rent yet" banner waits.
        var isLoaded = false
    }

    /// What the rent and upkeep depend on: the transactions, the categories and their
    /// subcategory links, the rates, the asset and the day.
    private struct LinkedKey: Hashable {
        let asset: Asset
        let transactions: Int
        let categories: Int
        let subcategories: Int
        let rates: Int
        let day: Date
    }

    private var appSettings: AppSettings { coordinator.transactionsViewModel.appSettings }

    var body: some View {
        Group {
            if let asset = assetStore.asset(id: assetId) {
                scaffold(for: asset)
            } else {
                EmptyState(
                    icon: "house",
                    title: String(localized: "asset.notFound"),
                    description: String(localized: "asset.notFoundDescription")
                )
                .navigationTitle(String(localized: "asset.listTitle"))
            }
        }
    }

    /// The payments by hand, on the shared `LinkPaymentsView` (search, category and subcategory
    /// filters, select all): any expense or income its rent and upkeep don't count yet, the ones
    /// they count, or the ones removed.
    private func paymentsView(_ screen: PaymentsScreen, asset: Asset, counted: Set<String>) -> some View {
        let store = assetStore
        let assetId = asset.id
        let removed = Set(asset.excludedTransactionIds)
        let title: String
        var options = LinkPaymentsView.Options.asset
        let findCandidates: @Sendable ([Transaction], AmountMatchMode) -> [Transaction]
        let perform: @Sendable ([Transaction]) async throws -> Void
        switch screen {
        case .link:
            title = String(localized: "asset.payments.link")
            findCandidates = { all, _ in
                all.filter { ($0.type == .expense || $0.type == .income) && !counted.contains($0.id) }
            }
            perform = { selected in await store.include(selected.map(\.id), in: assetId) }
        case .remove:
            title = String(localized: "asset.payments.remove")
            options.actionTitleFormat = String(localized: "asset.payments.removeCount")
            findCandidates = { all, _ in all.filter { counted.contains($0.id) } }
            perform = { selected in await store.exclude(selected.map(\.id), from: assetId) }
        case .removed:
            title = String(localized: "asset.payments.removed")
            options.actionTitleFormat = String(localized: "asset.payments.returnCount")
            findCandidates = { all, _ in all.filter { removed.contains($0.id) } }
            perform = { selected in await store.restore(selected.map(\.id), to: assetId) }
        }
        return LinkPaymentsView(
            title: title,
            displayCurrency: appSettings.baseCurrency,
            findCandidates: findCandidates,
            performLink: perform,
            options: options,
            transactionStore: coordinator.transactionStore,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel
        )
    }

    @ViewBuilder
    private func scaffold(for asset: Asset) -> some View {
        // An asset in another currency shows its value in the base one at the cached rates, and a
        // linked loan's balance moves with its payments: drawn again when either changes.
        let _ = coordinator.transactionStore.currencyRatesVersion
        let _ = coordinator.transactionStore.accounts.count
        // Rent and upkeep come from the category indexes (@ObservationIgnored): the transactions,
        // the categories and the subcategory links are read so an edit to any redraws.
        let _ = coordinator.transactionStore.transactions.count
        let _ = coordinator.transactionStore.categoriesMutationVersion
        let _ = coordinator.transactionStore.subcategoriesMutationVersion
        let summary = assetStore.summary(for: asset, today: today)
        let income = linked.income
        let linkedTransactions = linked.transactions
        let linkedKey = LinkedKey(
            asset: asset,
            transactions: coordinator.transactionStore.mutationVersion,
            categories: coordinator.transactionStore.categoriesMutationVersion,
            subcategories: coordinator.transactionStore.subcategoriesMutationVersion,
            rates: coordinator.transactionStore.currencyRatesVersion,
            day: Calendar.current.startOfDay(for: today)
        )
        let history = AssetValuationMath.history(of: asset)
        let isStale = AssetValuationMath.isStale(asset, today: today)
        EntityDetailScaffold(
            navigationTitle: asset.name,
            navigationAmount: summary.value,
            navigationCurrency: asset.currency,
            primaryAction: asset.isSold ? nil : ActionConfig(
                title: String(localized: "asset.updateValue"),
                systemImage: "chart.line.uptrend.xyaxis",
                action: {
                    HapticManager.light()
                    showingValuation = true
                }
            ),
            secondaryAction: asset.isSold
                ? ActionConfig(
                    title: String(localized: "asset.undoSale"),
                    systemImage: "arrow.uturn.backward",
                    action: {
                        HapticManager.warning()
                        showingUndoSale = true
                    }
                )
                : ActionConfig(
                    title: String(localized: "asset.sell"),
                    systemImage: "tag",
                    action: {
                        HapticManager.selection()
                        showingSale = true
                    }
                ),
            infoRows: infoRows(for: asset, summary: summary, income: income),
            transactions: linkedTransactions,
            historyCurrency: appSettings.baseCurrency,
            accountsById: coordinator.transactionStore.accountById,
            styleHelper: { tx in
                CategoryStyleHelper.cached(
                    category: tx.category,
                    type: tx.type,
                    customCategories: coordinator.categoriesViewModel.customCategories
                )
            },
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.balanceCoordinator,
            hero: {
                hero(for: asset, summary: summary, history: history)
            },
            customSections: {
                if linked.isLoaded, asset.isSold, !linked.saleRecorded, !isSaleIncomeDismissed(asset) {
                    // Selling makes no transaction: the money, filled in, one tap away (2.4).
                    StatusBanner(
                        String(localized: "asset.saleIncome.banner"),
                        status: .info,
                        systemImage: "banknote",
                        action: {
                            HapticManager.light()
                            choosingSaleCategory = true
                        }
                    )
                    .screenPadding()
                }
                if let loanName = unpaidLoanName(of: asset) {
                    // Sold with the loan still owed: its screen, to repay it from the money.
                    StatusBanner(
                        String(format: String(localized: "asset.saleLoan.banner"), loanName),
                        status: .warning,
                        action: {
                            HapticManager.light()
                            showingLoan = true
                        }
                    )
                    .screenPadding()
                }
                if isStale {
                    // The value was set too long ago: one tap to a new valuation.
                    StatusBanner(
                        String(
                            format: String(localized: "asset.stale.banner"),
                            DateFormatters.displayDateOmittingCurrentYear(AssetValuationMath.lastValuedOn(asset))
                        ),
                        status: .warning,
                        action: {
                            HapticManager.light()
                            // From listings once the server values assets; by hand otherwise.
                            if canEstimate(asset) {
                                showingEstimate = true
                            } else {
                                showingValuation = true
                            }
                        }
                    )
                    .screenPadding()
                }
                if linked.isLoaded, let category = rentCategory(of: asset), !income.hasRent, !asset.isSold {
                    // A rent category without rent: the first payment, made monthly in the form.
                    StatusBanner(
                        String(format: String(localized: "asset.rent.empty"), category.name),
                        status: .info,
                        action: {
                            HapticManager.light()
                            showingRentEntry = true
                        }
                    )
                    .screenPadding()
                }
                if !history.isEmpty {
                    historySection(for: asset, history: history)
                }
            },
            toolbarMenu: {
                AskAssistantMenuItem(topic: .asset(name: asset.name))
                if canEstimate(asset) {
                    Button {
                        HapticManager.selection()
                        showingEstimate = true
                    } label: {
                        Label(String(localized: "asset.estimate.action"), systemImage: "magnifyingglass")
                    }
                }
                Button {
                    HapticManager.selection()
                    showingEdit = true
                } label: {
                    Label(String(localized: "button.edit"), systemImage: "pencil")
                }
                // Payments by hand: any expense or income linked to it, the ones its category
                // counts taken out, and given back.
                Button {
                    HapticManager.selection()
                    paymentsScreen = .link
                } label: {
                    Label(String(localized: "asset.payments.link"), systemImage: "link.badge.plus")
                }
                if !linkedTransactions.isEmpty {
                    Button {
                        HapticManager.selection()
                        paymentsScreen = .remove
                    } label: {
                        Label(String(localized: "asset.payments.remove"), systemImage: "minus.circle")
                    }
                }
                if !asset.excludedTransactionIds.isEmpty {
                    Button {
                        HapticManager.selection()
                        paymentsScreen = .removed
                    } label: {
                        Label(String(localized: "asset.payments.removed"), systemImage: "arrow.uturn.backward.circle")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    HapticManager.warning()
                    showingDelete = true
                } label: {
                    Label(String(localized: "asset.delete"), systemImage: "trash")
                }
            }
        )
        .heroAccentGlow(icon: asset.displayIcon)
        // The money sheet already played the success haptic.
        .celebration(trigger: celebrations, playsHaptic: false)
        .sheet(isPresented: $showingEdit) {
            AssetEditView(
                asset: asset,
                loanAccounts: coordinator.transactionStore.accounts.filter { $0.loanInfo != nil },
                baseCurrency: appSettings.baseCurrency,
                linkOptions: AssetLinkOptions.make(store: coordinator.transactionStore, assets: assetStore, excluding: asset.id)
            ) { updated in
                Task { await assetStore.update(updated) }
            }
        }
        .sheet(isPresented: $showingValuation) {
            MoneyEntrySheet(
                title: asset.name,
                icon: asset.displayIcon,
                subtitle: String(localized: "asset.valuationHint"),
                currency: asset.currency,
                appSettings: appSettings,
                suggestedAmount: summary.value
            ) { amount, date, note in
                let before = summary.value
                Task {
                    await assetStore.addValuation(AssetValuation(date: date, value: amount, source: .manual, note: note), to: asset.id)
                    if amount > before { valuationSparkles += 1 }
                }
            }
        }
        .sheet(isPresented: $showingEstimate, onDismiss: {
            if valuationAfterEstimate {
                valuationAfterEstimate = false
                showingValuation = true
            }
        }) {
            if let transport = coordinator.assetEstimateTransport {
                AssetEstimateSheet(
                    model: AssetEstimateViewModel(
                        asset: asset,
                        assets: assetStore,
                        transport: transport,
                        defaultCountry: AssetAttributesDraft.phoneCountry
                    ),
                    onManual: { valuationAfterEstimate = true },
                    onSaved: { value in
                        if value > summary.value { valuationSparkles += 1 }
                    }
                )
            }
        }
        .sheet(item: $editingValuation) { valuation in
            AssetValuationEditView(valuation: valuation, currency: asset.currency) { updated in
                Task { await assetStore.updateValuation(updated, in: asset.id) }
            }
        }
        .sheet(isPresented: $showingSale) {
            MoneyEntrySheet(
                title: asset.name,
                icon: asset.displayIcon,
                subtitle: String(localized: "asset.saleHint"),
                currency: asset.currency,
                appSettings: appSettings,
                suggestedAmount: summary.value
            ) { amount, date, note in
                Task {
                    await assetStore.sell(assetId: asset.id, price: amount, date: date, note: note)
                    if let price = asset.purchasePrice, amount > price { celebrations += 1 }
                }
            }
        }
        .navigationDestination(item: $paymentsScreen) { screen in
            paymentsView(screen, asset: asset, counted: Set(linkedTransactions.map(\.id)))
        }
        .navigationDestination(isPresented: $showingRentEntry) {
            if let category = rentCategory(of: asset) {
                TransactionAddModal(
                    category: category.name,
                    type: .income,
                    currency: asset.currency,
                    accounts: coordinator.accountsViewModel.accounts,
                    transactionsViewModel: coordinator.transactionsViewModel,
                    categoriesViewModel: coordinator.categoriesViewModel,
                    accountsViewModel: coordinator.accountsViewModel,
                    transactionStore: coordinator.transactionStore,
                    // The link's subcategories: a rent it does not count would leave the banner.
                    subcategoryIds: Set(asset.incomeLink?.subcategoryIds ?? []),
                    onDismiss: { showingRentEntry = false }
                )
                .environment(timeFilterManager)
            }
        }
        .confirmationDialog(
            String(localized: "asset.saleIncome.choose"),
            isPresented: $choosingSaleCategory,
            titleVisibility: .visible
        ) {
            ForEach(incomeCategories, id: \.id) { category in
                Button(category.name) {
                    saleIncomeCategory = category.name
                }
            }
            Button(String(localized: "asset.saleIncome.recorded")) {
                dismissSaleIncome(asset)
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        }
        .navigationDestination(item: $saleIncomeCategory) { category in
            TransactionAddModal(
                category: category,
                type: .income,
                currency: asset.currency,
                accounts: coordinator.accountsViewModel.accounts,
                transactionsViewModel: coordinator.transactionsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                transactionStore: coordinator.transactionStore,
                prefill: saleIncomePrefill(of: asset),
                onDismiss: { saleIncomeCategory = nil }
            )
            .environment(timeFilterManager)
        }
        .navigationDestination(isPresented: $showingLoan) {
            if let loanId = asset.linkedLoanAccountId {
                LoanDetailView(
                    loansViewModel: coordinator.loansViewModel,
                    transactionsViewModel: coordinator.transactionsViewModel,
                    balanceCoordinator: coordinator.balanceCoordinator,
                    accountId: loanId
                )
            }
        }
        .alert(String(localized: "asset.undoSale.title"), isPresented: $showingUndoSale) {
            Button(String(localized: "asset.undoSale"), role: .destructive) {
                undoSale(asset)
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "asset.undoSale.message"))
        }
        .alert(String(localized: "asset.deleteTitle"), isPresented: $showingDelete) {
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                Task { await assetStore.delete(id: asset.id) }
                dismiss()
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "asset.deleteMessage"))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            today = Date()
        }
        .task {
            await coordinator.checkAssetEstimates()
        }
        .task(id: linkedKey) {
            let gathered = assetStore.linkedTransactions(of: asset)
            linked = Linked(
                transactions: ((gathered.rent ?? []) + (gathered.upkeep ?? [])).sorted { $0.date > $1.date },
                income: assetStore.incomeSummary(for: asset, linked: gathered, today: today),
                saleRecorded: assetStore.isSaleIncomeRecorded(asset),
                isLoaded: true
            )
        }
    }

    // MARK: - Sale

    /// The income categories, in the person's order: where the sale's money can go.
    private var incomeCategories: [CustomCategory] {
        coordinator.categoriesViewModel.customCategories.filter { $0.type == .income }
    }

    /// The income form of the sale: the price at the person's share, the sale day, "Sale: …".
    private func saleIncomePrefill(of asset: Asset) -> TransactionAddModal.Prefill? {
        guard let proceeds = AssetSale.proceeds(of: asset), let soldAt = asset.soldAt else { return nil }
        return TransactionAddModal.Prefill(amount: proceeds, date: soldAt, description: AssetSale.incomeDescription(of: asset))
    }

    private func isSaleIncomeDismissed(_ asset: Asset) -> Bool {
        dismissedSaleIncome.split(separator: "\n").contains { $0 == asset.id }
    }

    private func dismissSaleIncome(_ asset: Asset) {
        HapticManager.selection()
        guard !isSaleIncomeDismissed(asset) else { return }
        dismissedSaleIncome = (dismissedSaleIncome.split(separator: "\n").map(String.init) + [asset.id]).joined(separator: "\n")
    }

    /// A sold asset's linked loan while something is still owed on it: its name.
    private func unpaidLoanName(of asset: Asset) -> String? {
        guard asset.isSold, let loanId = asset.linkedLoanAccountId,
              let loan = assetStore.loan(for: asset), loan.amount > PersonalDebt.centTolerance,
              let account = coordinator.transactionStore.accountById[loanId] else { return nil }
        return account.name
    }

    /// A held asset, and Ten's server values assets from listings.
    private func canEstimate(_ asset: Asset) -> Bool {
        !asset.isSold && coordinator.assetEstimatesAvailable && coordinator.assetEstimateTransport != nil
    }

    // MARK: - Hero

    private func hero(for asset: Asset, summary: AssetValuationMath.Summary, history: [AssetValuation]) -> some View {
        VStack(spacing: AppSpacing.lg) {
            HeroSection(
                icon: asset.displayIcon,
                title: asset.name,
                primaryAmount: summary.value,
                primaryCurrency: asset.currency,
                subtitle: subtitle(for: asset, summary: summary),
                showBaseConversion: asset.currency != appSettings.baseCurrency,
                baseCurrency: appSettings.baseCurrency
            ) {
                if let gain = summary.gain, let percent = summary.gainPercent {
                    TrendBadge(direction: AssetCard.direction(of: gain), changePercent: percent, style: .pill)
                }
            }
            // A valuation above the value: a burst of sparkles over it (DesignKit).
            .sparkleBurst(trigger: valuationSparkles, tint: AppColors.income)

            // Evenly in time (D3): a month apart from the first point to today or the sale.
            let points = AssetValuationMath.chartHistory(of: asset, today: today)
            if points.count >= 2 {
                HeroSparkline(
                    dataPoints: AssetChartPoints.points(points, estimateLast: summary.isEstimate),
                    series: AssetChartPoints.series(color: chartColor(summary)),
                    valueFormat: .currency(asset.currency),
                    entranceDelay: AssetChartPoints.entranceDelay
                )
            }
        }
    }

    private func subtitle(for asset: Asset, summary: AssetValuationMath.Summary) -> String? {
        if let soldAt = asset.soldAt {
            return String(format: String(localized: "asset.soldOn"), DateFormatters.displayDateOmittingCurrentYear(soldAt))
        }
        return AssetCard.valuedLine(summary)
    }

    /// The line follows the gain: green up, red down, the accent without a purchase price.
    private func chartColor(_ summary: AssetValuationMath.Summary) -> Color {
        guard let gain = summary.gain else { return AppColors.accent }
        return AssetCard.direction(of: gain).color
    }

    // MARK: - Info rows

    /// The category the asset's rent comes from, while it exists.
    private func rentCategory(of asset: Asset) -> CustomCategory? {
        asset.incomeLink.flatMap { coordinator.transactionStore.categoryById[$0.categoryId] }
    }

    private func infoRows(for asset: Asset, summary: AssetValuationMath.Summary, income: AssetValuationMath.IncomeSummary) -> [InfoRowConfig] {
        var rows: [InfoRowConfig] = [
            InfoRowConfig(icon: "square.grid.2x2", label: String(localized: "asset.kind"), value: AssetEditView.title(of: asset.kind))
        ]
        if let price = asset.purchasePrice {
            rows.append(InfoRowConfig(icon: "cart", label: String(localized: "asset.purchasePrice"), amount: price, currency: asset.currency))
        }
        if let date = asset.purchaseDate {
            rows.append(InfoRowConfig(icon: "calendar", label: String(localized: "asset.purchaseDate"), value: DateFormatters.displayDateOmittingCurrentYear(date)))
        }
        if let gain = summary.gain {
            let direction = AssetCard.direction(of: gain)
            rows.append(InfoRowConfig(
                icon: direction == .down ? "arrow.down.right" : "arrow.up.right",
                label: asset.isSold ? String(localized: "asset.result") : String(localized: "asset.gain"),
                amount: abs(gain),
                currency: asset.currency,
                prefix: direction == .up ? "+" : direction == .down ? "\u{2212}" : "",
                iconColor: direction == .down ? AppColors.destructive : AppColors.income
            ))
        }
        if let growth = summary.annualGrowthPercent {
            rows.append(InfoRowConfig(
                icon: "chart.line.uptrend.xyaxis",
                label: String(localized: "asset.annualGrowth"),
                value: TrendBadge.format(growth),
                iconColor: growth < 0 ? AppColors.destructive : AppColors.income
            ))
        }
        if let rate = AssetValuationMath.depreciationRate(of: asset), !asset.isSold {
            rows.append(InfoRowConfig(
                icon: "chart.line.downtrend.xyaxis",
                label: String(localized: "asset.depreciation"),
                value: String(format: String(localized: "asset.depreciationValue"), Self.percentText(rate)),
                iconColor: AppColors.textSecondary
            ))
        }
        if asset.ownershipShare < 1 {
            rows.append(InfoRowConfig(
                icon: "person.2",
                label: String(format: String(localized: "asset.shareLabel"), Self.percentText(asset.ownershipShare)),
                amount: summary.ownedValue,
                currency: asset.currency
            ))
        }
        if let remaining = summary.loanRemaining {
            rows.append(InfoRowConfig(icon: "building.columns", label: String(localized: "asset.loanLeft"), amount: remaining, currency: asset.currency, iconColor: AppColors.destructive))
            if let equity = summary.equity {
                rows.append(InfoRowConfig(icon: "key", label: String(localized: "asset.equity"), amount: equity, currency: asset.currency))
            }
        }
        if let rent = income.rentYear {
            rows.append(InfoRowConfig(icon: "arrow.down.circle", label: String(localized: "asset.rentYear"), amount: rent, currency: asset.currency, iconColor: AppColors.income))
        }
        if let upkeep = income.upkeepYear {
            rows.append(InfoRowConfig(icon: "wrench.and.screwdriver", label: String(localized: "asset.upkeepYear"), amount: upkeep, currency: asset.currency))
        }
        if let yield = income.yieldPercent {
            rows.append(InfoRowConfig(
                icon: "percent",
                label: String(localized: "asset.yield"),
                value: Self.percentText(yield / 100, fractionDigits: 1),
                iconColor: yield < 0 ? AppColors.destructive : AppColors.income
            ))
        }
        if let result = income.fullResult {
            let direction = AssetCard.direction(of: result)
            rows.append(InfoRowConfig(
                icon: "sum",
                label: String(localized: "asset.fullResult"),
                amount: abs(result),
                currency: asset.currency,
                prefix: direction == .up ? "+" : direction == .down ? "\u{2212}" : "",
                iconColor: direction == .down ? AppColors.destructive : AppColors.income
            ))
        }
        if let soldAt = asset.soldAt {
            rows.append(InfoRowConfig(
                icon: "checkmark.seal",
                label: String(localized: "asset.soldDate"),
                value: DateFormatters.displayDateOmittingCurrentYear(soldAt),
                iconColor: AppColors.income
            ))
        }
        if !asset.includeInNetWorth, !asset.isSold {
            rows.append(InfoRowConfig(
                icon: "chart.pie",
                label: String(localized: "asset.includeInNetWorth"),
                value: String(localized: "asset.attr.no"),
                iconColor: AppColors.textSecondary
            ))
        }
        if let note = asset.note, !note.isEmpty {
            rows.append(InfoRowConfig(icon: "text.alignleft", label: String(localized: "asset.note"), value: note, iconColor: AppColors.textSecondary))
        }
        return rows
    }

    /// "50%" (or "8.6%" with one fraction digit) in the app's locale.
    static func percentText(_ share: Double, fractionDigits: Int = 0) -> String {
        share.formatted(.percent.precision(.fractionLength(fractionDigits)))
    }

    // MARK: - History

    private func historySection(for asset: Asset, history: [AssetValuation]) -> some View {
        let entries = Array(history.reversed())
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(String(localized: "asset.history"))
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    VStack(spacing: 0) {
                        Button {
                            HapticManager.selection()
                            // The purchase is the asset's own price and day: changed in Edit.
                            if entry.source == .purchase {
                                showingEdit = true
                            } else {
                                editingValuation = entry
                            }
                        } label: {
                            HistoryEntryRow(
                                date: entry.date,
                                note: entry.note.flatMap { $0.isEmpty ? nil : $0 } ?? Self.sourceTitle(entry.source),
                                amount: entry.value,
                                currency: asset.currency,
                                symbol: Self.symbol(of: entry.source)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if entry.source != .purchase {
                                Button {
                                    HapticManager.selection()
                                    editingValuation = entry
                                } label: {
                                    Label(String(localized: "button.edit"), systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    HapticManager.warning()
                                    Task { await assetStore.deleteValuation(id: entry.id, from: asset.id) }
                                } label: {
                                    Label(String(localized: "button.delete"), systemImage: "trash")
                                }
                            }
                        }
                        if entry.id != entries.last?.id {
                            RowDivider(inset: AppIconSize.Tile.sm + AppSpacing.md)
                        }
                    }
                    // A deleted entry breaks into dust, as a deleted transaction does.
                    .transition(AsymmetricTransition(insertion: OpacityTransition(), removal: DissolveTransition()))
                }
            }
            .padding(AppSpacing.lg)
            .cardStyle()
            .animation(AppAnimation.gentleSpring, value: entries.map(\.id))
        }
        .screenPadding()
    }

    static func sourceTitle(_ source: AssetValuation.Source) -> String {
        switch source {
        case .purchase: return String(localized: "asset.source.purchase")
        case .manual: return String(localized: "asset.source.manual")
        case .assistant: return String(localized: "asset.source.assistant")
        case .sale: return String(localized: "asset.source.sale")
        }
    }

    static func symbol(of source: AssetValuation.Source) -> String {
        switch source {
        case .purchase: return "cart"
        case .manual: return "pencil"
        case .assistant: return "sparkles"
        case .sale: return "tag"
        }
    }

    // MARK: - Actions

    private func undoSale(_ asset: Asset) {
        HapticManager.selection()
        // Sold again later, its money is offered again.
        dismissedSaleIncome = dismissedSaleIncome.split(separator: "\n").filter { $0 != asset.id }.joined(separator: "\n")
        Task { await assetStore.undoSale(assetId: asset.id) }
    }
}

#Preview("Asset Detail") {
    let coordinator = AppCoordinator()
    NavigationStack {
        AssetDetailView(assetStore: coordinator.assetStore, assetId: "missing")
    }
    .environment(coordinator)
    .environment(coordinator.transactionStore)
    .environment(TimeFilterManager())
}
