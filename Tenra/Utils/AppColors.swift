//
//  AppColors.swift
//  Tenra
//
//  Semantic color tokens + category palette. Single source of truth for all colors.
//

import SwiftUI

// MARK: - Semantic Colors

/// Семантические цвета приложения (дополняют существующую систему)
enum AppColors {
    // MARK: Backgrounds
    //
    // Три уровня иерархии — base → card → muted.
    // bgBase   — фон самого экрана.
    // bgCard   — приподнятая поверхность (карточки, fallback под cardStyle на iOS<26).
    // bgMuted  — "утопленный" слой внутри карточек (треки прогресс-баров, фон чипов).

    /// Фон самого экрана.
    static let bgBase = Color(.systemBackground)

    /// Приподнятая поверхность — карточки, elevated containers.
    static let bgCard = Color(.secondarySystemBackground)

    /// "Утопленный" фон — chips, прогресс-бар треки, secondary buttons.
    static let bgMuted = Color(.systemGray5)

    // MARK: Text Colors

    /// Primary text (используй системный .primary для auto light/dark)
    static let textPrimary = Color.primary

    /// Secondary text — системный адаптивный цвет (.secondary).
    static let textSecondary = Color.secondary

    /// Tertiary text (используй системный .gray для мета-информации)
    nonisolated static let textTertiary = Color.gray

    // MARK: Interactive Colors

    /// Accent color (для выделений, selections)
    nonisolated static let accent = Color.indigo

    /// Destructive actions
    nonisolated static let destructive = Color.red

    /// Success/positive — используй для UI-состояний (кнопки, индикаторы).
    /// Для финансового дохода используй `income`.
    nonisolated static let success = Color.green

    /// Warning
    nonisolated static let warning = Color.orange

    // MARK: Static Colors

    /// Белый цвет без адаптации к теме — для текста поверх тёмных/цветных фонов.
    /// Не используй для обычного текста: предпочитай `textPrimary`.
    static let staticWhite = Color.white

    // MARK: Transaction Type Colors (semantic)

    /// Income transactions — финансово-специфичный зелёный.
    /// Не зависит от `success`: если дизайн меняет success, income не изменится.
    static let income = Color(red: 0.13, green: 0.70, blue: 0.37)

    /// Expense transactions.
    /// Сознательно НЕ красный (как могло бы подсказать "destructive"-чтение расхода):
    /// если бы расходы рендерились красным, всё приложение визуально кричало бы
    /// тревогой — большинство транзакций это расходы. Чёрный (`.primary`) даёт
    /// нейтральный baseline, а контраст создаётся через `income` (зелёный)
    /// и `transfer` (cyan). Резолвится в тот же цвет, что и `textPrimary`,
    /// но семантически это отдельный токен — менять расход на другой цвет
    /// (если когда-нибудь понадобится) можно будет в одной точке.
    static let expense = Color.primary

    /// Transfer / internal transactions (distinct cyan-teal, not accent blue)
    static let transfer = Color(red: 0.0, green: 0.75, blue: 0.85)

    /// Planned / future / scheduled transactions
    static let planned = Color.blue

}

// MARK: - Category Color Palette

/// Цвета для категорий транзакций — hash-based assignment из палитры
struct CategoryColors {
    /// Pre-computed color palette (avoids hex parsing on every call)
    private nonisolated static let palette: [Color] = {
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

    /// Возвращает цвет по палитре с учётом пользовательских категорий.
    /// Legacy O(N_cat) path — still used in cold/preview contexts. Prefer the
    /// store-backed overload below on the hot path.
    nonisolated static func hexColor(for category: String, opacity: Double = 1.0, customCategories: [CustomCategory] = []) -> Color {
        if let custom = customCategories.first(where: { $0.name.lowercased() == category.lowercased() }) {
            return custom.color.opacity(opacity)
        }

        let index = abs(category.hashValue) % palette.count
        return palette[index].opacity(opacity)
    }

    /// O(1) — looks up the custom category through TransactionStore.categoryIdByName
    /// and falls back to the deterministic palette by name hash.
    @MainActor
    static func hexColor(for category: String, opacity: Double = 1.0, store: TransactionStore) -> Color {
        if let id = store.categoryIdByName[category.lowercased()],
           let custom = store.categoryById[id] {
            return custom.color.opacity(opacity)
        }
        let index = abs(category.hashValue) % palette.count
        return palette[index].opacity(opacity)
    }
}
