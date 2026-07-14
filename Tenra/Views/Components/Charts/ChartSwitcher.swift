//
//  ChartSwitcher.swift
//  Tenra
//
//  Wraps `LineChart` and `BarChart` with a 2-segment bar/line
//  picker + zoom controls. Both charts are multi-series capable — the
//  income/expense overlay is just `series: [.income, .spending]` (the former
//  IncomeExpense* chart family was merged into this pair, 2026-07).
//
//  Layout:
//  ┌──────────┐               ┌────┐ ┌────┐
//  │ Bar/Line │  …            │  − │ │  + │       ← controls row
//  └──────────┘               └────┘ └────┘
//  ┌──────────────────────────────────────────┐
//  │              chart content               │
//  └──────────────────────────────────────────┘
//

import SwiftUI

struct ChartSwitcher: View {
    let dataPoints: [PeriodDataPoint]
    let seriesList: [PeriodChartSeries]
    let granularity: InsightGranularity
    var currency: String = ""

    @State private var style: ChartStyle
    @State private var zoomScale: CGFloat = 1.0

    init(
        dataPoints: [PeriodDataPoint],
        series: [PeriodChartSeries],
        granularity: InsightGranularity,
        currency: String = "",
        initialStyle: ChartStyle = .line
    ) {
        self.dataPoints = dataPoints
        self.seriesList = series
        self.granularity = granularity
        self.currency = currency
        self._style = State(initialValue: initialStyle)
    }

    /// Single-series convenience.
    init(
        dataPoints: [PeriodDataPoint],
        series: PeriodChartSeries,
        granularity: InsightGranularity,
        currency: String = "",
        initialStyle: ChartStyle = .line
    ) {
        self.init(
            dataPoints: dataPoints,
            series: [series],
            granularity: granularity,
            currency: currency,
            initialStyle: initialStyle
        )
    }

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            controlsRow.screenPadding()

            Group {
                switch style {
                case .line:
                    LineChart(
                        dataPoints: dataPoints,
                        series: seriesList,
                        granularity: granularity,
                        currency: currency,
                        zoomScale: $zoomScale
                    )
                case .bar:
                    BarChart(
                        dataPoints: dataPoints,
                        series: seriesList,
                        granularity: granularity,
                        currency: currency,
                        zoomScale: $zoomScale
                    )
                }
            }
            .id(style)        // force fresh state (selection) on style change
            .transition(.opacity)
        }
        .animation(AppAnimation.gentleSpring, value: style)
    }

    // MARK: - Controls row

    private var controlsRow: some View {
        HStack(spacing: AppSpacing.md) {
            picker

            Spacer()

            ChartZoomControls(zoomScale: $zoomScale, range: 0.4...4.0)
        }
    }

    private var picker: some View {
        Picker("", selection: $style) {
            ForEach(ChartStyle.allCases) { s in
                Label(s.label, systemImage: s.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(s)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .frame(maxWidth: 120)
        .accessibilityLabel(Text(verbatim: "Chart style"))
        .onChange(of: style) { _, _ in
            HapticManager.selection()
        }
    }
}

#Preview("Trend Switcher — Cash Flow") {
    ChartSwitcher(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .cashFlow,
        granularity: .month,
        currency: "KZT"
    )
}
