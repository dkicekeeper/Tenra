//
//  InsightDetailLists.swift
//  Tenra
//
//  Detail lists for InsightDetailView (2026-07 UX pass) — extracted from the
//  monolithic view file. Every list follows one contract: optional large
//  SectionHeaderView above, rows inside a `.cardStyle()` card (inner padding
//  AppSpacing.lg per the design-system card contract), `.screenPadding()`
//  owned by the shared shell.
//
//  Detail structure contract (docs/domains/insights.md): HeroSection → chart
//  → cards → these lists.
//

import SwiftUI

// MARK: - Shared card shell

/// Card shell all detail lists share: header outside (feed-section convention),
/// rows inside the glass card.
private struct InsightDetailListCard<Rows: View>: View {
    var title: String? = nil
    var rowSpacing: CGFloat = AppSpacing.sm
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let title {
                SectionHeaderView(title, style: .large)
            }
            VStack(alignment: .leading, spacing: rowSpacing) {
                rows()
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .screenPadding()
    }
}

// MARK: - Category breakdown

/// Category rows with optional deep-dive drill-down. Generic over the
/// destination (mirrors InsightDetailView — no AnyView type erasure).
struct InsightCategoryBreakdownList<Destination: View>: View {
    let items: [CategoryBreakdownItem]
    let currency: String
    /// Period key of the page the user is viewing (paged breakdown);
    /// nil = current/all-time bucket.
    var periodKey: String? = nil
    let onCategoryTap: ((CategoryBreakdownItem, String?) -> Destination)?

    var body: some View {
        InsightDetailListCard {
            ForEach(items) { item in
                row(item)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: CategoryBreakdownItem) -> some View {
        if let onCategoryTap {
            NavigationLink(destination: onCategoryTap(item, periodKey)) {
                CategoryBreakdownRow(item: item, currency: currency, showsChevron: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            CategoryBreakdownRow(item: item, currency: currency)
        }
    }
}

// MARK: - Recurring breakdown

struct InsightRecurringBreakdownList: View {
    let items: [RecurringInsightItem]
    let currency: String

    var body: some View {
        InsightDetailListCard(title: String(localized: "insights.breakdown")) {
            ForEach(items) { item in
                InsightEntityRow(
                    iconSource: item.iconSource,
                    title: item.name,
                    subtitle: item.frequency.displayName,
                    amount: item.monthlyEquivalent,
                    currency: currency,
                    amountCaption: String(localized: "insights.perMonth")
                )
            }
        }
    }
}

// MARK: - Period breakdown

/// Period-by-period breakdown. `metric` selects which value each row surfaces
/// (cash-flow triple vs. a single metric matching the insight).
struct InsightPeriodBreakdownList: View {
    let points: [PeriodDataPoint]
    let granularity: InsightGranularity
    let metric: PeriodListMetric
    let currency: String

    var body: some View {
        InsightDetailListCard(title: granularity.breakdownTitle) {
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
}

// MARK: - Ranked periods (records)

/// Ranked Top-10 list of periods by net flow (best = descending, worst =
/// ascending). Worst ranking only ranks deficit periods — a "worst" list that
/// surfaces profitable months reads as a bug.
struct InsightRankedPeriodList: View {
    let points: [PeriodDataPoint]
    let best: Bool
    let currency: String

    private var top: [PeriodDataPoint] {
        let candidates = best ? points : points.filter { $0.netFlow < 0 }
        let sorted = candidates.sorted { best ? $0.netFlow > $1.netFlow : $0.netFlow < $1.netFlow }
        return Array(sorted.prefix(10))
    }

    var body: some View {
        InsightDetailListCard(
            title: best
                ? String(localized: "insights.topMonths.best")
                : String(localized: "insights.topMonths.worst")
        ) {
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
}

// MARK: - Wealth accounts

struct InsightAccountBreakdownList: View {
    let accounts: [AccountInsightItem]
    let currency: String

    var body: some View {
        InsightDetailListCard(title: String(localized: "insights.wealth.accounts")) {
            ForEach(accounts) { account in
                InsightEntityRow(
                    iconSource: account.iconSource,
                    title: account.accountName,
                    subtitle: account.currency,
                    amount: account.balance,
                    currency: currency,
                    amountColor: account.balance >= 0 ? AppColors.textPrimary : AppColors.destructive
                )
            }
        }
    }
}

// MARK: - Dormant accounts

/// Each dormant account with last activity date and balance.
struct InsightDormantAccountList: View {
    let accounts: [AccountInsightItem]
    let currency: String

    var body: some View {
        InsightDetailListCard(title: String(localized: "insights.dormant.accounts")) {
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
            }
        }
    }
}

// MARK: - Budget progress

/// Budget rows are NOT wrapped in the shared card shell — `BudgetProgressRow`
/// is already a standalone `.cardStyle()` card; wrapping the list would nest
/// cards. LazyVStack defers upfront layout of all rows (P22).
struct InsightBudgetBreakdownList: View {
    let items: [BudgetInsightItem]
    let currency: String

    var body: some View {
        LazyVStack(spacing: AppSpacing.md) {
            ForEach(items) { item in
                BudgetProgressRow(item: item, currency: currency)
            }
        }
        .screenPadding()
    }
}

// MARK: - Previews

#Preview("Category breakdown list") {
    ScrollView {
        InsightCategoryBreakdownList<Never>(
            items: CategoryBreakdownItem.mockItems(),
            currency: "KZT",
            onCategoryTap: nil
        )
    }
}

#Preview("Period breakdown list") {
    ScrollView {
        InsightPeriodBreakdownList(
            points: PeriodDataPoint.mockMonthly(),
            granularity: .month,
            metric: .cashFlow,
            currency: "KZT"
        )
    }
}

#Preview("Ranked periods") {
    ScrollView {
        InsightRankedPeriodList(
            points: PeriodDataPoint.mockMonthly(),
            best: true,
            currency: "KZT"
        )
    }
}
