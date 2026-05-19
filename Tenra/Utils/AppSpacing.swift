//
//  AppSpacing.swift
//  Tenra
//
//  Spatial tokens: spacing, corner radii, icon sizes, container sizes.
//

import CoreGraphics

// MARK: - Spacing System (4pt Grid)

/// Консистентная система отступов на основе 4pt grid
/// Используй ТОЛЬКО эти значения для всех spacing и padding
enum AppSpacing {
    /// 2pt - Минимальный отступ (tight inline spacing, fine-tuned layouts)
    static let xxs: CGFloat = 2

    /// 4pt - Микро отступ (между иконкой и текстом в одной строке)
    static let xs: CGFloat = 4

    /// 8pt - Малый отступ (vertical padding для rows, spacing внутри кнопок)
    static let sm: CGFloat = 8

    /// 12pt - Средний отступ (default VStack/HStack spacing, внутренний padding карточек)
    static let md: CGFloat = 12

    /// 16pt - Большой отступ (horizontal padding экранов, spacing между карточками)
    static let lg: CGFloat = 16

    /// 20pt - Очень большой отступ (spacing между major sections)
    static let xl: CGFloat = 20

    /// 24pt - Максимальный отступ (spacing между screen sections)
    static let xxl: CGFloat = 24

    /// 32pt - Screen margins (редко используется)
    static let xxxl: CGFloat = 32
}

// MARK: - Corner Radius System

/// Консистентная система скругления углов
enum AppRadius {
    /// 4pt - Минимальные элементы (indicators, badges)
    static let xs: CGFloat = 4

    /// 12pt - Стандартные карточки и кнопки (основной радиус)
    static let md: CGFloat = 12

    /// 16pt - Большие карточки
    static let lg: CGFloat = 16

    /// 20pt - Large radius (cards, pills, filter chips)
    static let xl: CGFloat = 20

    // MARK: - Semantic Radius

    /// Card corner radius (alias для md)
    static let card: CGFloat = md

    /// Button corner radius (alias для md)
    static let button: CGFloat = md
}

// MARK: - Icon Sizing System

/// Консистентная система размеров иконок
enum AppIconSize {
    /// 16pt - Inline icons (в тексте, мелкие индикаторы)
    static let sm: CGFloat = 16

    /// 20pt - Default icons (toolbar, списки)
    static let md: CGFloat = 20

    /// 24pt - Emphasized icons (category icons в списках)
    static let lg: CGFloat = 24

    /// 32pt - Large icons (bank logos)
    static let xl: CGFloat = 32

    /// 40pt - Medium avatar size (logo picker, subscription icons)
    static let avatar: CGFloat = 40

    /// 44pt - Extra large (category circles в QuickAdd)
    static let xxl: CGFloat = 44

    /// 48pt - Hero icons (empty states)
    static let xxxl: CGFloat = 48

    /// 52pt - Category row icons
    static let categoryIcon: CGFloat = 52

    /// 64pt - Mega icons (category coins, large display elements)
    static let mega: CGFloat = 64

    /// 72pt - Budget ring (coin + 8pt stroke space)
    static let budgetRing: CGFloat = 72

    /// 80pt - Ultra icons (hero sections, large action buttons)
    static let ultra: CGFloat = 80
}
