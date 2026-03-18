//
//  IconStyle.swift
//  AIFinanceManager
//
//  Unified icon styling configuration with full Design System integration
//  Created: 2026-02-12
//

import SwiftUI

/// Форма контейнера иконки
enum IconShape: Equatable, Hashable {
    case circle
    case roundedSquare(cornerRadius: CGFloat)
    case square

    /// Локализованное название формы
    var localizedName: String {
        switch self {
        case .circle:
            return String(localized: "iconStyle.shape.circle")
        case .roundedSquare:
            return String(localized: "iconStyle.shape.roundedSquare")
        case .square:
            return String(localized: "iconStyle.shape.square")
        }
    }

    /// Создает скругленный квадрат с относительным радиусом
    static func roundedSquare(relativeTo size: CGFloat, ratio: CGFloat = 0.2) -> IconShape {
        .roundedSquare(cornerRadius: size * ratio)
    }

    /// Создает скругленный квадрат используя токены Design System
    static var cardShape: IconShape {
        .roundedSquare(cornerRadius: AppRadius.card)
    }

    static var chipShape: IconShape {
        .roundedSquare(cornerRadius: AppRadius.chip)
    }
}

/// Стиль раскраски иконки
enum IconTint: Equatable, Hashable {
    case monochrome(Color)      // Монохромная раскраска (для SF Symbols)
    case hierarchical(Color)    // Иерархическая раскраска (iOS 15+, для SF Symbols)
    case palette([Color])       // Палитра цветов (multicolor SF Symbols)
    case original               // Оригинальные цвета (для растровых изображений)

    /// Локализованное название тинта
    var localizedName: String {
        switch self {
        case .monochrome:
            return String(localized: "iconStyle.tint.monochrome")
        case .hierarchical:
            return String(localized: "iconStyle.tint.hierarchical")
        case .palette:
            return String(localized: "iconStyle.tint.palette")
        case .original:
            return String(localized: "iconStyle.tint.original")
        }
    }

    // MARK: - Design System Presets

    /// Accent monochrome (основной цвет приложения)
    static var accentMonochrome: IconTint {
        .monochrome(AppColors.accent)
    }

    /// Primary text color для иконок
    static var primaryMonochrome: IconTint {
        .monochrome(AppColors.textPrimary)
    }

    /// Secondary text color для иконок
    static var secondaryMonochrome: IconTint {
        .monochrome(AppColors.textSecondary)
    }

    /// Success color (для income категорий)
    static var successMonochrome: IconTint {
        .monochrome(AppColors.success)
    }

    /// Destructive color (для expense важных действий)
    static var destructiveMonochrome: IconTint {
        .monochrome(AppColors.destructive)
    }
}

/// Полная конфигурация стиля иконки с интеграцией Design System
struct IconStyle: Equatable, Hashable {
    var size: CGFloat
    var shape: IconShape
    var tint: IconTint
    var contentMode: ContentMode
    var backgroundColor: Color?
    var padding: CGFloat?  // Внутренний padding (опционально)
    var hasGlassEffect: Bool  // Применять ли glass effect

    // MARK: - Basic Initializers

    /// Создает стиль с круглой формой
    static func circle(
        size: CGFloat,
        tint: IconTint = .original,
        backgroundColor: Color? = nil,
        padding: CGFloat? = nil,
        hasGlassEffect: Bool = false
    ) -> IconStyle {
        IconStyle(
            size: size,
            shape: .circle,
            tint: tint,
            contentMode: .fit,
            backgroundColor: backgroundColor,
            padding: padding,
            hasGlassEffect: hasGlassEffect
        )
    }

    /// Создает стиль с квадратной формой и скругленными углами
    static func roundedSquare(
        size: CGFloat,
        cornerRadius: CGFloat? = nil,
        tint: IconTint = .original,
        backgroundColor: Color? = nil,
        padding: CGFloat? = nil,
        hasGlassEffect: Bool = false
    ) -> IconStyle {
        let radius = cornerRadius ?? (size * 0.2)
        return IconStyle(
            size: size,
            shape: .roundedSquare(cornerRadius: radius),
            tint: tint,
            contentMode: .fit,
            backgroundColor: backgroundColor,
            padding: padding,
            hasGlassEffect: hasGlassEffect
        )
    }

