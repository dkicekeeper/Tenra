//
//  MiniSparkline.swift
//  Tenra
//
//  Lightweight Canvas-based sparkline for `.periodTrend` mini-chart overlays
//  in the Insights feed. Replaces `LineChart(mode: .compact)` to avoid
//  spinning up an Apple Charts render-tree per insight card.
//
//  Visual contract matches the compact `LineChart`:
//  - Solid line stroke (no per-point dynamic gradient — at 60pt height the
//    multi-stop gradient is perceptually a solid colour anyway)
//  - Tinted area fill below the line, fading toward the bottom
//  - Linear interpolation between points (smooth enough at sparkline scale;
//    upgrade to Catmull-Rom only if needed)
//  - For `.cashFlow` series, the entire sparkline tints by the sign of the
//    series' summary (last point's net flow): green if non-negative, red otherwise
//  - "You are here" dot on the LAST point — visually ties the sparkline to the
//    card's current-period metric + trend badge. The plot rect is inset by the
//    dot radius so the dot never clips at the canvas edges.
//  - For `.cashFlow` with negative values in range, a dashed zero baseline shows
//    where surplus flips to deficit (color alone doesn't place the crossing).
//

import SwiftUI

struct MiniSparkline: View {
    let dataPoints: [PeriodDataPoint]
    let series: PeriodChartSeries
    var lineWidth: CGFloat = 1.5
    var height: CGFloat = 60
    /// Radius of the last-point marker; doubles as the plot-rect inset.
    var endDotRadius: CGFloat = 3

    private var values: [Double] {
        dataPoints.map { series.value(for: $0) }
    }

    /// Solid colour used for line + area tint (mini-mode simplification of
    /// `PeriodChartSeries.lineStyle/areaStyle`). For `.cashFlow` we sample
    /// the last value's sign so the user can read "currently in surplus / deficit"
    /// at a glance.
    private var tintColor: Color {
        switch series {
        case .spending, .avgDailyExpenses:
            return AppColors.destructive
        case .income:
            return AppColors.success
        case .wealth:
            return AppColors.accent
        case .cashFlow:
            let last = values.last ?? 0
            return last >= 0 ? AppColors.success : AppColors.destructive
        }
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard dataPoints.count >= 2 else { return }
                let vals = values
                let domain = series.yDomain(values: vals)
                let span = max(domain.upperBound - domain.lowerBound, .leastNonzeroMagnitude)

                // Plot rect inset by the dot radius so the end dot (and the line
                // at the domain extremes) renders fully inside the canvas.
                let inset = endDotRadius
                let plotWidth = max(size.width - inset * 2, 1)
                let plotHeight = max(size.height - inset * 2, 1)
                let stepX = plotWidth / CGFloat(max(dataPoints.count - 1, 1))

                // Y axis is inverted in screen coords. Higher value → smaller y.
                func plotPoint(index: Int, value: Double) -> CGPoint {
                    let yNorm = CGFloat((value - domain.lowerBound) / span)
                    return CGPoint(
                        x: inset + CGFloat(index) * stepX,
                        y: inset + (1 - yNorm) * plotHeight
                    )
                }

                // Build the line path once.
                var linePath = Path()
                for (idx, v) in vals.enumerated() {
                    let p = plotPoint(index: idx, value: v)
                    if idx == 0 {
                        linePath.move(to: p)
                    } else {
                        linePath.addLine(to: p)
                    }
                }

                // Build the area path by closing the line down to the bottom.
                var areaPath = linePath
                areaPath.addLine(to: CGPoint(x: inset + plotWidth, y: size.height))
                areaPath.addLine(to: CGPoint(x: inset, y: size.height))
                areaPath.closeSubpath()

                let tint = tintColor
                let gradient = Gradient(colors: [
                    tint.opacity(0.30),
                    tint.opacity(0.05)
                ])
                context.fill(
                    areaPath,
                    with: .linearGradient(
                        gradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                // Dashed zero baseline — only for cashFlow AND only when the
                // domain actually dips below zero (otherwise it hugs the bottom
                // edge and reads as chart chrome).
                if series == .cashFlow, domain.lowerBound < 0 {
                    let zeroY = plotPoint(index: 0, value: 0).y
                    var zeroPath = Path()
                    zeroPath.move(to: CGPoint(x: inset, y: zeroY))
                    zeroPath.addLine(to: CGPoint(x: inset + plotWidth, y: zeroY))
                    context.stroke(
                        zeroPath,
                        with: .color(AppColors.textSecondary.opacity(0.35)),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                    )
                }

                context.stroke(
                    linePath,
                    with: .color(tint),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

                // "You are here" dot on the last point — anchors the eye to the
                // current period the card's metric and trend badge describe.
                if let lastValue = vals.last {
                    let center = plotPoint(index: vals.count - 1, value: lastValue)
                    let dotRect = CGRect(
                        x: center.x - endDotRadius,
                        y: center.y - endDotRadius,
                        width: endDotRadius * 2,
                        height: endDotRadius * 2
                    )
                    context.fill(Path(ellipseIn: dotRect), with: .color(tint))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: height)
    }
}

// MARK: - Previews

#Preview("Sparkline — cashFlow positive") {
    MiniSparkline(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .cashFlow
    )
    .frame(width: 120, height: 60)
    .padding()
}

#Preview("Sparkline — spending") {
    MiniSparkline(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .spending
    )
    .frame(width: 120, height: 60)
    .padding()
}

#Preview("Sparkline — wealth") {
    MiniSparkline(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .wealth
    )
    .frame(width: 120, height: 60)
    .padding()
}

#Preview("Sparkline — too few points") {
    MiniSparkline(
        dataPoints: [],
        series: .cashFlow
    )
    .frame(width: 120, height: 60)
    .padding()
}
