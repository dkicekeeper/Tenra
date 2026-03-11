//
//  InsightsSectionView.swift
//  AIFinanceManager
//
//  Universal parameterised section view for Insights.
//  Replaces: IncomeInsightsSection, BudgetInsightsSection, RecurringInsightsSection,
//            SpendingInsightsSection, CashFlowInsightsSection, WealthInsightsSection.
//
//  Usage — simple section (Income, Budget, Recurring):
//      InsightsSectionView(category: .income, insights: insights, currency: currency, namespace: ns)
//
//  Usage — section with drill-down (Spending):
//      InsightsSectionView(category: .spending, insights: insights, currency: currency, namespace: ns)
//      onCategoryTap is handled centrally via navigationDestination in InsightsView.
//
//  Phase 29 (revised): Full chart removed from section view.
//  All sections show compact mini-chart cards on the main Insights screen.
//  Full charts appear in InsightDetailView when tapping individual insight cards.
//
//  Task 2: value-based NavigationLink + zoom transition via matchedTransitionSource.
//

import SwiftUI

struct InsightsSectionView: View {

    // MARK: - Properties

    let category: InsightCategory
    let insights: [Insight]
    let currency: String
    var namespace: Namespace.ID
    var granularity: InsightGranularity? = nil

    // MARK: - Body

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeaderView(category.displayName, style: .insights)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .screenPadding()

                // ALL cards use compact mini-charts
                ForEach(insights) { insight in
                    NavigationLink(value: insight) {
                        InsightsCardView(insight: insight)
                            .matchedTransitionSource(id: insight.id, in: namespace)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Simple — Income") {
    @Previewable @Namespace var ns
    return NavigationStack {
        ScrollView {
            InsightsSectionView(
                category: .income,
                insights: [.mockIncomeGrowth()],
                currency: "KZT",
                namespace: ns
            )
            .padding(.vertical, AppSpacing.md)
        }
    }
}

#Preview("Spending — with drill-down") {
    @Previewable @Namespace var ns
    return NavigationStack {
        ScrollView {
            InsightsSectionView(
                category: .spending,
                insights: [.mockTopSpending(), .mockMoM(), .mockAvgDaily()],
                currency: "KZT",
                namespace: ns
            )
            .padding(.vertical, AppSpacing.md)
        }
    }
}

#Preview("Cash Flow — compact cards only") {
    @Previewable @Namespace var ns
    return NavigationStack {
        ScrollView {
            InsightsSectionView(
                category: .cashFlow,
                insights: [.mockCashFlow(), .mockProjectedBalance()],
                currency: "KZT",
                namespace: ns
            )
            .padding(.vertical, AppSpacing.md)
        }
    }
}

#Preview("Wealth — compact cards only") {
    @Previewable @Namespace var ns
    return NavigationStack {
        ScrollView {
            InsightsSectionView(
                category: .wealth,
                insights: [.mockWealthBreakdown()],
                currency: "KZT",
                namespace: ns
            )
            .padding(.vertical, AppSpacing.md)
        }
    }
}
