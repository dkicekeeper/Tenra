//
//  AppColors.swift
//  AIFinanceManager
//
//  Semantic color tokens + category palette. Single source of truth for all colors.
//

import SwiftUI

// MARK: - Semantic Colors

/// Семантические цвета приложения (дополняют существующую систему)
enum AppColors {
    // MARK: Backgrounds

    /// Фон primary экрана
    static let backgroundPrimary = Color(.systemBackground)

    /// Фон surface (карточки, elevated elements)
    static let surface = Color(.secondarySystemBackground)

    /// Фон вторичных элементов (chips, secondary buttons)
    static let secondaryBackground = Color(.systemGray5)

    /// Фон сгруппированных экранов (List/Form с .grouped style)
    static let groupedBackground = Color(.systemGroupedBackground)

    /// Фон вторичных секций внутри сгруппированных экранов
    static let groupedBackgroundSecondary = Color(.secondarySystemGroupedBackground)

    // MARK: Text Colors

    /// Primary text (используй системный .primary для auto light/dark)
    static let textPrimary = Color.primary

    /// Secondary text — системный адаптивный цвет.
    /// Light mode: ~2.5:1 контраст на белом фоне — допустимо для вспомогательного текста
    /// (временны́е метки, описания, подписи). Для критических данных используй `textSecondaryAccessible`.
    static let textSecondary = Color.secondary

    /// Secondary text с гарантированным контрастом ≥ 4.5:1 (WCAG AA).
    /// Light: #595959 (7:1 на белом) | Dark: white 75% (5.5:1 на чёрном).
    /// Используй для secondary-текста, который несёт важную информацию (суммы, статусы).
    static let textSecondaryAccessible = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.75)
            : UIColor(red: 89/255, green: 89/255, blue: 89/255, alpha: 1)
    })

    /// Tertiary text (используй системный .gray для мета-информации)
    static let textTertiary = Color.gray

    // MARK: Interactive Colors

    /// Accent color (для выделений, selections)
    static let accent = Color.blue

    /// Destructive actions
    static let destructive = Color.red

    /// Success/positive — используй для UI-состояний (кнопки, индикаторы).
    /// Для финансового дохода используй `income`.
    static let success = Color.green

    /// Warning
    static let warning = Color.orange

    // MARK: Static Colors

    /// Белый цвет без адаптации к теме — для текста поверх тёмных/цветных фонов.
    /// Не используй для обычного текста: предпочитай `textPrimary`.
    static let staticWhite = Color.white

    // MARK: Transaction Type Colors (semantic)

    /// Income transactions — финансово-специфичный зелёный.
    /// Не зависит от `success`: если дизайн меняет success, income не изменится.
    static let income = Color(red: 0.13, green: 0.70, blue: 0.37)

    /// Expense transactions
    static let expense = Color.primary

    /// Transfer / internal transactions (distinct cyan-teal, not accent blue)
    static let transfer = Color(red: 0.0, green: 0.75, blue: 0.85)

    /// Planned / future / scheduled transactions
    static let planned = Color.blue

    // MARK: Status Colors (explicit aliases)

    /// Active status (alias for success)
    static let statusActive = success

    /// Paused status (alias for warning)
    static let statusPaused = warning

    /// Archived / inactive status
    static let statusArchived = Color(.systemGray)
}

// MARK: - Category Color Palette

/// Цвета для категорий транзакций — hash-based assignment из палитры
struct CategoryColors {
    /// Pre-computed color palette (avoids hex parsing on every call)
    private static let palette: [Color] = {
        let hexValues: [UInt64] = [
            0x3b82f6, 0x8b5cf6, 0xec4899, 0xf97316, 0xeab308,
            0x22c55e, 0x14b8a6, 0x06b6d4, 0x6366f1, 0xd946ef,
            0xf43f5e, 0xa855f7, 0x10b981, 0xf59e0b
        ]
        return hexValues.map { rgb in
            Color(
                red:   Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8)  / 255.0,
                blue:  Double( rgb & 0x0000FF)         / 255.0
            )
        }
    }()

    /// Возвращает цвет по палитре с учётом пользовательских категорий
    static func hexColor(for category: String, opacity: Double = 1.0, customCategories: [CustomCategory] = []) -> Color {
        if let custom = customCategories.first(where: { $0.name.lowercased() == category.lowercased() }) {
            return custom.color.opacity(opacity)
        }

        let index = abs(category.hashValue) % palette.count
        return palette[index].opacity(opacity)
    }
}
