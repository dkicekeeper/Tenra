//
//  SiriGlowView.swift
//  Tenra
//
//  Apple Intelligence–style edge glow using MeshGradient.
//  5×7 grid: more vertical rows for even side color density on tall screens.
//
//  Time-only driver (no audio amplitude) — keeps render cost predictable.
//  Renders at ~30 fps via a periodic timeline, flattens into one Metal
//  texture per frame with drawingGroup(), and uses a light blur instead
//  of the full-screen Gaussian pass that previously dominated render time.
//

import SwiftUI

struct SiriGlowView: View {

    /// Throttled redraw cadence. 30 fps is indistinguishable from 60 fps for
    /// the slow ambient motion this view shows.
    private static let frameInterval: TimeInterval = 1.0 / 30.0

    /// Blur radius. Kept small because the outer cells are already saturated
    /// color — a heavy Gaussian over a full-screen mesh was the previous hot
    /// path.
    private static let blurRadius: CGFloat = 14

    @State private var aspect: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Reduce Motion: freeze the mesh (t = 0). Full-screen ambient motion is
                // exactly the class of animation this setting exists to suppress.
                meshGlow(t: 0)
            } else {
                TimelineView(.periodic(from: .now, by: Self.frameInterval)) { timeline in
                    meshGlow(t: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.width / max(proxy.size.height, 1)
        } action: { newAspect in
            if abs(newAspect - aspect) > 0.01 {
                aspect = newAspect
            }
        }
    }

    @ViewBuilder
    private func meshGlow(t: Double) -> some View {
        let points = buildPoints(t: t, aspect: aspect)
        let colors = buildColors(t: t)

        MeshGradient(width: 5, height: 7, points: points, colors: colors)
            .blur(radius: Self.blurRadius)
            .opacity(0.9)
            .drawingGroup()
            .allowsHitTesting(false)
    }

    // MARK: - Colors: 5×7 = 35 colors

    private func buildColors(t: Double) -> [Color] {
        func hue(phase: Double) -> Color {
            let slow = t * 0.18 + phase
            let r = 0.55 + 0.45 * sin(slow)
            let g = 0.35 + 0.35 * sin(slow * 1.3 + 2.1)
            let b = 0.55 + 0.45 * sin(slow * 0.7 + 4.2)
            return Color(red: r, green: g, blue: b)
        }

        // Slow time-driven breathing replaces the old amplitude-driven side alpha.
        let sa = 0.55 + 0.25 * sin(t * 0.6)

        return [
            // Row 0 — top edge
            hue(phase: 0.0), hue(phase: 1.5), hue(phase: 3.0), hue(phase: 4.5), hue(phase: 6.0),
            // Row 1 — near-top
            hue(phase: 13.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 7.0).opacity(sa),
            // Row 2 — upper-mid
            hue(phase: 12.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 8.0).opacity(sa),
            // Row 3 — center
            hue(phase: 11.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 9.0).opacity(sa),
            // Row 4 — lower-mid
            hue(phase: 10.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 10.0).opacity(sa),
            // Row 5 — near-bottom
            hue(phase: 9.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 11.0).opacity(sa),
            // Row 6 — bottom edge
            hue(phase: 6.5), hue(phase: 8.0), hue(phase: 9.5), hue(phase: 11.0), hue(phase: 12.5),
        ]
    }

    // MARK: - Points: 5×7 grid, aspect-corrected

    private func buildPoints(t: Double, aspect: Double) -> [SIMD2<Float>] {
        // Fixed glow fraction now that amplitude no longer modulates it.
        let glowFraction = 0.18

        let insetX = Float(glowFraction)
        let insetY = Float(glowFraction * min(aspect, 1.0))

        // 5 columns
        let colX: [Float] = [0.0, insetX, 0.5, 1.0 - insetX, 1.0]

        // 7 rows: outer edges + 5 inner rows evenly spaced.
        let innerSpan = 1.0 - 2.0 * Double(insetY)
        var rowY: [Float] = [0.0]
        rowY.append(insetY)
        for i in 1...3 {
            rowY.append(Float(Double(insetY) + innerSpan * Double(i) / 4.0))
        }
        rowY.append(1.0 - insetY)
        rowY.append(1.0)

        let rows = 7
        let cols = 5
        var pts = [SIMD2<Float>](repeating: .zero, count: rows * cols)

        // Inner-cell wobble range. No more amplitude² boost — purely time-driven.
        let range = 0.05

        for row in 0..<rows {
            for col in 0..<cols {
                let idx = row * cols + col
                let isOuterRow = (row == 0 || row == rows - 1)
                let isOuterCol = (col == 0 || col == cols - 1)

                let x = Double(colX[col])
                let y = Double(rowY[row])

                if isOuterRow || isOuterCol {
                    pts[idx] = SIMD2<Float>(Float(x), Float(y))
                } else {
                    let seed = Double(idx) * 1.7
                    let s1 = 0.3 + seed.truncatingRemainder(dividingBy: 0.4)
                    let s2 = 0.25 + (seed * 1.3).truncatingRemainder(dividingBy: 0.35)

                    let px = x + sin(t * s1 + seed) * range
                    let py = y + cos(t * s2 + seed * 1.4) * range
                    pts[idx] = SIMD2<Float>(Float(px), Float(py))
                }
            }
        }

        return pts
    }
}

#Preview("Siri Glow") {
    ZStack {
        Color.white
        Text("Siri Glow").font(.title2)
    }
    .overlay { SiriGlowView().ignoresSafeArea() }
}
