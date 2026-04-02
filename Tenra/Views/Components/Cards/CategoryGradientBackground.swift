//
//  CategoryGradientBackground.swift
//  AIFinanceManager
//
//  Animated blurred colour orbs as the home screen gradient background.
//  Each orb maps to a top expense category; its size, brightness, and
//  breathing speed are proportional to that category's spend weight.
//  Two depth layers (back/front) with different blur radii create
//  a lava-lamp parallax effect.  Reduce Motion → static fallback.
//

import SwiftUI

/// Renders soft, heavily-blurred colour orbs that represent the user's top
/// expense categories by spend proportion.  Orbs breathe (scale) and drift
/// (position) at weight-dependent speeds across two depth layers.
///
/// **Usage** — place this view *behind* a glass card layer:
/// ```swift
/// ZStack {
///     CategoryGradientBackground(weights: weights, customCategories: cats)
///         .clipShape(.rect(cornerRadius: AppRadius.xl))
///     contentView
///         .cardStyle()   // glassEffect sits on top, picks up orb colours
/// }
/// ```
///
/// **Performance** — up to 5 blurred orbs, GPU-accelerated via `drawingGroup()`.
/// Animations are declarative (`.repeatForever`) so `body` is never re-invoked.
/// Never embed inside `List`/`ForEach`.
struct CategoryGradientBackground: View {

    // MARK: - Input

    /// Top expense categories with normalised weights (0.0–1.0, largest = 1.0).
    let weights: [CategoryColorWeight]
    /// Passed through to `CategoryColors.hexColor` for custom-category tints.
    let customCategories: [CustomCategory]

    // MARK: - Orb Layout

    /// Deterministic positions for each orb index so the view is stable
    /// across recompositions and never triggers spurious animations.
    ///
    /// Values are fractional offsets relative to the view's width/height:
    /// `(dx, dy)` where ±0.5 puts the orb centre at the card edge.
    private static let orbOffsets: [(dx: CGFloat, dy: CGFloat)] = [
        (-0.18,  0.08),  // 0 – dominant: left-centre
        ( 0.22, -0.22),  // 1 – top-right
        ( 0.05,  0.28),  // 2 – bottom-centre
        ( 0.28,  0.12),  // 3 – right-mid
        (-0.24, -0.18),  // 4 – top-left
    ]

    // MARK: - Animated Orb

    /// A single animated orb that manages its own breathing and drift state.
    /// Each orb is a separate sub-view so `@State` is per-orb, not per-array.
    private struct AnimatedOrbView: View {
        let color: Color
        let diameter: CGFloat
        let baseOffset: CGPoint
        let weight: CGFloat
        let index: Int
        let isBackLayer: Bool

        @State private var isBreathing = false
        @State private var isDrifting = false

        /// Deterministic drift targets per orb index — ensures each orb
        /// drifts in a unique direction. Values are fractional of driftRadius.
        private static let driftDirections: [(dx: CGFloat, dy: CGFloat)] = [
            ( 1.0,  0.6),   // 0
            (-0.7,  1.0),   // 1
            ( 0.5, -0.9),   // 2
            (-1.0,  0.3),   // 3
            ( 0.8, -0.7),   // 4
        ]

        var body: some View {
            let breathScale = isBreathing
                ? AppAnimation.orbBreathScale(weight: weight)
                : 1.0
            let driftR = AppAnimation.orbDriftRadius(isBackLayer: isBackLayer)
            let dir = Self.driftDirections[index % Self.driftDirections.count]
            let driftX = isDrifting ? dir.dx * driftR : 0
            let driftY = isDrifting ? dir.dy * driftR : 0

            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(AppAnimation.orbOpacity(weight: weight)),
                                 color.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.5
                    )
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(breathScale)
                .offset(
                    x: baseOffset.x + driftX,
                    y: baseOffset.y + driftY
                )
                .blur(radius: AppAnimation.orbBlur(isBackLayer: isBackLayer))
                .onAppear {
                    withAnimation(AppAnimation.orbBreathAnimation(weight: weight)) {
                        isBreathing = true
                    }
                    withAnimation(AppAnimation.orbDriftAnimation(index: index)) {
                        isDrifting = true
                    }
                }
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let base = max(w, h) * 0.85
            let items = Array(weights.prefix(5))

            // Back layer: first 2 orbs (highest weight) — larger, slower, deeper blur.
            // Front layer: orbs 3-5 — smaller, faster drift, sharper blur.
            let backItems = Array(items.prefix(2))
            let frontItems = items.count > 2 ? Array(items.dropFirst(2)) : []

            ZStack {
                if AppAnimation.isReduceMotionEnabled {
                    // Static fallback — identical to original implementation.
                    staticOrbs(items: items, base: base, w: w, h: h)
                } else {
                    // Back layer
                    ForEach(Array(backItems.enumerated()), id: \.offset) { index, item in
                        animatedOrb(
                            item: item, index: index, base: base,
                            w: w, h: h, isBackLayer: true
                        )
                    }
                    .blendMode(.screen)

                    // Front layer
                    ForEach(Array(frontItems.enumerated()), id: \.offset) { index, item in
                        animatedOrb(
                            item: item, index: index + 2, base: base,
                            w: w, h: h, isBackLayer: false
                        )
                    }
                    .blendMode(.screen)
                }
            }
            .frame(width: w, height: h)
            .drawingGroup()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    /// Animated orb using the AnimatedOrbView sub-view.
    private func animatedOrb(
        item: CategoryColorWeight,
        index: Int,
        base: CGFloat,
        w: CGFloat,
        h: CGFloat,
        isBackLayer: Bool
    ) -> some View {
        let color = CategoryColors.hexColor(
            for: item.category,
            opacity: 1.0,
            customCategories: customCategories
        )
        let diameter = base * (0.40 + item.weight * 0.60)
        let offset = Self.orbOffsets[index]

        return AnimatedOrbView(
            color: color,
            diameter: diameter,
            baseOffset: CGPoint(x: offset.dx * w, y: offset.dy * h),
            weight: item.weight,
            index: index,
            isBackLayer: isBackLayer
        )
    }

    /// Static orbs for Reduce Motion — preserves original rendering.
    private func staticOrbs(
        items: [CategoryColorWeight],
        base: CGFloat,
        w: CGFloat,
        h: CGFloat
    ) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            let color = CategoryColors.hexColor(
                for: item.category,
                opacity: 1.0,
                customCategories: customCategories
            )
            let diameter = base * (0.40 + item.weight * 0.60)
            let offset = Self.orbOffsets[index]

            Ellipse()
                .fill(color.opacity(0.55))
                .frame(width: diameter, height: diameter * 0.80)
                .offset(x: offset.dx * w, y: offset.dy * h)
                .blur(radius: 48)
        }
    }
}
