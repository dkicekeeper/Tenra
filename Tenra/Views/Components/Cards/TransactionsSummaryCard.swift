//
//  TransactionsSummaryCard.swift
//  Tenra
//
//  Unified transactions summary card with empty state handling. Adapter over DesignKit's
//  `CashFlowCard`: maps the summary model and the home-screen copy.
//  Gradient background is rendered at ContentView level (homeBackground).
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
        CashFlowCard(
            title: String(localized: "analytics.history", defaultValue: "History"),
            totals: summary.map { summary in
                CashFlowCard.Totals(
                    income: summary.totalIncome,
                    expenses: summary.totalExpenses,
                    extra: summary.plannedAmount > 0
                        ? .init(label: String(localized: "analytics.planned", defaultValue: "Planned"),
                                amount: summary.plannedAmount)
                        : nil
                )
            },
            currency: currency,
            isEmpty: isEmpty,
            emptyMessage: String(localized: "emptyState.noTransactions"),
            loadingLabel: String(localized: "progress.loadingTransactions")
        )
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
