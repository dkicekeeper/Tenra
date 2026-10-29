//
//  AssetsListView.swift
//  Tenra
//
//  The assets, from the Assets card in Finances (docs/domains/assets.md). On top, what the held
//  assets are worth in the base currency on the colour of their gain (DesignKit's
//  `.heroBackground`), with the gain over what they cost and their worth over time; the cards
//  rise over the colour's end. Then the held assets by kind (real estate, transport, other) and
//  the sold ones, each a HoldingCard whose value rolls up as the list opens. A tap opens one
//  (AssetDetailView), a long press edits or deletes it, the toolbar selects several to delete,
//  reorders them within their section and adds one. Adding is Tenra Pro: without it "+" and
//  the empty state's button open the paywall and continue into the form once Pro is on.
//

import SwiftUI

struct AssetsListView: View {
    let assetStore: AssetStore

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(PremiumManager.self) private var premium
    @Environment(\.amountsHidden) private var amountsHidden
    @State private var showingAdd = false
    @State private var showingPaywall = false
    @State private var mode: CardListMode = .browsing
    @State private var selection: Set<String> = []
    @State private var editingAsset: Asset?
    /// The assets a confirmation is asked for: one from its menu, or the ones selected.
    @State private var assetsToDelete: [String] = []

    private var baseCurrency: String {
        coordinator.transactionsViewModel.appSettings.baseCurrency
    }

    /// The loan accounts an asset can be bought with (a mortgage, a car loan).
    private var loanAccounts: [Account] {
        coordinator.transactionStore.accounts.filter { $0.loanInfo != nil }
    }

