//
//  SubscriptionsCardView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsCardView: View {
    // ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    // Fix #7: Double instead of Decimal — avoids NSDecimalNumber round-trip at the use site.
    @State private var totalAmount: Double = 0
    @State private var isLoadingTotal: Bool = false

    private var subscriptions: [RecurringSeries] {
        transactionStore.activeSubscriptions
    }

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    /// Combined key driving .task(id:) — restarts automatically when count or currency changes.
    private var refreshID: String {
        "\(subscriptions.count)-\(baseCurrency)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(String(localized: "subscriptions.title"))
                    .font(AppTypography.h3)
                    .foregroundStyle(.primary)

                if subscriptions.isEmpty {
                    EmptyStateView(title: String(localized: "emptyState.noActiveSubscriptions"), style: .compact)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        if isLoadingTotal {
                            // Fix #13: skeleton instead of ProgressView — seamless visual
                            // continuity with the outer skeleton; no spinner flash after it lifts.
                            SkeletonView(width: 120, height: 20)
                        } else {
                            FormattedAmountText(
                                amount: totalAmount,
                                currency: baseCurrency,
                                fontSize: AppTypography.h2,
                                fontWeight: .bold,
                                color: AppColors.textPrimary
                            )
                        }

                        Text(String(format: String(localized: "subscriptions.activeCount"), subscriptions.count))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !subscriptions.isEmpty {
                StaticSubscriptionIconsView(subscriptions: subscriptions)
                    .frame(width: AppSize.subscriptionCardWidth, alignment: .top)
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        // Fix #3: replaced two separate `onChange + unstructured Task {}` blocks with a single
        // `.task(id: refreshID)`. SwiftUI automatically cancels and restarts this task whenever
        // `refreshID` changes (subscriptions count or base currency), and cancels it on view
        // removal — no task leaks on sheet dismiss.
        .task {
            await refreshTotal()
        }
        .task(id: refreshID) {
            await refreshTotal()
        }
    }

    /// Calculate total subscription amount in base currency.
    private func refreshTotal() async {
        isLoadingTotal = true
        let result = await transactionStore.calculateSubscriptionsTotalInCurrency(baseCurrency)
        // (result.total as NSDecimalNumber) is a free bridge cast — Decimal IS NSDecimalNumber.
        totalAmount = (result.total as NSDecimalNumber).doubleValue
        isLoadingTotal = false
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionsCardView(
        transactionStore: coordinator.transactionStore,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .screenPadding()
}
