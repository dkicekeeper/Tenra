//
//  InsightDeepDiveView.swift
//  Tenra
//
//  Phase 17: Financial Insights Feature
//  Full category detail: subcategory breakdown, spending trends, anomalies
//

import SwiftUI
import os

struct InsightDeepDiveView: View {
    let categoryName: String
    let color: Color
    let iconSource: IconSource?
    let currency: String
    let viewModel: InsightsViewModel?

    @State private var subcategories: [SubcategoryBreakdownItem] = []
    /// Previous-bucket total for the comparison card.
    @State private var prevBucketAmount: Double = 0
    /// Precomputed index map — eliminates O(n^2) firstIndex(where:) in ForEach.
    @State private var subcategoryIndexMap: [String: Int] = [:]

    private static let logger = Logger(subsystem: "Tenra", category: "CategoryDeepDive")

    // MARK: - Initializers

    /// Production initializer
    init(categoryName: String, color: Color, iconSource: IconSource?, currency: String, viewModel: InsightsViewModel) {
        self.categoryName = categoryName
        self.color = color
        self.iconSource = iconSource
        self.currency = currency
        self.viewModel = viewModel
    }

    /// Preview initializer — pre-populates state, no ViewModel needed
    fileprivate init(
        categoryName: String,
        color: Color,
        iconSource: IconSource?,
        currency: String,
        subcategories: [SubcategoryBreakdownItem],
        prevBucketAmount: Double = 0
    ) {
        self.categoryName = categoryName
        self.color = color
        self.iconSource = iconSource
        self.currency = currency
        self.viewModel = nil
        _subcategories = State(initialValue: subcategories)
        _prevBucketAmount = State(initialValue: prevBucketAmount)
        _subcategoryIndexMap = State(initialValue: Dictionary(
            uniqueKeysWithValues: subcategories.enumerated().map { ($1.id, $0) }
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                headerSection

                if !subcategories.isEmpty {
                    comparisonSection

                }

                if !subcategories.isEmpty {
                    subcategorySection
                }
            }
        }
        .task { await loadDataAsync() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            SimpleHeroSection(
                iconSource: iconSource,
                title: categoryName
            )

            let totalAmount = subcategories.reduce(0.0) { $0 + $1.amount }
            FormattedAmountText(
                amount: totalAmount,
                currency: currency,
                fontSize: AppTypography.h4,
                fontWeight: .semibold,
                color: color
            )
        }
    }

    // MARK: - Subcategories

    private var subcategorySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
//            SectionHeaderView(String(localized: "insights.subcategories"), style: .default)

            DonutChart(
                slices: DonutSlice.from(subcategories, baseColor: color),
                showAnnotations: false,
                showLegend: false
            )
            

            // List
            ForEach(subcategories) { item in
                HStack (alignment:.top){
                    Circle()
                        .fill(color.opacity(Double(subcategoryIndexMap[item.id] ?? 0) * 0.15 + 0.3))
                        .frame(width: 24, height: 24)

                    Text(item.name)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        FormattedAmountText(amount: item.amount, currency: currency, color: AppColors.textPrimary)
                        Text(String(format: "%.1f%%", item.percentage))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .screenPadding()
    }

    // MARK: - Comparison

    private var comparisonSection: some View {
        let gran = viewModel?.currentGranularity ?? .month
        let currentLabel  = gran.periodLabel(for: gran.currentPeriodKey)
        let previousLabel = gran.periodLabel(for: gran.previousPeriodKey)
        let currentAmount = subcategories.reduce(0.0) { $0 + $1.amount }
        return VStack(spacing: AppSpacing.md) {
//            SectionHeaderView(String(localized: "insights.periodComparison"), style: .default)
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

    /// Async because categoryDeepDive is CPU-heavy (filter + grouping).
    /// .task cancels automatically on view disappear.
    @MainActor
    private func loadDataAsync() async {
        guard let viewModel else { return } // Preview mode — data pre-populated
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

#Preview("Insight Deep Dive — Food") {
    NavigationStack {
        InsightDeepDiveView(
            categoryName: "Food",
            color: AppColors.warning,
            iconSource: .sfSymbol("fork.knife"),
            currency: "KZT",
            subcategories: [
                SubcategoryBreakdownItem(id: "restaurants", name: "Restaurants", amount: 42_000, percentage: 49),
                SubcategoryBreakdownItem(id: "groceries",   name: "Groceries",   amount: 28_000, percentage: 33),
                SubcategoryBreakdownItem(id: "delivery",    name: "Delivery",    amount: 15_000, percentage: 18)
            ],
            prevBucketAmount: 78_000
        )
    }
}
