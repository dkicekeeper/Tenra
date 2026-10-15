# Design Tokens Quick Reference
## Быстрая справка по дизайн-токенам

> **Дата:** 2026-01-29
> Используй этот документ как шпаргалку при рефакторинге View файлов

---

## 🎨 AppSpacing

| Value | Token | Use Case |
|-------|-------|----------|
| `2` | `AppSpacing.xxs` | Tight inline spacing |
| `4` | `AppSpacing.xs` или `AppSpacing.iconText` | Icon ↔ Text |
| `6` | `AppSpacing.compact` | Tight button padding |
| `8` | `AppSpacing.sm` или `AppSpacing.listRowSpacing` | Row vertical padding |
| `12` | `AppSpacing.md` или `AppSpacing.cardPadding` | Card padding, label-value |
| `16` | `AppSpacing.lg` или `AppSpacing.pageHorizontal` | Screen horizontal padding |
| `20` | `AppSpacing.xl` | Major sections spacing |
| `24` | `AppSpacing.xxl` или `AppSpacing.sectionVertical` | Screen sections spacing |
| `32` | `AppSpacing.xxxl` | Screen margins (редко) |

### View Modifiers
```swift
.screenPadding()       // = .padding(.horizontal, AppSpacing.pageHorizontal)
.cardContentPadding()  // = .padding(AppSpacing.cardPadding)
.sectionSpacing()      // = .padding(.vertical, AppSpacing.sectionVertical)
.listRowPadding()      // = .padding(.horizontal, pageHorizontal).padding(.vertical, listRowSpacing)
```

---

## 📐 AppRadius

| Value | Token | Use Case |
|-------|-------|----------|
| `4` | `AppRadius.xs` | Indicators, badges |
| `6` | `AppRadius.compact` | Compact chips |
| `8` | `AppRadius.sm` или `AppRadius.chip` | Chips, small buttons |
| `10` | `AppRadius.md`, `AppRadius.card`, `AppRadius.button` | Standard cards & buttons |
| `12` | `AppRadius.lg` или `AppRadius.sheet` | Large cards, sheets |
| `20` | `AppRadius.pill` | Pills, filter chips |
| `∞` | `AppRadius.circle` | Circles (avatars, category icons) |

---

## 🔲 AppIconSize

| Value | Token | Use Case |
|-------|-------|----------|
| `12` | `AppIconSize.xs` | Micro icons (tiny indicators) |
| `14` | `AppIconSize.indicator` | Small indicators (dots, badges) |
| `16` | `AppIconSize.sm` | Inline icons (в тексте) |
| `20` | `AppIconSize.md` | Default icons (toolbar, списки) |
| `24` | `AppIconSize.lg` | Emphasized icons |
| `32` | `AppIconSize.xl` | Large icons (bank logos) |
| `40` | `AppIconSize.avatar` | Medium avatar size (logo picker) |
| `44` | `AppIconSize.xxl` | Extra large (category circles) |
| `48` | `AppIconSize.xxxl` | Hero icons (empty states) |
| `50` | `AppIconSize.categoryIcon` | Category row icons |
| `56` | `AppIconSize.fab` | Floating action buttons |
| `64` | `AppIconSize.coin` | Category coins |
| `80` | `AppIconSize.largeButton` | Large action buttons |

---

## 📦 AppSize (Container Sizes)

### Buttons
| Value | Token |
|-------|-------|
| `40x40` | `AppSize.buttonSmall` |
| `56x56` | `AppSize.buttonMedium` |
| `64x64` | `AppSize.buttonLarge` |
| `80x80` | `AppSize.buttonXL` |

### Cards
| Value | Token |
|-------|-------|
| `120` (width) | `AppSize.subscriptionCardWidth` |
| `80` (height) | `AppSize.subscriptionCardHeight` |
| `200` (width) | `AppSize.analyticsCardWidth` |
| `140` (height) | `AppSize.analyticsCardHeight` |

### Constraints
| Value | Token |
|-------|-------|
| `300` | `AppSize.previewScrollHeight` |
| `150` | `AppSize.resultListHeight` |
| `120` | `AppSize.contentMinHeight` |
| `60` | `AppSize.rowHeight` |

### Specific Elements
| Value | Token |
|-------|-------|
| `180` | `AppSize.calendarPickerWidth` |
| `80` | `AppSize.waveHeightSmall` |
| `100` | `AppSize.waveHeightMedium` |
| `16` | `AppSize.skeletonHeight` |
| `2` | `AppSize.cursorWidth` |
| `36` | `AppSize.cursorHeight` |

---

## 🎭 AppColors

### Backgrounds
```swift
Color(.systemBackground)     → AppColors.backgroundPrimary / .screenBackground
Color(.systemGray6)          → AppColors.surface / .cardBackground
Color(.systemGray5)          → AppColors.secondaryBackground
```

### Text
```swift
Color.primary / .foregroundColor(.primary)  → AppColors.textPrimary
Color.secondary / .foregroundColor(.secondary) → AppColors.textSecondary
Color.gray                   → AppColors.textTertiary
```

### Interactive
```swift
Color.blue     → AppColors.accent
Color.red      → AppColors.destructive
Color.green    → AppColors.success
Color.orange   → AppColors.warning
```

### Dividers & Borders
```swift
Color(.separator)   → AppColors.divider
Color(.systemGray4) → AppColors.border
```

