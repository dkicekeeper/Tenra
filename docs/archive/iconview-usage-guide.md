# IconView Usage Guide

## 📖 Обзор

`IconView` - универсальный компонент для отображения иконок и логотипов с полной интеграцией Design System и локализацией.

### ✨ Основные возможности

- **Единый API** для всех типов иконок (SF Symbols, банковские логотипы, сервисные логотипы)
- **Гибкая стилизация** через `IconStyle` (размер, форма, цвет, фон, padding)
- **Design System пресеты** для типовых случаев
- **Локализация** всех названий стилей (EN/RU)
- **Производительность** - использует существующий кэш `LogoService`
- **Полная миграция** - заменяет устаревший `BrandLogoDisplayView`

---

## 🎯 Быстрый старт

### Простое использование (автоматический стиль)

```swift
// Автоматически выберет правильный стиль в зависимости от типа источника
IconView(source: account.iconSource, size: AppIconSize.xl)
```

### С Design System пресетом

```swift
// Иконка категории
IconView(source: .sfSymbol("cart.fill"), style: .categoryIcon())

// Банковский логотип
IconView(source: .bankLogo(.kaspi), style: .bankLogo())

// Логотип сервиса
IconView(source: .brandService("netflix"), style: .serviceLogo())
```

### Полный контроль

```swift
IconView(
    source: .sfSymbol("heart.fill"),
    style: .circle(
        size: 60,
        tint: .monochrome(.red),
        backgroundColor: AppColors.surface,
        padding: AppSpacing.sm
    )
)
```

---

## 🎨 IconStyle API

### Формы (IconShape)

```swift
.circle                                    // Круг
.roundedSquare(cornerRadius: 12)          // Скругленный квадрат
.square                                    // Квадрат без скругления

// Утилиты
.roundedSquare(relativeTo: size, ratio: 0.2)  // Относительный радиус
IconShape.cardShape                        // AppRadius.card
IconShape.chipShape                        // AppRadius.chip
```

### Раскраска (IconTint)

```swift
.monochrome(Color)      // Монохромная (SF Symbols)
.hierarchical(Color)    // Иерархическая (iOS 15+, SF Symbols)
.palette([Color])       // Палитра цветов (multicolor SF Symbols)
.original               // Оригинальные цвета (растровые изображения)

// Design System пресеты
.accentMonochrome       // AppColors.accent
.primaryMonochrome      // AppColors.textPrimary
.secondaryMonochrome    // AppColors.textSecondary
.successMonochrome      // AppColors.success
.destructiveMonochrome  // AppColors.destructive
```

### Базовые конструкторы

```swift
IconStyle.circle(
    size: CGFloat,
    tint: IconTint = .original,
    backgroundColor: Color? = nil,
    padding: CGFloat? = nil
)

IconStyle.roundedSquare(
    size: CGFloat,
    cornerRadius: CGFloat? = nil,  // nil = 20% от размера
    tint: IconTint = .original,
    backgroundColor: Color? = nil,
    padding: CGFloat? = nil
)

IconStyle.square(
    size: CGFloat,
    tint: IconTint = .original,
    backgroundColor: Color? = nil,
    padding: CGFloat? = nil
)
```

### Design System пресеты

```swift
// Категории
.categoryIcon(size: AppIconSize.lg)       // Стандартная иконка
.categoryCoin(size: AppIconSize.coin)     // Крупная монета с фоном

// Банки
.bankLogo(size: AppIconSize.xl)           // Стандартный логотип
.bankLogoLarge(size: AppIconSize.avatar)  // Крупный для карточек

// Сервисы
.serviceLogo(size: AppIconSize.xl)        // Стандартный
.serviceLogoLarge(size: AppIconSize.avatar) // Крупный

// Утилиты
.placeholder(size: CGFloat)               // Пустое состояние
.inline(tint: IconTint)                   // Inline иконка (16pt)
.toolbar(tint: IconTint)                  // Toolbar иконка (20pt)
.emptyState()                             // Empty state (48pt)
```

---

## 📚 Примеры для разных компонентов

### 1. AccountRow

**После миграции:**
```swift
IconView(
    source: account.iconSource,
    style: .bankLogo()
)
```

