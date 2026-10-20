//
//  MerchantDetailView.swift
//  Tenra
//
//  One merchant's screen (docs/plan-auto-capture.md §7): its logo and name, what was
//  spent there in the selected period, this month and this year, visits, the average
//  check, the last visit, the last 12 months as a chart and every transaction, whatever
//  recorded it (Apple Pay, a statement, by hand).
//  Opened from Settings → Siri & Shortcuts → Wallet merchants and from the transaction
//  of a remembered merchant or of one with a logo or a given name (TransactionEditView);
//  the menu edits the merchant (MerchantCategoryEditView).
//
//  Built on EntityDetailScaffold like the category screen. The history sweep runs off
//  the main actor (MerchantHistory, red flag #9), keyed on every dimension it reads
//  (red flag #12).
//

import SwiftUI

struct MerchantDetailView: View {
    /// The merchant as Wallet or the bank wrote it.
    let merchant: String
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    @Environment(TransactionStore.self) private var transactionStore
    @Environment(TimeFilterManager.self) private var timeFilterManager

    @State private var summary = MerchantHistory.Summary.empty
    @State private var accountsById: [String: Account] = [:]
    @State private var editing: MerchantCategoryMemory.Merchant?

    private var merchantKey: String { CategorySuggestionService.normalizedMerchant(merchant) }

    private var name: String {
        MerchantLogoStore.shared.customName(forDescription: merchant) ?? MerchantName.displayName(merchant)
    }

    private var usualCategory: CustomCategory? {
        summary.usualCategory.flatMap { name in
            categoriesViewModel.customCategories.first { $0.name == name && $0.type == .expense }
        }
    }

    /// The merchant's logo, else its usual category's icon, else a shop.
    private var heroIcon: (source: IconSource, tint: IconTint) {
        if let logo = MerchantLogoStore.shared.iconSource(forDescription: merchant) {
            return (logo, .original)
        }
        if let category = usualCategory {
            return (category.iconSource, .monochrome(category.color))
        }
        return (.sfSymbol("storefront"), .monochrome(AppColors.textSecondary))
    }

    private var refreshKey: RefreshKey {
        // `mutationVersion` is @ObservationIgnored: reading the observable array is what
        // re-evaluates the body after an edit (CLAUDE.md, entity detail refresh trigger).
        _ = transactionStore.transactions.count
        return RefreshKey(
            merchant: merchantKey,
            mutationVersion: transactionStore.mutationVersion,
            ratesVersion: transactionStore.currencyRatesVersion,
            baseCurrency: transactionsViewModel.appSettings.baseCurrency,
            filterHash: timeFilterManager.currentFilter.hashValue,
            day: DateFormatters.dateFormatter.string(from: Date())
        )
    }

    private struct RefreshKey: Equatable {
        let merchant: String
        let mutationVersion: Int
        let ratesVersion: Int
        let baseCurrency: String
        let filterHash: Int
        /// Visits and totals leave out future operations: a new day changes them.
        let day: String
    }

    var body: some View {
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        let icon = heroIcon

        EntityDetailScaffold(
            navigationTitle: name,
            navigationAmount: summary.spentInPeriod,
            navigationCurrency: baseCurrency,
            infoRows: infoRows(baseCurrency: baseCurrency),
            transactions: summary.transactions,
            historyCurrency: baseCurrency,
            accountsById: accountsById,
            styleHelper: { tx in
                CategoryStyleHelper.cached(
                    category: tx.category,
                    type: tx.type,
                    customCategories: categoriesViewModel.customCategories
                )
            },
            viewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            balanceCoordinator: accountsViewModel.balanceCoordinator,
            hero: {
                HeroSection(
                    icon: icon.source,
                    title: name,
                    iconTint: icon.tint,
                    primaryAmount: summary.spentInPeriod,
                    primaryCurrency: baseCurrency,
                    subtitle: timeFilterManager.currentFilter.displayName
                )
            },
            customSections: { monthlyChart(baseCurrency: baseCurrency) },
            toolbarMenu: { toolbarMenu }
        )
        .heroAccentGlow(icon: icon.source, tint: icon.tint)
        .sheet(item: $editing) { known in
            MerchantCategoryEditView(
                merchant: known,
                categoriesViewModel: categoriesViewModel,
                memory: MerchantCategoryMemory.shared
            )
        }
        .task(id: refreshKey) {
            await refresh()
        }
        .task(id: transactionStore.accountsMutationVersion) {
            accountsById = Dictionary(uniqueKeysWithValues: transactionStore.accounts.map { ($0.id, $0) })
        }
    }

