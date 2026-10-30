//
//  MerchantDetailView.swift
//  Tenra
//
//  One merchant's screen (docs/domains/intents.md §6.1): its logo and name, what was
//  spent there in the selected period, this month and this year, visits, the average
//  check, the last visit, its months as a chart and every transaction, whatever recorded
//  it (Apple Pay, a statement, by hand).
//  Opened from Settings → Wallet → Merchants and from the transaction of a remembered
//  merchant, of one with a logo or a given name, of a brand's point or of an operation
//  linked to a merchant (TransactionEditView); the menu edits the merchant
//  (MerchantCategoryEditView), combines points of one brand (MerchantMergeView) and links
//  operations entered by hand (LinkPaymentsView).
//
//  A merchant merged into a brand (MerchantGroupStore) shows the whole brand: every point's
//  operations and figures, with chips under the hero to see one point.
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
    /// The figures arrived: until then the hero has no amount and the rows wait, rather than
    /// showing zeros that jump to the real values.
    @State private var hasLoaded = false
    @State private var accountsById: [String: Account] = [:]
    @State private var editing: MerchantCategoryMemory.Merchant?
    /// The brands and the linked operations: the screen follows every change.
    @State private var groups = MerchantGroupStore.shared
    /// The brand's point picked under the hero (a normalized merchant); nil: every point.
    @State private var point: String?
    @State private var showingMerge = false
    @State private var showingLink = false
    @State private var showingSplitConfirmation = false
    /// The linked operation whose glyph was tapped: the dialog offers to unlink it.
    @State private var unlinking: String?
    /// Settings → "Merchant logos" (on by default), as on the merchant's transaction rows.
    @AppStorage(MerchantLogoStore.enabledKey) private var showsMerchantLogos = true

    private var merchantKey: String { CategorySuggestionService.normalizedMerchant(merchant) }

    /// The brand the merchant is a point of.
    private var group: MerchantGroupStore.Group? { groups.group(forKey: merchantKey) }

    /// The point picked, while it is still one of the brand's.
    private var activePoint: String? {
        guard let point, group?.members.contains(point) == true else { return nil }
        return point
    }

    /// The operations the screen counts: the brand's or the point's, with those linked by hand.
    private var selection: MerchantGroupStore.Selection {
        groups.selection(forMerchant: merchant, point: activePoint)
    }

    private var name: String {
        if let group { return groups.displayName(of: group) }
        return MerchantLogoStore.shared.customName(forDescription: merchant) ?? MerchantName.displayName(merchant)
    }

    /// The bank's text of the point picked, else of the screen's merchant: where linked
    /// operations go.
    private var linkTarget: String {
        activePoint.flatMap { group?.memberNames[$0] } ?? merchant
    }

    private var usualCategory: CustomCategory? {
        summary.usualCategory.flatMap { name in
            categoriesViewModel.customCategories.first { $0.name == name && $0.type == .expense }
        }
    }

    /// The merchant's logo (when logos are on), else one of its brand's points', else its
    /// usual category's icon, else a shop.
    private var heroIcon: (source: IconSource, tint: IconTint) {
        if showsMerchantLogos {
            let names = [merchant] + (group.map { group in group.members.compactMap { group.memberNames[$0] } } ?? [])
            if let logo = names.lazy.compactMap({ MerchantLogoStore.shared.iconSource(forDescription: $0) }).first {
                return (logo, .original)
            }
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
            selection: selection,
            mutationVersion: transactionStore.mutationVersion,
            ratesVersion: transactionStore.currencyRatesVersion,
            baseCurrency: transactionsViewModel.appSettings.baseCurrency,
            filterHash: timeFilterManager.currentFilter.hashValue,
            day: DateFormatters.dateFormatter.string(from: Date())
        )
    }

    private struct RefreshKey: Equatable {
        /// The points counted and the operations linked to them.
        let selection: MerchantGroupStore.Selection
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
            navigationAmount: hasLoaded ? summary.spentInPeriod : nil,
            navigationCurrency: baseCurrency,
            infoRows: hasLoaded ? infoRows(baseCurrency: baseCurrency) : [],
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
                VStack(spacing: AppSpacing.lg) {
                    HeroSection(
                        icon: icon.source,
                        title: name,
                        iconTint: icon.tint,
                        primaryAmount: hasLoaded ? summary.spentInPeriod : nil,
                        primaryCurrency: baseCurrency,
                        subtitle: timeFilterManager.currentFilter.displayName
                    )
                    pointPicker
                }
            },
            customSections: { monthlyChart(baseCurrency: baseCurrency) },
            historyRowOverlay: { tx in linkedMark(tx) },
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
        .sheet(isPresented: $showingMerge) {
            MerchantMergeView(merchant: merchant)
        }
        .navigationDestination(isPresented: $showingLink) {
            linkView(baseCurrency: baseCurrency)
        }
        .confirmationDialog(
            String(localized: "merchant.points.splitTitle"),
            isPresented: $showingSplitConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "merchant.points.split"), role: .destructive) {
                guard let group else { return }
                HapticManager.warning()
                point = nil
                groups.dissolve(groupId: group.id)
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "merchant.points.splitMessage"))
        }
        .confirmationDialog(
            String(localized: "merchant.link.linked"),
            isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "merchant.link.unlink"), role: .destructive) {
                guard let id = unlinking else { return }
                HapticManager.selection()
                groups.unlink(transactionId: id)
                unlinking = nil
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
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
        let counted = selection
        let range = timeFilterManager.currentFilter.dateRange()
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        let computed = await Task.detached(priority: .userInitiated) {
            MerchantHistory.summary(
                of: counted,
                in: all,
                periodStart: range.start,
                periodEnd: range.end,
                baseCurrency: baseCurrency
            )
        }.value
        guard !Task.isCancelled else { return }
        summary = computed
        hasLoaded = true
    }

    // MARK: - Points

    /// A brand's points as chips under the hero, "All" first: one picked, the screen shows
    /// only its operations and figures.
    @ViewBuilder
    private var pointPicker: some View {
        if let group, group.members.count > 1 {
            ChipPicker(
                options: group.members,
                selection: $point,
                allTitle: String(localized: "merchant.points.all"),
                inset: AppSpacing.lg
            ) { key in
                pointLabel(key, in: group)
            }
            // The hero is padded: the chips scroll to the screen's edges, the first one in line.
            .padding(.horizontal, -AppSpacing.lg)
            .accessibilityIdentifier("merchant.points")
        }
    }

    /// A point's chip: the name the person gave it, else the bank's text without the words
    /// every point starts with ("ZARA DOSTYK PLAZA" → "Dostyk Plaza").
    private func pointLabel(_ key: String, in group: MerchantGroupStore.Group) -> String {
        let raw = group.memberNames[key] ?? key
        if let custom = MerchantLogoStore.shared.customName(forDescription: raw) { return custom }
        let full = MerchantName.displayName(raw)
        let names = group.members.compactMap { group.memberNames[$0] }
        guard let shared = MerchantGroupStore.sharedLeadingWords(of: names) else { return full }
        let sharedKey = CategorySuggestionService.normalizedMerchant(shared)
        let words = full.split(separator: " ")
        for count in 1..<max(words.count, 1) {
            if CategorySuggestionService.normalizedMerchant(words.prefix(count).joined(separator: " ")) == sharedKey {
                return words.dropFirst(count).joined(separator: " ")
            }
        }
        return full
    }

    // MARK: - Linked operations

    /// An operation linked to the merchant by hand: a link glyph that asks to unlink it.
    @ViewBuilder
    private func linkedMark(_ tx: Transaction) -> some View {
        if groups.linkedMerchant(forTransactionId: tx.id) != nil {
            Button {
                unlinking = tx.id
            } label: {
                Icon("link", size: AppIconSize.sm, tint: .monochrome(AppColors.textSecondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "merchant.link.linked"))
            .accessibilityHint(String(localized: "merchant.link.unlink"))
        }
    }

    /// Operations of the history that are not the merchant's yet, to link by hand.
    private func linkView(baseCurrency: String) -> some View {
        let counted = selection
        let target = linkTarget
        return LinkPaymentsView(
            title: String(localized: "merchant.link.title"),
            displayCurrency: baseCurrency,
            findCandidates: { all, _ in
                MerchantDirectory.linkCandidates(in: all, excluding: counted)
            },
            performLink: { selected in
                let ids = selected.map(\.id)
                await MainActor.run {
                    MerchantGroupStore.shared.link(transactionIds: ids, toMerchant: target)
                }
            },
            options: .merchant,
            transactionStore: transactionStore,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel
        )
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

    private enum ChartKey {
        static let spent = "spent"
        static let yearAgo = "yearAgo"
        static let forecast = "forecast"
    }

    /// Its months as bars, by the category screen's rules (CategoryDetailView.monthlyChart,
    /// DesignKit 8.3): two years, so the chart opens on this month in the middle; this month
    /// fading towards its forecast and the same month a year ago behind each bar, from the
    /// chart's menu; a tap shows a month's amount. None until something was spent. Less spent
    /// is better, so a month's change reads green when it fell.
    @ViewBuilder
    private func monthlyChart(baseCurrency: String) -> some View {
        if summary.months.contains(where: { $0.total > 0 }) {
            let title = String(localized: "merchant.detail.byMonth")
            let series: ChartSeries<ChartValuePoint> = .keyed(
                ChartKey.spent, name: title, coloring: .solid(AppColors.accent), baseline: .zero, better: .lower,
                projectedKey: ChartKey.forecast, comparisonKey: ChartKey.yearAgo
            )
            let points: [ChartValuePoint] = summary.months.map { month in
                var values = [ChartKey.spent: month.total]
                if let yearAgo = month.yearAgo { values[ChartKey.yearAgo] = yearAgo }
                if let forecast = month.forecast { values[ChartKey.forecast] = forecast }
                return ChartValuePoint(
                    label: month.key,
                    axisLabel: PeriodAxisLabel.month(month.start),
                    title: month.start.formatted(.dateTime.month(.wide).year()),
                    isPartial: month.isCurrent,
                    values: values
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
        Button {
            showingMerge = true
        } label: {
            Label(String(localized: "merchant.merge.action"), systemImage: "arrow.triangle.merge")
        }
        Button {
            showingLink = true
        } label: {
            Label(String(localized: "merchant.link.action"), systemImage: "link.badge.plus")
        }
        if let group {
            if let activePoint {
                Button {
                    point = nil
                    groups.remove(point: activePoint)
                } label: {
                    Label(
                        String(format: String(localized: "merchant.points.remove"), pointLabel(activePoint, in: group)),
                        systemImage: "minus.circle"
                    )
                }
            }
            Button(role: .destructive) {
                showingSplitConfirmation = true
            } label: {
                Label(String(localized: "merchant.points.split"), systemImage: "arrow.triangle.branch")
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
