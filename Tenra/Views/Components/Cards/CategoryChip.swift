//
//  CategoryChip.swift
//  Tenra
//
//  Category tile of the category grids. Adapter over DesignKit's `ProgressRingTile`: the
//  category style lookup (CategoryStyleCache, icon/colour overrides), its budget and the
//  VoiceOver copy stay here.
//

import SwiftUI

struct CategoryChip: View {
    let category: String
    let type: TransactionType
    let customCategories: [CustomCategory]
    let isSelected: Bool
    let onTap: () -> Void

    // Budget support
    let budgetProgress: BudgetProgress?

    /// Optional icon/color override — when provided (e.g. from CategoryDisplayData),
    /// bypasses CategoryStyleCache entirely so edits to icon/color are reflected immediately.
    var iconName: String? = nil
    var iconColor: Color? = nil

    /// Optional zoom-transition source. When set, the icon ZStack becomes the
    /// matched source for `.navigationTransition(.zoom(sourceID:in:))` on the
    /// destination view — the destination zooms out of the icon circle, not
    /// the surrounding chip+totals block.
    var transitionSourceID: String? = nil
    var transitionNamespace: Namespace.ID? = nil

    // OPTIMIZATION: Use cached style data instead of recreating on every render.
    // If iconName/iconColor overrides are provided, build style data from them directly
    // (bypasses cache which may have stale data when customCategories is []).
    private var styleData: CategoryStyleData {
        if let name = iconName, let color = iconColor {
            return CategoryStyleData(
                coinColor: color.opacity(0.3),
                coinBorderColor: color.opacity(0.6),
                iconColor: color,
                primaryColor: color,
                lightBackgroundColor: color.opacity(0.15),
                iconName: name
            )
        }
        return CategoryStyleHelper.cached(category: category, type: type, customCategories: customCategories)
    }

    var body: some View {
        ProgressRingTile(
            title: category,
            systemImage: styleData.iconName,
            // The selected glass tint is this colour at 30%, which is styleData.coinColor.
            color: styleData.iconColor,
            // Budget ring for expense categories only
            progress: type == .expense ? budgetProgress.map { LimitProgress($0) } : nil,
            isSelected: isSelected,
            transitionSourceID: transitionSourceID,
            transitionNamespace: transitionNamespace,
            action: onTap
        )
        .accessibilityLabel(String(format: String(localized: "accessibility.category.label"), category))
        .accessibilityHint(budgetProgress.map {
            String(format: String(localized: "accessibility.category.budgetHint"), Int($0.percentage))
        } ?? "")
    }
}

#Preview("Category Chip") {
    VStack(spacing: 20) {
        CategoryChip(
            category: "Food",
            type: .expense,
            customCategories: [],
            isSelected: false,
            onTap: {},
            budgetProgress: nil
        )

        CategoryChip(
            category: "Food",
            type: .expense,
            customCategories: [],
            isSelected: false,
            onTap: {},
            budgetProgress: BudgetProgress(budgetAmount: 10000, spent: 5000)
        )

        CategoryChip(
            category: "Auto",
            type: .expense,
            customCategories: [],
            isSelected: false,
            onTap: {},
            budgetProgress: BudgetProgress(budgetAmount: 10000, spent: 12000)
        )
    }
    .padding()
}
