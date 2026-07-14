//
//  HeroChartEffects.swift
//  Tenra
//
//  Shared "wow" toolkit for full-size hero visuals on insight detail screens
//  (2026-07 visual refresh). Generalises OrbChart's techniques so every hero
//  speaks the same visual language:
//  - chartGlow: colour-matched blurred underlay (OrbChart's orbShadow, generalised)
//  - materialize: spring pop + sharpen-out-of-blur entrance (OrbChart's orb entry)
//  - glassBar: Liquid Glass sheen on rounded-rect marks (OrbChart's glassSphere)
//
//  Layer discipline (docs/domains/charts.md): data lives in thin crisp elements
//  (arcs, ticks, bars); wow lives in soft underlays. Blur layers are STATIC —
//  only opacity/scale/trim animate, the blur itself is never re-computed
//  per-frame. All entrances respect Reduce Motion via AppAnimation.
//

import SwiftUI

extension View {
    /// Colour-matched glow: a blurred, saturated copy of the view itself dropped
    /// below it. Because the copy IS the view, the glow automatically picks up
    /// the data's colours (and follows its trim/shape animations for free).
    func chartGlow(radius: CGFloat = 16, yOffset: CGFloat = 10, opacity: Double = 0.55) -> some View {
        background {
            blur(radius: radius)
                .saturation(2)
                .offset(y: yOffset)
                .opacity(opacity)
        }
    }

    /// OrbChart-style materialise entrance: spring "pop" while sharpening out
    /// of a blur. Instant under Reduce Motion or when `animatesOnAppear` is
    /// false (re-mounts). Stagger sibling layers via `delay`.
    func materialize(delay: Double = 0, animatesOnAppear: Bool = true) -> some View {
        modifier(MaterializeModifier(delay: delay, animatesOnAppear: animatesOnAppear))
    }

    /// Liquid Glass sheen for rounded bar marks (iOS 26+); no-op fallback earlier.
    @ViewBuilder
    func glassBar(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
        }
    }
}

private struct MaterializeModifier: ViewModifier {
    let delay: Double
    let animatesOnAppear: Bool

    @State private var entered = false
    private var immediate: Bool { !animatesOnAppear || AppAnimation.isReduceMotionEnabled }

    func body(content: Content) -> some View {
        content
            .scaleEffect(entered ? 1 : 0.9)
            .opacity(entered ? 1 : 0)
            .blur(radius: entered ? 0 : 6)
            .animation(
                immediate ? nil : .spring(response: 0.55, dampingFraction: 0.6).delay(delay),
                value: entered
            )
            .onAppear { entered = true }
    }
}
