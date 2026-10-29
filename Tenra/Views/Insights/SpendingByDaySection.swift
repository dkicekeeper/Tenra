//
//  SpendingByDaySection.swift
//  Tenra
//
//  "By day"'s detail under its header (`spending_by_day`, InsightsService+Spending): the last
//  weeks day by day (DesignKit's CalendarHeatmap), each weekday's average (a BarChart that
//  opens on the busiest one, with the average across), the categories of the weekday picked
//  on it, and what stands out. The chart's selection drives the list, so the chart and the
//  lists are one view, rendered in InsightDetailView's chart section.
//

import SwiftUI

struct SpendingByDaySection: View {
    let detail: WeekdayPatternDetail
    let currency: String

    /// The weekday picked on the chart (its `Calendar` weekday as a string); opens on the busiest.
    @State private var selectedWeekday: String?

    init(detail: WeekdayPatternDetail, currency: String) {
        self.detail = detail
        self.currency = currency
        let busiest = detail.weekdays.indices.contains(detail.busiestIndex) ? detail.weekdays[detail.busiestIndex] : nil
        _selectedWeekday = State(initialValue: busiest.map { String($0.id) })
    }

    private static let seriesId = "average"

    private var selected: WeekdaySpending? {
        detail.weekdays.first { String($0.id) == selectedWeekday }
            ?? (detail.weekdays.indices.contains(detail.busiestIndex) ? detail.weekdays[detail.busiestIndex] : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "insights.byDay.dayByDay"), style: .large)
                CalendarHeatmap(
                    values: detail.days,
                    weeks: detail.weeks,
                    color: AppColors.destructive,
                    valueFormat: .currency(currency)
                )
            }
            .screenPadding()

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "insights.byDay.weekdaysHeader"), style: .large)
                    .screenPadding()
                // Seven bars fit the window: nothing scrolls. Charts bleed to the screen edges
                // (docs/domains/charts.md). Not a trend: the person's chart options (a ruler, the
                // average of finished periods) do not apply; the line is the average weekday.
                BarChart(
                    dataPoints: weekdayPoints,
                    series: ChartSeries<ChartValuePoint>.keyed(
                        Self.seriesId,
                        name: String(localized: "insights.byDay.weekdaysHeader"),
                        coloring: .solid(AppColors.destructive),
                        better: .lower
                    ),
                    valueFormat: .currency(currency),
                    referenceLines: averageLine,
                    selection: $selectedWeekday
                )
                .chartDisplayOptions(.constant([]))
            }

            if let selected, !selected.categories.isEmpty {
                InsightCategoryBreakdownList<EmptyView>(
                    title: String(format: String(localized: "insights.byDay.categoriesOn"), selected.onPhrase),
                    items: selected.categories,
                    currency: currency,
                    onCategoryTap: nil
                )
                .animation(AppAnimation.chartBannerFade, value: selected.id)
            }

            if !detail.patterns.isEmpty {
                InsightWeekdayPatternList(items: detail.patterns, currency: currency)
            }

            Text(String(localized: "insights.byDay.footnote"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .screenPadding()
        }
    }

    /// The average weekday across the bars.
    private var averageLine: [ChartReferenceLine] {
        guard !detail.weekdays.isEmpty else { return [] }
        let average = detail.weekdays.reduce(0) { $0 + $1.average } / Double(detail.weekdays.count)
        return [.value(average, label: String(localized: "chart.average", defaultValue: "Average"), color: AppColors.textSecondary)]
    }

    /// The weekdays as chart points: the short name on the axis, the full one in the banner.
    private var weekdayPoints: [ChartValuePoint] {
        detail.weekdays.map { weekday in
            ChartValuePoint(
                label: String(weekday.id),
                axisLabel: weekday.shortName,
                title: weekday.name,
                values: [Self.seriesId: weekday.average]
            )
        }
    }
}
