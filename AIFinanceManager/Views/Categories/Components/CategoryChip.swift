//
//  CategoryChip.swift
//  AIFinanceManager
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
        Button(action: onTap) {
            VStack(spacing: AppSpacing.sm) {
                Text(category)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                ZStack {
                    // Budget progress ring (expense categories only)
                    if let progress = budgetProgress, type == .expense {
                        BudgetProgressCircle(
                            progress: progress.percentage / 100,
                            size: AppIconSize.budgetRing,
                            lineWidth: 4,
                            isOverBudget: progress.isOverBudget
                        )
                    }
                    
                    if #available(iOS 26, *) {
                        Image(systemName: styleData.iconName)
                            .font(AppTypography.h2)
                            .foregroundStyle(styleData.iconColor)
                            .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                            .glassEffect(
                                isSelected
                                    ? .regular.tint(styleData.coinColor).interactive()
                                    : .regular.interactive(),
                                in: .circle
                            )
                    } else {
                        Circle()
                            .fill(isSelected ? styleData.coinColor.opacity(0.2) : AppColors.secondaryBackground)
                            .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                            .overlay(
                                Image(systemName: styleData.iconName)
                                    .font(AppTypography.h2)
                                    .foregroundStyle(styleData.iconColor)
                            )
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? styleData.coinBorderColor : Color.clear, lineWidth: 3)
                            )
                    }
                }
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
