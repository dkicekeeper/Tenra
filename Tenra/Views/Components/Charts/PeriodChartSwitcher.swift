//
//  PeriodChartSwitcher.swift
//  Tenra
//
//  Wraps `PeriodBarChart` and `IncomeExpenseLineChart` with a 2-segment picker
//  so the user can choose how to visualise the same income/expense series.
//
//  Use this in detail/section views where both representations make sense.
//  Compact mode (sparkline) skips the picker and renders bars only — same as
//  the previous standalone `PeriodBarChart` API.
//

import SwiftUI

enum PeriodChartStyle: String, CaseIterable, Identifiable {
    case bar
    case line

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bar:  return String(localized: "insights.chart.bar")
        case .line: return String(localized: "insights.chart.line")
        }
    }

    var systemImage: String {
        switch self {
        case .bar:  return "chart.bar"
        case .line: return "chart.xyaxis.line"
        }
    }
}

struct PeriodChartSwitcher: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full
    var initialStyle: PeriodChartStyle = .bar

    @State private var style: PeriodChartStyle

    init(
        dataPoints: [PeriodDataPoint],
        currency: String,
        granularity: InsightGranularity,
        mode: ChartDisplayMode = .full,
        initialStyle: PeriodChartStyle = .bar
    ) {
        self.dataPoints = dataPoints
        self.currency = currency
        self.granularity = granularity
        self.mode = mode
        self.initialStyle = initialStyle
        self._style = State(initialValue: initialStyle)
    }

    var body: some View {
        if mode == .compact {
            // No picker in compact sparklines — keep the cell uncluttered.
            PeriodBarChart(
                dataPoints: dataPoints,
                currency: currency,
                granularity: granularity,
                mode: .compact
            )
        } else {
            VStack(alignment: .trailing, spacing: AppSpacing.sm) {
                picker
                Group {
                    switch style {
                    case .bar:
                        PeriodBarChart(
                            dataPoints: dataPoints,
                            currency: currency,
                            granularity: granularity,
                            mode: .full
                        )
                    case .line:
                        IncomeExpenseLineChart(
                            dataPoints: dataPoints,
                            currency: currency,
                            granularity: granularity,
                            mode: .full
                        )
                    }
                }
                .id(style)        // force fresh state (zoom/range) on style change
                .transition(.opacity)
            }
            .animation(AppAnimation.gentleSpring, value: style)
        }
    }

    private var picker: some View {
        Picker("", selection: $style) {
            ForEach(PeriodChartStyle.allCases) { s in
                Label(s.label, systemImage: s.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(s)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 120)
        .accessibilityLabel(Text(verbatim: "Chart style"))
    }
}

#Preview("Switcher — Monthly") {
    PeriodChartSwitcher(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
