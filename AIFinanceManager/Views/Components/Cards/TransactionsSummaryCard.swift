//
//  TransactionsSummaryCard.swift
//  AIFinanceManager
//
//  Unified transactions summary card with empty state handling
//

import SwiftUI

/// Displays transactions summary analytics card or empty state
/// Handles three states: empty, loaded, loading
struct TransactionsSummaryCard: View {
    // MARK: - Properties
    let summary: Summary?
    let currency: String
    let isEmpty: Bool

    // MARK: - Body
    var body: some View {
        // Fix #14: ZStack + .transition(.opacity) + .animation gives a smooth fade
        // between loading → loaded → empty states instead of abrupt view replacement.
        // minHeight = analyticsCardHeight: фиксирует высоту контейнера во время
        // перехода loadingState (fixed height) → emptyState/loadedState (variable height),
        // предотвращая layout shift ("прыжок" контента вверх/вниз).
        ZStack {
            if isEmpty {
                emptyState
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
        .frame(minHeight: AppSize.analyticsCardHeight)
        .animation(AppAnimation.gentleSpring, value: isEmpty)
        .animation(AppAnimation.gentleSpring, value: summary != nil)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                Text(String(localized: "analytics.history"))
                    .font(AppTypography.h3)
                    .foregroundStyle(.primary)
            }

            EmptyStateView(
                title: String(localized: "emptyState.noTransactions"),
                style: .compact
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: AppRadius.xl)
    }

    // MARK: - Loaded State
    private func loadedState(summary: Summary) -> some View {
        AnalyticsCard(
            summary: summary,
            currency: currency
        )
    }

    // MARK: - Loading State
    private var loadingState: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .accessibilityLabel(String(localized: "progress.loadingTransactions"))
            Text(String(localized: "progress.loadingData"))
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppSize.analyticsCardHeight)
        .cardStyle(radius: AppRadius.xl)
        .accessibilityElement(children: .combine)
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
