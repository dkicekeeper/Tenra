# IconView Cheat Sheet 🚀

## ⚡️ Быстрый старт

```swift
// Автостиль
IconView(source: account.iconSource, size: 32)

// С пресетом
IconView(source: .sfSymbol("star"), style: .categoryIcon())
```

---

## 🎨 Пресеты

```swift
.categoryIcon()          // Категории (circle, accent, 24pt)
.categoryCoin()          // Монета категории (circle, accent, 64pt, фон)
.bankLogo()              // Банк (rounded, 32pt)
.bankLogoLarge()         // Крупный банк (rounded, 40pt)
.serviceLogo()           // Сервис (rounded, 32pt)
.serviceLogoLarge()      // Крупный сервис (rounded, 40pt)
.placeholder(size)       // Пустое (rounded, серый, фон)
.toolbar()               // Toolbar (circle, 20pt)
.inline()                // Inline (circle, 16pt)
.emptyState()            // Empty state (circle, 48pt, secondary)
```

---

## 🔧 Базовые стили

```swift
// Круг
.circle(
    size: 40,
    tint: .accentMonochrome,
    backgroundColor: .gray,
    padding: 8
)

// Скругленный квадрат
.roundedSquare(
    size: 40,
    cornerRadius: 10,  // nil = 20% от size
    tint: .original,
    backgroundColor: nil,
    padding: nil
)

// Квадрат
.square(
    size: 40,
    tint: .monochrome(.blue)
)
```

---

## 🎨 Цвета (Tint)

```swift
.monochrome(.red)             // Монохром
.hierarchical(.blue)          // Иерархический (iOS 15+)
.palette([.red, .blue, .green])  // Палитра (iOS 15+)
.original                     // Оригинальные цвета

// Пресеты
.accentMonochrome            // AppColors.accent
.primaryMonochrome           // AppColors.textPrimary
.secondaryMonochrome         // AppColors.textSecondary
.successMonochrome           // AppColors.success
.destructiveMonochrome       // AppColors.destructive
```

---

## 📏 Размеры (AppIconSize)

```swift
.xs          // 12pt
.indicator   // 14pt
.sm          // 16pt - inline
.md          // 20pt - toolbar
.lg          // 24pt - category
.xl          // 32pt - bank logo
.avatar      // 40pt
.xxl         // 44pt
.xxxl        // 48pt - empty state
.categoryIcon // 50pt
.fab         // 56pt
.coin        // 64pt - category coin
.budgetRing  // 72pt
.largeButton // 80pt
```

---

## 💡 Типовые случаи

### Account/Bank
```swift
IconView(source: account.iconSource, style: .bankLogo())
```

### Category
```swift
IconView(source: category.iconSource, style: .categoryIcon())
```

### Subscription/Service
```swift
IconView(source: subscription.iconSource, style: .serviceLogo())
```

### Button
```swift
IconView(source: .sfSymbol("gear"), style: .toolbar())
```

### Placeholder
```swift
IconView(source: nil, style: .placeholder(size: 40))
```

### Custom
```swift
IconView(
    source: .sfSymbol("heart.fill"),
    style: .circle(
        size: 50,
        tint: .monochrome(.red),
        backgroundColor: .pink.opacity(0.2)
    )
)
```

---

## ✅ Миграция завершена

`BrandLogoDisplayView` полностью заменен на `IconView`

```swift
// Текущий API
IconView(source: source, size: 32)

// С пресетом
IconView(source: source, style: .bankLogo())
```

---

## ⚠️ Best Practices

✅ **DO**
```swift
// Используй пресеты
IconView(source: source, style: .categoryIcon())

// Используй Design System токены
.circle(size: AppIconSize.xl, tint: .accentMonochrome)

// Кэшируй стиль
private let style: IconStyle = .bankLogo()
```

❌ **DON'T**
```swift
// Не создавай стиль в body
IconView(source: source, style: .circle(size: 40, ...))

// Не используй магические числа
.circle(size: 32, tint: .monochrome(.blue))

// Не дублируй настройки пресетов
.circle(size: AppIconSize.lg, tint: .accentMonochrome)  // Используй .categoryIcon()
```

---

## 🎯 Шаблоны

### List Row
```swift
HStack(spacing: AppSpacing.md) {
    IconView(source: item.iconSource, style: .bankLogo())
    Text(item.name)
    Spacer()
}
```

### Card Header
```swift
HStack {
    IconView(source: item.iconSource, style: .serviceLogoLarge())
    VStack(alignment: .leading) {
        Text(item.name).font(AppTypography.h4)
        Text(item.subtitle).font(AppTypography.bodySmall)
    }
}
```

### Empty State
```swift
VStack(spacing: AppSpacing.lg) {
    IconView(source: .sfSymbol("photo"), style: .emptyState())
    Text("No items").font(AppTypography.h4)
    Text("Add your first item").font(AppTypography.body)
}
```

### Toolbar
```swift
.toolbar {
    ToolbarItem {
        Button {
            // action
        } label: {
            IconView(source: .sfSymbol("gear"), style: .toolbar())
        }
    }
}
```

### Grid Item
```swift
LazyVGrid(columns: columns) {
    ForEach(items) { item in
        VStack(spacing: AppSpacing.xs) {
            IconView(source: item.iconSource, style: .serviceLogo())
            Text(item.name).font(AppTypography.caption)
        }
    }
}
```

---

**Версия:** 1.0 | **Дата:** 2026-02-12
