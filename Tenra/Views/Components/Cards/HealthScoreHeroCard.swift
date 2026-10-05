//
//  HealthScoreHeroCard.swift
//  Tenra
//
//  Large hero card on the Financial Health detail screen:
//  half-circle score gauge (0–100, zone ticks at 40/70, colour-matched glow)
//  + score + grade capsule + grade-band subtitle. 2026-07 visual refresh:
//  the full progress ring became a HeroHalfGauge — the score has a fixed
//  0–100 scale with meaningful zone boundaries, which is gauge semantics.
//  Adapter over DesignKit's `ScoreGaugeCard`: maps the score, its grade colour
//  and the grade-band copy.
//

import SwiftUI

struct HealthScoreHeroCard: View {
    let score: FinancialHealthScore
    /// True when the score is meaningful (totalIncomeWindow > 0). When false,
    /// the ring and number are replaced with an "—" placeholder.
    let isAvailable: Bool

    private var gradeBandSubtitleKey: String {
        switch score.score {
        case 80...100: return "insights.health.subtitle.excellent"
        case 60..<80:  return "insights.health.subtitle.good"
        case 40..<60:  return "insights.health.subtitle.fair"
        default:       return "insights.health.subtitle.needsAttention"
        }
    }

    var body: some View {
        ScoreGaugeCard(
            score: isAvailable ? score.score : nil,
            maxScore: 100,
            zoneTicks: [40, 70],
            grade: score.grade,
            color: score.gradeColor,
            subtitle: String(localized: isAvailable
                             ? String.LocalizationValue(gradeBandSubtitleKey)
                             : "insights.health.unavailable.title")
        )
    }
}

// MARK: - Previews

#Preview("Good score") {
    HealthScoreHeroCard(score: FinancialHealthScore.mockGood(), isAvailable: true)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Needs attention") {
    HealthScoreHeroCard(score: FinancialHealthScore.mockNeedsAttention(), isAvailable: true)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Unavailable") {
    HealthScoreHeroCard(score: .unavailable(), isAvailable: false)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}
