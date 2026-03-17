//
//  CategoryGradientBackground.swift
//  AIFinanceManager
//
//  Apple Card-style blurred colour orbs used as the gradient background
//  of TransactionsSummaryCard.  Each orb maps to one of the top expense
//  categories; its size is proportional to that category's share of total
//  spend.  The view is purely decorative and hidden from accessibility.
//

import SwiftUI

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
/// **Performance** — up to 5 blurred `Ellipse` shapes, GPU-accelerated.
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

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Base diameter: 85 % of the card's larger dimension so orbs
            // fill the card comfortably while still overlapping each other.
            let base = max(w, h) * 0.85

            ZStack {
                ForEach(Array(weights.prefix(5).enumerated()), id: \.offset) { index, item in
                    let color = CategoryColors.hexColor(
                        for: item.category,
                        opacity: 1.0,
                        customCategories: customCategories
                    )
                    // Largest category (weight ≈ 1.0) → full base size.
                    // Smaller categories → 40 %–100 % of base size.
                    let diameter = base * (0.40 + item.weight * 0.60)
                    let offset = Self.orbOffsets[index]

                    Ellipse()
                        .fill(color.opacity(0.55))
                        .frame(width: diameter, height: diameter * 0.80)
                        .offset(x: offset.dx * w, y: offset.dy * h)
                        .blur(radius: 48)
                }
            }
            // Centre the ZStack so offsets are relative to the card midpoint.
            .frame(width: w, height: h)
        }
        // Purely decorative — VoiceOver should ignore this layer entirely.
        .accessibilityHidden(true)
    }
}
