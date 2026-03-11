//
//  HealthScoreBadge.swift
//  AIFinanceManager
//
//  Financial health score row: heart icon + score + grade capsule.
//  Extracted from InsightsSummaryHeader — Phase 26.
//

import SwiftUI

/// Compact row displaying the composite financial health score with grade badge.
/// Intended for use inside glass cards in Insights and Settings.
struct HealthScoreBadge: View {
    let score: FinancialHealthScore

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "heart.text.square.fill")
                .foregroundStyle(score.gradeColor)
                .font(AppTypography.bodyEmphasis)

            Text(String(localized: "insights.healthScore"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text("\(score.score)")
                .font(AppTypography.body.bold())
                .foregroundStyle(score.gradeColor)

            Text(score.grade)
                .font(AppTypography.body)
                .foregroundStyle(score.gradeColor)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(score.gradeColor.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Previews

#Preview("Good / Needs Attention") {
    VStack(spacing: AppSpacing.md) {
        HealthScoreBadge(score: .mockGood())
        HealthScoreBadge(score: .mockNeedsAttention())
    }
    .cardStyle(radius: AppRadius.xl)
    .screenPadding()
    .padding(.vertical)
}
