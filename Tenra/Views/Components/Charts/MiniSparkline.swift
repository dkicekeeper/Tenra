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
//

import SwiftUI

struct MiniSparkline: View {
    let dataPoints: [PeriodDataPoint]
    let series: PeriodChartSeries
    var lineWidth: CGFloat = 1.5
    var height: CGFloat = 60

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

                let stepX = size.width / CGFloat(max(dataPoints.count - 1, 1))

                // Build the line path once.
                var linePath = Path()
                for (idx, v) in vals.enumerated() {
                    let x = CGFloat(idx) * stepX
                    // Y axis is inverted in screen coords. Higher value → smaller y.
                    let yNorm = CGFloat((v - domain.lowerBound) / span)
                    let y = size.height - yNorm * size.height
                    if idx == 0 {
                        linePath.move(to: CGPoint(x: x, y: y))
                    } else {
                        linePath.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                // Build the area path by closing the line down to the bottom.
                var areaPath = linePath
                areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
                areaPath.addLine(to: CGPoint(x: 0, y: size.height))
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

                context.stroke(
                    linePath,
                    with: .color(tint),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
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
