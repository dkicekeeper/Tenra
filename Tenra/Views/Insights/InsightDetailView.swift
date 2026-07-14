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
                    onCategoryTap: _onCategoryTap
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        // Header — hidden for formula-breakdown detail (the card already
                        // carries hero + label).
                        if !isFormulaBreakdown {
                            headerSection
                        }

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

    private var isFormulaBreakdown: Bool {
        if case .formulaBreakdown = insight.detailData { return true }
        return false
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
    private var periodChartSeries: PeriodLineChartSeries {
        switch insight.type {
        case .averageDailySpending: return .avgDailyExpenses
        case .monthOverMonthChange: return .spending
        case .incomeGrowth:         return .income
        default:                    return insight.category == .wealth ? .wealth : .cashFlow
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: insight.severity.icon)
                    .foregroundStyle(insight.severity.color)
                Text(insight.subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                if let trend = insight.trend {
                    InsightTrendBadge(trend: trend, style: .inline, colorOverride: insight.trendBadgeColorOverride)
                }
            }

            Text(insight.metric.formattedValue)
                .font(AppTypography.h1)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.textPrimary)

            // Only show the comparison period when it adds information — several
            // insights set trend.comparisonPeriod identical to the subtitle
            // (monthOverMonth, wealthGrowth), which rendered the same line twice.
            if let trend = insight.trend, trend.comparisonPeriod != insight.subtitle {
                Text(trend.comparisonPeriod)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .screenPadding()
    }

    // MARK: - Chart Section

    @ViewBuilder
    private var chartSection: some View {
        switch insight.detailData {
        case .categoryBreakdown(let items):
            SpendingOrbChart(slices: DonutSlice.from(items))
                .screenPadding()
        case .categoryBreakdownPaged:
            // Chart + list are rendered together per page in detailSection.
            EmptyView()
        case .periodTrend(let points):
            // Scrollable charts (line/bar) bleed edge-to-edge — no horizontal
            // padding here, otherwise the visible plot area is offset from the
            // screen left edge and the first datapoint appears clipped.
            let gran = points.first?.granularity ?? .month
            if insight.type == .bestMonth {
                // Period records show ranked Top-10 lists (in detailSection), no chart.
                EmptyView()
            } else {
                // Single-series line chart plotting the metric that matches the insight.
                PeriodLineChart(
                    dataPoints: points,
                    series: periodChartSeries,
                    granularity: gran,
                    currency: currency
                )
            }
        case .budgetProgressList(let items):
            budgetChartSection(items)
                .screenPadding()
        case .recurringList:
            EmptyView()
        case .accountComparison:
            EmptyView()
        case .wealthBreakdown:
            // Account balance list rendered in detailSection
            EmptyView()
        case .formulaBreakdown(let model):
            InsightFormulaCard(model: model)
                .screenPadding()
        case nil:
            EmptyView()
        }
    }

    // P22: LazyVStack eliminates upfront layout of all budget rows
    private func budgetChartSection(_ items: [BudgetInsightItem]) -> some View {
        LazyVStack(spacing: AppSpacing.md) {
            ForEach(items) { item in
                BudgetProgressRow(item: item, currency: currency)
            }
        }
    }

    // MARK: - Detail Section

    @ViewBuilder
    private var detailSection: some View {
        switch insight.detailData {
        case .categoryBreakdown(let items):
            categoryDetailList(items)
        case .categoryBreakdownPaged:
            // Rendered full-screen at body level (TabView), not inside the ScrollView.
            EmptyView()
        case .recurringList(let items):
            recurringDetailList(items)
        case .budgetProgressList:
            EmptyView()
        case .periodTrend(let points):
            let gran = points.first?.granularity ?? .month
            if insight.type == .bestMonth {
                // Merged "period records" card: best ranking always; worst ranking
                // only when there is at least one negative period to rank.
                rankedPeriodList(points, best: true)
                if points.contains(where: { $0.netFlow < 0 }) {
                    rankedPeriodList(points, best: false)
                }
            } else {
                periodBreakdownList(points, granularity: gran, metric: periodListMetric)
            }
        case .wealthBreakdown(let accounts):
            accountDetailList(accounts)
        case .accountComparison(let accounts):
            dormantAccountDetailList(accounts)
        case .formulaBreakdown:
            EmptyView()
        case nil:
            EmptyView()
        }
    }

    private func categoryDetailList(_ items: [CategoryBreakdownItem]) -> some View {
        // Rows own their horizontal inset (per-row .screenPadding inside categoryRow),
        // so the full width — including the padding — is tappable in NavigationLink.
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(items) { item in
                categoryRow(item)
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ item: CategoryBreakdownItem) -> some View {
        // P9: drill-down destination — generic CategoryDestination, no AnyView type erasure.
        // Non-paged breakdown → nil period key (current/all-time bucket).
        if let tapHandler = _onCategoryTap {
            NavigationLink(destination: tapHandler(item, nil)) {
                CategoryBreakdownRow(item: item, currency: currency, showsChevron: true)
                    .screenPadding()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            CategoryBreakdownRow(item: item, currency: currency)
                .screenPadding()
        }
    }

    private func recurringDetailList(_ items: [RecurringInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.breakdown"), style: .large)

            ForEach(items) { item in
                InsightEntityRow(
                    iconSource: item.iconSource,
                    title: item.name,
                    subtitle: item.frequency.displayName,
                    amount: item.monthlyEquivalent,
                    currency: currency,
                    amountCaption: String(localized: "insights.perMonth")
                )
                .screenPadding()
            }
        }
    }

    // P10: Single unified function replacing monthlyDetailList + periodDetailList.
    // `metric` selects which value each row surfaces (cash-flow triple vs. a single
    // metric matching the insight: expenses, income, or average daily expenses).
    private func periodBreakdownList(_ points: [PeriodDataPoint], granularity: InsightGranularity, metric: PeriodListMetric) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(granularity.breakdownTitle, style: .large)

            ForEach(points.reversed()) { point in
                PeriodBreakdownRow(
                    label: point.granularity.headingLabel(for: point.key),
                    income: point.income,
                    expenses: point.expenses,
                    netFlow: point.netFlow,
                    currency: currency,
                    singleValue: metric.value(for: point),
                    singleColor: metric.color
                )
            }
        }
    }

    /// Ranked Top-10 list of periods by net flow (best = descending, worst = ascending).
    /// No chart, no income/expenses triple — just rank + period + net flow.
    private func rankedPeriodList(_ points: [PeriodDataPoint], best: Bool) -> some View {
        // Worst ranking only makes sense for deficit periods — a "worst" list that
        // surfaces profitable months reads as a bug.
        let candidates = best ? points : points.filter { $0.netFlow < 0 }
        let sorted = candidates.sorted { best ? $0.netFlow > $1.netFlow : $0.netFlow < $1.netFlow }
        let top = Array(sorted.prefix(10))
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(
                best ? String(localized: "insights.topMonths.best")
                     : String(localized: "insights.topMonths.worst"),
                style: .large
            )
            ForEach(Array(top.enumerated()), id: \.element.id) { index, point in
                PeriodBreakdownRow(
                    label: "\(index + 1). " + point.granularity.headingLabel(for: point.key),
                    income: point.income,
                    expenses: point.expenses,
                    netFlow: point.netFlow,
                    currency: currency,
                    singleValue: point.netFlow,
                    singleColor: point.netFlow >= 0 ? AppColors.success : AppColors.destructive
                )
            }
        }
    }

    private func accountDetailList(_ accounts: [AccountInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.wealth.accounts"), style: .large)

            ForEach(accounts) { account in
                InsightEntityRow(
                    iconSource: account.iconSource,
                    title: account.accountName,
                    subtitle: account.currency,
                    amount: account.balance,
                    currency: currency,
                    amountColor: account.balance >= 0 ? AppColors.textPrimary : AppColors.destructive
                )
                .screenPadding()
            }
        }
    }

    /// Shows each dormant account with last activity date and balance.
    private func dormantAccountDetailList(_ accounts: [AccountInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.dormant.accounts"), style: .large)

            ForEach(accounts) { account in
                InsightEntityRow(
                    iconSource: account.iconSource,
                    title: account.accountName,
                    amount: account.balance,
                    currency: currency,
                    amountColor: AppColors.textSecondary
                ) {
                    if let lastActivity = account.lastActivityDate {
                        Text(lastActivity, style: .relative)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .screenPadding()
            }
        }
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
        onCategoryTap: ((CategoryBreakdownItem, String?) -> CategoryDestination)?
    ) {
        self.pages = pages
        self.currency = currency
        self.onCategoryTap = onCategoryTap
        let clamped = min(max(0, currentIndex), max(0, pages.count - 1))
        _index = State(initialValue: clamped)
    }

    private var page: PeriodCategoryBreakdown? {
        pages.indices.contains(index) ? pages[index] : nil
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            pagerLabel

            // Fixed-height donut band with the period-switch arrows overlaid on the
            // left/right edges, vertically centered on the pie chart.
            chartBand

            // List of categories pages on horizontal swipe. TabView captures the swipe
            // so paging doesn't fight the navigation's edge swipe-to-go-back.
            listPager
        }
    }

    // MARK: - Header label

    private var pagerLabel: some View {
        // Iconless hero — consistent with InsightDeepDiveView's header.
        HeroSection(
            icon: nil,
            title: page?.label ?? "",
            showsIcon: false,
            primaryAmount: page.flatMap { $0.totalExpenses > 0 ? $0.totalExpenses : nil },
            primaryCurrency: currency
        )
    }

    // MARK: - Chart band (donut + centered side arrows)

    private var chartBand: some View {
        ZStack {
            // Donut for the current page. Empty periods keep the band height stable so
            // the arrows stay put. `.id(index)` cross-fades the chart on page change.
            Group {
                if let page, !page.items.isEmpty {
                    // Always replay the entrance (per page / re-appearance) while iterating on it.
                    SpendingOrbChart(slices: DonutSlice.from(page.items), animatesOnAppear: true)
                        .screenPadding()
                } else {
                    Color.clear.frame(height: 280)
                }
            }
            .id(index)
            .transition(.opacity)

            // Arrows are vertically centered on the donut by the ZStack.
            HStack {
                arrowButton(step: -1, systemImage: "chevron.left", enabled: index > 0)
                Spacer()
                arrowButton(step: 1, systemImage: "chevron.right", enabled: index < pages.count - 1)
            }
            .screenPadding()
        }
        .animation(pageAnimation, value: index)
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

    // MARK: - List pager

    private var listPager: some View {
        TabView(selection: $index) {
            ForEach(pages.indices, id: \.self) { i in
                listContent(pages[i])
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(pageAnimation, value: index)
    }

    @ViewBuilder
    private func listContent(_ page: PeriodCategoryBreakdown) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if page.items.isEmpty {
                    emptyState
                } else {
                    ForEach(page.items) { categoryRow($0, periodKey: page.id) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.md)
        }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard pages.indices.contains(next) else { return }
        withAnimation(pageAnimation) { index = next }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "tray",
            title: String(localized: "insights.noExpensesForPeriod"),
            description: String(localized: "insights.swipeHint")
        )
        .padding(.vertical, AppSpacing.xxl)
    }

    @ViewBuilder
    private func categoryRow(_ item: CategoryBreakdownItem, periodKey: String) -> some View {
        if let tapHandler = onCategoryTap {
            NavigationLink(destination: tapHandler(item, periodKey)) {
                CategoryBreakdownRow(item: item, currency: currency, showsChevron: true)
                    .screenPadding()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            CategoryBreakdownRow(item: item, currency: currency)
                .screenPadding()
        }
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
        PeriodCategoryBreakdown(id: "2026-05", label: "Май 2026", totalExpenses: 180_000, items: CategoryBreakdownItem.mockItems()),
        PeriodCategoryBreakdown(id: "2026-04", label: "Апрель 2026", totalExpenses: 95_000, items: CategoryBreakdownItem.mockItems()),
        PeriodCategoryBreakdown(id: "2026-03", label: "Март 2026", totalExpenses: 0, items: [])
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