    private func refresh() async {
        let all = transactionStore.transactions
        let key = merchantKey
        let range = timeFilterManager.currentFilter.dateRange()
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        let computed = await Task.detached(priority: .userInitiated) {
            MerchantHistory.summary(
                merchant: key,
                in: all,
                periodStart: range.start,
                periodEnd: range.end,
                baseCurrency: baseCurrency
            )
        }.value
        guard !Task.isCancelled else { return }
        summary = computed
    }

    // MARK: - Info rows

    private func infoRows(baseCurrency: String) -> [InfoRowConfig] {
        var rows = [
            InfoRowConfig(
                icon: "figure.walk",
                label: String(localized: "merchant.detail.visits"),
                value: "\(summary.visitsInPeriod)"
            )
        ]
        if summary.visitsInPeriod > 0 {
            rows.append(InfoRowConfig(
                icon: "receipt",
                label: String(localized: "merchant.detail.averageCheck"),
                amount: summary.spentInPeriod / Double(summary.visitsInPeriod),
                currency: baseCurrency
            ))
        }
        if let lastVisit = summary.lastVisit {
            rows.append(InfoRowConfig(
                icon: "calendar",
                label: String(localized: "merchant.detail.lastVisit"),
                value: DateFormatters.displayString(from: lastVisit)
            ))
        }
        if let category = usualCategory {
            rows.append(InfoRowConfig(
                icon: "folder",
                label: String(localized: "transactionForm.category"),
                value: category.name
            ))
        }
        rows.append(InfoRowConfig(
            icon: "calendar.circle",
            label: String(localized: "merchant.detail.thisMonth"),
            amount: summary.spentThisMonth,
            currency: baseCurrency
        ))
        rows.append(InfoRowConfig(
            icon: "calendar.badge.clock",
            label: String(localized: "merchant.detail.thisYear"),
            amount: summary.spentThisYear,
            currency: baseCurrency
        ))
        rows.append(InfoRowConfig(
            icon: "sum",
            label: String(localized: "category.detail.totalSpent", defaultValue: "Total spent"),
            amount: summary.spentAllTime,
            currency: baseCurrency
        ))
        return rows
    }

    // MARK: - Monthly chart

    private static let chartSeriesId = "spent"

    /// The last 12 months as bars, a tap shows a month's amount. None until something was spent.
    @ViewBuilder
    private func monthlyChart(baseCurrency: String) -> some View {
        if summary.months.contains(where: { $0.spent > 0 }) {
            let title = String(localized: "merchant.detail.byMonth")
            let series: ChartSeries<ChartValuePoint> = .keyed(
                Self.chartSeriesId, name: title, coloring: .solid(AppColors.accent), baseline: .zero
            )
            let points: [ChartValuePoint] = summary.months.map { month in
                ChartValuePoint(
                    label: month.key,
                    axisLabel: month.start.formatted(.dateTime.month(.abbreviated)),
                    title: month.start.formatted(.dateTime.month(.wide).year()),
                    values: [Self.chartSeriesId: month.spent]
                )
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                SectionHeader(title)
                    .screenPadding()
                // Charts bleed to the screen edges (docs/domains/charts.md).
                BarChart(dataPoints: points, series: series, valueFormat: .currency(baseCurrency))
            }
        }
    }

    // MARK: - Toolbar menu

    /// A merchant the memory does not hold yet, as the edit sheet's starting values: its usual
    /// expense category. nil without one (a merchant of income only), since the sheet saves
    /// an expense category.
    private var unremembered: MerchantCategoryMemory.Merchant? {
        guard let category = usualCategory,
              let key = MerchantCategoryMemory.key(forMerchant: merchant) else { return nil }
        return MerchantCategoryMemory.Merchant(id: key, displayName: merchant, categoryId: category.id, subcategoryIds: nil)
    }

    @ViewBuilder
    private var toolbarMenu: some View {
        if let known = MerchantCategoryMemory.shared.merchant(forDescription: merchant) ?? unremembered {
            Button {
                editing = known
            } label: {
                Label(String(localized: "common.edit", defaultValue: "Edit"), systemImage: "pencil")
            }
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    NavigationStack {
        MerchantDetailView(
            merchant: "GREENMART 12",
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel
        )
    }
    .environment(coordinator)
    .environment(coordinator.transactionStore)
    .environment(TimeFilterManager())
}
