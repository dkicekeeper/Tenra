//
//  LineChart.swift
//  Tenra
//
//  Phase 43 (chart merge): Unified granularity-aware area/line chart.
//  Replaces three structurally identical components:
//  - PeriodSpendingTrendChart (expenses, 0-based Y, destructive color)
//  - PeriodCashFlowChart     (netFlow, ±Y, dynamic green/red, zero ruler)
//  - WealthChart             (cumulativeBalance, ±Y, accent color)
//
//  Behavioral differences are captured in PeriodChartSeries enum.
//  Layout, scrolling, Y-axis overlay, and animation are shared.
//

import SwiftUI
import Charts

// MARK: - PeriodChartSeries

/// Defines which data field and visual style a `LineChart` uses.
enum PeriodChartSeries {
    /// Spending trend: `expenses` field, Y starts at 0, destructive color.
    case spending
    /// Income trend: `income` field, Y starts at 0, success color.
    case income
    /// Average daily spending: `expenses / days-in-period`, Y starts at 0, destructive color.
    case avgDailyExpenses
    /// Cash flow: `netFlow` field, ± Y, color tracks direction, zero reference line.
    case cashFlow
    /// Wealth: `cumulativeBalance` field (falls back to `netFlow`), ± Y, accent color.
    case wealth

    // MARK: - Data extraction

    func value(for point: PeriodDataPoint) -> Double {
        switch self {
        case .spending: return point.expenses
        case .income:   return point.income
        case .avgDailyExpenses:
            let days = Swift.max(1, Calendar.current.dateComponents([.day], from: point.periodStart, to: point.periodEnd).day ?? 1)
            return point.expenses / Double(days)
        case .cashFlow: return point.netFlow
        case .wealth:   return point.cumulativeBalance ?? point.netFlow
        }
    }

    // MARK: - Y-domain

    func yDomain(values: [Double]) -> ClosedRange<Double> {
        switch self {
        case .spending, .income, .avgDailyExpenses:
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
        case .spending, .avgDailyExpenses: return AppColors.destructive
        case .income:   return AppColors.success
        case .cashFlow: return value >= 0 ? AppColors.success : AppColors.destructive
        case .wealth:   return AppColors.accent
        }
    }

