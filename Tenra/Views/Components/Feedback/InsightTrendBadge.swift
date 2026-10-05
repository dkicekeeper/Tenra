//
//  InsightTrendBadge.swift
//  Tenra
//
//  Trend indicator for Insights cards and detail headers. The badge itself is
//  DesignKit's TrendBadge (0.4.0); this adapter maps InsightTrend onto it.
//

import SwiftUI

/// `InsightTrend` → DesignKit `TrendBadge` (direction icon + percentage change).
///
/// Styles: `.pill` (InsightsCardView), `.inline` (InsightDetailView header),
/// `.changeIndicator` (PeriodComparisonCard).
struct InsightTrendBadge: View {
    let trend: InsightTrend

    typealias Style = TrendBadge.Style

    var style: Style = .pill

    /// Optional color override — use when context-aware coloring differs from trend direction
    /// (e.g., expense context where up = bad). Falls back to `trend.trendColor` when `nil`.
    var colorOverride: Color? = nil

    var body: some View {
        TrendBadge(
            direction: trend.direction.badgeDirection,
            changePercent: trend.changePercent,
            style: style,
            color: colorOverride ?? trend.trendColor
        )
    }
}

extension TrendDirection {
    /// The matching DesignKit `TrendBadge` direction.
    var badgeDirection: TrendBadge.Direction {
        switch self {
        case .up: return .up
        case .down: return .down
        case .flat: return .flat
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
