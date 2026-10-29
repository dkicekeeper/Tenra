//
//  AssetDetailView.swift
//  Tenra
//
//  One asset (docs/domains/assets.md), on EntityDetailScaffold. The hero: its icon, the value
//  (the sale price once sold) with when it was valued and the gain over the purchase price as a
//  trend pill, then its worth over time, the purchase and every valuation, drawing in. Actions:
//  "Update value" (a valuation, MoneyEntrySheet) and "Sell" (the sale price and day), or
//  "Return to assets" once sold. Info rows: the purchase, the gain, the growth a year, the
//  person's share, the linked loan and their own money in it. Then the valuations, newest first
//  (a long press deletes one, which breaks into dust). A valuation above the value bursts
//  sparkles over the hero; a sale above the purchase price celebrates.
//

import SwiftUI

struct AssetDetailView: View {
    let assetStore: AssetStore
    let assetId: String

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.amountsHidden) private var amountsHidden
    @State private var showingEdit = false
    @State private var showingValuation = false
    @State private var showingSale = false
    @State private var showingDelete = false
    /// Bumped by a valuation above the value: one burst of sparkles over the hero.
    @State private var valuationSparkles = 0
    /// Bumped by a sale above the purchase price: one confetti burst.
    @State private var celebrations = 0
    /// The growth a year depends on the day: moved at midnight.
    @State private var today = Date()

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

    @ViewBuilder
    private func scaffold(for asset: Asset) -> some View {
        // An asset in another currency shows its value in the base one at the cached rates, and a
        // linked loan's balance moves with its payments: drawn again when either changes.
        let _ = coordinator.transactionStore.currencyRatesVersion
        let _ = coordinator.transactionStore.accounts.count
        let summary = assetStore.summary(for: asset, today: today)
        let history = AssetValuationMath.history(of: asset)
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
                    action: { undoSale(asset) }
                )
                : ActionConfig(
                    title: String(localized: "asset.sell"),
                    systemImage: "tag",
                    action: {
                        HapticManager.selection()
                        showingSale = true
                    }
                ),
            infoRows: infoRows(for: asset, summary: summary),
            hero: {
                hero(for: asset, summary: summary, history: history)
            },
            customSections: {
                if !history.isEmpty {
                    historySection(for: asset, history: history)
                }
            },
            toolbarMenu: {
                Button {
                    HapticManager.selection()
                    showingEdit = true
                } label: {
                    Label(String(localized: "button.edit"), systemImage: "pencil")
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
                baseCurrency: appSettings.baseCurrency
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

            if history.count >= 2 {
                HeroSparkline(
                    dataPoints: AssetChartPoints.points(history.map { AssetValuationMath.DatedValue(date: $0.date, value: $0.value) }),
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
        return summary.valuedOn.map {
            String(format: String(localized: "asset.valuedOn"), DateFormatters.displayDateOmittingCurrentYear($0))
        }
    }

    /// The line follows the gain: green up, red down, the accent without a purchase price.
    private func chartColor(_ summary: AssetValuationMath.Summary) -> Color {
        guard let gain = summary.gain else { return AppColors.accent }
        return AssetCard.direction(of: gain).color
    }

    // MARK: - Info rows

    private func infoRows(for asset: Asset, summary: AssetValuationMath.Summary) -> [InfoRowConfig] {
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
        if let soldAt = asset.soldAt {
            rows.append(InfoRowConfig(
                icon: "checkmark.seal",
                label: String(localized: "asset.soldDate"),
                value: DateFormatters.displayDateOmittingCurrentYear(soldAt),
                iconColor: AppColors.income
            ))
        }
        return rows
    }

    /// "50%" in the app's locale.
    static func percentText(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - History

    private func historySection(for asset: Asset, history: [AssetValuation]) -> some View {
        let entries = Array(history.reversed())
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(String(localized: "asset.history"))
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    VStack(spacing: 0) {
                        HistoryEntryRow(
                            date: entry.date,
                            note: entry.note.flatMap { $0.isEmpty ? nil : $0 } ?? Self.sourceTitle(entry.source),
                            amount: entry.value,
                            currency: asset.currency,
                            symbol: Self.symbol(of: entry.source)
                        )
                        .contentShape(Rectangle())
                        .contextMenu {
                            // The purchase is the asset's own price and day: changed in Edit.
                            if entry.source != .purchase {
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
