//
//  ChartDisplayMode.swift
//  AIFinanceManager
//
//  Phase 25: Replaces `compact: Bool` across all Insights chart components.
//

/// Controls the visual fidelity of Insights chart components.
///
/// - `.compact`: 60pt sparkline — hidden axes/labels/legend. Used in `InsightsCardView`.
/// - `.full`: Full-height chart with axes, gridlines, and legend. Used in detail/section views.
enum ChartDisplayMode {
    case compact
    case full

    /// Whether axes and gridlines should be rendered.
    var showAxes: Bool   { self == .full }
    /// Whether a legend should be rendered (where applicable).
    var showLegend: Bool { self == .full }
}
