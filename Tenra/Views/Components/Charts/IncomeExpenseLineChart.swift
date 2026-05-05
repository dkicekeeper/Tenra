//
//  IncomeExpenseLineChart.swift
//  Tenra
//
//  Two-line area chart that overlays income (green) and expenses (red) on the
//  same `PeriodDataPoint` series. Companion to `PeriodBarChart`.
//
//  Performance notes (after audit): see PeriodBarChart.swift header.
//  Same rules: static Y, range-only selection, hot-path body kept lean.
//

import SwiftUI
import Charts

struct IncomeExpenseLineChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity

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
    private let lineWidth: CGFloat = 2

    private var fullYMax: Double { cache.yMax }

    private var selectedSinglePoint: PeriodDataPoint? {
        guard let label = selectedValueLabel,
              let idx = cache.labelToIndex[label] else { return nil }
        return dataPoints[idx]
    }

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
            icon: "chart.xyaxis.line",
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
                // Both `series:` AND `stacking: .unstacked` are required:
                //   • `series:` ensures Apple Charts treats income and expenses as
                //     two distinct lines/areas (without it, alternating x-values
                //     would merge into a single zig-zag).
                //   • `stacking: .unstacked` keeps each area baseline at y=0 instead
                //     of stacking expense on top of income (which would inflate
                //     the visible expense area beyond its actual value).
                AreaMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.income),
                    series: .value("Type", "income"),
                    stacking: .unstacked
                )
                .foregroundStyle(LinearGradient(
                    colors: [AppColors.success.opacity(0.25), AppColors.success.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.income),
                    series: .value("Type", "income")
                )
                .foregroundStyle(AppColors.success)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth))

                PointMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.income)
                )
                .foregroundStyle(AppColors.success)
                .symbolSize(28)

                AreaMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.expenses),
                    series: .value("Type", "expenses"),
                    stacking: .unstacked
                )
                .foregroundStyle(LinearGradient(
                    colors: [AppColors.destructive.opacity(0.25), AppColors.destructive.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.expenses),
                    series: .value("Type", "expenses")
                )
                .foregroundStyle(AppColors.destructive)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth))

                PointMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.expenses)
                )
                .foregroundStyle(AppColors.destructive)
                .symbolSize(28)
            }

            // Selection emphasis last. Two-series chart so we highlight BOTH the
            // income and expense points at the selected x. Halos are skipped
            // when a value is 0 — drawing a tinted halo at the baseline reads
            // as visual noise (no actual data point).
            if let label = selectedValueLabel,
               let idx = cache.labelToIndex[label] {
                let p = dataPoints[idx]

                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(AppColors.accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                if p.income > 0 {
                    PointMark(x: .value("SelHaloIn", p.label), y: .value("V", p.income))
                        .symbolSize(180)
                        .foregroundStyle(AppColors.success.opacity(0.20))
                    PointMark(x: .value("SelInnerIn", p.label), y: .value("V", p.income))
                        .symbolSize(70)
                        .foregroundStyle(AppColors.success)
                }

                if p.expenses > 0 {
                    PointMark(x: .value("SelHaloEx", p.label), y: .value("V", p.expenses))
                        .symbolSize(180)
                        .foregroundStyle(AppColors.destructive.opacity(0.20))
                    PointMark(x: .value("SelInnerEx", p.label), y: .value("V", p.expenses))
                        .symbolSize(70)
                        .foregroundStyle(AppColors.destructive)
                }
            }
        }
        .chartXScale(domain: categoryDomain)
        .chartYScale(domain: 0...yMaxNow)
        .chartXVisibleDomain(length: visibleCount)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(initialX: trailingAnchorLabel)
        .chartXLabelSelectionWithFeedback($selectedValueLabel)
        .periodChartXAxis(labelMap: axisLabelMap)
        .periodChartYAxis()
        .chartLegend(.hidden)
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
