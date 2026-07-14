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
    /// Period bucket the user drilled in from. `nil` = current period (non-paged
    /// breakdowns). Threaded so a drill-down from a non-current month shows that
    /// month's data, not the current period's.
    let periodKey: String?

    @State private var subcategories: [SubcategoryBreakdownItem] = []
    /// Previous-bucket total for the comparison card.
    @State private var prevBucketAmount: Double = 0

    private static let logger = Logger(subsystem: "Tenra", category: "CategoryDeepDive")

    // MARK: - Initializers

    /// Production initializer
    init(categoryName: String, color: Color, iconSource: IconSource?, currency: String, viewModel: InsightsViewModel, periodKey: String? = nil) {
        self.categoryName = categoryName
        self.color = color
        self.iconSource = iconSource
        self.currency = currency
        self.viewModel = viewModel
        self.periodKey = periodKey
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
        self.periodKey = nil
        _subcategories = State(initialValue: subcategories)
        _prevBucketAmount = State(initialValue: prevBucketAmount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                headerSection

                if !subcategories.isEmpty {
                    subcategorySection
                }
                
                if !subcategories.isEmpty {
                    comparisonSection

                }
            }
        }
        .task { await loadDataAsync() }
    }

    // MARK: - Header

    private var headerSection: some View {
        let totalAmount = subcategories.reduce(0.0) { $0 + $1.amount }
        // Icon is hidden here — it now lives in the centre of the orb chart below.
        // Amount uses HeroSection's built-in slot (consistent with InsightDetailView).
        return HeroSection(
            icon: nil,
            title: categoryName,
            iconTint: .monochrome(color),
            showsIcon: false,
            primaryAmount: totalAmount > 0 ? totalAmount : nil,
            primaryCurrency: currency,
            primaryAmountColor: color
        )
    }

    // MARK: - Subcategories

    private var subcategorySection: some View {
        // Build slices once so the chart and the list draw each subcategory in the
        // exact same color — keyed by id, not by a separate per-view index formula.
        let slices = DonutSlice.from(subcategories, baseColor: color)
        let colorByID = Dictionary(uniqueKeysWithValues: slices.map { ($0.id, $0.color) })
        return VStack(alignment: .leading, spacing: AppSpacing.lg) {
            OrbChart(slices: slices, showLabels: true, centerIcon: iconSource)


            // List
            ForEach(subcategories) { item in
                HStack (alignment:.top){
                    Circle()
                        .fill(colorByID[item.id] ?? color)
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
        let curKey = periodKey ?? gran.currentPeriodKey
        let currentLabel  = gran.headingLabel(for: curKey)
        let previousLabel = gran.headingLabel(for: gran.previousPeriodKey(before: curKey))
        let currentAmount = subcategories.reduce(0.0) { $0 + $1.amount }
        return VStack(spacing: AppSpacing.md) {
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
        let result = viewModel.categoryDeepDive(categoryName: categoryName, periodKey: periodKey)

        // Write results (already on MainActor)
        subcategories    = result.subcategories
        prevBucketAmount = result.prevBucketTotal

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