    var body: some View {
        // Assets in other currencies convert at the cached rates: drawn again when they change.
        let _ = coordinator.transactionStore.currencyRatesVersion
        Group {
            if !assetStore.isLoaded {
                // The cards to come (AssetCard is DesignKit's HoldingCard).
                VStack(spacing: AppSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        HoldingCardSkeleton().screenPadding()
                    }
                }
                .padding(.vertical, AppSpacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            } else if assetStore.assets.isEmpty {
                MascotEmptyState(
                    icon: "house",
                    title: String(localized: "asset.emptyTitle"),
                    description: String(localized: "asset.emptyDescription"),
                    actionTitle: String(localized: "asset.new"),
                    action: add,
                    line: String(localized: "assistant.empty.assets")
                )
                .transition(.skeletonReveal)
            } else {
                list
                    .transition(.skeletonReveal)
            }
        }
        .animation(AppAnimation.smooth, value: assetStore.isLoaded)
        .navigationTitle(String(localized: "asset.listTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .cardListToolbar(
            mode: $mode,
            selection: $selection,
            allIDs: assetStore.assets.map(\.id),
            addLabel: String(localized: "asset.new"),
            onAdd: add,
            onDeleteSelected: { assetsToDelete = Array(selection) }
        )
        .paywallSheet(isPresented: $showingPaywall) {
            // After unlocking Pro, continue straight into the new asset.
            showingAdd = true
        }
        .sheet(isPresented: $showingAdd) {
            AssetEditView(asset: nil, loanAccounts: loanAccounts, baseCurrency: baseCurrency) { asset in
                Task { await assetStore.add(asset) }
            }
        }
        .sheet(item: $editingAsset) { asset in
            AssetEditView(asset: asset, loanAccounts: loanAccounts, baseCurrency: baseCurrency) { updated in
                Task { await assetStore.update(updated) }
            }
        }
        .alert(
            assetsToDelete.count > 1
                ? String(format: String(localized: "bulk.deleteAssets.title", defaultValue: "Delete %d assets?"), assetsToDelete.count)
                : String(localized: "asset.deleteTitle"),
            isPresented: Binding(get: { !assetsToDelete.isEmpty }, set: { if !$0 { assetsToDelete = [] } })
        ) {
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                let ids = assetsToDelete
                assetsToDelete = []
                Task {
                    for id in ids {
                        await assetStore.delete(id: id)
                    }
                }
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .browsing
                }
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "asset.deleteMessage"))
        }
        .task { await assetStore.load() }
    }

    // MARK: - List

    private var list: some View {
        let held = assetStore.held
        return ScrollView {
            VStack(spacing: AppSpacing.xl) {
                if !held.isEmpty {
                    hero
                }
                // Leading: the section titles start at the cards' edge.
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(AssetKind.Group.allCases, id: \.self) { group in
                        section(title(of: group), assets: assetStore.held(in: group), canReorder: true)
                    }
                    section(String(localized: "asset.section.sold"), assets: assetStore.sold, canReorder: false)
                }
                // Rises over the fading end of the hero's colour.
                .padding(.top, held.isEmpty ? 0 : -AppSpacing.xxl)
            }
            .padding(.top, held.isEmpty ? AppSpacing.md : 0)
            .padding(.bottom, AppSpacing.md)
        }
        // The hero's colour reaches the top of the screen under the bar.
        .heroScrollEdge()
    }

    /// What the held assets are worth, the gain over what they cost, and their worth over
    /// time, on the colour of the gain.
    private var hero: some View {
        let totals = assetStore.totals(in: baseCurrency)
        let history = assetStore.valueHistory(in: baseCurrency)
        return VStack(spacing: AppSpacing.xl) {
            HeroSection(
                icon: nil,
                title: String(localized: "asset.heroTitle"),
                showsIcon: false,
                primaryAmount: totals.value,
                primaryCurrency: baseCurrency,
                subtitle: totals.gain.map {
                    String(format: String(localized: "asset.gainSincePurchase"), AssetCard.signedAmount($0, currency: baseCurrency, hidden: amountsHidden))
                }
            ) {
                if let gain = totals.gain, let percent = totals.gainPercent {
                    TrendBadge(direction: AssetCard.direction(of: gain), changePercent: percent, style: .pill)
                }
            }
            .frame(maxWidth: .infinity)
            .screenPadding()

            if history.count >= 2 {
                HeroSparkline(
                    dataPoints: AssetChartPoints.points(history),
                    series: AssetChartPoints.series(color: AppColors.income),
                    valueFormat: .currency(baseCurrency),
                    entranceDelay: AssetChartPoints.entranceDelay
                )
            }
        }
        .heroBackground(heroColor(gain: totals.gain))
    }

    /// Green while the assets gained, the accent otherwise.
    private func heroColor(gain: Double?) -> Color {
        (gain ?? 0) > 0.5 ? AppColors.income : AppColors.accent
    }

    private func title(of group: AssetKind.Group) -> String {
        switch group {
        case .realEstate: return String(localized: "asset.section.realEstate")
        case .transport: return String(localized: "asset.section.transport")
        case .other: return String(localized: "asset.section.other")
        }
    }

    /// One section as DesignKit's `CardList` of ready-made cards (8.0.0); a drag puts an asset
    /// in its place within the section (the sold ones keep the order of their sale).
    @ViewBuilder
    private func section(_ title: String, assets: [Asset], canReorder: Bool) -> some View {
        if !assets.isEmpty {
            let onMove: ((IndexSet, Int) -> Void)? = canReorder ? { source, destination in
                var reordered = assets
                reordered.move(fromOffsets: source, toOffset: destination)
                Task { await assetStore.reorder(reordered.map(\.id)) }
            } : nil
            SectionHeader(title)
                .screenPadding()
                .padding(.top, AppSpacing.sm)
            CardList(assets, layout: .stack, mode: mode, selection: $selection, onMove: onMove) { asset in
                row(asset)
            }
            .screenPadding()
        }
    }

    private func row(_ asset: Asset) -> some View {
        NavigationLink(value: FinancesDestination.assetDetail(asset.id)) {
            AssetCard(asset: asset, summary: assetStore.summary(for: asset))
        }
        .buttonStyle(.plain)
        .scrollReveal()
        .accessibilityIdentifier("assets.card")
        .contextMenu {
            Button {
                editingAsset = asset
            } label: {
                Label(String(localized: "button.edit", defaultValue: "Edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                HapticManager.warning()
                assetsToDelete = [asset.id]
            } label: {
                Label(String(localized: "button.delete"), systemImage: "trash")
            }
        }
    }

    private func add() {
        HapticManager.light()
        if premium.isPro {
            showingAdd = true
        } else {
            showingPaywall = true
        }
    }
}

/// The valuation charts' points (the list's hero and an asset's screen): DesignKit's
/// `ChartValuePoint`, a label per point, the month and year on the axis, the day in the
/// selection banner.
enum AssetChartPoints {
    static let key = "value"
    /// The charts draw in once the push has settled.
    static let entranceDelay = 0.3

    static func points(_ values: [AssetValuationMath.DatedValue]) -> [ChartValuePoint] {
        values.enumerated().map { index, point in
            ChartValuePoint(
                label: "p\(index)",
                axisLabel: point.date.formatted(.dateTime.month(.abbreviated).year(.twoDigits)),
                title: DateFormatters.displayDateOmittingCurrentYear(point.date),
                values: [key: point.value]
            )
        }
    }

    static func series(color: Color) -> ChartSeries<ChartValuePoint> {
        .keyed(key, name: String(localized: "asset.chart.value"), coloring: .solid(color))
    }
}

#Preview("Assets List") {
    let coordinator = AppCoordinator()
    NavigationStack {
        AssetsListView(assetStore: coordinator.assetStore)
    }
    .environment(coordinator)
    // Required: the view reads `@Environment(PremiumManager.self)` for the Pro gate.
    .environment(PremiumManager.shared)
}
