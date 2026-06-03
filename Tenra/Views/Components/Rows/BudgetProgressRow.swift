//
//  BudgetProgressRow.swift
//  Tenra
//
//  Full budget progress row: icon + name + BudgetProgressBar + spent/budget amounts.
//  Extracted from InsightDetailView.budgetChartSection — Phase 26.
//

import SwiftUI

/// One row in the budget breakdown list.
/// Shows category name, progress bar, spent vs budget amounts, and remaining days.
struct BudgetProgressRow: View {
    let item: BudgetInsightItem
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Icon + name + percentage
            HStack {
                IconView(
                    source: item.iconSource,
                    style: .circle(
                        size: AppIconSize.xxl,
                        tint: .monochrome(item.color),
                        backgroundColor: item.color.opacity(0.15)
                    )
                )
                Text(item.categoryName)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(String(format: "%.0f%%", item.percentage))
                    .font(AppTypography.body)
                    .foregroundStyle(item.isOverBudget ? AppColors.destructive : AppColors.textPrimary)
            }

            // Progress bar
            BudgetProgressBar(
                percentage: item.percentage,
                isOverBudget: item.isOverBudget,
                color: item.color
            )

            // Spent / Budget / Days left
            HStack {
                SpentBudgetText(
                    spent: item.spent,
                    budget: item.budgetAmount,
                    currency: currency,
                    font: AppTypography.caption,
                    separatorColor: AppColors.textTertiary
                )
                Spacer()
                if item.daysRemaining > 0 {
                    Text(String(format: String(localized: "insights.daysLeft"), item.daysRemaining))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle(radius: AppRadius.xl)
    }
}

// MARK: - Previews

#Preview {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            ForEach(BudgetInsightItem.mockItems()) { item in
                BudgetProgressRow(item: item, currency: "KZT")
            }
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}
