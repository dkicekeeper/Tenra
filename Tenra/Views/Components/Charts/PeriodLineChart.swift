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
}

// MARK: - PeriodLineChart

/// Granularity-aware area/line chart for any `PeriodDataPoint` series.
///
/// Native Apple Charts horizontal scrolling (`chartScrollableAxes`) with a
/// sticky leading Y-axis. The visible window is controlled by `zoomScale`
/// (1.0 = default), driven by the `+/-` zoom controls (clamped to `[0.4, 4.0]`).
/// Pinch-to-zoom is intentionally NOT used — it conflicts with the navigation
/// swipe-to-go-back gesture on the parent view.
///
/// Compact rendering for insight cards lives in `MiniSparkline` instead — it
/// avoids spinning up a full Apple Charts render-tree per card.
///
/// Usage:
/// ```swift
/// PeriodLineChart(dataPoints: points, series: .cashFlow, granularity: .month)
/// PeriodLineChart(dataPoints: points, series: .wealth,   granularity: .month)
/// ```
struct PeriodLineChart: View {
    let dataPoints: [PeriodDataPoint]
    let series: PeriodLineChartSeries
    let granularity: InsightGranularity
    /// ISO currency code for the selection-banner amount. Defaults to "" so
    /// callers without a currency keep compiling; the banner falls back to
    /// non-currency compact formatting in that case.
    var currency: String = ""

    @State private var zoomScale: CGFloat = 1.0
    @State private var selectedValueLabel: String?
    @State private var cache = PeriodChartCache()

    private var basePointWidth: CGFloat { granularity.pointWidth }
    private var effectivePointWidth: CGFloat { basePointWidth * zoomScale }
    private let chartHeight: CGFloat = 200
    private var lineWidth: CGFloat { series.fullLineWidth }

    /// Static Y-domain computed once over the entire dataset, derived from
    /// the cached yMin/yMax envelope. Stable across scroll for two reasons:
    ///   1. **Visual stability**: with a dynamic domain, the Y axis re-scaled
    ///      as the user scrolled — points visually jumped under their finger.
    ///   2. **Performance**: a stable domain means `lineStyle`/`areaStyle`
    ///      (multi-stop `LinearGradient` for `.cashFlow`/`.wealth`) are constant
    ///      and can be hoisted out of the per-frame body.
    private var fullYDomain: ClosedRange<Double> {
        switch series {
        case .spending:
            return 0...max(cache.yMax, 1)
        case .cashFlow, .wealth:
            return min(cache.yMin, 0)...max(cache.yMax, 1)
        }
    }

    private var selectedSinglePoint: PeriodDataPoint? {
        guard let label = selectedValueLabel,
              let idx = cache.labelToIndex[label] else { return nil }
        return dataPoints[idx]
    }

    /// How many data points fit in the visible window. Width-independent:
    /// `chartXVisibleDomain(length:)` on a category x-axis means "show N
    /// categories regardless of width", so we don't need a `GeometryReader`.
    /// Default = 12 buckets; zoom-in halves, zoom-out doubles.
    private var visibleCount: Int {
        let base = 12.0
        let raw = Int((base / max(zoomScale, 0.1)).rounded())
        return max(1, min(dataPoints.count, raw))
    }

    private var todayLabel: String? { cache.todayLabel }

    private func rebuildCacheIfNeeded() {
        rebuildPeriodCacheIfNeeded(cache, dataPoints: dataPoints) { p in
            [series.value(for: p)]
        }
    }

    private var axisLabelMap: [String: String] {
        ChartAxisLabelMapCache.shared.map(for: dataPoints)
    }

    // MARK: Body

    var body: some View {
        // Prime per-dataset caches before any cache-reading getter fires.
        let _ = rebuildCacheIfNeeded()
        if dataPoints.isEmpty {
            emptyState.frame(height: chartHeight)
        } else {
            VStack(spacing: AppSpacing.sm) {
                zoomToolbar.screenPadding()
                bannerSlot
                fullChart.frame(height: chartHeight)
            }
            .chartAppear()
        }
    }

    private var bannerSlot: some View {
        ZStack {
            if let p = selectedSinglePoint {
                let value = series.value(for: p)
                ChartSelectionBanner(
                    title: granularity.bannerLabel(for: p.key),
                    currency: currency,
                    content: .single(value: value, color: series.pointColor(for: value))
                )
                .transition(.opacity)
            }
        }
        .chartBannerSlotStyle(animationKey: selectedSinglePoint?.label)
        .chartSelectionAnnouncement(announcementText)
    }

    private var announcementText: String? {
        guard let p = selectedSinglePoint else { return nil }
        return chartBannerAnnouncementText(
            title: granularity.bannerLabel(for: p.key),
            value: series.value(for: p),
            currency: currency
        )
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

    // MARK: - Interactive full chart

    private var fullChart: some View {
        let domain = fullYDomain
        // Stable styles: yDomain is fixed for the lifetime of this view, so the
        // multi-stop `LinearGradient` for `.cashFlow`/`.wealth` is computed once.
        let lineFill = series.lineStyle(yDomain: domain)
        let areaFill = series.areaStyle(yDomain: domain)
        let categoryDomain = dataPoints.map { $0.label }
        let leftIdx = max(0, dataPoints.count - visibleCount)
        let trailingAnchorLabel = dataPoints[leftIdx].label
        return Chart {
            // Today / future boundary marker — drawn first; today is part of
            // dataPoints' label set so this doesn't introduce a new category.
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

            // Selection emphasis — drawn LAST so it renders on top. The x-domain
            // is also locked via `chartXScale(domain:)` below. Both safeguards
            // ensure selection marks cannot reorder the X axis.
            //
            // Visual layers (back-to-front): ruler → halo → emphasized point.
            if let label = selectedValueLabel,
               let idx = cache.labelToIndex[label] {
                let selectedPoint = dataPoints[idx]
                let v = series.value(for: selectedPoint)
                let pointColor = series.pointColor(for: v)

                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(pointColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                PointMark(
                    x: .value("SelectedHalo", selectedPoint.label),
                    y: .value("SelectedV", v)
                )
                .symbolSize(180)
                .foregroundStyle(pointColor.opacity(0.20))

                PointMark(
                    x: .value("SelectedInner", selectedPoint.label),
                    y: .value("SelectedV", v)
                )
                .symbolSize(70)
                .foregroundStyle(pointColor)
            }
        }
        // Lock category order to the dataPoints' label sequence. Without this,
        // Apple Charts derives x-domain from "first occurrence across marks in
        // declaration order" — which made the selection RuleMark's label define
        // the leading category, flipping the axis on every tap.
        .chartXScale(domain: categoryDomain)
        .chartYScale(domain: domain)
        .chartXVisibleDomain(length: visibleCount)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(initialX: trailingAnchorLabel)
        .chartXLabelSelectionWithFeedback($selectedValueLabel)
        .periodChartXAxis(labelMap: axisLabelMap)
        .periodChartYAxis()
        .chartLegend(.hidden)
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
