//
//  BudgetProgressBar.swift
//  AIFinanceManager
//
//  Reusable horizontal budget progress bar with over-budget state.
//  Extracted from InsightsCardView and InsightDetailView (Phase 26).
//

import SwiftUI

/// Horizontal progress bar for budget utilisation.
/// - Parameter percentage: 0–100+ (clamped at 100 for bar width)
/// - Parameter isOverBudget: true → bar fills with AppColors.destructive
/// - Parameter color: brand color for the category (used when not over budget)
/// - Parameter height: bar height in points (default 8; InsightsCardView uses 6)
struct BudgetProgressBar: View {
    let percentage: Double
    let isOverBudget: Bool
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppRadius.xs)
                .fill(AppColors.secondaryBackground)
                .frame(maxWidth: .infinity)
                .frame(height: height)

            RoundedRectangle(cornerRadius: AppRadius.xs)
                .fill(isOverBudget ? AppColors.destructive : color)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .scaleEffect(x: min(percentage, 100) / 100, anchor: .leading)
        }
    }
}

// MARK: - Previews

#Preview("Normal") {
    VStack(spacing: AppSpacing.md) {
        BudgetProgressBar(percentage: 65, isOverBudget: false, color: .blue)
        BudgetProgressBar(percentage: 95, isOverBudget: false, color: .green)
        BudgetProgressBar(percentage: 120, isOverBudget: true, color: .orange)
    }
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Compact (height 6)") {
    BudgetProgressBar(percentage: 72, isOverBudget: false, color: .purple, height: 6)
        .screenPadding()
}
