//
//  InsightDetailView.swift
//  Tenra
//
//  Phase 23: UI fixes
//  - P9: viewModel replaced with onCategoryTap closure — SRP, no full ViewModel dependency
//  - P10: monthlyDetailList + periodDetailList merged into single periodBreakdownList
//  - P22: budgetChartSection uses LazyVStack
//

import SwiftUI
import os

struct InsightDetailView<CategoryDestination: View>: View {
    let insight: Insight
    let currency: String
    /// P9: SRP — pass only what's needed for drill-down, not the entire ViewModel.
    /// Nil = no drill-down chevron shown. Generic over CategoryDestination avoids AnyView type erasure.
    /// The `String?` is the period key of the breakdown page the user tapped from
    /// (`nil` for non-paged breakdowns) so the destination dives into the right month.
    private let _onCategoryTap: ((CategoryBreakdownItem, String?) -> CategoryDestination)?

    private var logger: Logger { Logger(subsystem: "Tenra", category: "InsightDetailView") }

    // MARK: - Init (with drill-down)
    init(
        insight: Insight,
        currency: String,
        @ViewBuilder onCategoryTap: @escaping (CategoryBreakdownItem, String?) -> CategoryDestination
    ) {
        self.insight = insight
        self.currency = currency
        self._onCategoryTap = onCategoryTap
    }

