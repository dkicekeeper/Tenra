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
    /// Forecast value: the fact line compresses to ~72% of the width and a
    /// dashed tail runs to this value at the right edge (hollow endpoint —
    /// forecast grammar: dashed/hollow = not yet real).
    var projectedValue: Double? = nil
    /// Marks the series extremes: max → success dot, min → destructive dot
    /// (period-records card — the extremes ARE the message).
    var markExtremes: Bool = false

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
                // The projection endpoint must fit inside the y-domain.
                var domainValues = vals
                if let projectedValue { domainValues.append(projectedValue) }
                let domain = series.yDomain(values: domainValues)
                let span = max(domain.upperBound - domain.lowerBound, .leastNonzeroMagnitude)

                // Plot rect inset by the dot radius so the end dot (and the line
                // at the domain extremes) renders fully inside the canvas.
                let inset = endDotRadius
                let plotWidth = max(size.width - inset * 2, 1)
                let plotHeight = max(size.height - inset * 2, 1)
                // The fact line yields the right ~28% to the projection tail.
                let factWidth = projectedValue != nil ? plotWidth * 0.72 : plotWidth
                let stepX = factWidth / CGFloat(max(dataPoints.count - 1, 1))

                // Y axis is inverted in screen coords. Higher value → smaller y.
                func yFor(_ value: Double) -> CGFloat {
                    let yNorm = CGFloat((value - domain.lowerBound) / span)
                    return inset + (1 - yNorm) * plotHeight
                }
                func plotPoint(index: Int, value: Double) -> CGPoint {
                    CGPoint(x: inset + CGFloat(index) * stepX, y: yFor(value))
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

                // Build the area path by closing the line down to the bottom
                // (fact only — no fill under the projection tail).
                var areaPath = linePath
                areaPath.addLine(to: CGPoint(x: inset + factWidth, y: size.height))
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

                // Dashed projection tail: last fact point → forecast value at the
                // right edge, ending in a hollow dot (not yet real).
                if let projectedValue, let lastValue = vals.last {
                    let from = plotPoint(index: vals.count - 1, value: lastValue)
                    let to = CGPoint(x: inset + plotWidth, y: yFor(projectedValue))
                    var dash = Path()
                    dash.move(to: from)
                    dash.addLine(to: to)
                    context.stroke(
                        dash,
                        with: .color(tint),
                        style: StrokeStyle(lineWidth: lineWidth, dash: [3, 4])
                    )
                    let r = endDotRadius
                    context.stroke(
                        Path(ellipseIn: CGRect(x: to.x - r, y: to.y - r, width: r * 2, height: r * 2)),
                        with: .color(tint),
                        lineWidth: 1.5
                    )
                }

                // Extreme markers — best (max) and worst (min) of the series.
                if markExtremes,
                   let maxIdx = vals.indices.max(by: { vals[$0] < vals[$1] }),
                   let minIdx = vals.indices.min(by: { vals[$0] < vals[$1] }),
                   maxIdx != minIdx {
                    for (idx, color) in [(maxIdx, AppColors.success), (minIdx, AppColors.destructive)] {
                        let c = plotPoint(index: idx, value: vals[idx])
                        let dotRect = CGRect(
                            x: c.x - endDotRadius, y: c.y - endDotRadius,
                            width: endDotRadius * 2, height: endDotRadius * 2
                        )
                        context.fill(Path(ellipseIn: dotRect), with: .color(color))
                    }
                }

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
