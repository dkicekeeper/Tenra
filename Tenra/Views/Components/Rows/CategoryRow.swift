//
//  CategoryRow.swift
//  AIFinanceManager
//
//  Reusable category row component for displaying categories in lists
//

import SwiftUI

struct CategoryRow: View {
    let category: CustomCategory
    let isDefault: Bool
    let budgetProgress: BudgetProgress?
    let currency: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var categoryAccessibilityLabel: String {
        var parts = [category.name]
        if let progress = budgetProgress {
            parts.append(String(format: String(localized: "accessibility.category.budgetProgress"), Int(progress.percentage)))
            if progress.isOverBudget {
                parts.append(String(localized: "accessibility.category.overBudget"))
            }
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: AppSpacing.md) {
                    // Иконка с бюджетным прогрессом
                    ZStack {
                        // Budget progress ring (if budget exists)
                        if let progress = budgetProgress {
                            BudgetProgressCircle(
                                progress: progress.percentage / 100,
                                size: AppIconSize.categoryIcon,
                                lineWidth: 3,
                                isOverBudget: progress.isOverBudget
                            )
                        }

                        // Иконка с цветом категории
                        IconView(
                            source: category.iconSource,
                            style: .circle(
                                size: AppIconSize.xxl,
                                tint: .monochrome(category.color)
                            )
                        )
                    }

                    // Название и бюджет
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(category.name)
                            .font(AppTypography.h4)

                        if let progress = budgetProgress {
                            HStack(spacing: AppSpacing.xs) {
                                HStack(spacing: 0) {
                                    FormattedAmountText(
                                        amount: progress.spent,
                                        currency: currency,
                                        fontSize: AppTypography.bodySmall,
                                        color: progress.isOverBudget ? .red : .secondary
                                    )
                                    Text(" / ")
                                        .font(AppTypography.bodySmall)
                                        .foregroundStyle(progress.isOverBudget ? .red : .secondary)
                                    FormattedAmountText(
                                        amount: progress.budgetAmount,
                                        currency: currency,
                                        fontSize: AppTypography.bodySmall,
                                        color: progress.isOverBudget ? .red : .secondary
                                    )
                                }

                                Text("(\(Int(progress.percentage))%)")
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(.secondary)
                            }
                        } else if category.type == .expense {
                            Text(String(localized: "category.noBudgetSet"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
//                .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(categoryAccessibilityLabel)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isDefault {
                Button(role: .destructive) {
                    HapticManager.warning()
                    onDelete()
                } label: {
                    Label(String(localized: "button.delete"), systemImage: "trash")
                }
            }
        }
        // Budget overflow haptic — fires when spending first crosses 100 %
        .onChange(of: budgetProgress?.isOverBudget) { _, isOver in
            if isOver == true { HapticManager.warning() }
        }
    }
}

// formatAmount больше не нужен - используем FormattedAmountText

#Preview {
    let sampleCategory = CustomCategory(
        id: "test",
        name: "Food",
        iconSource: .sfSymbol("fork.knife"),
        colorHex: "#3b82f6",
        type: .expense
    )

    List {
        CategoryRow(
            category: sampleCategory,
            isDefault: false,
            budgetProgress: nil,
            currency: "KZT",
            onEdit: {},
            onDelete: {}
        )
        .padding(.vertical, AppSpacing.xs)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
    .listStyle(PlainListStyle())
}