### 2. CategoryRow

**До:**
```swift
if case .sfSymbol(let symbolName) = category.iconSource {
    Image(systemName: symbolName)
        .resizable()
        .frame(width: AppIconSize.categoryIcon, height: AppIconSize.categoryIcon)
        .foregroundStyle(AppColors.accent)
}
```

**После:**
```swift
IconView(
    source: category.iconSource,
    style: .categoryCoin()
)
```

### 3. SubscriptionCard

**После миграции:**
```swift
IconView(
    source: subscription.iconSource,
    style: .serviceLogo()
)
```

### 4. Toolbar Button

**До:**
```swift
Button {
    // action
} label: {
    Image(systemName: "gear")
        .font(.system(size: AppIconSize.md))
        .foregroundStyle(AppColors.textPrimary)
}
```

**После:**
```swift
Button {
    // action
} label: {
    IconView(
        source: .sfSymbol("gear"),
        style: .toolbar()
    )
}
```

### 5. Empty State

**До:**
```swift
VStack(spacing: AppSpacing.lg) {
    Image(systemName: "photo")
        .font(.system(size: AppIconSize.xxxl))
        .foregroundStyle(.secondary)
    Text("No items")
}
```

**После:**
```swift
VStack(spacing: AppSpacing.lg) {
    IconView(
        source: .sfSymbol("photo"),
        style: .emptyState()
    )
    Text("No items")
}
```

### 6. Кастомная иконка с фоном

**До:**
```swift
ZStack {
    Circle()
        .fill(AppColors.surface)
        .frame(width: 50, height: 50)

    Image(systemName: "star.fill")
        .resizable()
        .frame(width: 30, height: 30)
        .foregroundStyle(.yellow)
}
```

**После:**
```swift
IconView(
    source: .sfSymbol("star.fill"),
    style: .circle(
        size: 50,
        tint: .monochrome(.yellow),
        backgroundColor: AppColors.surface,
        padding: 10
    )
)
```

### 7. Hierarchical Symbol (iOS 15+)

```swift
IconView(
    source: .sfSymbol("person.crop.circle.badge.checkmark"),
    style: .circle(
        size: AppIconSize.xl,
        tint: .hierarchical(AppColors.success)
    )
)
```

### 8. Multicolor Palette (iOS 15+)

```swift
IconView(
    source: .sfSymbol("heart.circle.fill"),
    style: .circle(
        size: AppIconSize.xl,
        tint: .palette([.red, .pink, .white])
    )
)
```

---

## 🎯 Сценарии использования

### Когда использовать автоматический стиль?

```swift
// Когда тип иконки определяет нужный стиль
IconView(source: account.iconSource, size: 32)
```

**Подходит для:**
- Списки элементов с разными типами иконок
- Универсальные компоненты
- Быстрое прототипирование

### Когда использовать пресеты?

```swift
IconView(source: subscription.iconSource, style: .serviceLogo())
```

**Подходит для:**
- Типовые случаи из Design System
- Консистентность UI
- Когда нужна семантика (categoryIcon, bankLogo)

### Когда использовать полную кастомизацию?

```swift
IconView(
    source: .sfSymbol("star.fill"),
    style: IconStyle(
        size: 64,
        shape: .roundedSquare(cornerRadius: 16),
        tint: .monochrome(.orange),
        contentMode: .fit,
        backgroundColor: .yellow.opacity(0.2),
        padding: 12
    )
)
```

**Подходит для:**
- Уникальные UI элементы
- Анимации и эффекты
- Специальные требования дизайна

---

## ✅ Миграция завершена

`BrandLogoDisplayView` был полностью заменен на `IconView` во всем проекте.

### Пример замены

**Было:**
```swift
BrandLogoDisplayView(iconSource: source, size: 32)
```

**Стало:**
```swift
IconView(source: source, size: 32)
```

### С использованием пресетов

**Простой вариант:**
```swift
IconView(source: account.iconSource, size: AppIconSize.xl)
```

**С семантическим пресетом:**
```swift
IconView(source: account.iconSource, style: .bankLogo())
```

---

## 🚀 Best Practices

### 1. Используйте Design System токены

