//
//  PeriodLineChart.swift
//  AIFinanceManager
//
//  Phase 43 (chart merge): Unified granularity-aware area/line chart.
//  Replaces three structurally identical components:
//  - PeriodSpendingTrendChart (expenses, 0-based Y, destructive color)
//  - PeriodCashFlowChart     (netFlow, ±Y, dynamic green/red, zero ruler)
//  - WealthChart             (cumulativeBalance, ±Y, accent color)
//
//  Behavioral differences are captured in PeriodLineChartSeries enum.
//  Layout, scrolling, Y-axis overlay, and animation are shared.
//

import SwiftUI
import Charts

// MARK: - PeriodLineChartSeries

/// Defines which data field and visual style a `PeriodLineChart` uses.
enum PeriodLineChartSeries {
    /// Spending trend: `expenses` field, Y starts at 0, destructive color.
    case spending
    /// Cash flow: `netFlow` field, ± Y, color tracks direction, zero reference line.
    case cashFlow
    /// Wealth: `cumulativeBalance` field (falls back to `netFlow`), ± Y, accent color.
    case wealth

    // MARK: - Data extraction

    func value(for point: PeriodDataPoint) -> Double {
        switch self {
        case .spending: return point.expenses
        case .cashFlow: return point.netFlow
        case .wealth:   return point.cumulativeBalance ?? point.netFlow
        }
    }

    // MARK: - Y-domain

    func yDomain(values: [Double]) -> ClosedRange<Double> {
        switch self {
        case .spending:
            return 0...Swift.max(values.max() ?? 0, 1)
        case .cashFlow, .wealth:
            let min = Swift.min(values.min() ?? 0, 0)
            let max = Swift.max(values.max() ?? 0, 1)
            return min...max
        }
    }

    // MARK: - Colors

    /// Line and gradient color (computed from last data point for cashFlow).
    func lineColor(lastValue: Double) -> Color {
        switch self {
        case .spending: return AppColors.destructive
        case .cashFlow: return lastValue >= 0 ? AppColors.success : AppColors.destructive
        case .wealth:   return AppColors.accent
        }
    }

    /// Per-point color used for PointMark (cashFlow colors each point individually).
    func pointColor(for value: Double) -> Color {
        switch self {
        case .spending: return AppColors.destructive
        case .cashFlow: return value >= 0 ? AppColors.success : AppColors.destructive
        case .wealth:   return AppColors.accent
        }
    }

    // MARK: - Visual flags

    /// Whether to render a dashed zero reference line (RuleMark at y=0).
    var showZeroRuler: Bool {
        switch self {
        case .spending, .wealth: return false
        case .cashFlow:          return true
        }
    }

    /// Line width in full (non-compact) mode.
    var fullLineWidth: CGFloat {
        switch self {
        case .spending, .cashFlow: return 2
        case .wealth:              return 2.5
        }
    }
}

// MARK: - PeriodLineChart

/// Granularity-aware area/line chart for any `PeriodDataPoint` series.
///
/// Y-axis is pinned to the left (always visible) while content scrolls right.
/// Default scroll position: trailing (most recent data visible on load).
///
/// Usage:
/// ```swift
/// PeriodLineChart(dataPoints: points, series: .cashFlow, granularity: .month)
/// PeriodLineChart(dataPoints: points, series: .wealth,   granularity: .month, mode: .compact)
/// ```
struct PeriodLineChart: View {
    let dataPoints: [PeriodDataPoint]
    let series: PeriodLineChartSeries
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }

    private var pointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }
    private var lineWidth: CGFloat { isCompact ? 1.5 : series.fullLineWidth }

    private var values: [Double] { dataPoints.map { series.value(for: $0) } }
    private var yDomain: ClosedRange<Double> { series.yDomain(values: values) }
    private var lineColor: Color { series.lineColor(lastValue: values.last ?? 0) }

    // MARK: Body

    var body: some View {
        Group {
            if isCompact {
                // Compact: no GeometryReader needed — chart fills proposed width from parent.
                // GeometryReader in compact mode adds an extra two-pass layout per sparkline;
                // removing it reduces per-chart layout cost during initial InsightsView render.
                mainChart
                    .frame(maxWidth: .infinity)
            } else {
                GeometryReader { proxy in
                    let container = proxy.size.width
                    let yAxisWidth: CGFloat = 50
                    let scrollWidth = max(
                        container,
                        CGFloat(dataPoints.count) * pointWidth
                    )
                    ZStack(alignment: .topLeading) {
                        // Scrollable chart content
                        ScrollView(.horizontal, showsIndicators: false) {
                            mainChart
                                .frame(width: scrollWidth, height: chartHeight)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .defaultScrollAnchor(.trailing)

                        // Y-axis overlay — always visible, doesn't scroll with chart
                        yAxisReferenceChart
                            .frame(width: yAxisWidth, height: chartHeight)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: chartHeight)
        .padding(.top, isCompact ? 0 : AppSpacing.sm)
        .chartAppear()
    }

    // MARK: - Y-axis reference chart

    private var yAxisReferenceChart: some View {
        Chart(dataPoints) { point in
            LineMark(
                x: .value("p", point.label),
                y: .value("v", series.value(for: point))
            )
            .opacity(0)
        }
        .chartYScale(domain: yDomain)
        .chartXAxis { AxisMarks { _ in } }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(ChartAxisHelpers.formatCompact(amount))
                            .font(AppTypography.caption2)
                    }
                }
            }
        }
    }

    // MARK: - Main chart

    private var mainChart: some View {
        let labelMap = ChartAxisHelpers.axisLabelMap(for: dataPoints)
        return Chart {
            ForEach(dataPoints) { point in
                let value = series.value(for: point)

                AreaMark(
                    x: .value("Period", point.label),
                    y: .value("Value", value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [lineColor.opacity(0.3), lineColor.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Period", point.label),
                    y: .value("Value", value)
                )
                .foregroundStyle(lineColor)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: lineWidth))

                if !isCompact {
                    PointMark(
                        x: .value("Period", point.label),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(series.pointColor(for: value))
                    .symbolSize(isCompact ? 20 : 30)
                }
            }

            // Zero reference line — rendered once, outside per-point ForEach
            if series.showZeroRuler && !isCompact {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            if isCompact {
                AxisMarks { _ in }
            } else {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(labelMap[label] ?? label)
                                .font(AppTypography.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            // Grid lines only — labels handled by yAxisReferenceChart
            if isCompact {
                AxisMarks { _ in }
            } else {
                AxisMarks { _ in
                    AxisGridLine()
                }
            }
        }
        .chartLegend(.hidden)
        .animation(AppAnimation.chartUpdateAnimation, value: dataPoints.count)
    }
}

// MARK: - Previews

#Preview("Spending — Monthly") {
    PeriodLineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .spending,
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Cash Flow — Monthly") {
    PeriodLineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .cashFlow,
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Wealth — Monthly") {
    PeriodLineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .wealth,
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Compact — all series") {
    VStack(spacing: AppSpacing.md) {
        PeriodLineChart(dataPoints: PeriodDataPoint.mockMonthly(), series: .spending, granularity: .month, mode: .compact)
        PeriodLineChart(dataPoints: PeriodDataPoint.mockMonthly(), series: .cashFlow, granularity: .month, mode: .compact)
        PeriodLineChart(dataPoints: PeriodDataPoint.mockMonthly(), series: .wealth, granularity: .month, mode: .compact)
    }
    .screenPadding()
    .frame(height: 280)
}