    var body: some View {
        Group {
            if case .categoryBreakdownPaged(let pages) = insight.detailData {
                // Paged breakdown owns the full screen (TabView page-swipe) — must NOT be
                // nested in a ScrollView, and its horizontal swipe replaces the chart/list
                // sections entirely.
                PagedCategoryBreakdownView(
                    pages: pages.periods,
                    currentIndex: pages.currentIndex,
                    currency: currency,
                    emptyTitle: insight.type == .incomeSourceBreakdown
                        ? String(localized: "insights.noIncomeForPeriod")
                        : String(localized: "insights.noExpensesForPeriod"),
                    onCategoryTap: _onCategoryTap
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        // Detail structure contract (2026-07 UX pass), top to bottom:
                        // HeroSection → chart (hero visual / full chart) → cards →
                        // detail lists. Every detail shows the header — formula
                        // details render InsightFormulaCard with showsHero: false
                        // so the metric isn't duplicated.
                        headerSection

                        // Hero visual (2026-07 visual refresh) — full-size sibling
                        // of the feed card's cardVisual, above the data sections.
                        heroChartSection

                        // Full-size chart
                        chartSection

                        // Detail breakdown
                        detailSection
                    }
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
        .navigationTitle(insight.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            logger.debug("📋 [InsightDetail] OPEN — type=\(String(describing: insight.type), privacy: .public), category=\(String(describing: insight.category), privacy: .public), metric=\(insight.metric.formattedValue, privacy: .public), drillDown=\(_onCategoryTap != nil)")
        }
    }

    /// Which single metric a period-trend breakdown list should surface, derived from
    /// the insight type. Cash-flow style insights keep the income/expenses/net triple.
    private var periodListMetric: PeriodListMetric {
        switch insight.type {
        case .averageDailySpending: return .avgDailyExpenses
        case .monthOverMonthChange: return .expenses
        case .incomeGrowth:         return .income
        case .wealthGrowth:         return .cumulativeBalance
        default:                    return .cashFlow
        }
    }

    /// Which series the period-trend chart plots, matching the insight metric.
    private var periodChartSeries: PeriodChartSeries {
        switch insight.type {
        case .averageDailySpending: return .avgDailyExpenses
        case .monthOverMonthChange: return .spending
        case .incomeGrowth:         return .income
        default:                    return insight.category == .wealth ? .wealth : .cashFlow
        }
    }

    // MARK: - Header

    /// Unified entity-detail hero (2026-07 UX pass — replaced a bespoke
    /// three-line leading-aligned header). Mapping:
    /// title ← insight.subtitle (insight.title is already the nav title),
    /// amount slot ← metric (FormattedAmountText for currency, `primaryText`
    /// otherwise), accessory ← trend badge, subtitle ← comparison period
    /// (suppressed when it duplicates insight.subtitle — several generators
    /// set them identical: monthOverMonth, wealthGrowth). Iconless — the
    /// severity glyph carried no information over the trend badge + hero chart.
    private var headerSection: some View {
        HeroSection(
            icon: nil,
            title: insight.subtitle,
            showsIcon: false,
            primaryAmount: insight.metric.currency != nil ? insight.metric.value : nil,
            primaryCurrency: insight.metric.currency ?? "",
            primaryText: insight.metric.currency == nil ? nonCurrencyMetricText : nil,
            subtitle: comparisonSubtitle
        ) {
            if let trend = insight.trend {
                InsightTrendBadge(trend: trend, style: .pill, colorOverride: insight.trendBadgeColorOverride)
            }
        }
        .frame(maxWidth: .infinity)
        .screenPadding()
    }

    /// Non-currency metric (percent, count) with its unit appended.
    private var nonCurrencyMetricText: String {
        if let unit = insight.metric.unit {
            return "\(insight.metric.formattedValue) \(unit)"
        }
        return insight.metric.formattedValue
    }

    /// Comparison period line — only when it adds information over the title.
    private var comparisonSubtitle: String? {
        guard let trend = insight.trend, trend.comparisonPeriod != insight.subtitle else { return nil }
        return trend.comparisonPeriod
    }

    // MARK: - Hero Section (2026-07 visual refresh)

    /// Delay before hero entrance animations start. The detail is pushed with a
    /// zoom `navigationTransition`; entrance animations running DURING the
    /// transition made the hero visibly jump the moment the push settled.
    /// Delaying past the transition keeps the open buttery and choreographs
    /// the hero as a second beat.
    private static var heroEntranceDelay: Double { 0.5 }

    /// Full-size hero rendered from the generator-set `cardVisual` payload —
    /// same data the feed mini-visual draws, as a DEDICATED hero component per
    /// visual (never the Mini* view scaled up) with the wow toolkit and
    /// tap interactivity (see HeroChartEffects + Hero* components).
    /// Special-cases by payload, NOT by adding InsightDetailData cases
    /// (domain-doc rule).
    @ViewBuilder
    private var heroChartSection: some View {
        switch insight.cardVisual {
        case .halfGauge(let value, let norm, let color):
            HeroHalfGauge(value: value, norm: norm, color: color, entranceDelay: Self.heroEntranceDelay)
                .frame(maxWidth: .infinity)
                .screenPadding()
        case .barPair(let previous, let current, let color, let isProjection):
            HeroBarPair(
                previous: previous,
                current: current,
                color: color,
                isProjection: isProjection,
                currency: currency,
                entranceDelay: Self.heroEntranceDelay
            )
            .frame(maxWidth: .infinity)
            .screenPadding()
        case .milestoneGauge(let value, let target, let maxValue, let color):
            HeroMilestoneGauge(
                value: value,
                target: target,
                maxValue: maxValue,
                color: color,
                entranceDelay: Self.heroEntranceDelay
            )
            .screenPadding()
        case .sparkline(let points, let series, let projectedValue, let markExtremes):
            // Interactive Swift Charts hero (tap selection + banner) with the
            // projection tail / extreme markers the mini draws.
            HeroSparkline(
                dataPoints: points,
                series: series,
                projectedValue: projectedValue,
                markExtremes: markExtremes,
                currency: currency,
                entranceDelay: Self.heroEntranceDelay
            )
        case .proportionBar(let segments):
            // Interactive composition hero: animated stacked bar + tappable
            // legend (name / share / amount per segment).
            HeroProportionBar(
                segments: segments,
                currency: currency,
                entranceDelay: Self.heroEntranceDelay
            )
            .screenPadding()
        case .ring, .budgetBars, .donut, nil:
            // Ring/budget-bars/donut details already render their own full-size
            // sections (budget rows, OrbChart, account lists) — no hero needed.
            EmptyView()
        }
    }

    // MARK: - Chart Section

    @ViewBuilder
    private var chartSection: some View {
        switch insight.detailData {
        case .categoryBreakdown(let items):
            OrbChart(slices: DonutSlice.from(items))
                .screenPadding()
        case .categoryBreakdownPaged:
            // Chart + list are rendered together per page in detailSection.
            EmptyView()
        case .periodTrend(let points):
            // Scrollable charts (line/bar) bleed edge-to-edge — no horizontal
            // padding here, otherwise the visible plot area is offset from the
            // screen left edge and the first datapoint appears clipped.
            let gran = points.first?.granularity ?? .month
            if insight.type == .bestMonth || insight.type == .monthOverMonthChange {
                // No full trend chart here: period records show ranked Top-10
                // lists instead, and MoM already leads with the HeroBarPair —
                // a second (trend) chart under it duplicated the message.
                EmptyView()
            } else {
                // Single-series bar/line pair plotting the metric that matches the
                // insight, with the same style switcher the income/expense pair has.
                ChartSwitcher(
                    dataPoints: points,
                    series: periodChartSeries,
                    granularity: gran,
                    currency: currency
                )
            }
        case .budgetProgressList(let items):
            InsightBudgetBreakdownList(items: items, currency: currency)
        case .recurringList:
            EmptyView()
        case .accountComparison:
            EmptyView()
        case .wealthBreakdown(let accounts):
            // Composition orb from the generator's ready donut slices (top
            // accounts + "Other" already aggregated) — the account list alone
            // left the detail chartless. List renders in detailSection.
            if case .donut(let slices) = insight.cardVisual, !slices.isEmpty {
                WealthOrbSection(accounts: accounts, fallbackSlices: slices)
                    .screenPadding()
            }
        case .formulaBreakdown(let model):
            // showsHero: false — the metric already leads the screen in
            // headerSection; the card keeps its formula rows + explainer.
            InsightFormulaCard(model: model, showsHero: false)
                .screenPadding()
        case nil:
            EmptyView()
        }
    }

    // MARK: - Detail Section

    // Lists live in InsightDetailLists.swift — carded per the detail structure
    // contract (SectionHeaderView above, rows inside .cardStyle()).
    @ViewBuilder
    private var detailSection: some View {
        switch insight.detailData {
        case .categoryBreakdown(let items):
            // P9: drill-down destination — generic CategoryDestination, no AnyView
            // type erasure. Non-paged breakdown → nil period key (current bucket).
            InsightCategoryBreakdownList(items: items, currency: currency, onCategoryTap: _onCategoryTap)
        case .categoryBreakdownPaged:
            // Rendered full-screen at body level (TabView), not inside the ScrollView.
            EmptyView()
        case .recurringList(let items):
            InsightRecurringBreakdownList(items: items, currency: currency)
        case .budgetProgressList:
            EmptyView()
        case .periodTrend(let points):
            let gran = points.first?.granularity ?? .month
            if insight.type == .bestMonth {
                // Merged "period records" card: best ranking always; worst ranking
                // only when there is at least one negative period to rank.
                InsightRankedPeriodList(points: points, best: true, currency: currency)
                if points.contains(where: { $0.netFlow < 0 }) {
                    InsightRankedPeriodList(points: points, best: false, currency: currency)
                }
            } else {
                InsightPeriodBreakdownList(points: points, granularity: gran, metric: periodListMetric, currency: currency)
            }
        case .wealthBreakdown(let accounts):
            InsightAccountBreakdownList(accounts: accounts, currency: currency)
        case .accountComparison(let accounts):
            InsightDormantAccountList(accounts: accounts, currency: currency)
        case .formulaBreakdown:
            EmptyView()
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Wealth composition orb

/// Wealth orb with account-brand colours and NAME labels. Slice tints resolve
/// asynchronously from the dominant logo colour (`DominantColorExtractor`,
/// in-memory cached — usually instant) for brand-icon accounts; SF-symbol
/// accounts and misses keep the generator's hash palette. The generator can't
/// do this itself: it runs nonisolated/off-main with no access to logo images.
private struct WealthOrbSection: View {
    let accounts: [AccountInsightItem]
    let fallbackSlices: [DonutSlice]

    @State private var brandSlices: [DonutSlice]?

    var body: some View {
        OrbChart(slices: brandSlices ?? fallbackSlices, labelStyle: .name)
            .task { await resolveBrandColors() }
    }

    private func resolveBrandColors() async {
        guard brandSlices == nil else { return }
        var resolved: [DonutSlice] = []
        resolved.reserveCapacity(fallbackSlices.count)
        for slice in fallbackSlices {
            guard let account = accounts.first(where: { $0.id == slice.id }),
                  case .brandService(let brand) = account.iconSource,
                  let brandColor = await DominantColorExtractor.accentColor(forBrand: brand)
            else {
                resolved.append(slice)
                continue
            }
            resolved.append(DonutSlice(
                id: slice.id,
                amount: slice.amount,
                color: brandColor,
                label: slice.label,
                percentage: slice.percentage
            ))
        }
        brandSlices = resolved
    }
}

// MARK: - Convenience init (no drill-down)

extension InsightDetailView where CategoryDestination == Never {
    /// Init without category drill-down. No chevron shown; category rows are non-tappable.
    init(insight: Insight, currency: String) {
        self.insight = insight
        self.currency = currency
        self._onCategoryTap = nil
    }
}

// MARK: - Paged Category Breakdown

/// Swipeable per-period category breakdown. Opens on the current period and pages back
/// to the first transaction's period. Empty periods show an empty state so the user can
/// keep swiping. Generic over the drill-down destination (mirrors InsightDetailView).
struct PagedCategoryBreakdownView<CategoryDestination: View>: View {
    let pages: [PeriodCategoryBreakdown]
    let currency: String
    /// Empty-page copy. The pager is flavor-agnostic (expense categories and income
    /// sources both page through it), so the caller supplies the wording.
    let emptyTitle: String
    /// Second arg is the period key of the page tapped from, so the drill-down dives
    /// into the period the user is viewing rather than the current one.
    let onCategoryTap: ((CategoryBreakdownItem, String?) -> CategoryDestination)?

    @State private var index: Int

    /// Chart band and list pager page together, so their page transition must stay
    /// in lockstep — one value instead of three hand-typed `easeInOut(0.25)`.
    /// (Computed, not `static let` — this type is generic, which bars stored statics.)
    private var pageAnimation: Animation { .easeInOut(duration: AppAnimation.standard) }

    init(
        pages: [PeriodCategoryBreakdown],
        currentIndex: Int,
        currency: String,
        emptyTitle: String = String(localized: "insights.noExpensesForPeriod"),
        onCategoryTap: ((CategoryBreakdownItem, String?) -> CategoryDestination)?
    ) {
        self.pages = pages
        self.currency = currency
        self.emptyTitle = emptyTitle
        self.onCategoryTap = onCategoryTap
        let clamped = min(max(0, currentIndex), max(0, pages.count - 1))
        _index = State(initialValue: clamped)
    }

    var body: some View {
        // Outer pager owns the full screen; each page is its own ScrollView so
        // the hero and orb scroll together with the category list (they used to
        // be pinned above a list-only pager). TabView captures the horizontal
        // swipe so paging doesn't fight the navigation's edge swipe-to-go-back.
        TabView(selection: $index) {
            ForEach(pages.indices, id: \.self) { i in
                pageContent(pages[i])
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: - Page content (hero + orb + list, scrolling together)

    private func pageContent(_ page: PeriodCategoryBreakdown) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // Iconless hero — consistent with InsightDeepDiveView's header.
                HeroSection(
                    icon: nil,
                    title: page.label,
                    showsIcon: false,
                    primaryAmount: page.total > 0 ? page.total : nil,
                    primaryCurrency: currency
                )
                .frame(maxWidth: .infinity)

                chartBand(page)

                if page.items.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                } else {
                    InsightCategoryBreakdownList(
                        items: page.items,
                        currency: currency,
                        periodKey: page.id,
                        onCategoryTap: onCategoryTap
                    )
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - Chart band (donut + centered side arrows)

    private func chartBand(_ page: PeriodCategoryBreakdown) -> some View {
        ZStack {
            // Empty periods keep the band height stable so the arrows stay put.
            if !page.items.isEmpty {
                OrbChart(slices: DonutSlice.from(page.items), animatesOnAppear: true)
                    .screenPadding()
            } else {
                Color.clear.frame(height: 280)
            }

            // Arrows are vertically centered on the donut by the ZStack.
            HStack {
                arrowButton(step: -1, systemImage: "chevron.left", enabled: index > 0)
                Spacer()
                arrowButton(step: 1, systemImage: "chevron.right", enabled: index < pages.count - 1)
            }
            .screenPadding()
        }
    }

    private func arrowButton(step delta: Int, systemImage: String, enabled: Bool) -> some View {
        Button { step(delta) } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? AppColors.accent : AppColors.textTertiary)
        .disabled(!enabled)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard pages.indices.contains(next) else { return }
        withAnimation(pageAnimation) { index = next }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "tray",
            title: emptyTitle,
            description: String(localized: "insights.swipeHint")
        )
        .padding(.vertical, AppSpacing.xxl)
    }
}

// MARK: - Previews

#Preview("Category Breakdown") {
    NavigationStack {
        InsightDetailView(insight: .mockTopSpending(), currency: "KZT")
    }
}

#Preview("Cash Flow Trend") {
    NavigationStack {
        InsightDetailView(insight: .mockCashFlow(), currency: "KZT")
    }
}

#Preview("Budget Overspend") {
    NavigationStack {
        InsightDetailView(insight: .mockBudgetOver(), currency: "KZT")
    }
}

#Preview("Recurring Payments") {
    NavigationStack {
        InsightDetailView(insight: .mockRecurring(), currency: "KZT")
    }
}

#Preview("Income Growth") {
    NavigationStack {
        InsightDetailView(insight: .mockIncomeGrowth(), currency: "KZT")
    }
}

#Preview("Period Trend") {
    NavigationStack {
        InsightDetailView(insight: .mockPeriodTrend(), currency: "KZT")
    }
}

#Preview("Wealth Breakdown") {
    NavigationStack {
        InsightDetailView(insight: .mockWealthBreakdown(), currency: "KZT")
    }
}

#Preview("Category — Drill Down") {
    NavigationStack {
        InsightDetailView(insight: .mockTopSpending(), currency: "KZT") { item, periodKey in
            Text("Deep dive: \(item.categoryName) [\(periodKey ?? "current")]")
                .padding()
        }
    }
}

#Preview("Paged Breakdown — centered arrows") {
    let pages = [
        PeriodCategoryBreakdown(id: "2026-05", label: "Май 2026", total: 180_000, items: CategoryBreakdownItem.mockItems()),
        PeriodCategoryBreakdown(id: "2026-04", label: "Апрель 2026", total: 95_000, items: CategoryBreakdownItem.mockItems()),
        PeriodCategoryBreakdown(id: "2026-03", label: "Март 2026", total: 0, items: [])
    ]
    return NavigationStack {
        PagedCategoryBreakdownView<Never>(
            pages: pages,
            currentIndex: 0,
            currency: "KZT",
            onCategoryTap: nil
        )
    }
}
