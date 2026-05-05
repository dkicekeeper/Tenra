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

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive && !AppAnimation.isReduceMotionEnabled {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: duration) / duration
                        let degrees = phase * 360

                        ZStack {
                            beamStroke(width: lineWidth + 4, blur: lineWidth * 2, opacity: 0.45, rotation: degrees)
                            beamStroke(width: lineWidth, blur: 0, opacity: 1.0, rotation: degrees)
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private func beamStroke(width: CGFloat, blur: CGFloat, opacity: Double, rotation: Double) -> some View {
        // Shape stays fixed — only the gradient rotates via its `angle:` parameter.
        // This makes the bright spot travel along the rect's perimeter instead of tilting the rect itself.
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(beamGradient(rotation: rotation), lineWidth: width)
            .blur(radius: blur)
            .opacity(opacity)
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
}

// MARK: - Preview

#Preview("Border Beam") {
    VStack(spacing: AppSpacing.xxl) {
        RoundedRectangle(cornerRadius: AppRadius.xl)
            .fill(AppColors.secondaryBackground)
            .frame(height: 80)
            .borderBeam()

        RoundedRectangle(cornerRadius: AppRadius.xl)
            .fill(AppColors.secondaryBackground)
            .frame(height: 80)
            .borderBeam(colors: [.green, .teal, .cyan], duration: 2.0)

        RoundedRectangle(cornerRadius: AppRadius.xl)
            .fill(AppColors.secondaryBackground)
            .frame(height: 80)
            .borderBeam(colors: [.orange, .yellow], lineWidth: 2.5, duration: 4.0)
    }
    .padding(AppSpacing.pageHorizontal)
}
