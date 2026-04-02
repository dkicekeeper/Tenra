//
//  AppSpacing.swift
//  AIFinanceManager
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

    /// 6pt - Компактный отступ (tight button padding, small chip padding)
    static let compact: CGFloat = 6

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

    // MARK: - Semantic Spacing

    /// Горизонтальный padding для страниц (alias для lg)
    static let pageHorizontal: CGFloat = lg

    /// Вертикальный spacing между секциями страницы (alias для xxl)
    static let sectionVertical: CGFloat = xxl

    /// Padding внутри карточек (alias для md)
    static let cardPadding: CGFloat = md

    /// Spacing между элементами в списке (alias для sm)
    static let listRowSpacing: CGFloat = sm

    /// Spacing между иконкой и текстом inline (alias для xs)
    static let iconText: CGFloat = xs

    /// Spacing между label и value в InfoRow (alias для md)
    static let labelValue: CGFloat = md
}

// MARK: - Corner Radius System

/// Консистентная система скругления углов
enum AppRadius {
    /// 4pt - Минимальные элементы (indicators, badges)
    static let xs: CGFloat = 4

    /// 6pt - Очень малые элементы (compact chips)
    static let compact: CGFloat = 6

    /// 8pt - Малые элементы (chips, небольшие кнопки)
    static let sm: CGFloat = 8

    /// 12pt - Стандартные карточки и кнопки (основной радиус)
    static let md: CGFloat = 12

    /// 16pt - Большие карточки
    static let lg: CGFloat = 16

    /// 20pt - Large radius (cards, pills, filter chips)
    static let xl: CGFloat = 20

    /// Бесконечность - Круги (category icons, avatars)
    static let circle: CGFloat = .infinity

    // MARK: - Semantic Radius

    /// Card corner radius (alias для md)
    static let card: CGFloat = md

    /// Button corner radius (alias для md)
    static let button: CGFloat = md

    /// Sheet corner radius (alias для lg)
    static let sheet: CGFloat = lg

    /// Chip corner radius (alias для sm)
    static let chip: CGFloat = sm
}

// MARK: - Icon Sizing System

/// Консистентная система размеров иконок
enum AppIconSize {
    /// 12pt - Micro icons (tiny indicators, badges)
    static let xs: CGFloat = 12

    /// 14pt - Small indicators (dots, small badges)
    static let indicator: CGFloat = 14

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

    /// 56pt - Floating action buttons
    static let fab: CGFloat = 56

    /// 64pt - Mega icons (category coins, large display elements)
    static let mega: CGFloat = 64

    /// 72pt - Budget ring (coin + 8pt stroke space)
    static let budgetRing: CGFloat = 72

    /// 80pt - Ultra icons (hero sections, large action buttons)
    static let ultra: CGFloat = 80
}

// MARK: - Container Sizes

/// Консистентные размеры контейнеров и макет-элементов
enum AppSize {
    // MARK: - Buttons & Controls

    /// Small button size (40x40)
    static let buttonSmall: CGFloat = 40

    /// Medium button size (56x56)
    static let buttonMedium: CGFloat = 56

    /// Large button size (64x64)
    static let buttonLarge: CGFloat = 64

    /// Extra large button size (80x80)
    static let buttonXL: CGFloat = 80

    // MARK: - Cards & Containers

    /// Subscription card width
    static let subscriptionCardWidth: CGFloat = 120

    /// Subscription card height
    static let subscriptionCardHeight: CGFloat = 80

    /// Analytics card skeleton width
    static let analyticsCardWidth: CGFloat = 200

    /// Analytics card skeleton height
    static let analyticsCardHeight: CGFloat = 140

    // MARK: - Scroll & List Constraints

    /// Max height for scrollable preview sections
    static let previewScrollHeight: CGFloat = 300

    /// Max height for result lists
    static let resultListHeight: CGFloat = 150

    /// Min height for content sections
    static let contentMinHeight: CGFloat = 120

    /// Standard height for rows/cells
    static let rowHeight: CGFloat = 60

    // MARK: - Specific UI Elements

    /// Calendar picker width
    static let calendarPickerWidth: CGFloat = 180

    /// Wave animation height (small)
    static let waveHeightSmall: CGFloat = 80

    /// Wave animation height (medium)
    static let waveHeightMedium: CGFloat = 100

    /// Skeleton placeholder height
    static let skeletonHeight: CGFloat = 16

    /// Cursor line width
    static let cursorWidth: CGFloat = 2

    /// Cursor line height for numeric amount input
    static let cursorHeight: CGFloat = 36

    /// Cursor line height for large title input (h1)
    static let cursorHeightLarge: CGFloat = 44

    // MARK: - Chart Heights

    /// Large chart height (analytics / deep-dive charts)
    static let chartHeightLarge: CGFloat = 200

    /// Small chart height (compact / inline charts)
    static let chartHeightSmall: CGFloat = 80

    // MARK: - Calendar / Date Picker

    /// Calendar row height (day rows in custom calendars)
    static let calendarRowHeight: CGFloat = 60

    /// Calendar header height (day-of-week labels)
    static let calendarHeaderHeight: CGFloat = 20

    /// Calendar day cell size (width & height)
    static let calendarDaySize: CGFloat = 32

    // MARK: - Indicator Dots

    /// Small dot indicator size
    static let dotSize: CGFloat = 10

    /// Large dot indicator size
    static let dotLargeSize: CGFloat = 12

    // MARK: - Color Swatch

    /// Color swatch size in color picker
    static let colorSwatchSize: CGFloat = 30

    // MARK: - Selection Border

    /// Border line width for selected state (account radio, icon picker, etc.)
    static let selectedBorderWidth: CGFloat = 2
}
