//
//  CategoryGradientBackground.swift
//  Tenra
//
//  Soft blurred colour orbs as the home screen gradient background.
//  Each orb maps to a top expense category; its size and brightness are
//  proportional to that category's spend weight. Two depth layers
//  (back/front) with different blur radii create a soft parallax look.
//

import SwiftUI

private enum Orb {
    /// Opacity for gradient orbs — weight=1.0 → 0.45, weight=0.4 → 0.25.
    static func opacity(weight: CGFloat) -> Double {
        0.25 + Double(weight) * 0.20
    }

    /// Blur radius per layer. Back layer = deeper blur (farther), front = sharper (closer).
    static func blur(isBackLayer: Bool) -> CGFloat {
        isBackLayer ? 44 : 28
    }
}

/// Renders soft, heavily-blurred colour orbs that represent the user's top
/// expense categories by spend proportion.
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
/// **Performance** — the orbs are **static**. A previous version animated
/// breathing (scale) + drift (offset) via `.repeatForever`; that motion was
/// barely perceptible behind the heavy blur yet forced a per-frame
/// blur + `.screen` blend + `drawingGroup` re-rasterisation of a full-screen
/// background — the main source of Home-screen animation jank. Rendered
/// statically, the whole background composites once. Never embed inside
/// `List`/`ForEach`.
struct CategoryGradientBackground: View {

    // MARK: - Input

    /// Top expense categories with normalised weights (0.0–1.0, largest = 1.0).
    let weights: [CategoryColorWeight]
    /// Passed through to `CategoryColors.hexColor` for custom-category tints.
    let customCategories: [CustomCategory]

    // MARK: - Orb Layout

    /// Deterministic positions for each orb index so the view is stable
    /// across recompositions.
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

    // MARK: - Orb

    /// A single static colour orb.
    private struct OrbView: View {
        let color: Color
        let diameter: CGFloat
        let baseOffset: CGPoint
        let weight: CGFloat
        let isBackLayer: Bool

        var body: some View {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(Orb.opacity(weight: weight)),
                                 color.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.5
                    )
                )
                .frame(width: diameter, height: diameter)
                .offset(x: baseOffset.x, y: baseOffset.y)
                .blur(radius: Orb.blur(isBackLayer: isBackLayer))
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let base = max(w, h) * 0.85
            // 3 orbs is enough to read as a soft gradient — the 4th/5th were
            // already mostly lost behind the heavy blur.
            let items = Array(weights.prefix(3))

            // Back layer: first 2 orbs (highest weight) — larger, deeper blur.
            // Front layer: orb 3 — smaller, sharper blur.
            let backItems = Array(items.prefix(2))
            let frontItems = items.count > 2 ? Array(items.dropFirst(2)) : []

            ZStack {
                ForEach(Array(backItems.enumerated()), id: \.offset) { index, item in
                    orb(item: item, index: index, base: base, w: w, h: h, isBackLayer: true)
                }
                .blendMode(.screen)

                ForEach(Array(frontItems.enumerated()), id: \.offset) { index, item in
                    orb(item: item, index: index + 2, base: base, w: w, h: h, isBackLayer: false)
                }
                .blendMode(.screen)
            }
            .frame(width: w, height: h)
            .drawingGroup()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    /// A single static orb positioned by index.
    private func orb(
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

        return OrbView(
            color: color,
            diameter: diameter,
            baseOffset: CGPoint(x: offset.dx * w, y: offset.dy * h),
            weight: item.weight,
            isBackLayer: isBackLayer
        )
    }
}
