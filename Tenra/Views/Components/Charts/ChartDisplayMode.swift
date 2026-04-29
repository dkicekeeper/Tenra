//
//  ChartDisplayMode.swift
//  Tenra
//
//  Phase 25: Replaces `compact: Bool` across all Insights chart components.
//

/// Controls the visual fidelity of Insights chart components.
///
/// - `.compact`: 60pt sparkline — hidden axes/labels. Used in `InsightsCardView`.
/// - `.full`: Full-height chart with axes and gridlines. Used in detail/section views.
enum ChartDisplayMode {
    case compact
    case full

    /// Whether axes and gridlines should be rendered.
    var showAxes: Bool { self == .full }
}
