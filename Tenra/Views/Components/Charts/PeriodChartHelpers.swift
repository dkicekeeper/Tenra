//
//  PeriodChartHelpers.swift
//  Tenra
//
//  Shared infrastructure for `PeriodDataPoint`-driven full-mode charts
//  (`PeriodBarChart`, `IncomeExpenseLineChart`, `PeriodLineChart`):
//
//  - `PeriodChartCache`: per-instance derived-value cache (label→index map,
//    yMin/yMax envelope, today-marker label) keyed off a dataset identity
//    fingerprint. Stays in `@State` so the same instance survives body re-evals.
//  - `rebuildPeriodCacheIfNeeded(_:dataPoints:values:)`: single O(N) pass that
//    rebuilds all derived values when the dataset identity changes. Cheap to
//    call on every body eval — when nothing changed, only the identity compare
//    runs.
//  - `View.periodChartXAxis(labelMap:)`, `View.periodChartYAxis()`: shared
//    axis builders. The X axis applies greedy collision resolution and looks
//    up display labels via the cached `labelMap`. The Y axis renders compact
//    amounts on the leading edge.
//  - `View.chartXLabelSelectionWithFeedback(_:)`: bundles `chartXSelection` +
//    a haptic on selection change. Routes through `HapticManager.selection()`
//    so the design-system entry point is consistent with the rest of the app.
//  - `View.chartBannerSlotStyle(animationKey:)`: fixed-height slot styling
//    for the selection banner so the chart layout doesn't shift.
//

import SwiftUI
import Charts

// MARK: - Cache

/// Per-chart-instance cache of values derived from `dataPoints`. Lives inside
/// `@State` as a class so the same instance survives body re-evals; mutating
/// its stored fields is safe because SwiftUI tracks reference identity, not
/// internal class state. Rebuilt only when the dataset identity changes.
@MainActor
final class PeriodChartCache {
    /// Maps `PeriodDataPoint.label` → index in `dataPoints`. O(1) lookup for
    /// tap selection (avoids `firstIndex(where:)` which fired on every frame
    /// during scroll).
    var labelToIndex: [String: Int] = [:]

    /// First label whose `periodStart` is in the future. Used to render the
    /// "today" marker. Nil if all data is in the past.
    var todayLabel: String?

    /// Smallest accumulated value across the dataset. For income/expense
    /// charts this is always 0 (signed series can be negative).
    var yMin: Double = 0

    /// Largest accumulated value across the dataset. Charts derive their
    /// own visible domain from this.
    var yMax: Double = 1

    /// Identity fingerprint of the last dataset processed.
    /// `rebuildPeriodCacheIfNeeded` short-circuits when this matches.
    var identity: String = ""
}

/// Cheap dataset fingerprint — count + first/last label. Stable as long as
/// the dataset's outer shape doesn't change, which is the only thing the
/// caches care about.
func periodCacheIdentity(_ dataPoints: [PeriodDataPoint]) -> String {
    guard let first = dataPoints.first, let last = dataPoints.last else { return "" }
    return "\(dataPoints.count)|\(first.label)|\(last.label)"
}

/// Rebuilds the derived caches in a single O(N) pass when the dataset
/// identity has changed. No-op otherwise.
///
/// `values(_:)` returns the per-point values to fold into the yMin/yMax
/// envelope. For `PeriodBarChart` and `IncomeExpenseLineChart` this is
/// `[income, expenses]`; for `PeriodLineChart` it's the single series value.
@MainActor
func rebuildPeriodCacheIfNeeded(
    _ cache: PeriodChartCache,
    dataPoints: [PeriodDataPoint],
    values: (PeriodDataPoint) -> [Double]
) {
    let identity = periodCacheIdentity(dataPoints)
    guard cache.identity != identity else { return }

    var map = [String: Int]()
    map.reserveCapacity(dataPoints.count)
    var minY = Double.infinity
    var maxY = -Double.infinity
    let now = Date()
    var todayLabel: String?

    for (i, p) in dataPoints.enumerated() {
        map[p.label] = i
        if todayLabel == nil, p.periodStart > now { todayLabel = p.label }
        for v in values(p) {
            if v < minY { minY = v }
            if v > maxY { maxY = v }
        }
    }

    cache.labelToIndex = map
    cache.todayLabel = todayLabel
    cache.yMin = minY.isFinite ? minY : 0
    cache.yMax = maxY.isFinite ? maxY : 1
    cache.identity = identity
}

// MARK: - Axis builders

extension View {
    /// Shared X-axis for `PeriodDataPoint` charts. Greedy collision resolution
    /// prevents overlapping date labels when zoomed in. Display strings come
    /// from `labelMap` (typically `ChartAxisLabelMapCache.shared.map(for:)`).
    func periodChartXAxis(labelMap: [String: String]) -> some View {
        chartXAxis {
            AxisMarks { value in
                AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 6)) {
                    if let label = value.as(String.self) {
                        Text(labelMap[label] ?? label)
                            .font(AppTypography.caption2)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// Shared Y-axis for `PeriodDataPoint` charts: leading position with grid
    /// lines and compact amount labels.
    func periodChartYAxis() -> some View {
        chartYAxis {
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
    }
}

// MARK: - Selection + banner

extension View {
    /// Bundles `chartXSelection(value:)` with a haptic firing on selection
    /// change. Routes through `HapticManager.selection()` so the haptic stays
    /// consistent with the rest of the app's design system.
    func chartXLabelSelectionWithFeedback(
        _ binding: Binding<String?>
    ) -> some View {
        chartXSelection(value: binding)
            .onChange(of: binding.wrappedValue) { _, new in
                guard new != nil else { return }
                HapticManager.selection()
            }
    }

    /// Fixed-height slot styling for the chart selection banner. Keeps the
    /// chart layout stable when the banner appears/disappears, applies the
    /// shared fade animation token, and adds horizontal screen padding.
    func chartBannerSlotStyle(animationKey: AnyHashable?) -> some View {
        frame(height: 56)
            .screenPadding()
            .animation(AppAnimation.chartBannerFade, value: animationKey)
    }

    /// Posts a VoiceOver announcement whenever `text` changes to a non-empty
    /// value. Mirrors the visual selection banner for users who rely on
    /// VoiceOver — the banner appears for sighted users; this fires the
    /// announcement so screen-reader users hear the selected period and values.
    func chartSelectionAnnouncement(_ text: String?) -> some View {
        onChange(of: text) { _, new in
            guard let new, !new.isEmpty else { return }
            AccessibilityNotification.Announcement(new).post()
        }
    }
}

// MARK: - Announcement text helpers

/// Builds the VoiceOver announcement string for an income/expense banner.
@MainActor
func chartBannerAnnouncementText(
    title: String,
    income: Double,
    expenses: Double,
    currency: String
) -> String {
    let incomeStr = AmountFormatter.format(Decimal(income))
    let expensesStr = AmountFormatter.format(Decimal(expenses))
    let incomeLabel = String(localized: "insights.income")
    let expensesLabel = String(localized: "insights.expenses")
    let suffix = currency.isEmpty ? "" : " \(currency)"
    return "\(title). \(incomeLabel): \(incomeStr)\(suffix). \(expensesLabel): \(expensesStr)\(suffix)."
}

/// Builds the VoiceOver announcement string for a single-value banner.
@MainActor
func chartBannerAnnouncementText(
    title: String,
    value: Double,
    currency: String
) -> String {
    let valueStr = AmountFormatter.format(Decimal(value))
    let suffix = currency.isEmpty ? "" : " \(currency)"
    return "\(title). \(valueStr)\(suffix)."
}
