//
//  CategoryStyleHelper.swift
//  AIFinanceManager
//
//  Utility для консистентного получения цветов и иконок категорий
//  Устраняет дублирование логики из AccountActionView, QuickAddTransactionView, HistoryView
//

import SwiftUI

/// Централизованная логика для стилизации категорий
struct CategoryStyleHelper {
    let category: String
    let type: TransactionType
    let customCategories: [CustomCategory]

    // MARK: - Color Getters with Opacity Variants

    /// Цвет фона "монеты" категории (30% opacity)
    var coinColor: Color {
        if type == .income {
            return AppColors.income.opacity(0.3)
        }
        return CategoryColors.hexColor(for: category, opacity: 0.3, customCategories: customCategories)
    }

    /// Цвет границы "монеты" категории (60% opacity)
    var coinBorderColor: Color {
        if type == .income {
            return AppColors.income.opacity(0.6)
        }
        return CategoryColors.hexColor(for: category, opacity: 0.6, customCategories: customCategories)
    }

    /// Цвет иконки категории (100% opacity)
    var iconColor: Color {
        if type == .income {
            return AppColors.income
        }
        return CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: customCategories)
    }

    /// Основной цвет категории (100% opacity) - для текста и акцентов
    var primaryColor: Color {
        if type == .income {
            return AppColors.income
        }
        return CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: customCategories)
    }

    /// Светлый фоновый цвет (15% opacity) - для card backgrounds
    var lightBackgroundColor: Color {
        if type == .income {
            return AppColors.income.opacity(0.15)
        }
        return CategoryColors.hexColor(for: category, opacity: 0.15, customCategories: customCategories)
    }

    // MARK: - Icon Name

    /// Имя иконки SF Symbol для категории
    var iconName: String {
        CategoryIcon.iconName(for: category, type: type, customCategories: customCategories)
    }

    // MARK: - Convenience Initializers

    /// Создать helper из транзакции
    static func from(transaction: Transaction, customCategories: [CustomCategory]) -> CategoryStyleHelper {
        CategoryStyleHelper(
            category: transaction.category,
            type: transaction.type,
            customCategories: customCategories
        )
    }

    // MARK: - Static Helpers for Quick Access

    /// Быстрый доступ к цвету категории без создания helper
    static func color(for category: String, type: TransactionType, opacity: Double = 1.0, customCategories: [CustomCategory]) -> Color {
        if type == .income {
            return AppColors.income.opacity(opacity)
        }
        return CategoryColors.hexColor(for: category, opacity: opacity, customCategories: customCategories)
    }

    /// Быстрый доступ к иконке категории без создания helper
    static func icon(for category: String, type: TransactionType, customCategories: [CustomCategory]) -> String {
        CategoryIcon.iconName(for: category, type: type, customCategories: customCategories)
    }
}

// MARK: - SwiftUI View Extensions

extension View {
    /// Применяет стиль "монеты" категории
    func categoryCircleStyle(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory],
        size: CGFloat = AppIconSize.xxl
    ) -> some View {
        let helper = CategoryStyleHelper(category: category, type: type, customCategories: customCategories)

        return self
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(helper.coinColor)
                    .overlay(
                        Circle()
                            .stroke(helper.coinBorderColor, lineWidth: 2)
                    )
            )
            .foregroundStyle(helper.iconColor)
    }
}
