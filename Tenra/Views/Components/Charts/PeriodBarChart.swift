//
//  PeriodBarChart.swift
//  AIFinanceManager
//
//  Phase 43 (chart merge): Unified granularity-aware income/expense grouped bar chart.
//  Replaces PeriodIncomeExpenseChart.
//
//  Phase 43 additions:
//  - chartAppear() entrance animation (opacity + scale from bottom)
//  - chartUpdateAnimation on Chart view (bars animate when data changes)
//

import SwiftUI
import Charts

// MARK: - PeriodBarChart

/// Granularity-aware income/expense grouped bar chart.
/// X-axis shows period labels (week/month/quarter/year) instead of raw Date.
/// Y-axis is pinned to the left (always visible) while content scrolls right.
/// Default scroll position: trailing (most recent data visible on load).
///
/// Usage:
/// ```swift
/// PeriodBarChart(dataPoints: points, currency: "KZT", granularity: .month)
/// PeriodBarChart(dataPoints: points, currency: "KZT", granularity: .week, mode: .compact)
/// ```
struct PeriodBarChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }

    private var pointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }

    /// Maximum Y value across all data points — used to sync Y-axis scale.
    private var yMax: Double {
        dataPoints.flatMap { [$0.income, $0.expenses] }.max() ?? 1
    }

    // MARK: Body

    var body: some View {
        Group {
            if isCompact {
                // Compact: no GeometryReader needed — chart fills proposed width from parent.
                // GeometryReader in compact mode adds an extra two-pass layout per sparkline;
                // removing it reduces per-chart layout cost during initial InsightsView render.
                mainChart(showYAxis: false)
                    .frame(maxWidth: .infinity)
            } else {
                GeometryReader { proxy in
                    let container = proxy.size.width
                    let yAxisWidth: CGFloat = 50
                    let scrollWidth = max(
                        container,
                        CGFloat(dataPoints.count) * pointWidth
                    )
                    ZStack(alignment: .topTrailing) {
                        // Scrollable bars (Y-axis hidden)
                        ScrollView(.horizontal, showsIndicators: false) {
                            mainChart(showYAxis: false)
                                .frame(width: scrollWidth, height: chartHeight)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .defaultScrollAnchor(.trailing)

                        // Y-axis overlay — always visible, doesn't scroll with chart
                        yAxisReferenceChart
                            .frame(width: yAxisWidth, height: chartHeight-44)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: chartHeight)
        .padding(.top, isCompact ? 0 : AppSpacing.sm)
        .chartAppear()
    }

    // MARK: - Y-axis reference chart (left panel, always visible)

    /// Invisible chart used solely to render the Y-axis labels with correct scale.
    private var yAxisReferenceChart: some View {
        Chart(dataPoints) { point in
            BarMark(x: .value("p", point.label), y: .value("v", point.income))
                .opacity(0)
            BarMark(x: .value("p", point.label), y: .value("v", point.expenses))
                .opacity(0)
        }
        .chartYScale(domain: 0...yMax)
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

    // MARK: - Main chart (bars + X-axis, optionally no Y-axis)

    private func mainChart(showYAxis: Bool) -> some View {
        Chart(dataPoints) { point in
            BarMark(
                x: .value("Period", point.label),
                y: .value("Income", point.income),
                width: isCompact ? .fixed(6) : .automatic
            )
            .cornerRadius(AppRadius.xs)
            .foregroundStyle(AppColors.success.opacity(0.85))
            .shadow(
                color: isCompact ? .clear : AppColors.success.opacity(0.35),
                radius: isCompact ? 0 : 4, x: 0, y: 2
            )
            .position(by: .value("Type", "Income"))

            BarMark(
                x: .value("Period", point.label),
                y: .value("Expenses", point.expenses),
                width: isCompact ? .fixed(6) : .automatic
            )
            .cornerRadius(AppRadius.xs)
            .foregroundStyle(AppColors.destructive.opacity(0.85))
            .shadow(
                color: isCompact ? .clear : AppColors.destructive.opacity(0.35),
                radius: isCompact ? 0 : 4, x: 0, y: 2
            )
            .position(by: .value("Type", "Expenses"))
        }
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            if isCompact {
                AxisMarks { _ in }
            } else {
                let labelMap = ChartAxisHelpers.axisLabelMap(for: dataPoints)
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
            if showYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(ChartAxisHelpers.formatCompact(amount))
                                .font(AppTypography.caption2)
                        }
                    }
                }
            } else {
                // Grid lines only — Y labels handled by yAxisReferenceChart
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel { EmptyView() }
                }
            }
        }
        .chartForegroundStyleScale([
            "Income": AppColors.success,
            "Expenses": AppColors.destructive
        ])
        .chartLegend(isCompact ? .hidden : .automatic)
        .animation(AppAnimation.chartUpdateAnimation, value: dataPoints.count)
    }
}

// MARK: - Previews

#Preview("PeriodBarChart — Monthly") {
    PeriodBarChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("PeriodBarChart — Compact") {
    PeriodBarChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month,
        mode: .compact
    )
    .screenPadding()
    .frame(height: 80)
}
