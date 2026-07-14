//
//  MiniBarPair.swift
//  Tenra
//
//  Canvas-based two-bar "was / now" comparison for insight feed cards
//  (2026-07 visual refresh). Pairwise metrics (MoM change, year-over-year,
//  subscription price increase, subscription growth, 30-day forecast) read as
//  A-vs-B, not as a trend — a sparkline hides exactly the comparison the
//  card's trend badge describes.
//
//  Visual grammar (docs/domains/charts.md §Insight mini-visuals):
//  - muted gray bar = the comparison base ("was")
//  - solid tinted bar = the current fact
//  - isProjection: current bar turns translucent with a dashed outline (forecast)
//  - 1pt hairline baseline under both bars
//
//  No text inside (values live in the card's metric row + trend badge) —
//  keeps the component localization-free and decorative for VoiceOver.
//

import SwiftUI

struct MiniBarPair: View {
    /// The comparison base ("was"): previous period, old price, last year.
    let previous: Double
    /// The current fact (or projection when `isProjection`).
    let current: Double
    /// Semantic tint of the current bar (severity/direction — the generator knows).
    let color: Color
    /// Renders the current bar as a forecast: translucent fill + dashed outline.
    var isProjection: Bool = false

    var barWidth: CGFloat = 26
    var barGap: CGFloat = 10
    var height: CGFloat = 60

    /// Bars shorter than this read as "missing" — a zero value stays visible.
    private static let minBarHeight: CGFloat = 6
    private static let cornerRadius: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let maxValue = max(previous, current, .leastNonzeroMagnitude)
            let baselineY = size.height - 1
            let plotHeight = baselineY - 2

            // Right-align the pair inside the slot (trailing overlay in the card).
            let currentX = size.width - barWidth
            let previousX = currentX - barGap - barWidth

            func barPath(x: CGFloat, value: Double) -> Path {
                let h = max(Self.minBarHeight, plotHeight * CGFloat(value / maxValue))
                // Rounded top corners only — bars sit flush on the baseline.
                return Path(
                    roundedRect: CGRect(x: x, y: baselineY - h, width: barWidth, height: h),
                    cornerRadii: RectangleCornerRadii(
                        topLeading: Self.cornerRadius, bottomLeading: 0,
                        bottomTrailing: 0, topTrailing: Self.cornerRadius
                    )
                )
            }

            // Baseline hairline under both bars.
            var baseline = Path()
            baseline.move(to: CGPoint(x: previousX - 6, y: baselineY))
            baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
            context.stroke(
                baseline,
                with: .color(AppColors.textSecondary.opacity(0.2)),
                style: StrokeStyle(lineWidth: 1)
            )

            // "Was" — muted gray, never tinted (the past is context, not signal).
            context.fill(
                barPath(x: previousX, value: previous),
                with: .color(AppColors.textSecondary.opacity(0.35))
            )

            // "Now" — solid fact, or translucent + dashed outline when projected.
            let currentPath = barPath(x: currentX, value: current)
            if isProjection {
                context.fill(currentPath, with: .color(color.opacity(0.28)))
                context.stroke(
                    currentPath,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
            } else {
                context.fill(currentPath, with: .color(color))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Previews

#Preview("Bar pair — spending grew") {
    MiniBarPair(previous: 120_000, current: 168_000, color: AppColors.destructive)
        .frame(width: 120, height: 60)
        .padding()
}

#Preview("Bar pair — income grew") {
    MiniBarPair(previous: 300_000, current: 360_000, color: AppColors.success)
        .frame(width: 120, height: 60)
        .padding()
}

#Preview("Bar pair — forecast (projection)") {
    MiniBarPair(previous: 140_000, current: 185_000, color: AppColors.destructive, isProjection: true)
        .frame(width: 120, height: 60)
        .padding()
}

#Preview("Bar pair — previous is zero") {
    MiniBarPair(previous: 0, current: 9_588, color: AppColors.warning)
        .frame(width: 120, height: 60)
        .padding()
}