```swift
// ✅ Хорошо
IconView(
    source: source,
    style: .circle(
        size: AppIconSize.xl,
        tint: .accentMonochrome,
        backgroundColor: AppColors.surface
    )
)

// ❌ Плохо
IconView(
    source: source,
    style: .circle(
        size: 32,  // магическое число
        tint: .monochrome(.blue),  // не из Design System
        backgroundColor: .gray  // не из Design System
    )
)
```

### 2. Используйте пресеты для типовых случаев

```swift
// ✅ Хорошо - семантический пресет
IconView(source: category.iconSource, style: .categoryIcon())

// ❌ Плохо - дублирование настроек
IconView(
    source: category.iconSource,
    style: .circle(size: AppIconSize.lg, tint: .accentMonochrome)
)
```

### 3. Группируйте похожие стили

```swift
// ✅ Хорошо - создайте extension для проекта
extension IconStyle {
    static func accountIcon(size: CGFloat = AppIconSize.xl) -> IconStyle {
        .bankLogo(size: size)
    }

    static func transactionIcon() -> IconStyle {
        .inline(tint: .primaryMonochrome)
    }
}
```

### 4. Не создавайте IconStyle в body

```swift
// ✅ Хорошо
struct MyView: View {
    private let iconStyle: IconStyle = .categoryIcon()

    var body: some View {
        IconView(source: source, style: iconStyle)
    }
}

// ❌ Плохо - создается на каждой перерисовке
struct MyView: View {
    var body: some View {
        IconView(
            source: source,
            style: .circle(size: 40, tint: .accentMonochrome)
        )
    }
}
```

---

## 🎨 Design System Sizes

Используйте размеры из `AppIconSize`:

```swift
AppIconSize.xs          // 12pt - micro icons
AppIconSize.indicator   // 14pt - small indicators
AppIconSize.sm          // 16pt - inline icons
AppIconSize.md          // 20pt - default (toolbar)
AppIconSize.lg          // 24pt - emphasized (category)
AppIconSize.xl          // 32pt - large (bank logos)
AppIconSize.avatar      // 40pt - medium avatar
AppIconSize.xxl         // 44pt - extra large
AppIconSize.xxxl        // 48pt - hero (empty states)
AppIconSize.categoryIcon // 50pt - category rows
AppIconSize.fab         // 56pt - floating action
AppIconSize.coin        // 64pt - category coins
AppIconSize.budgetRing  // 72pt - budget ring
AppIconSize.largeButton // 80pt - large buttons
```

---

## 🔍 Troubleshooting

### Иконка не отображается

**Проблема:** SF Symbol не показывается
```swift
IconView(source: .sfSymbol("nonexistent.icon"), style: .categoryIcon())
```

**Решение:** Проверьте название символа в SF Symbols app

---

### Логотип загружается медленно

**Проблема:** Долгая загрузка brand service логотипа

**Причина:** Первая загрузка с logo.dev идет через сеть

**Решение:** Используйте prefetch для важных логотипов:
```swift
Task {
    await LogoService.shared.prefetch(brandNames: ["netflix", "spotify"])
}
```

---

### Placeholder вместо иконки

**Проблема:** Показывается placeholder когда iconSource = nil

**Решение:** Это ожидаемое поведение. Если нужна другая иконка:
```swift
IconView(
    source: iconSource ?? .sfSymbol("photo"),
    style: .placeholder(size: 40)
)
```

---

## 📖 См. также

- `IconStyle.swift` - полное API стилей
- `IconSource.swift` - типы источников иконок
- `AppTheme.swift` - Design System токены
- `BankLogo.swift` - банковские логотипы
- `ServiceLogo.swift` - сервисные логотипы

---

## 🎯 Roadmap

### Планируется добавить:

- [ ] **SVG Support** - `.svg(String)` в IconSource
- [ ] **Анимация** - `.animated()` modifier для иконок
- [ ] **Accessibility** - улучшенные labels и hints
- [ ] **Dynamic Type** - автоматическое масштабирование
- [ ] **Цветовые схемы** - автоматическая адаптация под light/dark mode
- [ ] **Кэширование стилей** - переиспользование IconStyle instances

---

**Создано:** 2026-02-12
**Версия:** 1.0
**Автор:** Claude Sonnet 4.5
