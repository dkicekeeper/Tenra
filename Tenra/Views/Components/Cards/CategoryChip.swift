//
//  CategoryChip.swift
//  Tenra
//
//  Reusable category chip/button component
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

    /// The name as the chip lays it out: one line when it is a single word or short,
    /// otherwise two lines split at the word boundary that balances them. SwiftUI
    /// breaks a word that is too wide instead of shrinking it ("Коммунальны / е")
    /// while a spare line is left; once every line is spoken for, the only way to
    /// fit is `minimumScaleFactor`, which shrinks the whole name instead.
    static func displayLines(_ name: String) -> String {
        let words = name.split(separator: " ").map(String.init)
        guard words.count > 1, name.count > 11 else { return name }
        let split = (1..<words.count).min { lhs, rhs in
            func longer(_ index: Int) -> Int {
                max(words[..<index].joined(separator: " ").count, words[index...].joined(separator: " ").count)
            }
            return longer(lhs) < longer(rhs)
        } ?? 1
        return words[..<split].joined(separator: " ") + "\n" + words[split...].joined(separator: " ")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.sm) {
                // Up to two lines with gentle scaling: chips are ~80 pt wide, and one
                // 18 pt line fit about 7 characters, so "Кафе и рестораны",
                // "Коммунальные" or "Dienstleistungen" rendered as "Каф…". A hidden
                // two-line placeholder reserves the height, so icons in a row stay
                // aligned whether a name takes one line or two. The placeholder must
                // take the full width BEFORE the name is overlaid: an overlay is
                // proposed its base view's size, and the placeholder alone is one
                // letter wide, which cut every name down to "Т…".
                Text(verbatim: "A\nA")
                    .font(AppTypography.bodySmall.weight(.semibold))
                    .lineLimit(2)
                    .hidden()
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        Text(verbatim: Self.displayLines(category))
                            .font(AppTypography.bodySmall.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.55)
                    }
                ZStack {
                    // Budget progress ring (expense categories only)
                    if let progress = budgetProgress, type == .expense {
                        ProgressRing(
                            progress: progress.percentage / 100,
                            size: AppIconSize.budgetRing,
                            lineWidth: 4,
                            isOverBudget: progress.isOverBudget,
                            animatesOnAppear: false // lazy grid — onAppear re-fires on scroll
                        )
                    }

                    Image(systemName: styleData.iconName)
                        .font(AppTypography.h2)
                        .foregroundStyle(styleData.iconColor)
                        .frame(width: AppIconSize.mega, height: AppIconSize.mega)
                        .glassEffect(
                            isSelected
                                ? .regular.tint(styleData.coinColor).interactive()
                                : .regular.interactive(),
                            in: .circle
                        )
                }
                .matchedTransitionSourceIfPresent(
                    id: transitionSourceID,
                    namespace: transitionNamespace
                )
            }
        }
        .buttonStyle(.plain) 
        .accessibilityLabel(String(format: String(localized: "accessibility.category.label"), category))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
