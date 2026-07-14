//
//  InsightsView.swift
//  Tenra
//
//  Phase 23: Insights Performance & UI fixes
//  - P7: InsightsSummaryHeader now receives PeriodDataPoint directly (no per-render conversion)
//  - Loading / empty state kept; sections unchanged
//  Phase 27: Granularity picker moved to toolbar (top-left Menu)
//  Task 2: value-based NavigationLink(value:) + zoom transition via navigationDestination(for: Insight.self)
//

import SwiftUI

struct InsightsView: View {
    // MARK: - Dependencies

    @Bindable var insightsViewModel: InsightsViewModel

    // MARK: - State

    @Namespace private var insightNamespace

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                if !insightsViewModel.isLoading && !insightsViewModel.hasData {
                    emptyState
                } else {
                    insightsSummaryHeaderSection
                    insightsFilterSection
                    insightsSectionsSection
                }
            }
            .padding(.vertical, AppSpacing.md)
            // Note: no outer animation needed — each section's ContentRevealModifier
            // owns its own opacity animation, preventing compositing conflicts.
        }
        .navigationTitle(String(localized: "insights.title"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Insight.self) { insight in
            insightDetailView(for: insight)
                .navigationTransition(.zoom(sourceID: insight.id, in: insightNamespace))
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("", selection: $insightsViewModel.currentGranularity) {
                        ForEach(InsightGranularity.allCases) { g in
                            Label(g.displayName, systemImage: g.icon)
                                .tag(g)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: insightsViewModel.currentGranularity.icon)
                        Text(insightsViewModel.currentGranularity.displayName)
                    }
                }
                .accessibilityLabel(String(localized: "accessibility.insights.granularityPicker"))
                .accessibilityHint(String(localized: "accessibility.insights.granularityPickerHint"))
            }
        }
        .onChange(of: insightsViewModel.currentGranularity) { _, _ in
            HapticManager.light()
        }
        // Lazy compute — onAppear triggers computation only if stale;
        // onDisappear stops background recomputes on transaction changes.
        .task {
            insightsViewModel.onAppear()
        }
        .onDisappear {
            insightsViewModel.onDisappear()
        }
    }

    // MARK: - Category Filter Carousel

    private var categoryFilterCarousel: some View {
        UniversalCarousel(config: .filter) {
            // "All" filter
            UniversalFilterButton(
                title: String(localized: "insights.all"),
                isSelected: insightsViewModel.selectedCategory == nil,
                showChevron: false,
                onTap: {
                    HapticManager.light()
                    insightsViewModel.selectCategory(nil)
                }
            ) {
                Image(systemName: "square.grid.2x2")
            }

            // Category filters
            ForEach(InsightCategory.allCases, id: \.self) { category in
                UniversalFilterButton(
                    title: category.displayName,
                    isSelected: insightsViewModel.selectedCategory == category,
                    showChevron: false,
                    onTap: {
                        HapticManager.light()
                        insightsViewModel.selectCategory(
                            insightsViewModel.selectedCategory == category ? nil : category
                        )
                    }
                ) {
                    Image(systemName: category.icon)
                }
            }
        }
    }

    // MARK: - Summary Header Section

    private var insightsSummaryHeaderSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            NavigationLink(destination: InsightsSummaryDetailView(
                totalIncome: insightsViewModel.totalIncome,
                totalExpenses: insightsViewModel.totalExpenses,
                netFlow: insightsViewModel.netFlow,
                currentBucketIncome: insightsViewModel.currentBucketIncome,
                currentBucketExpenses: insightsViewModel.currentBucketExpenses,
                currentBucketNetFlow: insightsViewModel.currentBucketNetFlow,
                previousBucketIncome: insightsViewModel.previousBucketIncome,
                previousBucketExpenses: insightsViewModel.previousBucketExpenses,
                previousBucketNetFlow: insightsViewModel.previousBucketNetFlow,
                bucketLabel: insightsViewModel.currentBucketLabel,
                currency: insightsViewModel.baseCurrency,
                periodDataPoints: insightsViewModel.periodDataPoints,
                granularity: insightsViewModel.currentGranularity
            )) {
                summaryStatsGrid
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let hs = insightsViewModel.healthScore {
                NavigationLink(destination: FinancialHealthDetailView(score: hs)) {
                    HealthScoreBadge(score: hs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("insights.healthScore")
            }
        }
        .screenPadding()
        .contentReveal(isReady: !insightsViewModel.isLoading)
    }

    /// 2×2 grid of summary stat cards: available balance, expenses, income, net flow.
    private var summaryStatsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: AppSpacing.md),
            GridItem(.flexible(), spacing: AppSpacing.md)
        ]
        let currency = insightsViewModel.baseCurrency
        let netFlow = insightsViewModel.currentBucketNetFlow
        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            if !insightsViewModel.currentBucketLabel.isEmpty {
                Text(insightsViewModel.currentBucketLabel)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
            }
            LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                InsightsStatCard(
                    title: String(localized: "insights.availableBalance"),
                    amount: insightsViewModel.availableBalance,
                    currency: currency,
                    color: insightsViewModel.availableBalance >= 0 ? AppColors.textPrimary : AppColors.destructive
                )
                InsightsStatCard(
                    title: String(localized: "insights.netFlow"),
                    amount: netFlow,
                    currency: currency,
                    color: netFlow >= 0 ? AppColors.textPrimary : AppColors.destructive,
                    previous: insightsViewModel.previousBucketNetFlow,
                    upIsGood: true
                )
                InsightsStatCard(
                    title: String(localized: "insights.expenses"),
                    amount: insightsViewModel.currentBucketExpenses,
                    currency: currency,
                    color: AppColors.destructive,
                    previous: insightsViewModel.previousBucketExpenses,
                    upIsGood: false
                )
                InsightsStatCard(
                    title: String(localized: "insights.income"),
                    amount: insightsViewModel.currentBucketIncome,
                    currency: currency,
                    color: AppColors.success,
                    previous: insightsViewModel.previousBucketIncome,
                    upIsGood: true
                )
            }
        }
    }

    // MARK: - Filter Section

    private var insightsFilterSection: some View {
        categoryFilterCarousel
            .contentReveal(isReady: !insightsViewModel.isLoading, delay: 0.05)
    }

    // MARK: - Content Sections

    private var insightsSectionsSection: some View {
        // Note: insightSections is always evaluated (ViewModifier receives content regardless of
        // isLoading). While loading, filteredInsights is empty, so insightSections resolves to
        // the "no insights" empty view — this is discarded in favour of the skeleton. Accepted trade-off.
        insightSections
            // Force the card subtree to rebuild on granularity change. `Insight.==` is id-only
            // (detailData holds non-Hashable Colors) and insight ids are STABLE across
            // granularities — so SwiftUI's ForEach diffing treats a new granularity's cards as
            // unchanged and skips re-rendering, leaving stale data ("shows wrong granularity").
            // Keying by granularity gives the cards fresh identity each switch.
            .id(insightsViewModel.currentGranularity)
            .contentReveal(isReady: !insightsViewModel.isLoading, delay: 0.1)
    }

    // MARK: - Insight Sections

    @ViewBuilder
    private var insightSections: some View {
        let filtered = insightsViewModel.filteredInsights

        if filtered.isEmpty {
            EmptyStateView(
                icon: "chart.line.uptrend.xyaxis",
                title: String(localized: "insights.noInsightsForFilter")
            )
            .padding(.top, AppSpacing.xxxl)

        } else if insightsViewModel.selectedCategory == nil {
            // LazyVStack: defers body evaluation of off-screen sections — prevents simultaneous
            // layout measurement of all 40+ compact Chart views during granularity switch.
            LazyVStack(alignment: .leading, spacing: AppSpacing.xl) {
                urgentSection

                InsightsSectionView(
                    category: .spending,
                    insights: insightsViewModel.spendingInsights,
                    currency: insightsViewModel.baseCurrency,
                    namespace: insightNamespace,
                    granularity: insightsViewModel.currentGranularity
                )
                .screenPadding()

                InsightsSectionView(
                    category: .income,
                    insights: insightsViewModel.incomeInsights,
                    currency: insightsViewModel.baseCurrency,
                    namespace: insightNamespace,
                    granularity: insightsViewModel.currentGranularity
                )
                .screenPadding()

                InsightsSectionView(
                    category: .budget,
                    insights: insightsViewModel.budgetInsights,
                    currency: insightsViewModel.baseCurrency,
                    namespace: insightNamespace,
                    granularity: insightsViewModel.currentGranularity
                )
                .screenPadding()

                InsightsSectionView(
                    category: .recurring,
                    insights: insightsViewModel.recurringInsights,
                    currency: insightsViewModel.baseCurrency,
                    namespace: insightNamespace,
                    granularity: insightsViewModel.currentGranularity
                )
                .screenPadding()

                InsightsSectionView(
                    category: .cashFlow,
                    insights: insightsViewModel.cashFlowInsights,
                    currency: insightsViewModel.baseCurrency,
                    namespace: insightNamespace,
                    granularity: insightsViewModel.currentGranularity
                )
                .screenPadding()

                InsightsSectionView(
                    category: .wealth,
                    insights: insightsViewModel.wealthInsights,
                    currency: insightsViewModel.baseCurrency,
                    namespace: insightNamespace,
                    granularity: insightsViewModel.currentGranularity
                )
                .screenPadding()

                InsightsSectionView(
                    category: .savings,
                    insights: insightsViewModel.savingsInsights,
                    currency: insightsViewModel.baseCurrency,
                    namespace: insightNamespace,
                    granularity: insightsViewModel.currentGranularity
                )
                .screenPadding()

                InsightsSectionView(
                    category: .forecasting,
                    insights: insightsViewModel.forecastingInsights,
                    currency: insightsViewModel.baseCurrency,
                    namespace: insightNamespace,
                    granularity: insightsViewModel.currentGranularity
                )
                .screenPadding()
            }

        } else {
            ForEach(filtered) { insight in
                NavigationLink(value: insight) {
                    InsightsCardView(insight: insight)
                        .matchedTransitionSource(id: insight.id, in: insightNamespace)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("insights.card.\(insight.id)")
            }
            .screenPadding()
        }
    }

    // MARK: - Urgent Section

    /// "Важное сейчас" — cross-section critical/warning signals surfaced above the
    /// category sections. Promoted insights are excluded from their own sections
    /// (see InsightsViewModel.urgentInsights), so card ids stay unique in the namespace.
    @ViewBuilder
    private var urgentSection: some View {
        let urgent = insightsViewModel.urgentInsights
        if !urgent.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeaderView(
                    String(localized: "insights.urgentNow"),
                    systemImage: "exclamationmark.circle",
                    style: .large
                )

                ForEach(urgent) { insight in
                    NavigationLink(value: insight) {
                        InsightsCardView(insight: insight)
                            .matchedTransitionSource(id: insight.id, in: insightNamespace)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("insights.card.\(insight.id)")
                }
            }
            .screenPadding()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "chart.line.uptrend.xyaxis",
            title: String(localized: "insights.emptyState.title"),
            description: String(localized: "insights.emptyState.description")
        )
    }

    // MARK: - Navigation Detail Builder

    /// Builds the correct InsightDetailView variant depending on category.
    /// Spending insights get category drill-down; all others are read-only.
    /// @ViewBuilder enables conditional branches with different generic specialisations
    /// (InsightDetailView<InsightDeepDiveView> vs InsightDetailView<Never>) without AnyView.
    @ViewBuilder
    private func insightDetailView(for insight: Insight) -> some View {
        if insight.category == .spending {
            InsightDetailView(insight: insight, currency: insightsViewModel.baseCurrency) { item, periodKey in
                InsightDeepDiveView(
                    categoryName: item.categoryName,
                    color: item.color,
                    iconSource: item.iconSource,
                    currency: insightsViewModel.baseCurrency,
                    viewModel: insightsViewModel,
                    periodKey: periodKey
                )
            }
        } else {
            InsightDetailView(insight: insight, currency: insightsViewModel.baseCurrency)
        }
    }
}

// MARK: - Previews

#Preview("Insights — Loading") {
    let coordinator = AppCoordinator()
    return NavigationStack {
        InsightsView(insightsViewModel: coordinator.insightsViewModel)
            .navigationTitle(String(localized: "insights.title"))
            .navigationBarTitleDisplayMode(.large)
    }
}

#Preview("Insights — Empty State") {
    // Empty InsightsViewModel with no data — shows empty state illustration
    let coordinator = AppCoordinator()
    let vm = coordinator.insightsViewModel
    return NavigationStack {
        InsightsView(insightsViewModel: vm)
            .navigationTitle(String(localized: "insights.title"))
            .navigationBarTitleDisplayMode(.large)
    }
}
