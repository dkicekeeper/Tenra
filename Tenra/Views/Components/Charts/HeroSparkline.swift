//
//  HeroSparkline.swift
//  Tenra
//
//  Full-size interactive hero sibling of the feed's `MiniSparkline` (2026-07
//  visual refresh follow-up). The feed mini is Canvas (cheap in LazyVStack);
//  the hero is a real Swift Charts view — tap selection with haptic + banner,
//  same grammar as LineChart/BarChart — plus the sparkline extras the plain
//  detail charts can't express:
//  - dashed projection tail to `projectedValue`, hollow endpoint (forecast
//    grammar: dashed/hollow = not yet real)
//  - min/max extreme markers (period records — the extremes ARE the message)
//  - "you are here" dot on the last fact point
//
//  Non-scrollable: heroes show the generator-shaped series in one glance.
//  For scrollable exploration the detail's ChartSwitcher stays the tool.
//

import SwiftUI
import Charts

struct HeroSparkline: View {
    let dataPoints: [PeriodDataPoint]
    let series: PeriodChartSeries
    var projectedValue: Double? = nil
    var markExtremes: Bool = false
    /// ISO currency code for the selection banner amount.
    var currency: String = ""
    /// Extra delay before the entrance animation — pass the nav-transition
    /// duration so the chart materialises after the push settles (animating
    /// during the zoom transition made the hero visibly jump at its end).
    var entranceDelay: Double = 0

    @State private var selectedValueLabel: String?
    @State private var cache = PeriodChartCache()

    private let chartHeight: CGFloat = 220
    /// Synthetic x-category carrying the projection endpoint. Not present in
    /// `labelToIndex`, so tapping it never produces a (meaningless) selection.
    private static let projectionLabel = "→"

    private var granularity: InsightGranularity { dataPoints.first?.granularity ?? .month }

    private var values: [Double] { dataPoints.map { series.value(for: $0) } }

    /// Solid accent used for the last-point dot and projection tail. Mirrors
    /// MiniSparkline: `.cashFlow` tints by the sign of the latest value.
    private var tintColor: Color {
        switch series {
        case .spending, .avgDailyExpenses: return AppColors.destructive
        case .income:                      return AppColors.success
        case .wealth:                      return AppColors.accent
        case .cashFlow:
            return (values.last ?? 0) >= 0 ? AppColors.success : AppColors.destructive
        }
    }

    /// Padded axis domain (~6% headroom, LineChart convention) including the
    /// projection endpoint so the dashed tail never clips.
    private var yDomain: ClosedRange<Double> {
        var domainValues = values
        if let projectedValue { domainValues.append(projectedValue) }
        let raw = series.yDomain(values: domainValues)
        let headroom = (raw.upperBound - raw.lowerBound) * 0.06
        let paddedMin = raw.lowerBound < 0 ? raw.lowerBound - headroom : raw.lowerBound
        return paddedMin...(raw.upperBound + headroom)
    }

    private var selectedPoint: PeriodDataPoint? {
        guard let label = selectedValueLabel,
              let idx = cache.labelToIndex[label] else { return nil }
        return dataPoints[idx]
    }

    private func rebuildCacheIfNeeded() {
        rebuildPeriodCacheIfNeeded(cache, dataPoints: dataPoints) { p in
            [series.value(for: p)]
        }
    }

    private var axisLabelMap: [String: String] {
        ChartAxisLabelMapCache.shared.map(for: dataPoints)
    }

    // MARK: - Body

    var body: some View {
        let _ = rebuildCacheIfNeeded()
        if dataPoints.count >= 2 {
            VStack(spacing: AppSpacing.lg) {
                bannerSlot
                chart
                    .padding(.leading, AppSpacing.lg)
                    .padding(.trailing, AppSpacing.lg)
                    .frame(height: chartHeight)
            }
            .chartAppear(delay: entranceDelay)
        }
    }

    private var bannerSlot: some View {
        ZStack {
            if let p = selectedPoint {
                let v = series.value(for: p)
                ChartSelectionBanner(
                    title: granularity.bannerLabel(for: p.key),
                    currency: currency,
                    content: .single(value: v, color: series.pointColor(for: v))
                )
                .transition(.opacity)
            }
        }
        .chartBannerSlotStyle(animationKey: selectedPoint?.label)
        .chartSelectionAnnouncement(announcementText)
    }

    private var announcementText: String? {
        guard let p = selectedPoint else { return nil }
        return chartBannerAnnouncementText(
            title: granularity.bannerLabel(for: p.key),
            value: series.value(for: p),
            currency: currency
        )
    }

