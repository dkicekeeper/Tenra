//
//  HeroHalfGauge.swift
//  Tenra
//
//  Full-size half-circle gauge for insight detail screens (2026-07 visual
//  refresh) — the hero sibling of the feed's MiniHalfGauge, sharing its
//  geometry rules (relative scale, norm marker, cap-aligned arc start)
//  and adding the OrbChart-derived wow layer: colour-matched glow underlay,
//  spring sweep-in, materialising tick markers.
//
//  Two scale modes:
//  - relative (norm != nil): scale = max(value × 1.15, norm × 2), radial norm tick
//  - absolute (maxValue != nil): 0…maxValue, optional zone ticks (health 40/70)
//
//  Text-free — the detail header / hero card carries the numbers. Callers can
//  overlay center content into the semicircle's interior (health score).
//

import SwiftUI

struct HeroHalfGauge: View {
    /// The measured value.
    let value: Double
    /// Relative mode: the reference the norm tick marks.
    var norm: Double? = nil
    /// Absolute mode: fixed scale end (e.g. 100 for the health score).
    var maxValue: Double? = nil
    /// Absolute-mode zone boundaries (e.g. [40, 70]) — knockout dot markers.
    var zoneTicks: [Double] = []
    /// Semantic tint of the value arc.
    let color: Color

    var diameter: CGFloat = 240
    var lineWidth: CGFloat = 18
    /// Replay guard for re-mounts; also disables the sweep under Reduce Motion.
    var animatesOnAppear: Bool = true

    @State private var displayFraction: Double = 0
    private var fillAnimation: Animation? { AppAnimation.progressFillAnimation }

    private static let tickOvershoot: CGFloat = 8

    private var scale: Double {
        if let maxValue { return max(maxValue, .leastNonzeroMagnitude) }
        if let norm { return max(value * 1.15, norm * 2) }
        return max(value * 1.15, .leastNonzeroMagnitude)
    }

    private var targetFraction: Double { min(max(value / scale, 0), 1) }

    var body: some View {
        ZStack {
            // Track — the full scale.
            halfArc(from: 0, to: 0.5)
                .stroke(
                    AppColors.textSecondary.opacity(0.15),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Value arc + colour-matched glow (the glow is a blurred copy of the
            // arc itself, so it sweeps in together with the trim animation).
            // Starts at 0 like the track so both round caps coincide exactly —
            // an inset start makes the fill sit half a lineWidth above the
            // track's cap on the left.
            halfArc(from: 0, to: 0.5 * displayFraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .chartGlow(radius: lineWidth * 1.1, yOffset: 8)

            // Zone boundaries (absolute mode) — land staggered after the sweep.
            ForEach(zoneTicks.indices, id: \.self) { i in
                tickMarker(at: zoneTicks[i] / scale)
                    .materialize(delay: 0.55 + Double(i) * 0.1, animatesOnAppear: animatesOnAppear)
            }

            // Norm marker (relative mode) — lands after the sweep.
            if let norm {
                tickMarker(at: norm / scale)
                    .materialize(delay: 0.55, animatesOnAppear: animatesOnAppear)
            }
        }
        .frame(width: diameter, height: diameter)
        // The semicircle only occupies the square's top half (plus cap/tick
        // overshoot below the equator) — trim the layout to it.
        .frame(
            width: diameter + Self.tickOvershoot * 2,
            height: diameter / 2 + lineWidth / 2 + Self.tickOvershoot,
            alignment: .top
        )
        .onAppear {
            if animatesOnAppear {
                withAnimation(fillAnimation) { displayFraction = targetFraction }
            } else {
                displayFraction = targetFraction
            }
        }
        .onChange(of: value) { _, _ in
            withAnimation(fillAnimation) { displayFraction = targetFraction }
        }
    }

    /// Fractions 0…0.5 map left → top → right over the square's top half.
    private func halfArc(from: CGFloat, to: CGFloat) -> some Shape {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: from, to: max(to, from))
            .rotation(.degrees(180))
    }

    /// Knockout dot marker centred on the stroke at `fraction` (0 = left,
    /// 1 = right) — a background-coloured disc punching a gap in the arc,
    /// with an arc-tinted dot inside (Activity-ring-style marker).
    private func tickMarker(at fraction: Double) -> some View {
        let clamped = min(max(fraction, 0), 1)
        let radius = diameter / 2 - lineWidth / 2
        let markerDiameter = lineWidth + 12
        return ZStack {
            Circle()
                .fill(AppColors.bgBase)
            Circle()
                .fill(color)
                .frame(width: markerDiameter / 3, height: markerDiameter / 3)
        }
        .frame(width: markerDiameter, height: markerDiameter)
        .offset(y: -radius)
        .rotationEffect(.degrees(-90 + clamped * 180))
    }
}

// MARK: - Previews

#Preview("Hero gauge — spike vs norm") {
    HeroHalfGauge(value: 16_000, norm: 10_000, color: AppColors.warning)
        .padding()
}

#Preview("Hero gauge — savings 23% vs 20%") {
    HeroHalfGauge(value: 23, norm: 20, color: AppColors.success)
        .padding()
}

#Preview("Hero gauge — health 68/100 with zones") {
    HeroHalfGauge(value: 68, maxValue: 100, zoneTicks: [40, 70], color: AppColors.warning)
        .padding()
}
