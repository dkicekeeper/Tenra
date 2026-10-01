//
//  TransactionsSummaryCard.swift
//  Tenra
//
//  Unified transactions summary card with empty state handling.
//  Gradient background is now rendered at ContentView level (homeBackground),
//  so this card stays a pure glass card without per-card colour logic.
//

import SwiftUI

/// Displays transactions summary analytics card or empty state.
/// Handles three states: empty, loaded, loading.
struct TransactionsSummaryCard: View {

    // MARK: - Properties

    let summary: Summary?
    let currency: String
    let isEmpty: Bool

    // MARK: - Body

    var body: some View {
        // Fix #14: ZStack + .transition(.opacity) + .animation gives a smooth fade
        // between loading → loaded → empty states instead of abrupt view replacement.
        ZStack {
            if isEmpty {
                EmptyCardView(
                    sectionTitle: String(localized: "analytics.history"),
                    emptyTitle: String(localized: "emptyState.noTransactions")
                )
                .transition(.opacity)
            } else if let summary {
                // Fix #8: removed .id("summary-…") — it forced SwiftUI to throw away and
                // recreate AnalyticsCard on every income/expense change, preventing smooth
                // number transitions. @Observable's structural diffing handles updates correctly.
                loadedState(summary: summary)
                    .transition(.opacity)
            } else {
                loadingState
                    .transition(.opacity)
            }
        }
        .animation(AppAnimation.gentleSpring, value: isEmpty)
        .animation(AppAnimation.gentleSpring, value: summary != nil)
    }

    // MARK: - Loaded State

    private func loadedState(summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                Text(String(localized: "analytics.history", defaultValue: "History"))
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
            }

            AmountComparisonBar(
                expenseAmount: summary.totalExpenses,
                incomeAmount: summary.totalIncome,
                currency: currency
            )

            if summary.plannedAmount > 0 {
                HStack {
                    Text(String(localized: "analytics.planned", defaultValue: "Planned"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    FormattedAmountText(
                        amount: summary.plannedAmount,
                        currency: currency,
                        fontSize: AppTypography.body,
                        color: AppColors.textPrimary
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    // MARK: - Loading State

    /// Skeleton in the shape of the loaded card: the title, then the comparison bar.
    private var loadingState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            SkeletonView(height: 24, width: 120)
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                SkeletonView(height: 12, cornerRadius: 6)
                HStack {
                    SkeletonView(height: 14, width: 90)
                    Spacer()
                    SkeletonView(height: 14, width: 90)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "progress.loadingTransactions"))
    }
}

// MARK: - Preview

#Preview("Loaded State") {
    TransactionsSummaryCard(
        summary: Summary(
            totalIncome: 50000,
            totalExpenses: 35000,
            totalInternalTransfers: 10000,
            netFlow: 15000,
            currency: "KZT",
            startDate: "2026-01-01",
            endDate: "2026-01-31",
            plannedAmount: 5000
        ),
        currency: "KZT",
        isEmpty: false
    )
    .screenPadding()
}

#Preview("Empty State") {
    TransactionsSummaryCard(
        summary: nil,
        currency: "KZT",
        isEmpty: true
    )
    .screenPadding()
}

#Preview("Loading State") {
    TransactionsSummaryCard(
        summary: nil,
        currency: "KZT",
        isEmpty: false
    )
    .screenPadding()
}
