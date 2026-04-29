//
//  PeriodBarChart.swift
//  Tenra
//
//  Granularity-aware income/expense grouped bar chart.
//
//  Performance notes (after audit):
//  - X-domain is the full dataset; Y-domain is static across the entire dataset
//    so Y-axis doesn't recompute on scroll/drag.
//  - Long-press-and-drag selects a range via `chartXSelection(range:)`.
//    Single-tap selection (`chartXSelection(value:)`) is intentionally NOT used
//    because it conflicts with range selection on iOS 17/18 (range wins, single
//    never fires). Pick one, not both.
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
    var mode: ChartDisplayMode = .full

    /// External zoom binding — controlled by `PeriodChartSwitcher` toolbar.
    /// Defaults to 1.0 when the chart is used standalone (no parent toolbar).
    @Binding var zoomScale: CGFloat

    @State private var selectedRange: ClosedRange<String>?
    @State private var selectedValueLabel: String?
    @State private var visibleLeftLabel: String?

    init(
        dataPoints: [PeriodDataPoint],
        currency: String,
        granularity: InsightGranularity,
        mode: ChartDisplayMode = .full,
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.dataPoints = dataPoints
        self.currency = currency
        self.granularity = granularity
        self.mode = mode
        self._zoomScale = zoomScale
    }

    private var isCompact: Bool { mode == .compact }
    private var basePointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var effectivePointWidth: CGFloat { basePointWidth * zoomScale }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }

    /// Y max over the entire dataset (compact sparkline only).
    private var fullYMax: Double {
        dataPoints.flatMap { [$0.income, $0.expenses] }.max() ?? 1
    }

    /// Y max for the currently-visible window — recomputed when scroll position
    /// or zoom changes, so zooming into a quiet stretch doesn't squash bars.
    /// **Frozen during active range selection** so the Y axis doesn't recompute
    /// (and bars don't jump) while the user drags a selection.
    private func dynamicYMax(visibleCount: Int) -> Double {
        guard !dataPoints.isEmpty else { return fullYMax }
        if selectedRange != nil { return fullYMax }
        let leftIdx: Int
        if let label = visibleLeftLabel,
           let idx = dataPoints.firstIndex(where: { $0.label == label }) {
            leftIdx = idx
        } else {
            leftIdx = max(0, dataPoints.count - visibleCount)
        }
        let endIdx = min(dataPoints.count - 1, leftIdx + visibleCount - 1)
        let slice = dataPoints[leftIdx...endIdx]
        return slice.flatMap { [$0.income, $0.expenses] }.max() ?? 1
    }

    private var selectedSinglePoint: PeriodDataPoint? {
        guard selectionPoints.isEmpty,
              let label = selectedValueLabel else { return nil }
        return dataPoints.first { $0.label == label }
    }

    private func visibleCount(for containerWidth: CGFloat) -> Int {
        guard effectivePointWidth > 0 else { return dataPoints.count }
        let raw = Int((containerWidth / effectivePointWidth).rounded())
        return max(1, min(dataPoints.count, raw))
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

    private var axisLabelMap: [String: String] {
        ChartAxisLabelMapCache.shared.map(for: dataPoints)
    }

    // MARK: Body

    var body: some View {
        if dataPoints.isEmpty {
            emptyState.frame(height: chartHeight)
        } else if isCompact {
            sparkline
                .frame(height: chartHeight)
                .chartAppear()
        } else {
            VStack(spacing: AppSpacing.sm) {
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
            icon: "chart.bar",
            title: String(localized: "insights.empty.title"),
            description: String(localized: "insights.empty.subtitle"),
            style: .compact
        )
    }

    // MARK: - Compact sparkline

    private var sparkline: some View {
        Chart(dataPoints) { point in
            BarMark(
                x: .value("Period", point.label),
                y: .value("Income", point.income),
                width: .fixed(6)
            )
            .cornerRadius(AppRadius.xs)
            .foregroundStyle(AppColors.success.opacity(0.85))
            .position(by: .value("Type", "income"))

            BarMark(
                x: .value("Period", point.label),
                y: .value("Expenses", point.expenses),
                width: .fixed(6)
            )
            .cornerRadius(AppRadius.xs)
            .foregroundStyle(AppColors.destructive.opacity(0.85))
            .position(by: .value("Type", "expenses"))
        }
        .chartYScale(domain: 0...fullYMax)
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
        let yMaxNow = dynamicYMax(visibleCount: visibleCount)
        // Setter blocked during active range selection — see PeriodLineChart for rationale.
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
        }
        .chartYScale(domain: 0...yMaxNow)
        .chartXVisibleDomain(length: visibleCount)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: scrollBinding)
        .chartXSelection(range: $selectedRange)
        .chartXSelection(value: $selectedValueLabel)
        .chartXAxis {
            AxisMarks { value in
                // Greedy collision resolution prevents overlapping date labels
                // when zoomed in (many ticks crammed into narrow visible window).
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
        HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(axisLabelMap[point.label] ?? point.label)
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
