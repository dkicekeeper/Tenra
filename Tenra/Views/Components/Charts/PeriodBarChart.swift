//
//  PeriodBarChart.swift
//  Tenra
//
//  Granularity-aware income/expense grouped bar chart.
//
//  Performance notes (after audit):
//  - Single-tap selection (`chartXSelection(value:)`) is the only selection mode.
//    Range selection was removed: every frame, the range-banner subtree was a
//    body-redraw amplifier, plus the dual `chartXSelection(value:) + (range:)`
//    pair forced two state writes per gesture.
//  - Y-domain is dynamic for the visible window. Lookups use a cached
//    `[label: index]` map (`PeriodChartCache`) — replaces O(N)
//    `firstIndex(where:)` that fired on every scroll frame.
//  - Scroll-position binding throttles same-value writes (Apple Charts emits
//    redundant updates during settle).
//  - Localized labels and the axis label map are cached / hoisted out of body
//    to keep the per-frame body cost flat during scroll.
//  - No animations on hot-path state (selection, scroll position, zoom).
//

import SwiftUI
import Charts

struct PeriodBarChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity

    /// External zoom binding — controlled by `PeriodChartSwitcher` toolbar.
    /// Defaults to 1.0 when the chart is used standalone (no parent toolbar).
    @Binding var zoomScale: CGFloat

    @State private var selectedValueLabel: String?
    @State private var cache = PeriodChartCache()

    init(
        dataPoints: [PeriodDataPoint],
        currency: String,
        granularity: InsightGranularity,
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.dataPoints = dataPoints
        self.currency = currency
        self.granularity = granularity
        self._zoomScale = zoomScale
    }

    private var basePointWidth: CGFloat { granularity.pointWidth }
    private var effectivePointWidth: CGFloat { basePointWidth * zoomScale }
    private let chartHeight: CGFloat = 200

    /// Static Y max over the entire dataset. Replaces the previous dynamic
    /// per-window recompute (which caused bars to visually jump when scrolling
    /// across stretches with different magnitudes).
    private var fullYMax: Double { cache.yMax }

    private var selectedSinglePoint: PeriodDataPoint? {
        guard let label = selectedValueLabel,
              let idx = cache.labelToIndex[label] else { return nil }
        return dataPoints[idx]
    }

    /// Width-independent visible-window size. See PeriodLineChart for rationale.
    private var visibleCount: Int {
        let base = 12.0
        let raw = Int((base / max(zoomScale, 0.1)).rounded())
        return max(1, min(dataPoints.count, raw))
    }

    private var todayLabel: String? { cache.todayLabel }

    private func rebuildCacheIfNeeded() {
        rebuildPeriodCacheIfNeeded(cache, dataPoints: dataPoints) { p in
            [p.income, p.expenses]
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
                bannerSlot
                fullChart.frame(height: chartHeight)
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
                    content: .dual(income: p.income, expenses: p.expenses)
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
            income: p.income,
            expenses: p.expenses,
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
        let yMaxNow = fullYMax
        let categoryDomain = dataPoints.map { $0.label }
        let leftIdx = max(0, dataPoints.count - visibleCount)
        let trailingAnchorLabel = dataPoints[leftIdx].label
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

            ForEach(dataPoints) { point in
                BarMark(
                    x: .value("Period", point.label),
                    y: .value("Income", point.income)
                )
                .cornerRadius(AppRadius.xs)
                .foregroundStyle(AppColors.success.opacity(0.85))
                .position(by: .value("Type", "income"))

                BarMark(
                    x: .value("Period", point.label),
                    y: .value("Expenses", point.expenses)
                )
                .cornerRadius(AppRadius.xs)
                .foregroundStyle(AppColors.destructive.opacity(0.85))
                .position(by: .value("Type", "expenses"))
            }

            // Selection emphasis last — drawn on top.
            // Translucent vertical band highlighting the column, plus a stronger
            // ruler on top of the band centre.
            if let label = selectedValueLabel {
                RectangleMark(x: .value("SelBand", label))
                    .foregroundStyle(AppColors.accent.opacity(0.10))

                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(AppColors.accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXScale(domain: categoryDomain)
        .chartYScale(domain: 0...yMaxNow)
        .chartXVisibleDomain(length: visibleCount)
        .chartScrollableAxes(.horizontal)
        // Trailing anchor — see PeriodLineChart.
        .chartScrollPosition(initialX: trailingAnchorLabel)
        .chartXLabelSelectionWithFeedback($selectedValueLabel)
        .periodChartXAxis(labelMap: axisLabelMap)
        .periodChartYAxis()
        .chartLegend(.hidden)
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