    /// Создает стиль с квадратной формой без скругления
    static func square(
        size: CGFloat,
        tint: IconTint = .original,
        backgroundColor: Color? = nil,
        padding: CGFloat? = nil,
        hasGlassEffect: Bool = false
    ) -> IconStyle {
        IconStyle(
            size: size,
            shape: .square,
            tint: tint,
            contentMode: .fit,
            backgroundColor: backgroundColor,
            padding: padding,
            hasGlassEffect: hasGlassEffect
        )
    }

    // MARK: - Design System Semantic Presets

    /// Стандартная иконка категории (круг, accent цвет)
    /// Используется в: CategoryRow, CategoryChip, CategorySelectorView
    static func categoryIcon(size: CGFloat = AppIconSize.lg) -> IconStyle {
        .circle(
            size: size,
            tint: .accentMonochrome
        )
    }

    /// Крупная иконка категории для монеты (в CategoryRow)
    static func categoryCoin(size: CGFloat = AppIconSize.mega) -> IconStyle {
        .circle(
            size: size,
            tint: .accentMonochrome,
            backgroundColor: AppColors.surface
        )
    }

    /// Стандартный логотип с скругленным квадратом
    /// Используется в: AccountRow, AccountCard, AccountEditView
    static func roundedLogo(size: CGFloat = AppIconSize.xl) -> IconStyle {
        .roundedSquare(
            size: size,
            cornerRadius: AppRadius.md,
            tint: .original
        )
    }

    /// Крупный логотип для карточек счетов
    static func roundedLogoLarge(size: CGFloat = AppIconSize.avatar) -> IconStyle {
        .roundedSquare(
            size: size,
            cornerRadius: AppRadius.lg,
            tint: .original
        )
    }

    /// Стандартная иконка подписки/сервиса
    /// Используется в: SubscriptionCard, IconPickerView
    static func serviceLogo(size: CGFloat = AppIconSize.xl) -> IconStyle {
        .roundedSquare(
            size: size,
            cornerRadius: AppRadius.md,
            tint: .original
        )
    }

    /// Крупная иконка сервиса для карточек подписок
    static func serviceLogoLarge(size: CGFloat = AppIconSize.avatar) -> IconStyle {
        .roundedSquare(
            size: size,
            cornerRadius: AppRadius.lg,
            tint: .original
        )
    }

    /// Placeholder стиль (серый фон, secondary цвет)
    /// Используется когда iconSource == nil
    static func placeholder(size: CGFloat) -> IconStyle {
        .roundedSquare(
            size: size,
            cornerRadius: size * 0.2,
            tint: .secondaryMonochrome,
            backgroundColor: AppColors.surface
        )
    }

    /// Миниатюрная иконка для inline использования
    /// Используется в: текстовых полях, chips, small buttons
    static func inline(tint: IconTint = .primaryMonochrome) -> IconStyle {
        .circle(
            size: AppIconSize.sm,
            tint: tint
        )
    }

    /// Toolbar иконка
    /// Используется в: навигации, toolbar buttons
    static func toolbar(tint: IconTint = .primaryMonochrome) -> IconStyle {
        .circle(
            size: AppIconSize.md,
            tint: tint
        )
    }

    /// Иконка для Empty State
    static func emptyState() -> IconStyle {
        .circle(
            size: AppIconSize.ultra,
            tint: .accentMonochrome
        )
    }

    /// Стеклянная иконка для hero секций (подписки, счета)
    /// Используется в: SubscriptionDetailView, AccountDetailView
    static func glassHero(size: CGFloat = AppIconSize.ultra) -> IconStyle {
        .circle(
            size: size,
            tint: .original,
            hasGlassEffect: true
        )
    }

    /// Стеклянная иконка сервиса с rounded square
    static func glassService(size: CGFloat = AppIconSize.avatar) -> IconStyle {
        .roundedSquare(
            size: size,
            cornerRadius: AppRadius.lg,
            tint: .original,
            hasGlassEffect: true
        )
    }

    /// Локализованное название пресета
    var localizedPresetName: String? {
        // Определяем пресет по характеристикам
        if case .circle = shape,
           case .monochrome(let color) = tint,
           color == AppColors.accent,
           size == AppIconSize.lg {
            return String(localized: "iconStyle.preset.categoryIcon")
        }

        if case .roundedSquare = shape,
           case .original = tint,
           (size == AppIconSize.xl || size == AppIconSize.avatar) {
            return String(localized: "iconStyle.preset.serviceLogo")
        }

        if backgroundColor != nil,
           case .monochrome(let color) = tint,
           color == AppColors.textSecondary {
            return String(localized: "iconStyle.preset.placeholder")
        }

        return nil
    }
}
