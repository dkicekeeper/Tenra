//
//  IconView.swift
//  AIFinanceManager
//
//  Unified icon and logo display component with full Design System integration
//  Created: 2026-02-12
//

import SwiftUI

/// Универсальный компонент для отображения иконок и логотипов
/// Полностью интегрирован с Design System (AppTheme.swift)
///
/// # Примеры использования:
///
/// ## SF Symbol с пресетом
/// ```swift
/// IconView(source: .sfSymbol("star.fill"), style: .categoryIcon())
/// ```
///
/// ## Банковский логотип с кастомным размером
/// ```swift
/// IconView(source: .bankLogo(.kaspi), style: .bankLogo(size: 40))
/// ```
///
/// ## Динамический логотип сервиса
/// ```swift
/// IconView(source: .brandService("netflix"), style: .serviceLogo())
/// ```
///
/// ## Полный контроль над стилем
/// ```swift
/// IconView(
///     source: .sfSymbol("heart.fill"),
///     style: .circle(
///         size: AppIconSize.xl,
///         tint: .monochrome(.red),
///         backgroundColor: AppColors.surface
///     )
/// )
/// ```
struct IconView: View {

    // MARK: - Properties

    let source: IconSource?
    let style: IconStyle

    // MARK: - Initializers

    init(source: IconSource?, style: IconStyle) {
        self.source = source
        self.style = style
    }

    /// Convenience initializer с автоматическим выбором стиля по типу источника
    /// - Parameters:
    ///   - source: Источник иконки (IconSource)
    ///   - size: Размер иконки (по умолчанию AppIconSize.xl из Design System)
    init(source: IconSource?, size: CGFloat = AppIconSize.xl) {
        self.source = source

        // Автоматический выбор стиля в зависимости от типа источника
        switch source {
        case .sfSymbol:
            self.style = .categoryIcon(size: size)
        case .bankLogo:
            self.style = .bankLogo(size: size)
        case .brandService:
            self.style = .serviceLogo(size: size)
        case .none:
            self.style = .placeholder(size: size)
        }
    }

    // MARK: - Body

    var body: some View {
        containerView {
            contentView
                .frame(width: contentSize, height: contentSize)
        }
    }

    // MARK: - Computed Properties

    /// Адаптивный padding с нелинейным масштабированием по размеру
    /// - SF Symbols: 5% (малые <24pt) / 10% (средние 24–44pt) / 15% (большие 44–64pt) / 18% (героические 64pt+)
    /// - Логотипы (bank/brand): без padding (заполняют контейнер полностью)
    /// - Placeholder: нелинейная кривая аналогичная SF Symbols
    /// - Явно заданный padding имеет приоритет
    private var effectivePadding: CGFloat? {
        if let explicitPadding = style.padding { return explicitPadding }

        switch source {
        case .sfSymbol:
            return adaptiveSFSymbolPadding
        case .bankLogo, .brandService:
            return nil
        case .none:
            return adaptivePlaceholderPadding
        }
    }

    /// Нелинейный padding для SF Symbols:
    /// маленькие иконки получают меньше отступа (символ крупнее),
    /// большие иконки получают больше (визуальное дыхание в окружности)
    private var adaptiveSFSymbolPadding: CGFloat {
        switch style.size {
        case ..<24:   return style.size * 0   // малые: минимальный отступ, символ заметнее
        case 24..<44: return style.size * 0.10   // средние: сбалансированно
        case 44..<64: return style.size * 0.15   // крупные: пространство для дыхания
        default:      return style.size * 0.18   // героические (64pt+): щедрый отступ
        }
    }

    private var adaptivePlaceholderPadding: CGFloat {
        switch style.size {
        case ..<24:   return style.size * 0
        case 24..<44: return style.size * 0.12
        default:      return style.size * 0.18
        }
    }

    /// Размер контента с учетом padding
    private var contentSize: CGFloat {
        if let padding = effectivePadding {
            return style.size - (padding * 2)
        }
        return style.size
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch source {
        case .sfSymbol(let name):
            sfSymbolView(name)

        case .bankLogo(let logo):
            bankLogoView(logo)

        case .brandService(let name):
            brandServiceView(name)

        case .none:
            placeholderView
        }
    }

    // MARK: - SF Symbol View

    @ViewBuilder
    private func sfSymbolView(_ symbolName: String) -> some View {
        let image = Image(systemName: symbolName)
            .resizable()
            .aspectRatio(contentMode: style.contentMode)

        // Применяем rendering mode в зависимости от tint
        switch style.tint {
        case .monochrome(let color):
            image
                .foregroundStyle(color)

        case .hierarchical(let color):
            if #available(iOS 15, *) {
                image
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
            } else {
                image
                    .foregroundStyle(color)
            }

        case .palette(let colors):
            if #available(iOS 15, *) {
                applyPalette(to: image, colors: colors)
            } else {
                image
                    .foregroundStyle(colors.first ?? AppColors.accent)
            }

