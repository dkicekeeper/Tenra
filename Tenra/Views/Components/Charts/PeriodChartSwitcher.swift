//
//  PeriodChartSwitcher.swift
//  Tenra
//
//  Wraps `PeriodBarChart` and `IncomeExpenseLineChart` with a 2-segment picker
//  so the user can choose how to visualise the same income/expense series.
//
//  Layout (full mode):
//  ┌──────────┐               ┌────┐ ┌────┐
//  │ Bar/Line │  …            │  − │ │  + │       ← controls row
//  └──────────┘               └────┘ └────┘
//  ┌──────────────────────────────────────────┐
//  │              chart content               │
//  └──────────────────────────────────────────┘
//
//  Pinch-to-zoom is intentionally NOT used — it conflicts with the
//  navigation swipe-to-go-back gesture on the parent view.
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

// MARK: - ChartZoomControls

/// Reusable +/- zoom button pair. Used by `PeriodChartSwitcher` and `PeriodLineChart`.
struct ChartZoomControls: View {
    @Binding var zoomScale: CGFloat
    let range: ClosedRange<CGFloat>
    var step: CGFloat = 1.5

    private var canZoomIn: Bool { zoomScale < range.upperBound - 0.001 }
    private var canZoomOut: Bool { zoomScale > range.lowerBound + 0.001 }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                let next = max(range.lowerBound, zoomScale / step)
                zoomScale = next
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.glass)
            .disabled(!canZoomOut)
            .opacity(canZoomOut ? 1.0 : 0.4)
            .accessibilityLabel(Text(verbatim: "Zoom out"))

            Button {
                let next = min(range.upperBound, zoomScale * step)
                zoomScale = next
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.glass)
            .disabled(!canZoomIn)
            .opacity(canZoomIn ? 1.0 : 0.4)
            .accessibilityLabel(Text(verbatim: "Zoom in"))
        }
    }
}

// MARK: - PeriodChartSwitcher

struct PeriodChartSwitcher: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full
    var initialStyle: PeriodChartStyle = .bar

    @State private var style: PeriodChartStyle
    @State private var zoomScale: CGFloat = 1.0

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
            VStack(spacing: AppSpacing.sm) {
                controlsRow
                    .screenPadding()

                Group {
                    switch style {
                    case .bar:
                        PeriodBarChart(
                            dataPoints: dataPoints,
                            currency: currency,
                            granularity: granularity,
                            mode: .full,
                            zoomScale: $zoomScale
                        )
                    case .line:
                        IncomeExpenseLineChart(
                            dataPoints: dataPoints,
                            currency: currency,
                            granularity: granularity,
                            mode: .full,
                            zoomScale: $zoomScale
                        )
                    }
                }
                .id(style)        // force fresh state (range) on style change
                .transition(.opacity)
            }
            .animation(AppAnimation.gentleSpring, value: style)
        }
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
    .padding(.vertical, AppSpacing.md)
}
