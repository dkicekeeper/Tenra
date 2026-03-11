//
//  InsightTrendBadge.swift
//  AIFinanceManager
//
//  Trend indicator badge for Insights cards and detail headers.
//  Extracted from InsightsCardView (pill) and InsightDetailView (inline) — Phase 26.
//

import SwiftUI

/// Compact trend indicator displaying direction icon + percentage change.
///
/// Three styles:
/// - `.pill` — colored semi-transparent Capsule background (InsightsCardView)
/// - `.inline` — flat, no background (InsightDetailView header)
/// - `.changeIndicator` — vertical VStack: icon above percentage (PeriodComparisonCard)
struct InsightTrendBadge: View {
    let trend: InsightTrend

    enum Style {
        /// Colored capsule background.
        case pill
        /// Flat, no background.
        case inline
        /// Vertical layout: icon on top, percentage below. No background.
        case changeIndicator
    }

    var style: Style = .pill

    /// Optional color override — use when context-aware coloring differs from trend direction
    /// (e.g., expense context where up = bad). Falls back to `trend.trendColor` when `nil`.
    var colorOverride: Color? = nil

    private var effectiveColor: Color { colorOverride ?? trend.trendColor }

    var body: some View {
        if style == .changeIndicator {
            VStack(spacing: AppSpacing.xxs) {
                Image(systemName: trend.trendIcon)
                if let percent = trend.changePercent {
                    Text(String(format: "%+.1f%%", percent))
                        .font(AppTypography.captionEmphasis)
                }
            }
            .foregroundStyle(effectiveColor)
        } else {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: trend.trendIcon)
                    .font(style == .pill
                          ? AppTypography.caption.weight(.bold)
                          : AppTypography.bodySmall)

                if let percent = trend.changePercent {
                    Text(String(format: "%+.1f%%", percent))
                        .font(style == .pill ? AppTypography.caption : AppTypography.bodySmall)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(effectiveColor)
            .modifier(PillModifier(isActive: style == .pill, color: effectiveColor))
        }
    }
}

// MARK: - Pill modifier

private struct PillModifier: ViewModifier {
    let isActive: Bool
    let color: Color

    func body(content: Content) -> some View {
        if isActive {
            content
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        } else {
            content
        }
    }
}

// MARK: - Previews

#Preview {
    let upTrend = InsightTrend(direction: .up, changePercent: 12.4, changeAbsolute: nil, comparisonPeriod: "vs prev month")
    let downTrend = InsightTrend(direction: .down, changePercent: -5.1, changeAbsolute: nil, comparisonPeriod: "vs prev month")
    let flatTrend = InsightTrend(direction: .flat, changePercent: 0.8, changeAbsolute: nil, comparisonPeriod: "vs prev month")

    return VStack(spacing: AppSpacing.lg) {
        Text("Pill style").font(AppTypography.caption).foregroundStyle(.secondary)
        HStack(spacing: AppSpacing.md) {
            InsightTrendBadge(trend: upTrend, style: .pill)
            InsightTrendBadge(trend: downTrend, style: .pill)
        }

        Text("Inline style").font(AppTypography.caption).foregroundStyle(.secondary)
        HStack(spacing: AppSpacing.md) {
            InsightTrendBadge(trend: upTrend, style: .inline)
            InsightTrendBadge(trend: downTrend, style: .inline)
        }

        Text("Change indicator style").font(AppTypography.caption).foregroundStyle(.secondary)
        HStack(spacing: AppSpacing.xl) {
            InsightTrendBadge(trend: upTrend, style: .changeIndicator)
            InsightTrendBadge(trend: downTrend, style: .changeIndicator)
            InsightTrendBadge(trend: flatTrend, style: .changeIndicator)
            // With color override (expense context: up = bad)
            InsightTrendBadge(trend: upTrend, style: .changeIndicator, colorOverride: AppColors.destructive)
        }
    }
    .screenPadding()
}
