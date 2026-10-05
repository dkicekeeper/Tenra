//
//  HealthScoreCardView.swift
//  Tenra
//
//  Financial health score as an insight-feed-style card (2026-07 UX pass):
//  same geometry as InsightsCardView — title / grade / big metric on the left,
//  a 120pt mini half-gauge (absolute 0–100 mode, the mini sibling of the
//  detail's HeroHalfGauge) bleeding to the trailing edge. Replaces the old
//  compact HealthScoreBadge row; lives in the "Важное сейчас" section.
//  Adapter over DesignKit's `ScoreCard`.
//

import SwiftUI

struct HealthScoreCardView: View {
    let score: FinancialHealthScore

    var body: some View {
        ScoreCard(
            title: String(localized: "insights.healthScore"),
            grade: score.grade,
            score: score.score,
            maxScore: 100,
            color: score.gradeColor
        )
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
