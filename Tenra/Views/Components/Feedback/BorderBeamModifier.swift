//
//  BorderBeamModifier.swift
//  Tenra
//
//  Animated glowing border beam effect for card highlights and focus states.
//

import SwiftUI

// MARK: - BorderBeamModifier

/// Overlays a beam of light that continuously travels around the view's border.
///
/// Two-layer render: a sharp stroke on top plus a blurred, wider copy below for the glow.
/// Driven by `TimelineView(.animation)` so it ticks only while the overlay is visible —
/// flipping `isActive` to `false` stops the work entirely (no orphan animation).
/// Respects Reduce Motion — the overlay is skipped when enabled.
struct BorderBeamModifier: ViewModifier {
    var isActive: Bool
    var colors: [Color]
    var cornerRadius: CGFloat
    var lineWidth: CGFloat
    var duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive && !reduceMotion {
                    // Display-synced redraw — at 60–120 Hz the gradient sweep
                    // looks fluid. The per-tick work is now a single
                    // un-blurred stroke; the static halo is provided by the
                    // companion `borderGlow` modifier so we no longer pay for
                    // a full-overlay Gaussian on every frame.
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: duration) / duration
                        let degrees = phase * 360

                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(beamGradient(rotation: degrees), lineWidth: lineWidth)
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    // Beam spans ~20% of the arc (0→0.20); the rest is .clear.
    // Colors are spread evenly across the central 0.04→0.14 band.
    private func beamGradient(rotation: Double) -> AngularGradient {
        let c = colors.isEmpty ? [AppColors.accent] : colors
        var stops: [Gradient.Stop] = [
            .init(color: .clear, location: 0.00),
            .init(color: c[0].opacity(0.4), location: 0.02),
        ]
        for (i, color) in c.enumerated() {
            let fraction = c.count > 1 ? Double(i) / Double(c.count - 1) : 0.5
            let loc = 0.04 + (0.14 - 0.04) * fraction
            stops.append(.init(color: color, location: loc))
        }
        stops += [
            .init(color: c.last!.opacity(0.3), location: 0.17),
            .init(color: .clear, location: 0.20),
            .init(color: .clear, location: 1.00),
        ]
        return AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center,
            angle: .degrees(rotation)
        )
    }
}

// MARK: - BorderGlowModifier

/// Static, non-animated halo around a view's border. Designed to layer with
/// `BorderBeamModifier` so the card always reads as "lit up" even before the
/// traveling beam reaches a given edge.
struct BorderGlowModifier: ViewModifier {
    var isActive: Bool
    var colors: [Color]
    var cornerRadius: CGFloat
    var lineWidth: CGFloat
    var glowRadius: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    ZStack {
                        // Outer soft halo — wider, heavily blurred.
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(gradient, lineWidth: lineWidth + 2)
                            .blur(radius: glowRadius)
                            .opacity(opacity)
                        // Inner crisp ring — anchors the glow against the card edge.
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(gradient.opacity(0.6), lineWidth: lineWidth)
                            .blur(radius: max(0, glowRadius * 0.25))
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
    }

    private var gradient: AngularGradient {
        let palette = colors.isEmpty ? [AppColors.accent] : colors
        return AngularGradient(
            gradient: Gradient(colors: palette + [palette[0]]),
            center: .center
        )
    }
}

// MARK: - View Extension

extension View {
    /// Adds an animated glowing beam that travels around this view's border.
    ///
    /// - Parameters:
    ///   - isActive: Beam runs only while `true`. When `false` the overlay is removed
    ///     and the timeline stops ticking. Default: `true`.
    ///   - colors: Beam colors from leading to trailing edge.
    ///   - cornerRadius: Match your card's corner radius. Default: `AppRadius.xl`.
    ///   - lineWidth: Stroke width of the sharp beam layer. Default: `1.5`.
    ///   - duration: Seconds for one full revolution. Default: `3.0`.
    func borderBeam(
        isActive: Bool = true,
        colors: [Color] = [AppColors.accent, .purple, .pink],
        cornerRadius: CGFloat = AppRadius.xl,
        lineWidth: CGFloat = 1.5,
        duration: Double = 3.0
    ) -> some View {
        modifier(BorderBeamModifier(
            isActive: isActive,
            colors: colors,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            duration: duration
        ))
    }

    /// Adds a static (non-animated) glowing halo around this view's border.
    /// Pairs well with `borderBeam` — the halo provides constant edge
    /// presence while the beam sweeps through.
    ///
    /// - Parameter isActive: Halo is rendered only while `true`; the overlay
    ///   is removed entirely otherwise. Default: `true`.
    func borderGlow(
        isActive: Bool = true,
        colors: [Color] = [AppColors.accent, .purple, .pink],
        cornerRadius: CGFloat = AppRadius.xl,
        lineWidth: CGFloat = 1,
        glowRadius: CGFloat = 6,
        opacity: Double = 0.55
    ) -> some View {
        modifier(BorderGlowModifier(
            isActive: isActive,
            colors: colors,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            glowRadius: glowRadius,
            opacity: opacity
        ))
    }
}

// MARK: - Preview

#Preview("Border Beam") {
    VStack(spacing: AppSpacing.xxl) {
        labeled("Beam only") {
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.bgMuted)
                .frame(height: 80)
                .borderBeam()
        }

        labeled("Glow only (static)") {
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.bgMuted)
                .frame(height: 80)
                .borderGlow()
        }

        labeled("Glow + beam (VoiceInput card)") {
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.bgMuted)
                .frame(height: 80)
                .borderGlow()
                .borderBeam()
        }

        labeled("Green/teal beam, faster") {
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.bgMuted)
                .frame(height: 80)
                .borderGlow(colors: [.green, .teal, .cyan])
                .borderBeam(colors: [.green, .teal, .cyan], duration: 2.0)
        }
    }
    .padding(AppSpacing.lg)
}

@ViewBuilder
private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
        Text(title)
            .font(AppTypography.caption)
            .foregroundStyle(.secondary)
        content()
    }
}
