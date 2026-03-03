//
//  CategoryDeepDiveView.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Full category detail: subcategory breakdown, spending trends, anomalies
//

import SwiftUI
import os

struct CategoryDeepDiveView: View {
    let categoryName: String
    let color: Color
    let iconSource: IconSource?
    let currency: String
    let viewModel: InsightsViewModel

    @State private var subcategories: [SubcategoryBreakdownItem] = []
    /// Phase 31: previous-bucket total for the comparison card (trend chart removed).
    @State private var prevBucketAmount: Double = 0
    /// Phase 23-C P16: precomputed index map — eliminates O(n²) firstIndex(where:) in ForEach.
    @State private var subcategoryIndexMap: [String: Int] = [:]

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "CategoryDeepDive")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                headerSection

                if !subcategories.isEmpty {
                    comparisonSection
                    
                }

                if !subcategories.isEmpty {
                    subcategorySection
                }
            }
        }
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.inline)
        // Phase 23-A P5: offload heavy computation to background thread
        .task { await loadDataAsync() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: AppSpacing.md) {
            if let iconSource {
                IconView(source: iconSource, size: AppIconSize.xl)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(categoryName)
                    .font(AppTypography.h2)
                    .foregroundStyle(AppColors.textPrimary)

                let totalAmount = subcategories.reduce(0.0) { $0 + $1.amount }
                FormattedAmountText(
                    amount: totalAmount,
                    currency: currency,
                    fontSize: AppTypography.h4,
                    fontWeight: .semibold,
                    color: color
                )
            }

            Spacer()
        }
        .screenPadding()
    }

    // MARK: - Subcategories

    private var subcategorySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeaderView(String(localized: "insights.subcategories"), style: .insights)
                .screenPadding()

            DonutChart(
                slices: DonutSlice.from(subcategories, baseColor: color),
                showAnnotations: false,
                showLegend: false
            )
            .screenPadding()

            // List
            ForEach(subcategories) { item in
                HStack {
                    Circle()
                        .fill(color.opacity(Double(subcategoryIndexMap[item.id] ?? 0) * 0.15 + 0.3))
                        .frame(width: 10, height: 10)

                    Text(item.name)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    AmountWithPercentage(
                        amount: item.amount,
                        currency: currency,
                        percentage: item.percentage
                    )
                }
                .padding(.vertical, AppSpacing.xs)
                .screenPadding()
            }
        }
    }

    // MARK: - Comparison

    private var comparisonSection: some View {
        let gran = viewModel.currentGranularity
        let currentLabel  = gran.periodLabel(for: gran.currentPeriodKey)
        let previousLabel = gran.periodLabel(for: gran.previousPeriodKey)
        let currentAmount = subcategories.reduce(0.0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeaderView(String(localized: "insights.periodComparison"), style: .insights)
            PeriodComparisonCard(
                currentLabel: currentLabel,
                currentAmount: currentAmount,
                previousLabel: previousLabel,
                previousAmount: prevBucketAmount,
                currency: currency,
                isExpenseContext: true
            )
        }
        .screenPadding()
    }

    // MARK: - Data Loading

    /// Phase 23-A P5: async — viewModel.categoryDeepDive is CPU-heavy (filter + grouping).
    /// .task cancels automatically on view disappear.
    /// categoryDeepDive is @MainActor-isolated, so we call it directly (await hops to MainActor).
    @MainActor
    private func loadDataAsync() async {
        Self.logger.debug("🔍 [CategoryDeepDive] OPEN — category='\(categoryName, privacy: .public)' gran='\(viewModel.currentGranularity.rawValue, privacy: .public)'")

        // categoryDeepDive is @MainActor — call directly; Swift hops actors automatically.
        let result = viewModel.categoryDeepDive(categoryName: categoryName)

        // Write results (already on MainActor)
        subcategories    = result.subcategories
        prevBucketAmount = result.prevBucketTotal
        // Build index map once to avoid O(n²) firstIndex(where:) in body (P16 fix)
        subcategoryIndexMap = Dictionary(
            uniqueKeysWithValues: subcategories.enumerated().map { ($1.id, $0) }
        )

        let totalAmount = subcategories.reduce(0.0) { $0 + $1.amount }
        Self.logger.debug("🔍 [CategoryDeepDive] LOADED — subcategories=\(subcategories.count), prevBucket=\(String(format: "%.0f", prevBucketAmount), privacy: .public), total=\(String(format: "%.0f", totalAmount), privacy: .public)")
    }
}

// MARK: - Previews

/// Wrapper that injects mock data directly without going through InsightsViewModel
private struct CategoryDeepDivePreview: View {
    @State private var subcategories: [SubcategoryBreakdownItem] = [
        SubcategoryBreakdownItem(id: "restaurants", name: "Restaurants", amount: 42_000, percentage: 49),
        SubcategoryBreakdownItem(id: "groceries",   name: "Groceries",   amount: 28_000, percentage: 33),
        SubcategoryBreakdownItem(id: "delivery",    name: "Delivery",    amount: 15_000, percentage: 18)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Header
                HStack(spacing: AppSpacing.md) {
                    IconView(source: .sfSymbol("fork.knife"), size: AppIconSize.xl)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Food")
                            .font(AppTypography.h2)
                            .foregroundStyle(AppColors.textPrimary)
                        let total = subcategories.reduce(0.0) { $0 + $1.amount }
                        FormattedAmountText(
                            amount: total,
                            currency: "KZT",
                            fontSize: AppTypography.h3,
                            fontWeight: .semibold,
                            color: AppColors.warning
                        )
                    }
                    Spacer()
                }
                .screenPadding()

                // Subcategory list
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(String(localized: "insights.subcategories"))
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .screenPadding()
                    ForEach(subcategories) { item in
                        HStack {
                            Circle().fill(AppColors.warning.opacity(0.6)).frame(width: AppSize.dotSize, height: AppSize.dotSize)
                            Text(item.name).font(AppTypography.body)
                            Spacer()
                            VStack(alignment: .trailing) {
                                FormattedAmountText(
                                    amount: item.amount,
                                    currency: "KZT",
                                    fontSize: AppTypography.body,
                                    fontWeight: .semibold,
                                    color: AppColors.textPrimary
                                )
                                Text(String(format: "%.1f%%", item.percentage))
                                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .padding(.vertical, AppSpacing.xs)
                        .screenPadding()
                    }
                }

                // Comparison card (mock: current Feb vs Jan)
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeaderView(String(localized: "insights.periodComparison"), style: .insights)
                    PeriodComparisonCard(
                        currentLabel: "Feb 2026",
                        currentAmount: subcategories.reduce(0.0) { $0 + $1.amount },
                        previousLabel: "Jan 2026",
                        previousAmount: 78_000,
                        currency: "KZT",
                        isExpenseContext: true
                    )
                }
                .screenPadding()
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle("Food")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Category Deep Dive — Food") {
    NavigationStack {
        CategoryDeepDivePreview()
    }
}