    /// Line stroke style. For `.cashFlow` produces a vertical green→red gradient
    /// with the transition pinned to y=0, so the line color smoothly tracks the
    /// sign of each point along the curve. For other series returns a solid color.
    func lineStyle(yDomain: ClosedRange<Double>) -> AnyShapeStyle {
        switch self {
        case .spending, .avgDailyExpenses: return AnyShapeStyle(AppColors.destructive)
        case .income:   return AnyShapeStyle(AppColors.success)
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
        case .spending, .avgDailyExpenses:
            return AnyShapeStyle(LinearGradient(
                colors: [AppColors.destructive.opacity(0.3), AppColors.destructive.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            ))
        case .income:
            return AnyShapeStyle(LinearGradient(
                colors: [AppColors.success.opacity(0.3), AppColors.success.opacity(0.05)],
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

    // MARK: - Mark grouping

    /// Stable mark key for Charts `series:` / `position(by:)` grouping in
    /// multi-series charts. Static strings — safe on the per-frame hot path.
    var seriesKey: String {
        switch self {
        case .spending:         return "spending"
        case .income:           return "income"
        case .avgDailyExpenses: return "avgDaily"
        case .cashFlow:         return "cashFlow"
        case .wealth:           return "wealth"
        }
    }

    // MARK: - Visual flags

    /// Whether to render a dashed zero reference line (RuleMark at y=0).
    var showZeroRuler: Bool {
        switch self {
        case .spending, .wealth, .income, .avgDailyExpenses: return false
        case .cashFlow:                                      return true
        }
    }

    /// Line width in full (non-compact) mode.
    var fullLineWidth: CGFloat {
        switch self {
        case .spending, .cashFlow, .income, .avgDailyExpenses: return 2
        case .wealth:                                          return 2.5
        }
    }
}

// MARK: - LineChart

/// Granularity-aware area/line chart for one or more `PeriodDataPoint` series.
///
/// Multi-series (2026-07 charts refactor): pass `series: [.income, .spending]`
/// to get the income-vs-expense overlay that used to be a separate
/// `IncomeExpenseLineChart` — each series draws its own area/line/points with
/// the styles its `PeriodChartSeries` case defines. With two series the
/// selection banner switches to the dual income/expense layout.
///
/// Native Apple Charts horizontal scrolling (`chartScrollableAxes`) with a
/// sticky leading Y-axis. The visible window is controlled by `zoomScale`
/// (1.0 = default), owned by `ChartSwitcher`'s `+/-` controls
/// (clamped to `[0.4, 4.0]`). Pinch-to-zoom is intentionally NOT used — it
/// conflicts with the navigation swipe-to-go-back gesture on the parent view.
///
/// Compact rendering for insight cards lives in `MiniSparkline` instead — it
/// avoids spinning up a full Apple Charts render-tree per card.
///
/// Usage:
/// ```swift
/// LineChart(dataPoints: points, series: .cashFlow, granularity: .month)
/// LineChart(dataPoints: points, series: [.income, .spending], granularity: .month)
/// ```
struct LineChart: View {
    let dataPoints: [PeriodDataPoint]
    let seriesList: [PeriodChartSeries]
    let granularity: InsightGranularity
    /// ISO currency code for the selection-banner amount. Defaults to "" so
    /// callers without a currency keep compiling; the banner falls back to
    /// non-currency compact formatting in that case.
    var currency: String = ""

    /// External zoom binding — controlled by `ChartSwitcher` toolbar.
    /// Defaults to 1.0 when the chart is used standalone (no parent toolbar).
    @Binding var zoomScale: CGFloat

    @State private var selectedValueLabel: String?
    @State private var cache = PeriodChartCache()

    init(
        dataPoints: [PeriodDataPoint],
        series: [PeriodChartSeries],
        granularity: InsightGranularity,
        currency: String = "",
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.dataPoints = dataPoints
        self.seriesList = series
        self.granularity = granularity
        self.currency = currency
        self._zoomScale = zoomScale
    }

    /// Single-series convenience — the overwhelmingly common case.
    init(
        dataPoints: [PeriodDataPoint],
        series: PeriodChartSeries,
        granularity: InsightGranularity,
        currency: String = "",
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.init(
            dataPoints: dataPoints,
            series: [series],
            granularity: granularity,
            currency: currency,
            zoomScale: zoomScale
        )
    }

    private var basePointWidth: CGFloat { granularity.pointWidth }
    private var effectivePointWidth: CGFloat { basePointWidth * zoomScale }
    private let chartHeight: CGFloat = 200

    /// Static Y-domain computed once over the entire dataset (all series),
    /// derived from the cached yMin/yMax envelope. Stable across scroll for
    /// visual stability + hoisted gradient styles (see charts.md).
    /// ~6% headroom so the peak PointMark (and its selection ring) isn't
    /// clipped by the plot-area edge; zero-based series keep their 0 floor.
    private var fullYDomain: ClosedRange<Double> {
        let allowsNegative = seriesList.contains { $0 == .cashFlow || $0 == .wealth }
        let rawMin = allowsNegative ? min(cache.yMin, 0) : 0
        let rawMax = max(cache.yMax, 1)
        let headroom = (rawMax - rawMin) * 0.06
        let paddedMin = rawMin < 0 ? rawMin - headroom : rawMin
        return paddedMin...(rawMax + headroom)
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
            seriesList.map { $0.value(for: p) }
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
            VStack(spacing: AppSpacing.lg) {
                bannerSlot
                fullChart
                    .padding(.leading, AppSpacing.lg)
                    .frame(height: chartHeight)
            }
            .chartAppear()
        }
    }

    private var bannerSlot: some View {
        ZStack {
            if let p = selectedSinglePoint {
                ChartSelectionBanner(
                    title: granularity.bannerLabel(for: p.key),
                    currency: currency,
                    content: bannerContent(for: p)
                )
                .transition(.opacity)
            }
        }
        .chartBannerSlotStyle(animationKey: selectedSinglePoint?.label)
        .chartSelectionAnnouncement(announcementText)
    }

    /// The only shipped multi-series combo is income + expenses, so 2+ series
    /// use the dual income/expense banner layout.
    private func bannerContent(for p: PeriodDataPoint) -> ChartSelectionBanner.Content {
        if seriesList.count >= 2 {
            return .dual(income: p.income, expenses: p.expenses)
        }
        let s = seriesList[0]
        let value = s.value(for: p)
        return .single(value: value, color: s.pointColor(for: value))
    }

    private var announcementText: String? {
        guard let p = selectedSinglePoint else { return nil }
        if seriesList.count >= 2 {
            return chartBannerAnnouncementText(
                title: granularity.bannerLabel(for: p.key),
                income: p.income,
                expenses: p.expenses,
                currency: currency
            )
        }
        return chartBannerAnnouncementText(
            title: granularity.bannerLabel(for: p.key),
            value: seriesList[0].value(for: p),
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

    // MARK: - Interactive full chart

    private var fullChart: some View {
        let domain = fullYDomain
        // Stable styles: yDomain is fixed for the lifetime of this view, so the
        // multi-stop `LinearGradient` for `.cashFlow`/`.wealth` is computed once.
        //
        // ⚠️ Gradients resolve against the MARK's own bounds (the raw data
        // envelope), NOT the padded axis domain — computing `zeroRatio` from
        // `fullYDomain` (with its 6% headroom) shifted the green→red transition
        // ABOVE the true zero line (visible as a red band over y=0). Style
        // gradients must always use the unpadded envelope.
        let styleEnvelope = min(cache.yMin, 0)...max(cache.yMax, 1)
        let lineFills = seriesList.map { $0.lineStyle(yDomain: styleEnvelope) }
        let areaFills = seriesList.map { $0.areaStyle(yDomain: styleEnvelope) }
        let categoryDomain = dataPoints.map { $0.label }
        let leftIdx = max(0, dataPoints.count - visibleCount)
        let trailingAnchorLabel = dataPoints[leftIdx].label
        let showZeroRuler = seriesList.contains(where: \.showZeroRuler)
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

            // `series:` + `stacking: .unstacked` keep multiple series as distinct
            // overlaid lines/areas with a y=0 baseline (see charts.md Multi-Series
            // AreaMark). Harmless for the single-series case.
            ForEach(seriesList.indices, id: \.self) { i in
                let s = seriesList[i]
                ForEach(dataPoints) { point in
                    let v = s.value(for: point)
                    AreaMark(
                        x: .value("Period", point.label),
                        y: .value("Value", v),
                        series: .value("Type", s.seriesKey),
                        stacking: .unstacked
                    )
                    .foregroundStyle(areaFills[i])
                    .interpolationMethod(.monotone)
                    LineMark(
                        x: .value("Period", point.label),
                        y: .value("Value", v),
                        series: .value("Type", s.seriesKey)
                    )
                    .foregroundStyle(lineFills[i])
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: s.fullLineWidth))
                    PointMark(x: .value("Period", point.label), y: .value("Value", v))
                        .foregroundStyle(s.pointColor(for: v))
                        .symbolSize(30)
                }
            }

            if showZeroRuler {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }

            // Selection emphasis — drawn LAST so it renders on top. The x-domain
            // is also locked via `chartXScale(domain:)` below. Both safeguards
            // ensure selection marks cannot reorder the X axis.
            //
            // Visual layers (back-to-front): ruler → halo → emphasized point.
            // Multi-series: highlight every series' point at the selected x;
            // zero values are skipped (a halo at the baseline reads as noise).
            if let label = selectedValueLabel,
               let idx = cache.labelToIndex[label] {
                let selectedPoint = dataPoints[idx]
                let rulerColor = seriesList.count == 1
                    ? seriesList[0].pointColor(for: seriesList[0].value(for: selectedPoint))
                    : AppColors.accent

                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(rulerColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                ForEach(seriesList.indices, id: \.self) { i in
                    let s = seriesList[i]
                    let v = s.value(for: selectedPoint)
                    if seriesList.count == 1 || v > 0 {
                        let pointColor = s.pointColor(for: v)
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
    LineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .spending,
        granularity: .month
    )
}

#Preview("Cash Flow — Monthly") {
    LineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .cashFlow,
        granularity: .month
    )
}

#Preview("Income vs Expenses — Monthly") {
    LineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: [.income, .spending],
        granularity: .month,
        currency: "KZT"
    )
}
