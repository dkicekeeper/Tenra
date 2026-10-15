# Design Tokens Migration Guide
## Tenra — Руководство по миграции на дизайн-токены

> **Дата:** 2026-01-29
> **Версия:** 1.0
> **Статус:** Активный рефакторинг

---

## 📋 Оглавление

1. [Введение](#введение)
2. [Новые токены](#новые-токены)
3. [Паттерны миграции](#паттерны-миграции)
4. [Примеры рефакторинга](#примеры-рефакторинга)
5. [Чек-лист для View файлов](#чек-лист-для-view-файлов)
6. [Оставшаяся работа](#оставшаяся-работа)

---

## Введение

### Цель миграции
Устранить все **hardcoded значения** (magic numbers) из View файлов и заменить их на **семантические дизайн-токены** из `AppTheme.swift`.

### Принципы
- ✅ **Semantic naming** — токены описывают значение, не число
- ✅ **Single source of truth** — все UI константы в одном месте
- ✅ **Light/Dark compatible** — автоматическая адаптация цветов
- ✅ **Scalable** — легко менять дизайн глобально
- ✅ **No rewrites** — только замена значений, не архитектуры

### Статус
- **Расширено токенов**: 50+
- **Отрефакторено файлов**: 13
- **Осталось файлов**: ~30

---

## Новые токены

### AppSpacing (расширен на +8 токенов)

#### Базовые токены
```swift
AppSpacing.xxs     = 2   // Минимальный отступ (tight inline spacing)
AppSpacing.xs      = 4   // Микро отступ (icon ↔ text)
AppSpacing.compact = 6   // Компактный отступ (tight button padding)
AppSpacing.sm      = 8   // Малый отступ (vertical padding rows)
AppSpacing.md      = 12  // Средний отступ (default VStack/HStack spacing)
AppSpacing.lg      = 16  // Большой отступ (horizontal padding экранов)
AppSpacing.xl      = 20  // Очень большой отступ (major sections)
AppSpacing.xxl     = 24  // Максимальный отступ (screen sections)
AppSpacing.xxxl    = 32  // Screen margins (редко)
```

#### Семантические токены
```swift
AppSpacing.pageHorizontal   = lg   // Horizontal padding страниц
AppSpacing.sectionVertical  = xxl  // Vertical spacing секций
AppSpacing.cardPadding      = md   // Padding внутри карточек
AppSpacing.listRowSpacing   = sm   // Spacing между элементами списка
AppSpacing.iconText         = xs   // Spacing между иконкой и текстом
AppSpacing.labelValue       = md   // Spacing между label и value
```

---

### AppRadius (расширен на +6 токенов)

#### Базовые токены
```swift
AppRadius.xs       = 4   // Минимальные элементы (indicators, badges)
AppRadius.compact  = 6   // Очень малые элементы (compact chips)
AppRadius.sm       = 8   // Малые элементы (chips, small buttons)
AppRadius.md       = 10  // Стандартные карточки и кнопки
AppRadius.lg       = 12  // Большие карточки
AppRadius.pill     = 20  // Pills и filter chips
AppRadius.circle   = ∞   // Круги (category icons, avatars)
```

#### Семантические токены
```swift
AppRadius.card    = md   // Card corner radius
AppRadius.button  = md   // Button corner radius
AppRadius.sheet   = lg   // Sheet corner radius
AppRadius.chip    = sm   // Chip corner radius
```

---

### AppIconSize (расширен на +5 токенов)

```swift
AppIconSize.xs            = 12  // Micro icons (tiny indicators, badges)
AppIconSize.indicator     = 14  // Small indicators (dots, small badges)
AppIconSize.sm            = 16  // Inline icons (в тексте)
AppIconSize.md            = 20  // Default icons (toolbar, списки)
AppIconSize.lg            = 24  // Emphasized icons (category icons)
AppIconSize.xl            = 32  // Large icons (bank logos)
AppIconSize.avatar        = 40  // Medium avatar size (logo picker)
AppIconSize.xxl           = 44  // Extra large (category circles)
AppIconSize.xxxl          = 48  // Hero icons (empty states)
AppIconSize.categoryIcon  = 50  // Category row icons
AppIconSize.fab           = 56  // Floating action buttons
AppIconSize.coin          = 64  // Category coins
AppIconSize.largeButton   = 80  // Large action buttons (voice input)
```

---

### AppTypography (расширен на +6 семантических токенов)

```swift
// Базовые токены (существующие)
AppTypography.h1            // largeTitle.bold
AppTypography.h2            // title.semibold
AppTypography.h3            // title2.semibold
AppTypography.h4            // title3.semibold
AppTypography.bodyLarge     // body.medium
AppTypography.body          // body
AppTypography.bodySmall     // subheadline
AppTypography.caption       // caption
AppTypography.captionEmphasis // caption.medium
AppTypography.caption2      // caption2

// Новые семантические токены
AppTypography.screenTitle    = h1                      // Screen titles
AppTypography.sectionTitle   = h3                      // Section headers
AppTypography.bodyPrimary    = body                    // Primary body text
AppTypography.bodySecondary  = bodySmall               // Secondary text
AppTypography.label          = bodySmall.weight(.medium) // Label text
AppTypography.amount         = bodyLarge.weight(.semibold) // Monetary values
```

---

### AppColors (NEW — +16 токенов)

#### Backgrounds
```swift
AppColors.backgroundPrimary    = Color(.systemBackground)
AppColors.surface              = Color(.systemGray6)
AppColors.cardBackground       = surface  // Alias
AppColors.secondaryBackground  = Color(.systemGray5)
AppColors.screenBackground     = backgroundPrimary  // Alias
```

#### Text
```swift
AppColors.textPrimary   = Color.primary
AppColors.textSecondary = Color.secondary
AppColors.textTertiary  = Color.gray
```

#### Interactive
```swift
AppColors.accent      = Color.blue
AppColors.destructive = Color.red
AppColors.success     = Color.green
AppColors.warning     = Color.orange
```

#### Dividers & Borders
```swift
AppColors.divider = Color(.separator)
AppColors.border  = Color(.systemGray4)
```

#### Transaction Types (semantic)
```swift
AppColors.income   = Color.green
AppColors.expense  = Color.red
AppColors.transfer = Color.blue
```

---

### AppSize (NEW — +19 токенов)

#### Buttons & Controls
```swift
AppSize.buttonSmall   = 40   // Small button (40x40)
AppSize.buttonMedium  = 56   // Medium button (56x56)
AppSize.buttonLarge   = 64   // Large button (64x64)
AppSize.buttonXL      = 80   // Extra large button (80x80)
```

#### Cards & Containers
```swift
AppSize.subscriptionCardWidth    = 120
AppSize.subscriptionCardHeight   = 80
AppSize.analyticsCardWidth       = 200
AppSize.analyticsCardHeight      = 140
```

#### Scroll & List Constraints
```swift
AppSize.previewScrollHeight = 300  // Max height для scrollable previews
AppSize.resultListHeight    = 150  // Max height для result lists
AppSize.contentMinHeight    = 120  // Min height для content sections
AppSize.rowHeight           = 60   // Standard row height
```

#### Specific UI Elements
```swift
AppSize.calendarPickerWidth = 180  // Calendar picker width
AppSize.waveHeightSmall     = 80   // Wave animation height (small)
AppSize.waveHeightMedium    = 100  // Wave animation height (medium)
AppSize.skeletonHeight      = 16   // Skeleton placeholder height
AppSize.cursorWidth         = 2    // Cursor line width
AppSize.cursorHeight        = 36   // Cursor line height
```

---

### View Modifiers (новые +4 helper'а)

```swift
.screenPadding()       // Horizontal padding для экранов (pageHorizontal)
.sectionSpacing()      // Vertical spacing для секций (sectionVertical)
.cardContentPadding()  // Card padding (cardPadding)
.listRowPadding()      // List row padding (pageHorizontal + listRowSpacing)
```

---

## Паттерны миграции

### Паттерн 1: Spacing → AppSpacing

**До:**
```swift
VStack(spacing: 16) { }
.padding(.horizontal, 16)
.padding(.vertical, 8)
.padding(12)
```

**После:**
```swift
VStack(spacing: AppSpacing.lg) { }
.screenPadding()  // или .padding(.horizontal, AppSpacing.pageHorizontal)
.padding(.vertical, AppSpacing.listRowSpacing)
.cardContentPadding()  // или .padding(AppSpacing.cardPadding)
```

---

### Паттерн 2: Corner Radius → AppRadius

**До:**
```swift
.cornerRadius(10)
.cornerRadius(6)
.cornerRadius(4)
```

**После:**
```swift
.cornerRadius(AppRadius.card)
.cornerRadius(AppRadius.compact)
.cornerRadius(AppRadius.xs)
```

---

### Паттерн 3: Icon & Frame Sizes → AppIconSize / AppSize

**До:**
```swift
.font(.system(size: 24))
.frame(width: 40, height: 40)
.frame(width: 64, height: 64)
.frame(width: 80, height: 80)
```

**После:**
```swift
.font(.system(size: AppIconSize.lg))
.frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
.frame(width: AppSize.buttonLarge, height: AppSize.buttonLarge)
.frame(width: AppSize.buttonXL, height: AppSize.buttonXL)
```

---

### Паттерн 4: Colors → AppColors

**До:**
```swift
.foregroundColor(.primary)
.foregroundColor(.secondary)
.foregroundColor(.blue)
.foregroundColor(.red)
.foregroundColor(.green)
.background(Color(.systemGray6))
```

**После:**
```swift
.foregroundColor(AppColors.textPrimary)
.foregroundColor(AppColors.textSecondary)
.foregroundColor(AppColors.accent)
.foregroundColor(AppColors.destructive)
.foregroundColor(AppColors.success)
.background(AppColors.surface)
```

---

### Паттерн 5: Typography → AppTypography

**До:**
```swift
.font(.headline)
.font(.subheadline)
.font(.caption)
.font(.body)
```

**После:**
```swift
.font(AppTypography.h4)
.font(AppTypography.bodySecondary)
.font(AppTypography.caption)
.font(AppTypography.bodyPrimary)
```

---

## Примеры рефакторинга

### Пример 1: ContentView.swift (Bottom Actions)

**До:**
```swift
Button(action: { showingVoiceInput = true }) {
    Image(systemName: "mic.fill")
        .font(.system(size: 24, weight: .semibold))
        .frame(width: 64, height: 64)
}
.padding(.horizontal, AppSpacing.lg)
```

**После:**
```swift
Button(action: { showingVoiceInput = true }) {
    Image(systemName: "mic.fill")
        .font(.system(size: AppIconSize.lg))
        .fontWeight(.semibold)
        .frame(width: AppSize.buttonLarge, height: AppSize.buttonLarge)
}
.screenPadding()
```

**Изменения:**
- `24` → `AppIconSize.lg`
- `64` → `AppSize.buttonLarge`
- `.padding(.horizontal, AppSpacing.lg)` → `.screenPadding()`

---

### Пример 2: CSVPreviewView.swift (Cards & Layout)

**До:**
```swift
VStack(alignment: .leading, spacing: 16) {
    VStack(alignment: .leading, spacing: 8) {
        // ...
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(10)

    Text(header)
        .padding(8)
        .background(Color.blue.opacity(0.2))
        .cornerRadius(6)
}
```

**После:**
```swift
VStack(alignment: .leading, spacing: AppSpacing.lg) {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
        // ...
    }
    .cardContentPadding()
    .background(AppColors.surface)
    .cornerRadius(AppRadius.card)

    Text(header)
        .padding(AppSpacing.sm)
        .background(AppColors.accent.opacity(0.2))
        .cornerRadius(AppRadius.compact)
}
```

**Изменения:**
- `spacing: 16` → `spacing: AppSpacing.lg`
- `spacing: 8` → `spacing: AppSpacing.sm`
- `.padding()` → `.cardContentPadding()`
- `Color(.systemGray6)` → `AppColors.surface`
- `.cornerRadius(10)` → `.cornerRadius(AppRadius.card)`
- `.padding(8)` → `.padding(AppSpacing.sm)`
- `Color.blue` → `AppColors.accent`
- `.cornerRadius(6)` → `.cornerRadius(AppRadius.compact)`

---

### Пример 3: VoiceInputView.swift (Button Colors)

**До:**
```swift
Circle()
    .fill(Color.red)
    .frame(width: 80, height: 80)

Image(systemName: "stop.fill")
    .font(.system(size: 32))
```

**После:**
```swift
Circle()
    .fill(AppColors.destructive)
    .frame(width: AppSize.buttonXL, height: AppSize.buttonXL)

Image(systemName: "stop.fill")
    .font(.system(size: AppIconSize.xl))
```

**Изменения:**
- `Color.red` → `AppColors.destructive`
- `80` → `AppSize.buttonXL`
- `32` → `AppIconSize.xl`

---

### Пример 4: CategoryRow.swift (Semantic Colors & Animation)

**До:**
```swift
Circle()
    .stroke(progress.isOverBudget ? Color.red : Color.green, ...)
    .frame(width: 50, height: 50)
    .animation(.easeInOut(duration: 0.3), value: progress.percentage)
```

**После:**
```swift
Circle()
    .stroke(progress.isOverBudget ? AppColors.destructive : AppColors.success, ...)
    .frame(width: AppIconSize.categoryIcon, height: AppIconSize.categoryIcon)
    .animation(.easeInOut(duration: AppAnimation.standard), value: progress.percentage)
```

**Изменения:**
- `Color.red` → `AppColors.destructive`
- `Color.green` → `AppColors.success`
- `50` → `AppIconSize.categoryIcon`
- `0.3` → `AppAnimation.standard`

---

### Пример 5: AmountInputView.swift (Cursor)

**До:**
```swift
Rectangle()
    .fill(Color.primary)
    .frame(width: 2, height: 36)
```

**После:**
```swift
Rectangle()
    .fill(AppColors.textPrimary)
    .frame(width: AppSize.cursorWidth, height: AppSize.cursorHeight)
```

**Изменения:**
- `Color.primary` → `AppColors.textPrimary`
- `2` → `AppSize.cursorWidth`
- `36` → `AppSize.cursorHeight`

---

## Чек-лист для View файлов

При рефакторинге каждого View файла, проверь:

### ✅ Spacing
- [ ] Все `.padding()` с числами заменены на токены
- [ ] Все `spacing:` в VStack/HStack используют токены
- [ ] Использованы семантические токены где возможно (`.screenPadding()`, `.cardContentPadding()`)

### ✅ Corner Radius
- [ ] Все `.cornerRadius()` используют токены
- [ ] Использованы семантические токены (`.cornerRadius(AppRadius.card)`)

### ✅ Icon & Frame Sizes
- [ ] Все `.font(.system(size:))` заменены на токены
- [ ] Все `.frame(width:, height:)` с фиксированными размерами используют токены

### ✅ Colors
- [ ] Все `.foregroundColor()` используют семантические токены
- [ ] Все `.background()` используют семантические токены
- [ ] Transaction type colors используют `AppColors.income/expense/transfer`

### ✅ Typography
- [ ] Все `.font()` используют `AppTypography` где возможно
- [ ] Использованы семантические токены (`bodyPrimary`, `bodySecondary`, `sectionTitle`)

### ✅ Animation
- [ ] Все hardcoded duration заменены на `AppAnimation.standard/fast/slow`

---

## Оставшаяся работа

### Файлы для рефакторинга (приоритет HIGH)

#### CSV Views (4 файла)
- [ ] `CSVColumnMappingView.swift`
- [ ] `CSVEntityMappingView.swift`
- ✅ `CSVPreviewView.swift` (завершён)
- ✅ `CSVImportResultView.swift` (завершён)

#### Subscription Views (3 файла)
- [ ] `SubscriptionDetailView.swift`
- [ ] `SubscriptionsListView.swift`
- ✅ `SubscriptionCalendarView.swift` (завершён)
- ✅ `SubscriptionEditView.swift` (завершён)

#### Account/Category Management (3 файла)
- [ ] `AccountsManagementView.swift`
- [ ] `CategoriesManagementView.swift`
- [ ] `SubcategoriesManagementView.swift`

#### Transaction Views (2 файла)
- [ ] `EditTransactionView.swift`
- [ ] `QuickAddTransactionView.swift`

#### Other Core Views (5 файлов)
- [ ] `HistoryView.swift`
- [ ] `SettingsView.swift`
- [ ] `DepositDetailView.swift`
- [ ] `DepositEditView.swift`
- [ ] `AccountActionView.swift`

### Компоненты для рефакторинга (приоритет MEDIUM)

#### Cards & Rows (5 файлов)
- ✅ `CategoryRow.swift` (завершён)
- [ ] `AccountRow.swift`
- [ ] `AccountCard.swift`
- [ ] `AnalyticsCard.swift`
- [ ] `SubscriptionCard.swift`

#### Input Components (4 файла)
- ✅ `AmountInputView.swift` (завершён)
- [ ] `DescriptionTextField.swift`
- [ ] `DateButtonsView.swift`
- [ ] `RecurringToggleView.swift`

#### Selector Components (3 файла)
- [ ] `AccountSelectorView.swift`
- [ ] `CategorySelectorView.swift`
- [ ] `SubcategorySelectorView.swift`

#### Other Components (5 файлов)
- [ ] `InfoRow.swift`
- [ ] `FilterChip.swift`
- [ ] `SkeletonView.swift`
- [ ] `EmptyStateView.swift`
- [ ] `BrandLogoView.swift`

---

## Советы по рефакторингу

### 1. Начни с самых частых паттернов
- `.cornerRadius(10)` → `AppRadius.card` (20+ файлов)
- `.padding(8)` → `AppSpacing.sm` (15+ файлов)
- `Color(.systemGray6)` → `AppColors.surface` (10+ файлов)

### 2. Используй поиск по всему проекту
```bash
# Найти все .cornerRadius(10)
grep -r "\.cornerRadius(10)" Tenra/Views/

# Найти все .frame(width: 40
grep -r "frame(width: 40" Tenra/Views/

# Найти все .padding(8)
grep -r "\.padding(8)" Tenra/Views/
```

### 3. Тестируй визуально после каждого изменения
- Используй Xcode Preview
- Проверь на симуляторе (Light + Dark mode)
- Убедись что UI не изменился

### 4. Коммитируй часто
```bash
git add Views/CSVPreviewView.swift
git commit -m "refactor: CSVPreviewView uses design tokens"
```

### 5. Обновляй документацию
После завершения рефакторинга файла, отметь его в этом гайде как ✅ завершённый.

---

## Заключение

**Цель**: Достичь **100% coverage** дизайн-токенами во всех View файлах.

**Текущий прогресс**: ~13/43 файлов отрефакторены (~30%)

**Следующие шаги**:
1. Refactor CSV views (4 файла)
2. Refactor Subscription views (2 файла)
3. Refactor Management views (3 файла)
4. Refactor Transaction views (2 файла)
5. Refactor Components (20+ файлов)

**Помни**: Это **не переписывание**, а **систематическое улучшение**. Каждый отрефакторенный файл делает кодовую базу чище, понятнее и легче в поддержке.

---

*Последнее обновление: 2026-01-29*
