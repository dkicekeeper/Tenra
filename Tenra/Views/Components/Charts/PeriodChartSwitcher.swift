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
        GlassEffectContainer(spacing: AppSpacing.sm) {
            HStack(spacing: 0) {
                Button {
                    HapticManager.light()
                    let next = max(range.lowerBound, zoomScale / step)
                    zoomScale = next
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(AppTypography.h4.weight(.medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(!canZoomOut)
                .opacity(canZoomOut ? 1.0 : 0.4)
                .accessibilityLabel(Text(verbatim: "Zoom out"))

                Button {
                    HapticManager.light()
                    let next = min(range.upperBound, zoomScale * step)
                    zoomScale = next
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(AppTypography.h4.weight(.medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(!canZoomIn)
                .opacity(canZoomIn ? 1.0 : 0.4)
                .accessibilityLabel(Text(verbatim: "Zoom in"))
            }
        }
    }
}

// MARK: - PeriodChartSwitcher

struct PeriodChartSwitcher: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var initialStyle: PeriodChartStyle = .bar

    @State private var style: PeriodChartStyle
    @State private var zoomScale: CGFloat = 1.0

    init(
        dataPoints: [PeriodDataPoint],
        currency: String,
        granularity: InsightGranularity,
        initialStyle: PeriodChartStyle = .bar
    ) {
        self.dataPoints = dataPoints
        self.currency = currency
        self.granularity = granularity
        self.initialStyle = initialStyle
        self._style = State(initialValue: initialStyle)
    }

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            controlsRow.screenPadding()

            Group {
                switch style {
                case .bar:
                    PeriodBarChart(
                        dataPoints: dataPoints,
                        currency: currency,
                        granularity: granularity,
                        zoomScale: $zoomScale
                    )
                case .line:
                    IncomeExpenseLineChart(
                        dataPoints: dataPoints,
                        currency: currency,
                        granularity: granularity,
                        zoomScale: $zoomScale
                    )
                }
            }
            .id(style)        // force fresh state (range) on style change
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
            ForEach(PeriodChartStyle.allCases) { s in
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

#Preview("Switcher — Monthly") {
    PeriodChartSwitcher(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .padding(.vertical, AppSpacing.md)
}
