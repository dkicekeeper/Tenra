//
//  HealthScoreCardView.swift
//  Tenra
//
//  Financial health score as an insight-feed-style card (2026-07 UX pass):
//  same geometry as InsightsCardView — title / grade / big metric on the left,
//  a 120pt mini half-gauge (absolute 0–100 mode, the mini sibling of the
//  detail's HeroHalfGauge) bleeding to the trailing edge. Replaces the old
//  compact HealthScoreBadge row; lives in the "Важное сейчас" section.
//

import SwiftUI

struct HealthScoreCardView: View {
    let score: FinancialHealthScore

    // Mini-chart footprint — keep in sync with InsightsCardView.
    private static var miniChartWidth: CGFloat { 120 }
    private static var miniChartHeight: CGFloat { 120 }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: "insights.healthScore"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)

            Text(score.grade)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text("\(score.score)")
                    .font(AppTypography.h2)
                    .fontWeight(.bold)
                    .foregroundStyle(score.gradeColor)

                Text(verbatim: "/ 100")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, Self.miniChartWidth + AppSpacing.sm)
        .padding(AppSpacing.lg)
        .cardStyle()
        .overlay(alignment: .trailing) {
            MiniHalfGauge(
                value: Double(score.score),
                maxValue: 100,
                color: score.gradeColor
            )
            .frame(width: Self.miniChartWidth, height: Self.miniChartHeight)
            .padding(.trailing, AppSpacing.lg)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Previews

#Preview("Good / Needs Attention") {
    VStack(spacing: AppSpacing.md) {
        HealthScoreCardView(score: .mockGood())
        HealthScoreCardView(score: .mockNeedsAttention())
    }
    .screenPadding()
    .padding(.vertical)
}
