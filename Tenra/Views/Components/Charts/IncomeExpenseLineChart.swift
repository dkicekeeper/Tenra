//
//  IncomeExpenseLineChart.swift
//  Tenra
//
//  Two-line area chart that overlays income (green) and expenses (red) on the
//  same `PeriodDataPoint` series. Companion to `PeriodBarChart` — both visualise
//  the same data, used together by `PeriodChartSwitcher`.
//
//  Same interaction model as `PeriodLineChart`:
//  - native horizontal scrolling via `chartScrollableAxes`
//  - pinch zoom on the visible window (`chartXVisibleDomain`)
//  - long-press-and-drag X range selection with summary banner
//

import SwiftUI
import Charts

struct IncomeExpenseLineChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full

    @State private var zoomScale: CGFloat = 1.0
    @State private var pinchBaseScale: CGFloat = 1.0
    @State private var selectedRange: ClosedRange<String>?
    @State private var selectedValueLabel: String?
    @State private var scrollPositionLabel: String = ""
    @State private var containerWidth: CGFloat = 0

    private var isCompact: Bool { mode == .compact }
    private var basePointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var effectivePointWidth: CGFloat { basePointWidth * zoomScale }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }
    private var lineWidth: CGFloat { isCompact ? 1.5 : 2 }

    private var staticYMax: Double {
        dataPoints.flatMap { [$0.income, $0.expenses] }.max() ?? 1
    }

    private func visibleCount(for containerWidth: CGFloat) -> Int {
        guard effectivePointWidth > 0 else { return dataPoints.count }
        let raw = Int((containerWidth / effectivePointWidth).rounded())
        return max(1, min(dataPoints.count, raw))
    }

    private var visibleDataPoints: [PeriodDataPoint] {
        guard !dataPoints.isEmpty, containerWidth > 0 else { return dataPoints }
        let visible = visibleCount(for: containerWidth)
        if !scrollPositionLabel.isEmpty,
           let leftIdx = dataPoints.firstIndex(where: { $0.label == scrollPositionLabel }) {
            let endIdx = min(dataPoints.count - 1, leftIdx + visible - 1)
            return Array(dataPoints[leftIdx...endIdx])
        }
        let start = max(0, dataPoints.count - visible)
        return Array(dataPoints[start...])
    }

    private var dynamicYMax: Double {
        let pts = visibleDataPoints
        guard !pts.isEmpty else { return staticYMax }
        return pts.flatMap { [$0.income, $0.expenses] }.max() ?? 1
    }

    private var todayLabel: String? {
        let now = Date()
        return dataPoints.first(where: { $0.periodStart > now })?.label
    }

    private var selectionPoints: [PeriodDataPoint] {
        guard let range = selectedRange,
              let lo = dataPoints.firstIndex(where: { $0.label == range.lowerBound }),
              let hi = dataPoints.firstIndex(where: { $0.label == range.upperBound })
        else { return [] }
        let l = min(lo, hi)
        let h = max(lo, hi)
        return Array(dataPoints[l...h])
    }

    private var selectedSinglePoint: PeriodDataPoint? {
        guard selectionPoints.isEmpty,
              let label = selectedValueLabel else { return nil }
        return dataPoints.first { $0.label == label }
    }

    var body: some View {
        if dataPoints.isEmpty {
            emptyState
                .frame(height: chartHeight)
        } else if isCompact {
            sparkline
                .frame(height: chartHeight)
                .chartAppear()
        } else {
            VStack(spacing: AppSpacing.sm) {
                if !selectionPoints.isEmpty {
                    rangeBanner
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let p = selectedSinglePoint {
                    singleBanner(point: p)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                interactiveChart
                    .frame(height: chartHeight)
            }
            .padding(.top, AppSpacing.sm)
            .animation(AppAnimation.gentleSpring, value: selectionPoints.count)
            .animation(AppAnimation.gentleSpring, value: selectedValueLabel)
            .onChange(of: selectedRange) { _, new in
                guard new != nil else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                selectedValueLabel = nil
            }
            .onChange(of: selectedValueLabel) { _, new in
                guard new != nil else { return }
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .chartAppear()
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "chart.xyaxis.line",
            title: String(localized: "insights.empty.title"),
            description: String(localized: "insights.empty.subtitle"),
            style: .compact
        )
    }

    // MARK: - Compact sparkline

    private var sparkline: some View {
        let incomeLabel = String(localized: "insights.income")
        let expensesLabel = String(localized: "insights.expenses")
        return Chart(dataPoints) { point in
            LineMark(
                x: .value("Period", point.label),
                y: .value(incomeLabel, point.income),
                series: .value("Type", incomeLabel)
            )
            .foregroundStyle(AppColors.success)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))

            LineMark(
                x: .value("Period", point.label),
                y: .value(expensesLabel, point.expenses),
                series: .value("Type", expensesLabel)
            )
            .foregroundStyle(AppColors.destructive)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))
        }
        .chartYScale(domain: 0...staticYMax)
        .chartXAxis { AxisMarks { _ in } }
        .chartYAxis { AxisMarks { _ in } }
        .chartLegend(.hidden)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Interactive full chart

    private var interactiveChart: some View {
        GeometryReader { proxy in
            let visible = visibleCount(for: proxy.size.width)
            fullChart(visibleCount: visible)
                .gesture(magnifyGesture)
                .onAppear { containerWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, w in containerWidth = w }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let raw = pinchBaseScale * value.magnification
                zoomScale = max(0.4, min(4.0, raw))
            }
            .onEnded { _ in pinchBaseScale = zoomScale }
    }

    private func fullChart(visibleCount: Int) -> some View {
        let incomeLabel = String(localized: "insights.income")
        let expensesLabel = String(localized: "insights.expenses")
        let labelMap = ChartAxisHelpers.axisLabelMap(for: dataPoints)
        let yMaxNow = dynamicYMax
        return Chart {
            if let range = selectedRange {
                RectangleMark(
                    xStart: .value("Start", range.lowerBound),
                    xEnd: .value("End", range.upperBound)
                )
                .foregroundStyle(AppColors.accent.opacity(0.15))
            }

            if let label = selectedValueLabel, selectionPoints.isEmpty {
                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            if let today = todayLabel {
                RuleMark(x: .value("Today", today))
                    .foregroundStyle(AppColors.accent.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text(String(localized: "insights.today"))
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.accent)
                    }
            }

            ForEach(dataPoints) { point in
                AreaMark(
                    x: .value("Period", point.label),
                    y: .value(incomeLabel, point.income),
                    series: .value("Type", incomeLabel)
                )
                .foregroundStyle(LinearGradient(
                    colors: [AppColors.success.opacity(0.25), AppColors.success.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Period", point.label),
                    y: .value(incomeLabel, point.income),
                    series: .value("Type", incomeLabel)
                )
                .foregroundStyle(AppColors.success)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth))

                PointMark(
                    x: .value("Period", point.label),
                    y: .value(incomeLabel, point.income)
                )
                .foregroundStyle(AppColors.success)
                .symbolSize(28)

                AreaMark(
                    x: .value("Period", point.label),
                    y: .value(expensesLabel, point.expenses),
                    series: .value("Type", expensesLabel)
                )
                .foregroundStyle(LinearGradient(
                    colors: [AppColors.destructive.opacity(0.25), AppColors.destructive.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Period", point.label),
                    y: .value(expensesLabel, point.expenses),
                    series: .value("Type", expensesLabel)
                )
                .foregroundStyle(AppColors.destructive)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth))

                PointMark(
                    x: .value("Period", point.label),
                    y: .value(expensesLabel, point.expenses)
                )
                .foregroundStyle(AppColors.destructive)
                .symbolSize(28)
            }
        }
        .chartYScale(domain: 0...yMaxNow)
        .chartXVisibleDomain(length: visibleCount)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $scrollPositionLabel)
        .chartXSelection(range: $selectedRange)
        .chartXSelection(value: $selectedValueLabel)
        .chartXAxis {
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
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(ChartAxisHelpers.formatCompact(amount))
                            .font(AppTypography.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .animation(AppAnimation.chartUpdateAnimation, value: dataPoints.count)
        .animation(AppAnimation.gentleSpring, value: yMaxNow)
    }

    // MARK: - Single-point banner

    private func singleBanner(point: PeriodDataPoint) -> some View {
        let labelMap = ChartAxisHelpers.axisLabelMap(for: [point])
        return HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(labelMap[point.label] ?? point.label)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                HStack(spacing: AppSpacing.md) {
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.success).frame(width: 8, height: 8)
                        Text(ChartAxisHelpers.formatCompact(point.income))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.success)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.destructive).frame(width: 8, height: 8)
                        Text(ChartAxisHelpers.formatCompact(point.expenses))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.destructive)
                    }
                }
            }
            Spacer()
            Button {
                selectedValueLabel = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "insights.range.reset")))
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .cardStyle()
    }

    // MARK: - Range banner

    private var rangeBanner: some View {
        let pts = selectionPoints
        let totalIncome = pts.reduce(0) { $0 + $1.income }
        let totalExpenses = pts.reduce(0) { $0 + $1.expenses }
        return HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "insights.range.totalIncome"))
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                Text(ChartAxisHelpers.formatCompact(totalIncome))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.success)
            }
            Divider().frame(height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "insights.range.totalExpenses"))
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                Text(ChartAxisHelpers.formatCompact(totalExpenses))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.destructive)
            }
            Spacer()
            Button {
                selectedRange = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "insights.range.reset")))
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .cardStyle()
    }
}

#Preview("IncomeExpenseLineChart — Monthly") {
    IncomeExpenseLineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
