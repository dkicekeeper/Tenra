//
//  HealthScoreHeroCard.swift
//  Tenra
//
//  Large hero card on the Financial Health detail screen:
//  half-circle score gauge (0–100, zone ticks at 40/70, colour-matched glow)
//  + score + grade capsule + grade-band subtitle. 2026-07 visual refresh:
//  the full progress ring became a HeroHalfGauge — the score has a fixed
//  0–100 scale with meaningful zone boundaries, which is gauge semantics.
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
        VStack(spacing: AppSpacing.lg) {
            ZStack(alignment: .bottom) {
                HeroHalfGauge(
                    value: isAvailable ? Double(score.score) : 0,
                    maxValue: 100,
                    zoneTicks: [40, 70],
                    color: score.gradeColor,
                    diameter: 220,
                    lineWidth: 16
                )

                // Score + grade sit inside the semicircle's interior.
                VStack(spacing: AppSpacing.xs) {
                    Text(isAvailable ? "\(score.score)" : "—")
                        .font(AppTypography.h1.bold())
                        .foregroundStyle(isAvailable ? score.gradeColor : AppColors.textTertiary)
                        .materialize(delay: 0.35)

                    Text(score.grade)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(score.gradeColor)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(score.gradeColor.opacity(0.12))
                        .clipShape(Capsule())
                        .materialize(delay: 0.45)
                }
            }

            Text(String(localized: isAvailable
                        ? String.LocalizationValue(gradeBandSubtitleKey)
                        : "insights.health.unavailable.title"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .cardStyle()
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
