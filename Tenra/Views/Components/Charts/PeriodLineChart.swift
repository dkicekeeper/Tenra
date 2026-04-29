//
//  PeriodLineChart.swift
//  Tenra
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

    /// Per-point color used for PointMark (cashFlow colors each point individually).
    func pointColor(for value: Double) -> Color {
        switch self {
        case .spending: return AppColors.destructive
        case .cashFlow: return value >= 0 ? AppColors.success : AppColors.destructive
        case .wealth:   return AppColors.accent
        }
    }

    /// Line stroke style. For `.cashFlow` produces a vertical green→red gradient
    /// with the transition pinned to y=0, so the line color smoothly tracks the
    /// sign of each point along the curve. For other series returns a solid color.
    func lineStyle(yDomain: ClosedRange<Double>) -> AnyShapeStyle {
        switch self {
        case .spending: return AnyShapeStyle(AppColors.destructive)
        case .wealth:   return AnyShapeStyle(AppColors.accent)
        case .cashFlow:
            let total = yDomain.upperBound - yDomain.lowerBound
            guard total > 0 else { return AnyShapeStyle(AppColors.success) }
            let zeroRatio = (yDomain.upperBound - 0) / total
            if zeroRatio <= 0 { return AnyShapeStyle(AppColors.destructive) }
            if zeroRatio >= 1 { return AnyShapeStyle(AppColors.success) }
            let eps = 0.001
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: AppColors.success,     location: 0),
                    .init(color: AppColors.success,     location: max(0, zeroRatio - eps)),
                    .init(color: AppColors.destructive, location: min(1, zeroRatio + eps)),
                    .init(color: AppColors.destructive, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    /// Area fill style. Mirrors `lineStyle` but with reduced opacity. For `.cashFlow`
    /// the gradient flips opacity above and below zero so each side reads as a tinted area.
    func areaStyle(yDomain: ClosedRange<Double>) -> AnyShapeStyle {
        switch self {
        case .spending:
            return AnyShapeStyle(LinearGradient(
                colors: [AppColors.destructive.opacity(0.3), AppColors.destructive.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            ))
        case .wealth:
            return AnyShapeStyle(LinearGradient(
                colors: [AppColors.accent.opacity(0.3), AppColors.accent.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            ))
        case .cashFlow:
            let total = yDomain.upperBound - yDomain.lowerBound
            guard total > 0 else {
                return AnyShapeStyle(LinearGradient(
                    colors: [AppColors.success.opacity(0.3), AppColors.success.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            let zeroRatio = (yDomain.upperBound - 0) / total
            if zeroRatio <= 0 {
                return AnyShapeStyle(LinearGradient(
                    colors: [AppColors.destructive.opacity(0.05), AppColors.destructive.opacity(0.3)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            if zeroRatio >= 1 {
                return AnyShapeStyle(LinearGradient(
                    colors: [AppColors.success.opacity(0.3), AppColors.success.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            let eps = 0.001
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: AppColors.success.opacity(0.35),     location: 0),
                    .init(color: AppColors.success.opacity(0.05),     location: max(0, zeroRatio - eps)),
                    .init(color: AppColors.destructive.opacity(0.05), location: min(1, zeroRatio + eps)),
                    .init(color: AppColors.destructive.opacity(0.35), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
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

    // MARK: - Range summary

    /// Aggregates the selected points into a single representative number for the range banner.
    /// - `.spending` and `.cashFlow` → sum of values across the range.
    /// - `.wealth`  → end-of-range value minus start-of-range value (delta).
    func summarize(_ points: [PeriodDataPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        switch self {
        case .spending: return points.reduce(0) { $0 + $1.expenses }
        case .cashFlow: return points.reduce(0) { $0 + $1.netFlow }
        case .wealth:
            let last = points.last.map { $0.cumulativeBalance ?? $0.netFlow } ?? 0
            let first = points.first.map { $0.cumulativeBalance ?? $0.netFlow } ?? 0
            return last - first
        }
    }

    /// Localized title shown above the summary value in the range banner.
    var summaryTitle: String {
        switch self {
        case .spending: return String(localized: "insights.range.totalExpenses")
        case .cashFlow: return String(localized: "insights.range.netFlow")
        case .wealth:   return String(localized: "insights.range.wealthChange")
        }
    }
}

// MARK: - PeriodLineChart

/// Granularity-aware area/line chart for any `PeriodDataPoint` series.
///
/// Full mode uses native Apple Charts horizontal scrolling (`chartScrollableAxes`)
/// with a sticky leading Y-axis. The visible window is controlled by `zoomScale`
/// (1.0 = default), driven by a pinch gesture clamped to `[0.4, 4.0]`.
/// Long-press-and-drag on the chart selects an X range — the chart shows a
/// banner above with the aggregated value (sum/delta) and a reset button.
///
/// Compact mode is a static sparkline — no scrolling, zoom, or selection.
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

    @State private var zoomScale: CGFloat = 1.0
    @State private var selectedRange: ClosedRange<String>?
    @State private var selectedValueLabel: String?
    @State private var visibleLeftLabel: String?

    private var isCompact: Bool { mode == .compact }
    private var basePointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var effectivePointWidth: CGFloat { basePointWidth * zoomScale }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }
    private var lineWidth: CGFloat { isCompact ? 1.5 : series.fullLineWidth }

    private var values: [Double] { dataPoints.map { series.value(for: $0) } }

    /// Y-domain over the entire dataset (used by compact sparkline).
    private var fullYDomain: ClosedRange<Double> { series.yDomain(values: values) }

    /// Y-domain over the currently-visible window. Recomputed only when
    /// `visibleLeftLabel` or `zoomScale` changes — NOT on every body call.
    /// Apple Charts updates its scale smoothly without an explicit `.animation`,
    /// so we deliberately avoid attaching a spring here (that was the lag source).
    ///
    /// **Frozen during active range selection** — otherwise dragging across periods
    /// re-scales the Y axis mid-gesture, which makes bars/lines visually jump under
    /// the user's finger. Selection is a frozen viewport: range stays visible against
    /// a stable axis until the user resets it.
    private func dynamicYDomain(visibleCount: Int) -> ClosedRange<Double> {
        guard !dataPoints.isEmpty else { return fullYDomain }
        if selectedRange != nil { return fullYDomain }
        let leftIdx: Int
        if let label = visibleLeftLabel,
           let idx = dataPoints.firstIndex(where: { $0.label == label }) {
            leftIdx = idx
        } else {
            leftIdx = max(0, dataPoints.count - visibleCount)
        }
        let endIdx = min(dataPoints.count - 1, leftIdx + visibleCount - 1)
        let slice = dataPoints[leftIdx...endIdx]
        return series.yDomain(values: slice.map { series.value(for: $0) })
    }

    /// Single-tap selected point (only valid when no range is active).
    private var selectedSinglePoint: PeriodDataPoint? {
        guard selectionPoints.isEmpty,
              let label = selectedValueLabel else { return nil }
        return dataPoints.first { $0.label == label }
    }

    /// How many data points fit in the visible window for the current zoom.
    /// Smaller values = more zoomed-in; clamped between 1 and total count.
    private func visibleCount(for containerWidth: CGFloat) -> Int {
        guard effectivePointWidth > 0 else { return dataPoints.count }
        let raw = Int((containerWidth / effectivePointWidth).rounded())
        return max(1, min(dataPoints.count, raw))
    }

    /// Label of the first point whose period starts in the future. Nil if all data is in the past.
    private var todayLabel: String? {
        let now = Date()
        return dataPoints.first(where: { $0.periodStart > now })?.label
    }

    /// Points covered by the active range selection (in array order, not lex order).
    private var selectionPoints: [PeriodDataPoint] {
        guard let range = selectedRange,
              let lo = dataPoints.firstIndex(where: { $0.label == range.lowerBound }),
              let hi = dataPoints.firstIndex(where: { $0.label == range.upperBound })
        else { return [] }
        let l = min(lo, hi)
        let h = max(lo, hi)
        return Array(dataPoints[l...h])
    }

    // MARK: Body

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
                zoomToolbar
                    .screenPadding()

                if !selectionPoints.isEmpty {
                    rangeBanner
                } else if let p = selectedSinglePoint {
                    singleBanner(point: p)
                }

                interactiveChart
                    .frame(height: chartHeight)
            }
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
            icon: "chart.line.uptrend.xyaxis",
            title: String(localized: "insights.empty.title"),
            description: String(localized: "insights.empty.subtitle"),
            style: .compact
        )
    }

    /// Trailing-aligned zoom controls. Pinch-to-zoom was removed because it
    /// conflicted with the parent NavigationStack's swipe-to-go-back gesture.
    private var zoomToolbar: some View {
        HStack {
            Spacer()
            ChartZoomControls(zoomScale: $zoomScale, range: 0.4...4.0)
        }
    }

    // MARK: - Compact sparkline

    private var sparkline: some View {
        let domain = fullYDomain
        let lineFill = series.lineStyle(yDomain: domain)
        let areaFill = series.areaStyle(yDomain: domain)
        return Chart(dataPoints) { point in
            let v = series.value(for: point)
            AreaMark(x: .value("Period", point.label), y: .value("Value", v))
                .foregroundStyle(areaFill)
                .interpolationMethod(.monotone)
            LineMark(x: .value("Period", point.label), y: .value("Value", v))
                .foregroundStyle(lineFill)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth))
        }
        .chartYScale(domain: domain)
        .chartXAxis { AxisMarks { _ in } }
        .chartYAxis { AxisMarks { _ in } }
        .chartLegend(.hidden)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Interactive full chart

    private var interactiveChart: some View {
        GeometryReader { proxy in
            let visible = visibleCount(for: proxy.size.width)
            let leftIdx = max(0, dataPoints.count - visible)
            let initialLabel = dataPoints[leftIdx].label
            fullChart(visibleCount: visible, initialLeftLabel: initialLabel)
        }
    }

    private func fullChart(visibleCount: Int, initialLeftLabel: String) -> some View {
        let domain = dynamicYDomain(visibleCount: visibleCount)
        let lineFill = series.lineStyle(yDomain: domain)
        let areaFill = series.areaStyle(yDomain: domain)
        // Bind scrollPosition through a non-optional String binding (Apple Charts requirement).
        // Setter is **blocked while a range selection is active** so range-drag doesn't
        // cause the chart to auto-pan or re-trigger Y-axis recompute mid-gesture.
        let scrollBinding = Binding<String>(
            get: { visibleLeftLabel ?? initialLeftLabel },
            set: { newValue in
                guard selectedRange == nil else { return }
                visibleLeftLabel = newValue
            }
        )
        return Chart {
            // Translucent band highlighting the selected range.
            if let range = selectedRange {
                RectangleMark(
                    xStart: .value("Start", range.lowerBound),
                    xEnd: .value("End", range.upperBound)
                )
                .foregroundStyle(AppColors.accent.opacity(0.15))
            }

            // Single-tap selection ruler.
            if let label = selectedValueLabel, selectionPoints.isEmpty {
                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            // Today / future boundary marker.
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
                let v = series.value(for: point)
                AreaMark(x: .value("Period", point.label), y: .value("Value", v))
                    .foregroundStyle(areaFill)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Period", point.label), y: .value("Value", v))
                    .foregroundStyle(lineFill)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: lineWidth))
                PointMark(x: .value("Period", point.label), y: .value("Value", v))
                    .foregroundStyle(series.pointColor(for: v))
                    .symbolSize(30)
            }

            if series.showZeroRuler {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }
        }
        .chartYScale(domain: domain)
        .chartXVisibleDomain(length: visibleCount)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: scrollBinding)
        .chartXSelection(range: $selectedRange)
        .chartXSelection(value: $selectedValueLabel)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 6)) {
                    if let label = value.as(String.self) {
                        Text(axisLabelMap[label] ?? label)
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
    }

    // MARK: - Single-point banner

    private func singleBanner(point: PeriodDataPoint) -> some View {
        let value = series.value(for: point)
        return HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(axisLabelMap[point.label] ?? point.label)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                Text(ChartAxisHelpers.formatCompact(value))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(series.pointColor(for: value))
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
        let value = series.summarize(pts)
        return HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(series.summaryTitle)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                Text(ChartAxisHelpers.formatCompact(value))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
            }
            Spacer()
            if let first = pts.first?.label, let last = pts.last?.label {
                Text("\(axisLabelMap[first] ?? first) – \(axisLabelMap[last] ?? last)")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
            }
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

    // MARK: - Cached axis label map

    /// Built once per `dataPoints` array — survives every body re-eval driven by
    /// gesture/scroll state. Without this cache the dictionary was rebuilt at 60 fps
    /// during pinch/scroll, which dominated the frame budget on real devices.
    private var axisLabelMap: [String: String] {
        ChartAxisLabelMapCache.shared.map(for: dataPoints)
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
