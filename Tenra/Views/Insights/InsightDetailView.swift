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

/// Shared icon styling for analytics breakdown lists, so categories, subscriptions and
/// accounts all follow the app's standard: circle container, background, consistent size.
/// (Mirrors `IconView(source:size:)` auto-styling; categories keep their colour.)
enum InsightIconStyle {
    static let listSize = AppIconSize.xl

    /// Category icon: coloured glyph on a faint coloured circle.
    static func category(_ color: Color) -> IconStyle {
        .circle(size: listSize, tint: .monochrome(color), backgroundColor: color.opacity(0.15))
    }
}

struct InsightDetailView<CategoryDestination: View>: View {
    let insight: Insight
    let currency: String
    /// P9: SRP — pass only what's needed for drill-down, not the entire ViewModel.
    /// Nil = no drill-down chevron shown. Generic over CategoryDestination avoids AnyView type erasure.
    private let _onCategoryTap: ((CategoryBreakdownItem) -> CategoryDestination)?

    private var logger: Logger { Logger(subsystem: "Tenra", category: "InsightDetailView") }

    // MARK: - Init (with drill-down)
    init(
        insight: Insight,
        currency: String,
        @ViewBuilder onCategoryTap: @escaping (CategoryBreakdownItem) -> CategoryDestination
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
                    .font(AppTypography.bodySmall)
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

            if let trend = insight.trend {
                Text(trend.comparisonPeriod)
                    .font(AppTypography.caption)
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
            DonutChart(slices: DonutSlice.from(items))
                .screenPadding()
        case .categoryBreakdownPaged:
            // Chart + list are rendered together per page in detailSection.
            EmptyView()
        case .periodTrend(let points):
            // Scrollable charts (line/bar) bleed edge-to-edge — no horizontal
            // padding here, otherwise the visible plot area is offset from the
            // screen left edge and the first datapoint appears clipped.
            let gran = points.first?.granularity ?? .month
            if insight.type == .bestMonth || insight.type == .worstMonth
                || insight.type == .incomeVsExpenseRatio {
                // Income-vs-expense comparison charts keep the dual-series switcher.
                PeriodChartSwitcher(dataPoints: points, currency: currency, granularity: gran)
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
            periodBreakdownList(points, granularity: gran, metric: periodListMetric)
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
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
//            SectionHeaderView(String(localized: "insights.breakdown"), style: .default)

            ForEach(items) { item in
                categoryRow(item)
            }
        }
        .screenPadding()
    }

    @ViewBuilder
    private func categoryRow(_ item: CategoryBreakdownItem) -> some View {
        let rowContent = HStack(spacing: AppSpacing.md) {
            IconView(source: item.iconSource, style: InsightIconStyle.category(item.color))

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(item.categoryName)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                if !item.subcategories.isEmpty {
                    Text(item.subcategories.prefix(3).map(\.name).joined(separator: ", "))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: AppSpacing.xs) {
                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    FormattedAmountText(amount: item.amount, currency: currency, color: AppColors.textPrimary)
                    Text(String(format: "%.1f%%", item.percentage))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                // P9: chevron only when drill-down closure is provided
                if _onCategoryTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(.vertical, AppSpacing.sm)

        // P9: drill-down destination — generic CategoryDestination, no AnyView type erasure
        if let tapHandler = _onCategoryTap {
            NavigationLink(destination: tapHandler(item)) {
                rowContent.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private func recurringDetailList(_ items: [RecurringInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.breakdown"), style: .large)

            ForEach(items) { item in
                HStack(spacing: AppSpacing.md) {
                    IconView(source: item.iconSource, size: InsightIconStyle.listSize)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(item.name)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(item.frequency.displayName)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        FormattedAmountText(
                            amount: item.monthlyEquivalent,
                            currency: currency,
                            fontSize: AppTypography.body,
                            fontWeight: .semibold,
                            color: AppColors.textPrimary
                        )
                        Text(String(localized: "insights.perMonth"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.vertical, AppSpacing.sm)
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
                    label: point.label,
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

    private func accountDetailList(_ accounts: [AccountInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.wealth.accounts"), style: .large)

            ForEach(accounts) { account in
                HStack(spacing: AppSpacing.md) {
                    IconView(source: account.iconSource, size: InsightIconStyle.listSize)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(account.accountName)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(account.currency)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer()

                    FormattedAmountText(
                        amount: account.balance,
                        currency: currency,
                        fontSize: AppTypography.body,
                        fontWeight: .semibold,
                        color: account.balance >= 0 ? AppColors.textPrimary : AppColors.destructive
                    )
                }
                .padding(.vertical, AppSpacing.sm)
                .screenPadding()
            }
        }
    }

    /// Shows each dormant account with last activity date and balance.
    private func dormantAccountDetailList(_ accounts: [AccountInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.dormant.accounts"), style: .large)

            ForEach(accounts) { account in
                HStack(spacing: AppSpacing.md) {
                    IconView(source: account.iconSource, size: InsightIconStyle.listSize)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(account.accountName)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        if let lastActivity = account.lastActivityDate {
                            Text(lastActivity, style: .relative)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }

                    Spacer()

                    FormattedAmountText(
                        amount: account.balance,
                        currency: currency,
                        fontSize: AppTypography.body,
                        fontWeight: .semibold,
                        color: AppColors.textSecondary
                    )
                }
                .padding(.vertical, AppSpacing.sm)
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
    let onCategoryTap: ((CategoryBreakdownItem) -> CategoryDestination)?

    @State private var index: Int

    init(
        pages: [PeriodCategoryBreakdown],
        currentIndex: Int,
        currency: String,
        onCategoryTap: ((CategoryBreakdownItem) -> CategoryDestination)?
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
        VStack(spacing: 0) {
            pagerHeader
                .padding(.vertical, AppSpacing.sm)

            // TabView page style captures horizontal swipes across the whole content area,
            // so paging the period no longer fights the navigation's edge swipe-to-go-back.
            TabView(selection: $index) {
                ForEach(pages.indices, id: \.self) { i in
                    pageContent(pages[i])
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: index)
        }
    }

    @ViewBuilder
    private func pageContent(_ page: PeriodCategoryBreakdown) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if page.items.isEmpty {
                    emptyState
                } else {
                    DonutChart(slices: DonutSlice.from(page.items))
                        .screenPadding()
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(page.items) { categoryRow($0) }
                    }
                    .screenPadding()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.md)
        }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard pages.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { index = next }
    }

    private var pagerHeader: some View {
        HStack(spacing: AppSpacing.md) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(index > 0 ? AppColors.accent : AppColors.textTertiary)
            .disabled(index == 0)

            Spacer()

            VStack(spacing: AppSpacing.xxs) {
                Text(page?.label ?? "")
                    .font(AppTypography.h3)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
                if let total = page?.totalExpenses, total > 0 {
                    FormattedAmountText(
                        amount: total,
                        currency: currency,
                        fontSize: AppTypography.bodySmall,
                        fontWeight: .regular,
                        color: AppColors.textSecondary
                    )
                }
            }

            Spacer()

            Button { step(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(index < pages.count - 1 ? AppColors.accent : AppColors.textTertiary)
            .disabled(index >= pages.count - 1)
        }
        .screenPadding()
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "tray")
                .font(.system(size: AppIconSize.xl))
                .foregroundStyle(AppColors.textTertiary)
            Text(String(localized: "insights.noExpensesForPeriod"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            Text(String(localized: "insights.swipeHint"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
        .screenPadding()
    }

    @ViewBuilder
    private func categoryRow(_ item: CategoryBreakdownItem) -> some View {
        let rowContent = HStack(spacing: AppSpacing.md) {
            IconView(source: item.iconSource, style: InsightIconStyle.category(item.color))

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(item.categoryName)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                if !item.subcategories.isEmpty {
                    Text(item.subcategories.prefix(3).map(\.name).joined(separator: ", "))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: AppSpacing.xs) {
                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    FormattedAmountText(amount: item.amount, currency: currency, color: AppColors.textPrimary)
                    Text(String(format: "%.1f%%", item.percentage))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                if onCategoryTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(.vertical, AppSpacing.sm)

        if let tapHandler = onCategoryTap {
            NavigationLink(destination: tapHandler(item)) {
                rowContent.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            rowContent
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
        InsightDetailView(insight: .mockTopSpending(), currency: "KZT") { item in
            Text("Deep dive: \(item.categoryName)")
                .padding()
        }
    }
}
