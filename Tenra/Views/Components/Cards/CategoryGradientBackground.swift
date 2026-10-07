//
//  CategoryGradientBackground.swift
//  Tenra
//
//  Soft blurred colour orbs as the home screen gradient background. Each orb maps to a top
//  expense category; its size and brightness are proportional to that category's spend
//  weight. Adapter over DesignKit's `GradientOrbsBackground`: resolving the categories'
//  colours (custom categories included) stays here.
//

import SwiftUI

/// The user's top expense categories by spend proportion as `GradientOrbsBackground` orbs.
///
/// Place it *behind* the content (the home screen, the background picker's preview); the
/// orbs are static, so the background composites once. Never embed inside `List`/`ForEach`.
struct CategoryGradientBackground: View {
    /// Top expense categories with normalised weights (0.0–1.0, largest = 1.0).
    let weights: [CategoryColorWeight]
    /// Passed through to `CategoryColors.color` for custom-category tints.
    let customCategories: [CustomCategory]

    var body: some View {
        GradientOrbsBackground(
            weights.map { item in
                GradientOrbsBackground.Orb(
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