    // MARK: - Chart

    private var chart: some View {
        let domain = yDomain
        // Style gradients resolve against the marks' own bounds — pass the
        // UNPADDED data envelope, not the padded axis domain (charts.md rule).
        let styleEnvelope = min(cache.yMin, 0)...max(cache.yMax, 1)
        let lineFill = series.lineStyle(yDomain: styleEnvelope)
        let areaFill = series.areaStyle(yDomain: styleEnvelope)
        var categoryDomain = dataPoints.map { $0.label }
        if projectedValue != nil { categoryDomain.append(Self.projectionLabel) }
        let tint = tintColor
        let vals = values

        return Chart {
            ForEach(dataPoints) { point in
                let v = series.value(for: point)
                AreaMark(
                    x: .value("Period", point.label),
                    y: .value("Value", v),
                    series: .value("Type", "fact"),
                    stacking: .unstacked
                )
                .foregroundStyle(areaFill)
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Period", point.label),
                    y: .value("Value", v),
                    series: .value("Type", "fact")
                )
                .foregroundStyle(lineFill)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }

            if series.showZeroRuler, domain.lowerBound < 0 {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }

            // Dashed projection tail: last fact point → forecast endpoint,
            // hollow dot (not yet real).
            if let projectedValue, let last = dataPoints.last {
                LineMark(
                    x: .value("Period", last.label),
                    y: .value("Value", series.value(for: last)),
                    series: .value("Type", "projection")
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                LineMark(
                    x: .value("Period", Self.projectionLabel),
                    y: .value("Value", projectedValue),
                    series: .value("Type", "projection")
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                PointMark(
                    x: .value("Period", Self.projectionLabel),
                    y: .value("Value", projectedValue)
                )
                .symbol {
                    Circle()
                        .strokeBorder(tint, lineWidth: 2)
                        .frame(width: 11, height: 11)
                        .background(Circle().fill(AppColors.bgBase))
                }
            }

            // Extreme markers — best (max) and worst (min) of the series.
            if markExtremes,
               let maxIdx = vals.indices.max(by: { vals[$0] < vals[$1] }),
               let minIdx = vals.indices.min(by: { vals[$0] < vals[$1] }),
               maxIdx != minIdx {
                PointMark(
                    x: .value("Period", dataPoints[maxIdx].label),
                    y: .value("Value", vals[maxIdx])
                )
                .symbolSize(90)
                .foregroundStyle(AppColors.success)
                PointMark(
                    x: .value("Period", dataPoints[minIdx].label),
                    y: .value("Value", vals[minIdx])
                )
                .symbolSize(90)
                .foregroundStyle(AppColors.destructive)
            }

            // "You are here" dot on the last fact point.
            if let last = dataPoints.last {
                PointMark(
                    x: .value("Period", last.label),
                    y: .value("Value", series.value(for: last))
                )
                .symbolSize(55)
                .foregroundStyle(tint)
            }

            // Selection emphasis — drawn LAST so it renders on top; x-domain is
            // locked via chartXScale so selection marks can't reorder the axis.
            if let p = selectedPoint {
                let v = series.value(for: p)
                let pointColor = series.pointColor(for: v)
                RuleMark(x: .value("Selected", p.label))
                    .foregroundStyle(pointColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("SelectedHalo", p.label), y: .value("SelectedV", v))
                    .symbolSize(180)
                    .foregroundStyle(pointColor.opacity(0.20))
                PointMark(x: .value("SelectedInner", p.label), y: .value("SelectedV", v))
                    .symbolSize(70)
                    .foregroundStyle(pointColor)
            }
        }
        .chartXScale(domain: categoryDomain)
        .chartYScale(domain: domain)
        .chartXLabelSelectionWithFeedback($selectedValueLabel)
        .periodChartXAxis(labelMap: axisLabelMap)
        .periodChartYAxis()
        .chartLegend(.hidden)
    }
}

// MARK: - Previews

#Preview("Hero sparkline — records (extremes)") {
    HeroSparkline(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .cashFlow,
        markExtremes: true,
        currency: "KZT"
    )
}

#Preview("Hero sparkline — projection tail") {
    HeroSparkline(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .wealth,
        projectedValue: 1_250_000,
        currency: "KZT"
    )
}

#Preview("Hero sparkline — spending") {
    HeroSparkline(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .spending,
        currency: "KZT"
    )
}
