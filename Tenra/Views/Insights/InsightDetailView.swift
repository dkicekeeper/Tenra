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
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Header — hidden for formula-breakdown detail since the card already
                // carries hero + label.
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
        case .periodTrend(let points):
            // Scrollable charts (line/bar) bleed edge-to-edge — no horizontal
            // padding here, otherwise the visible plot area is offset from the
            // screen left edge and the first datapoint appears clipped.
            let gran = points.first?.granularity ?? .month
            if insight.type == .bestMonth || insight.type == .worstMonth
                || insight.type == .incomeGrowth || insight.type == .incomeVsExpenseRatio {
                PeriodChartSwitcher(dataPoints: points, currency: currency, granularity: gran, mode: .full)
            } else {
                PeriodLineChart(
                    dataPoints: points,
                    series: insight.category == .wealth ? .wealth : .cashFlow,
                    granularity: gran,
                    mode: .full
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
        case .recurringList(let items):
            recurringDetailList(items)
        case .budgetProgressList:
            EmptyView()
        case .periodTrend(let points):
            periodBreakdownList(points.map { BreakdownPoint(label: $0.label, income: $0.income, expenses: $0.expenses, netFlow: $0.netFlow) })
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

    /// Unified point model for breakdown list — eliminates monthlyDetailList/periodDetailList duplication.
    private struct BreakdownPoint {
        let label: String
        let income: Double
        let expenses: Double
        let netFlow: Double
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
            if let iconSource = item.iconSource {
                IconView(
                    source: iconSource,
                    style: .circle(size: AppIconSize.xl, tint: .monochrome(item.color))
                )
            }

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
                    if let iconSource = item.iconSource {
                        IconView(source: iconSource, size: AppIconSize.lg)
                    } else {
                        Image(systemName: "repeat.circle")
                            .font(.system(size: AppIconSize.md))
                            .foregroundStyle(AppColors.accent)
                    }

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
    private func periodBreakdownList(_ points: [BreakdownPoint]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.monthlyBreakdown"), style: .large)

            ForEach(points.reversed(), id: \.label) { point in
                PeriodBreakdownRow(
                    label: point.label,
                    income: point.income,
                    expenses: point.expenses,
                    netFlow: point.netFlow,
                    currency: currency
                )
            }
        }
    }

    private func accountDetailList(_ accounts: [AccountInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.wealth.accounts"), style: .large)

            ForEach(accounts) { account in
                HStack(spacing: AppSpacing.md) {
                    if let iconSource = account.iconSource {
                        IconView(source: iconSource, size: AppIconSize.lg)
                    } else {
                        Image(systemName: "building.columns")
                            .font(.system(size: AppIconSize.md))
                            .foregroundStyle(AppColors.accent)
                    }

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
                    if let iconSource = account.iconSource {
                        IconView(source: iconSource, size: AppIconSize.lg)
                    } else {
                        Image(systemName: "building.columns")
                            .font(.system(size: AppIconSize.md))
                            .foregroundStyle(AppColors.textSecondary)
                    }

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
