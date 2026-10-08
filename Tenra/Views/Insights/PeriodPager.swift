//
//  PeriodPager.swift
//  Tenra
//
//  Period paging shared by the Insights pagers: the paged category breakdown
//  (`PagedCategoryBreakdownView`) and the category drill-down (`InsightDeepDiveView`).
//  Both page with a `TabView(.page)` swipe (docs/domains/charts.md §Horizontal paging)
//  plus the chevrons centred on the page's chart; this file holds the chevrons, the
//  chart band they sit in, the empty page and the index arithmetic behind them.
//

import SwiftUI

// MARK: - Index arithmetic

/// Index math for the period pagers. Pure, so the stepping rules are unit-tested
/// without a view (`PeriodPagingTests`).
nonisolated enum PeriodPaging {
    /// `index` clamped into the pager's pages (0 for an empty pager).
    static func clamped(_ index: Int, count: Int) -> Int {
        min(max(0, index), max(0, count - 1))
    }

    /// The page `delta` steps away from `index`, or `nil` past either end.
    static func stepped(_ index: Int, by delta: Int, count: Int) -> Int? {
        let next = index + delta
        return next >= 0 && next < count ? next : nil
    }

    /// The page to show for `key`: its own page when the pager has it, else the
    /// `fallbackKey` page (the current period), else the newest page.
    static func index(of key: String?, in keys: [String], fallbackKey: String) -> Int {
        if let key, let index = keys.firstIndex(of: key) { return index }
        if let index = keys.firstIndex(of: fallbackKey) { return index }
        return max(0, keys.count - 1)
    }
}

// MARK: - Chart band

/// A period page's chart with the step arrows vertically centred on it. An empty page
/// keeps the band's height (the orb's default size) so the arrows stay put.
struct PeriodPagerChartBand<Chart: View>: View {
    @Binding private var index: Int
    private let count: Int
    private let isEmpty: Bool
    private let showsArrows: Bool
    private let chart: () -> Chart

    /// - Parameter showsArrows: `false` when there is nothing to step through
    ///   (`.allTime`, one bucket).
    init(
        index: Binding<Int>,
        count: Int,
        isEmpty: Bool,
        showsArrows: Bool = true,
        @ViewBuilder chart: @escaping () -> Chart
    ) {
        _index = index
        self.count = count
        self.isEmpty = isEmpty
        self.showsArrows = showsArrows
        self.chart = chart
    }

    /// DesignKit's `PagerArrows` (2.9.0) round the chart; the empty page keeps the orb's height.
    var body: some View {
        PagerArrows(index: $index, count: count, showsArrows: showsArrows) {
            if !isEmpty {
                chart()
            } else {
                Color.clear.frame(height: 280)
            }
        }
    }
}

// MARK: - Empty page

/// A period with nothing to show. The pager stays swipeable, so the hint says so.
struct PeriodPagerEmptyState: View {
    let title: String

    var body: some View {
        EmptyState(
            icon: "tray",
            title: title,
            description: String(localized: "insights.swipeHint")
        )
        .padding(.vertical, AppSpacing.xxl)
    }
}
