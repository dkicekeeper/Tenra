//
//  BarChart.swift
//  Tenra
//
//  Bar counterpart of `LineChart` for one or more `PeriodDataPoint`
//  series (`PeriodChartSeries` drives value + color). With 2+ series the bars
//  are grouped via `position(by:)` — `series: [.income, .spending]` replaces
//  the former standalone IncomeExpenseBarChart (merged 2026-07). Wrapped
//  together with the line chart by `ChartSwitcher`.
//
//  Performance rules (see charts.md): static Y, tap-only selection, cached
//  label→index lookups, no animations on hot-path state.
//

import SwiftUI
import Charts

struct BarChart: View {
    let dataPoints: [PeriodDataPoint]
    let seriesList: [PeriodChartSeries]
    let granularity: InsightGranularity
    var currency: String = ""

    /// External zoom binding — controlled by `ChartSwitcher` toolbar.
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

    /// Single-series convenience.
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

    private let chartHeight: CGFloat = 200

    /// Static Y-domain over the whole dataset (all series) with ~6% headroom
    /// (bars touching the plot edge read as clipped, same as line-chart peaks).
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

    /// Width-independent visible-window size. See LineChart for rationale.
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
            icon: "chart.bar",
            title: String(localized: "insights.empty.title"),
            description: String(localized: "insights.empty.subtitle"),
            style: .compact
        )
    }

    // MARK: - Interactive full chart

    private var fullChart: some View {
        let domain = fullYDomain
        let categoryDomain = dataPoints.map { $0.label }
        let leftIdx = max(0, dataPoints.count - visibleCount)
        let trailingAnchorLabel = dataPoints[leftIdx].label
        let isGrouped = seriesList.count > 1
        let showZeroRuler = seriesList.contains(where: \.showZeroRuler)
        return Chart {
            // Today marker — drawn first; today is always part of dataPoints'
            // label set so it doesn't introduce a new category.
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

            ForEach(seriesList.indices, id: \.self) { i in
                let s = seriesList[i]
                ForEach(dataPoints) { point in
                    let v = s.value(for: point)
                    // Per-point color so `.cashFlow` bars read green above zero
                    // and red below, matching the line chart's point colors.
                    if isGrouped {
                        BarMark(
                            x: .value("Period", point.label),
                            y: .value("Value", v)
                        )
                        .cornerRadius(AppRadius.xs)
                        .foregroundStyle(s.pointColor(for: v).opacity(0.85))
                        .position(by: .value("Type", s.seriesKey))
                    } else {
                        BarMark(
                            x: .value("Period", point.label),
                            y: .value("Value", v)
                        )
                        .cornerRadius(AppRadius.xs)
                        .foregroundStyle(s.pointColor(for: v).opacity(0.85))
                    }
                }
            }

            if showZeroRuler {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }

            // Selection emphasis last — drawn on top (translucent column band
            // plus a stronger ruler through its centre).
            if let label = selectedValueLabel {
                RectangleMark(x: .value("SelBand", label))
                    .foregroundStyle(AppColors.accent.opacity(0.10))

                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(AppColors.accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
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
    BarChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .spending,
        granularity: .month,
        currency: "KZT"
    )
}

#Preview("Cash Flow — Monthly") {
    BarChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .cashFlow,
        granularity: .month,
        currency: "KZT"
    )
}

#Preview("Income vs Expenses — Monthly") {
    BarChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: [.income, .spending],
        granularity: .month,
        currency: "KZT"
    )
}
