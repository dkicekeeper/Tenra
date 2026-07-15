//
//  MiniHalfGauge.swift
//  Tenra
//
//  Canvas-based half-circle gauge for insight feed cards (2026-07 visual
//  refresh): a value against a NORM tick on a relative scale. Used where the
//  metric's message is "X vs its usual/target level" — category spending
//  spike, large transaction vs average bill, savings rate vs the 20% target.
//
//  Visual grammar (docs/domains/charts.md §Insight mini-visuals):
//  - gray track = the scale, tinted arc = the fact
//  - knockout dot = the norm/target marker
//  - scale = max(value × 1.15, norm × 2) so the arc always keeps headroom and
//    the norm tick never hugs an edge; for extreme outliers the story is the
//    tick sitting near the start of an almost-full arc
//
//  Unlike ProgressRing (absolute "% of limit" on a full circle), the gauge's
//  scale is RELATIVE — the always-visible track + tick keep the two readable
//  as different things. The value arc starts at the same angle as the track
//  so their round caps coincide exactly on the left — an inset start makes
//  the fill sit half a lineWidth above the track's cap.
//
//  No text inside — values live in the card's metric row (localization-free,
//  decorative for VoiceOver).
//

import SwiftUI

struct MiniHalfGauge: View {
    /// The measured value (charge amount, spike total, savings %).
    let value: Double
    /// Relative mode: the reference the tick marks (category average, avg bill,
    /// 20% target). Nil in absolute mode (no tick).
    var norm: Double? = nil
    /// Absolute mode: fixed scale end (e.g. 100 for the health score) — the
    /// mini sibling of HeroHalfGauge's absolute mode.
    var maxValue: Double? = nil
    /// Semantic tint of the value arc (severity — the generator knows).
    let color: Color

    var lineWidth: CGFloat = 9
    var height: CGFloat = 60

    /// How far the norm tick overshoots the stroke on each side.
    private static let tickOvershoot: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            // Scale: absolute (fixed maxValue) or relative (norm-anchored).
            let scale: Double = {
                if let maxValue { return max(maxValue, .leastNonzeroMagnitude) }
                if let norm { return max(value * 1.15, norm * 2) }
                return max(value * 1.15, .leastNonzeroMagnitude)
            }()
            guard scale > 0, value >= 0 else { return }

            // Geometry: semicircle bulging up, ends on the horizontal through
            // `center`. Radius leaves room for the tick overshoot on all sides
            // (120×60 slot → radius 44, apex 4pt below the top edge).
            let center = CGPoint(x: size.width / 2, y: size.height - 4)
            let radius = min(size.width / 2, size.height - 4) - Self.tickOvershoot - 4

            let fraction = min(value / scale, 1.0)

            // Track — the full relative scale.
            var track = Path()
            track.addArc(
                center: center, radius: radius,
                startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false
            )
            context.stroke(
                track,
                with: .color(AppColors.textSecondary.opacity(0.18)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            // Value arc — starts at the track's angle so both round caps
            // coincide on the left (an inset start floats the fill above the
            // track's cap).
            if value > 0 {
                let start = Angle.degrees(180)
                let end = max(Angle.degrees(180 + fraction * 180), start + .degrees(1))
                var arc = Path()
                arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                context.stroke(
                    arc,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }

            // Norm marker — knockout dot punching a gap in the arc, with an
            // arc-tinted dot inside (matches HeroHalfGauge's tick marker).
            // Absolute mode has no norm → no tick.
            guard let norm, norm > 0 else { return }
            let tickRadians = CGFloat(Angle.degrees(180 + min(norm / scale, 1.0) * 180).radians)
            let tickCenter = CGPoint(
                x: center.x + radius * cos(tickRadians),
                y: center.y + radius * sin(tickRadians)
            )
            let markerRadius = lineWidth / 2 + 3.5
            context.fill(
                Path(ellipseIn: CGRect(
                    x: tickCenter.x - markerRadius,
                    y: tickCenter.y - markerRadius,
                    width: markerRadius * 2,
                    height: markerRadius * 2
                )),
                with: .color(AppColors.bgBase)
            )
            let dotRadius = markerRadius / 3
            context.fill(
                Path(ellipseIn: CGRect(
                    x: tickCenter.x - dotRadius,
                    y: tickCenter.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )),
                with: .color(color)
            )
        }
        .frame(height: height)
    }
}

// MARK: - Previews

#Preview("Half gauge — spike 1.6× the norm") {
    MiniHalfGauge(value: 16_000, norm: 10_000, color: AppColors.warning)
        .frame(width: 120, height: 60)
        .padding()
}

#Preview("Half gauge — large tx 14× the average") {
    MiniHalfGauge(value: 140_000, norm: 10_000, color: AppColors.destructive)
        .frame(width: 120, height: 60)
        .padding()
}

#Preview("Half gauge — savings 23% vs 20% target") {
    MiniHalfGauge(value: 23, norm: 20, color: AppColors.success)
        .frame(width: 120, height: 60)
        .padding()
}

#Preview("Half gauge — below target") {
    MiniHalfGauge(value: 8, norm: 20, color: AppColors.warning)
        .frame(width: 120, height: 60)
        .padding()
}
