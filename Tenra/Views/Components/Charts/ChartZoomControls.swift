//
//  ChartZoomControls.swift
//  Tenra
//
//  Reusable +/- zoom button pair for scrollable period charts.
//  Extracted during the 2026-07 charts refactor.
//

import SwiftUI

// MARK: - ChartZoomControls

/// Reusable +/- zoom button pair. Used by `ChartSwitcher`.
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
                        .frame(width: 44, height: 44)
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
                        .frame(width: 44, height: 44)
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

// MARK: - ChartStyle

/// Bar/line rendering style shared by the chart switchers
/// (`ChartSwitcher`).
enum ChartStyle: String, CaseIterable, Identifiable {
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
