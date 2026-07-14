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
//  - radial tick = the norm/target marker
//  - scale = max(value × 1.15, norm × 2) so the arc always keeps headroom and
//    the norm tick never hugs an edge; for extreme outliers the story is the
//    tick sitting near the start of an almost-full arc
//
//  Unlike ProgressRing (absolute "% of limit" on a full circle), the gauge's
//  scale is RELATIVE — the always-visible track + tick keep the two readable
//  as different things. The arc start uses the ProgressRing trim-inset lesson:
//  a round cap protrudes half a lineWidth beyond the path end, so the start is
//  inset by that arc-angle to begin exactly at the left horizontal.
//
//  No text inside — values live in the card's metric row (localization-free,
//  decorative for VoiceOver).
//

import SwiftUI

struct MiniHalfGauge: View {
    /// The measured value (charge amount, spike total, savings %).
    let value: Double
    /// The reference the tick marks (category average, avg bill, 20% target).
    let norm: Double
    /// Semantic tint of the value arc (severity — the generator knows).
    let color: Color

    var lineWidth: CGFloat = 9
    var height: CGFloat = 60

    /// How far the norm tick overshoots the stroke on each side.
    private static let tickOvershoot: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            guard value > 0, norm > 0 else { return }

            // Geometry: semicircle bulging up, ends on the horizontal through
            // `center`. Radius leaves room for the tick overshoot on all sides
            // (120×60 slot → radius 44, apex 4pt below the top edge).
            let center = CGPoint(x: size.width / 2, y: size.height - 4)
            let radius = min(size.width / 2, size.height - 4) - Self.tickOvershoot - 4

            let scale = max(value * 1.15, norm * 2)
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

            // Value arc. Start is inset by the cap's angular protrusion
            // (lineWidth/2 of arc length) so the round cap begins exactly at
            // the left horizontal instead of bleeding below the scale.
            let capInset = Angle.radians(Double(lineWidth / 2 / radius))
            let start = Angle.degrees(180) + capInset
            let end = max(Angle.degrees(180 + fraction * 180), start + .degrees(1))
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            context.stroke(
                arc,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            // Norm tick — radial marker crossing the stroke.
            let tickRadians = CGFloat(Angle.degrees(180 + min(norm / scale, 1.0) * 180).radians)
            let inner = CGPoint(
                x: center.x + (radius - Self.tickOvershoot) * cos(tickRadians),
                y: center.y + (radius - Self.tickOvershoot) * sin(tickRadians)
            )
            let outer = CGPoint(
                x: center.x + (radius + Self.tickOvershoot) * cos(tickRadians),
                y: center.y + (radius + Self.tickOvershoot) * sin(tickRadians)
            )
            var tick = Path()
            tick.move(to: inner)
            tick.addLine(to: outer)
            context.stroke(
                tick,
                with: .color(AppColors.textSecondary.opacity(0.7)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
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