        case .original:
            image
                .foregroundStyle(AppColors.accent)
        }
    }

    @available(iOS 15, *)
    @ViewBuilder
    private func applyPalette(to image: some View, colors: [Color]) -> some View {
        switch colors.count {
        case 1:
            image
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors[0])
        case 2:
            image
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors[0], colors[1])
        case 3...:
            image
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors[0], colors[1], colors[2])
        default:
            image
                .foregroundStyle(AppColors.accent)
        }
    }

    // MARK: - Bank Logo View

    @ViewBuilder
    private func bankLogoView(_ logo: BankLogo) -> some View {
        if logo == .none {
            placeholderView
        } else if let uiImage = UIImage(named: logo.rawValue) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: style.contentMode)
        } else {
            placeholderView
        }
    }

    // MARK: - Brand Service View

    @ViewBuilder
    private func brandServiceView(_ brandName: String) -> some View {
        // Интегрируем BrandLogoView напрямую для унификации
        BrandLogoView(brandName: brandName, size: contentSize)
    }

    // MARK: - Placeholder View

    private var placeholderView: some View {
        Image(systemName: "photo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(AppColors.textSecondary)
    }

    // MARK: - Container View

    @ViewBuilder
    private func containerView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let baseView = content()
            .frame(width: style.size, height: style.size)

        // Определяем, нужно ли обрезать контент (только для изображений, не для SF Symbols)
        let shouldClipContent = shouldClipContentForSource()

        // Применяем фон если задан
        let viewWithBackground = Group {
            if let bgColor = style.backgroundColor {
                // Для SF Symbols обрезаем только фон, не контент
                if shouldClipContent {
                    baseView.background(bgColor)
                } else {
                    // Для SF Symbols - фон с формой, но контент не обрезается
                    switch style.shape {
                    case .circle:
                        baseView.background(Circle().fill(bgColor))
                    case .roundedSquare(let radius):
                        baseView.background(RoundedRectangle(cornerRadius: radius).fill(bgColor))
                    case .square:
                        baseView.background(Rectangle().fill(bgColor))
                    }
                }
            } else {
                baseView
            }
        }

        // Применяем padding если задан (используем effectivePadding)
        let viewWithPadding = Group {
            if let padding = effectivePadding {
                viewWithBackground.padding(padding)
            } else {
                viewWithBackground
            }
        }

        // Применяем форму с обрезкой контента ТОЛЬКО для изображений (не SF Symbols)
        let viewWithShape = Group {
            if shouldClipContent {
                // Для изображений (bank logo, brand logo) - обрезаем по форме
                switch style.shape {
                case .circle:
                    viewWithPadding
                        .clipShape(Circle())
                        .contentShape(Circle())

                case .roundedSquare(let radius):
                    viewWithPadding
                        .clipShape(RoundedRectangle(cornerRadius: radius))
                        .contentShape(RoundedRectangle(cornerRadius: radius))

                case .square:
                    viewWithPadding
                        .clipShape(Rectangle())
                        .contentShape(Rectangle())
                }
            } else {
                // Для SF Symbols - только contentShape для tap area
                switch style.shape {
                case .circle:
                    viewWithPadding
                        .contentShape(Circle())

                case .roundedSquare(let radius):
                    viewWithPadding
                        .contentShape(RoundedRectangle(cornerRadius: radius))

                case .square:
                    viewWithPadding
                        .contentShape(Rectangle())
                }
            }
        }

        // Применяем glass effect если требуется
        if style.hasGlassEffect {
            if #available(iOS 18.0, *) {
                switch style.shape {
                case .circle:
                    viewWithShape
                        .glassEffect(in: Circle())
                case .roundedSquare(let radius):
                    viewWithShape
                        .glassEffect(in: RoundedRectangle(cornerRadius: radius))
                case .square:
                    viewWithShape
                        .glassEffect(in: Rectangle())
                }
            } else {
                // Fallback для более старых версий iOS
                viewWithShape
            }
        } else {
            viewWithShape
        }
    }

    // MARK: - Helper Methods

    /// Определяет, нужно ли обрезать контент по форме контейнера
    /// SF Symbols не обрезаются, только изображения (bank logos, brand logos)
    private func shouldClipContentForSource() -> Bool {
        switch source {
        case .sfSymbol:
            return false // SF Symbols не обрезаются
        case .bankLogo, .brandService:
            return true // Изображения обрезаются
        case .none:
            return false // Placeholder не обрезается
        }
    }
}