### Transaction Types
```swift
// Income
Color.green   → AppColors.income

// Expense
Color.red     → AppColors.expense

// Transfer
Color.blue    → AppColors.transfer
```

---

## ✍️ AppTypography

### Headers
```swift
.font(.headline)         → AppTypography.h4
.font(.title)            → AppTypography.h2
.font(.title2)           → AppTypography.h3 / .sectionTitle
.font(.title3)           → AppTypography.h4
.font(.largeTitle)       → AppTypography.h1 / .screenTitle
```

### Body
```swift
.font(.body)             → AppTypography.body / .bodyPrimary
.font(.subheadline)      → AppTypography.bodySmall / .bodySecondary
```

### Captions
```swift
.font(.caption)          → AppTypography.caption
.font(.caption2)         → AppTypography.caption2
```

### Semantic
```swift
// Amounts (monetary values)
AppTypography.amount     // = bodyLarge.weight(.semibold)

// Labels
AppTypography.label      // = bodySmall.weight(.medium)
```

---

## ⏱️ AppAnimation

```swift
duration: 0.1    → AppAnimation.fast
duration: 0.25   → AppAnimation.standard
duration: 0.35   → AppAnimation.slow

// Spring animation
AppAnimation.spring
```

---

## 🔄 Быстрые замены (Find & Replace)

### Spacing
```
.padding(16)              → .screenPadding()
.padding(.horizontal, 16) → .screenPadding()
.padding(12)              → .cardContentPadding()
.padding(8)               → .padding(AppSpacing.sm)
.padding(6)               → .padding(AppSpacing.compact)
.padding(4)               → .padding(AppSpacing.xs)
spacing: 16               → spacing: AppSpacing.lg
spacing: 12               → spacing: AppSpacing.md
spacing: 8                → spacing: AppSpacing.sm
spacing: 24               → spacing: AppSpacing.xxl
```

### Corner Radius
```
.cornerRadius(10)   → .cornerRadius(AppRadius.card) / .cornerRadius(AppRadius.button)
.cornerRadius(8)    → .cornerRadius(AppRadius.sm)
.cornerRadius(6)    → .cornerRadius(AppRadius.compact)
.cornerRadius(4)    → .cornerRadius(AppRadius.xs)
.cornerRadius(12)   → .cornerRadius(AppRadius.lg)
```

### Colors
```
.foregroundColor(.primary)              → .foregroundColor(AppColors.textPrimary)
.foregroundColor(.secondary)            → .foregroundColor(AppColors.textSecondary)
.foregroundColor(.blue)                 → .foregroundColor(AppColors.accent)
.foregroundColor(.red)                  → .foregroundColor(AppColors.destructive)
.foregroundColor(.green)                → .foregroundColor(AppColors.success)
.background(Color(.systemGray6))        → .background(AppColors.surface)
.background(Color(.systemGray5))        → .background(AppColors.secondaryBackground)
.background(Color.blue)                 → .background(AppColors.accent)
```

### Frame Sizes
```
.frame(width: 40, height: 40)   → .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
.frame(width: 64, height: 64)   → .frame(width: AppSize.buttonLarge, height: AppSize.buttonLarge)
.frame(width: 80, height: 80)   → .frame(width: AppSize.buttonXL, height: AppSize.buttonXL)
.frame(width: 24, height: 24)   → .frame(width: AppIconSize.lg, height: AppIconSize.lg)
.font(.system(size: 24))        → .font(.system(size: AppIconSize.lg))
.font(.system(size: 32))        → .font(.system(size: AppIconSize.xl))
.font(.system(size: 48))        → .font(.system(size: AppIconSize.xxxl))
```

---

## 📝 Шаблон рефакторинга

### 1. Найди паттерн
```bash
grep -r "\.cornerRadius(10)" Views/YourFile.swift
```

### 2. Замени на токен
```swift
// До
.cornerRadius(10)

// После
.cornerRadius(AppRadius.card)
```

### 3. Тестируй
- Проверь Xcode Preview
- Запусти на симуляторе (Light + Dark mode)
- Убедись что UI не изменился

### 4. Коммит
```bash
git add Views/YourFile.swift
git commit -m "refactor: YourFile uses design tokens"
```

---

## ⚠️ Важные правила

### ✅ DO
- Используй **семантические токены** когда возможно (`AppRadius.card`, не `AppRadius.md`)
- Используй **view modifiers** для общих паттернов (`.screenPadding()`)
- Замени **все** hardcoded значения в файле за раз
- Тестируй **визуально** после каждого изменения

### ❌ DON'T
- Не меняй **логику** View, только **стайлинг**
- Не вводи **новые токены** без обсуждения
- Не делай **breaking changes** в существующих токенах
- Не используй **magic numbers** в новом коде

---

## 🎯 Приоритеты рефакторинга

### HIGH (20+ instances)
1. `.cornerRadius(10)` → `AppRadius.card`
2. `Color(.systemGray6)` → `AppColors.surface`
3. `.padding(8)` → `AppSpacing.sm`

### MEDIUM (10-20 instances)
4. `.foregroundColor(.blue)` → `AppColors.accent`
5. `.foregroundColor(.secondary)` → `AppColors.textSecondary`
6. `spacing: 16` → `spacing: AppSpacing.lg`

### LOW (<10 instances)
7. `.frame(width: 40, height: 40)` → `AppIconSize.avatar`
8. `.font(.system(size: 24))` → `AppIconSize.lg`

---

*Последнее обновление: 2026-01-29*
