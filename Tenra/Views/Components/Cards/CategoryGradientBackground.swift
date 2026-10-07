//
//  CategoryGradientBackground.swift
//  Tenra
//
//  The home screen's background: soft pools of colour, one per top expense category, each
//  sized and brightened by that category's share of spending. Adapter over DesignKit's
//  `AuroraBackground(_ spots:)` (a still mesh, no blur; it replaced the blurred
//  `GradientOrbsBackground` in DesignKit 2.5.0): resolving the categories' colours (custom
//  categories included) stays here.
//

import SwiftUI

/// The user's top expense categories by spend proportion as `AuroraBackground` spots.
///
/// Place it *behind* the content (the home screen, the background picker's preview). It is
/// still, so the glass cards over it never redraw for it; a change of weights flows in 0.6 s.
/// Never embed inside `List`/`ForEach`.
struct CategoryGradientBackground: View {
    /// Top expense categories with normalised weights (0.0–1.0, largest = 1.0).
    let weights: [CategoryColorWeight]
    /// Passed through to `CategoryColors.color` for custom-category tints.
    let customCategories: [CustomCategory]

    var body: some View {
        AuroraBackground(
            weights.map { item in
                AuroraBackground.Spot(
                    color: CategoryColors.color(
                        for: item.category,
                        opacity: 1.0,
                        customCategories: customCategories
                    ),
                    weight: item.weight
                )
            }
        )
    }
}
