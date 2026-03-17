//
//  TransactionsSummaryCard.swift
//  AIFinanceManager
//
//  Unified transactions summary card with empty state handling.
//  The loaded state renders an Apple Card-style gradient background:
//  blurred colour orbs derived from the user's top expense categories,
//  visible through the iOS 26 Liquid Glass layer on top.
//

import SwiftUI

/// Displays transactions summary analytics card or empty state.
/// Handles three states: empty, loaded, loading.
struct TransactionsSummaryCard: View {

    // MARK: - Properties

    let summary: Summary?
    let currency: String
    let isEmpty: Bool
    /// Top expense categories with normalised weights — drives the gradient background.
    /// Empty array → plain glass card (no gradient), e.g. during loading or when there
    /// are no expense transactions in the selected period.
    let categoryWeights: [CategoryColorWeight]
    /// Custom categories needed to resolve non-palette colours for `categoryWeights`.
    let customCategories: [CustomCategory]

    // MARK: - Body

    var body: some View {
        // Fix #14: ZStack + .transition(.opacity) + .animation gives a smooth fade
        // between loading → loaded → empty states instead of abrupt view replacement.
        // minHeight = analyticsCardHeight: фиксирует высоту контейнера во время
        // перехода loadingState (fixed height) → emptyState/loadedState (variable height),
        // предотвращая layout shift ("прыжок" контента вверх/вниз).
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
        ZStack {
            // Layer 1 – colour orbs (behind glass).
            // Clipped to the same corner radius as cardStyle() so orbs never bleed
            // outside the card boundary.  On iOS 26 the glass layer on top picks up
            // these colours, giving the Apple Card tinted-glass appearance.
            if !categoryWeights.isEmpty {
                CategoryGradientBackground(
                    weights: categoryWeights,
                    customCategories: customCategories
                )
                .clipShape(.rect(cornerRadius: AppRadius.xl))
                .animation(AppAnimation.gentleSpring, value: categoryWeights)
            }

            // Layer 2 – content with glass on top.
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack {
                    Text(String(localized: "analytics.history", defaultValue: "History"))
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }

                ExpenseIncomeProgressBar(
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
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Loaded State — with gradient") {
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
        isEmpty: false,
        categoryWeights: [
            CategoryColorWeight(category: "Food", weight: 1.0),
            CategoryColorWeight(category: "Transport", weight: 0.55),
            CategoryColorWeight(category: "Entertainment", weight: 0.35),
            CategoryColorWeight(category: "Health", weight: 0.20),
            CategoryColorWeight(category: "Shopping", weight: 0.12),
        ],
        customCategories: []
    )
    .screenPadding()
}

#Preview("Loaded State — no gradient") {
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
        isEmpty: false,
        categoryWeights: [],
        customCategories: []
    )
    .screenPadding()
}

#Preview("Empty State") {
    TransactionsSummaryCard(
        summary: nil,
        currency: "KZT",
        isEmpty: true,
        categoryWeights: [],
        customCategories: []
    )
    .screenPadding()
}

#Preview("Loading State") {
    TransactionsSummaryCard(
        summary: nil,
        currency: "KZT",
        isEmpty: false,
        categoryWeights: [],
        customCategories: []
    )
    .screenPadding()
}
