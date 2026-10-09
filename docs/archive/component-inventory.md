# component-inventory.md
## Tenra — Полный реестр UI-компонентов

> **Дата создания:** 2026-01-28
> **Последнее обновление:** 2026-02-15 — Phase 9 Complete + UI Components Refactoring
> **Версия:** 4.0
> **Статус:** ✅ Production Ready
> **Всего компонентов:** 68

---

## 📋 Структура документа
1. [Общая статистика](#общая-статистика)
2. [Компоненты по категориям](#компоненты-по-категориям)
3. [Недавние изменения](#недавние-изменения)
4. [Design System Integration](#design-system-integration)
5. [Component Usage Guide](#component-usage-guide)

---

## 📊 Общая статистика

### По категориям
| Категория | Количество | Расположение |
|-----------|------------|--------------|
| Shared Components | 24 | `Views/Shared/Components/` |
| Settings Components | 13 | `Views/Settings/Components/` |
| Categories Components | 8 | `Views/Categories/Components/` |
| Accounts Components | 7 | `Views/Accounts/Components/` |
| Transactions Components | 5 | `Views/Transactions/Components/` |
| Subscriptions Components | 4 | `Views/Subscriptions/Components/` |
| History Components | 3 | `Views/History/Components/` |
| Deposits Components | 2 | `Views/Deposits/Components/` |
| VoiceInput Components | 1 | `Views/VoiceInput/Components/` |
| Root Components | 1 | `Views/Components/` |
| **TOTAL** | **68** | — |

### По типу
- **Cards:** 5 компонентов (display-only)
- **Rows:** 12 компонентов (list items)
- **Buttons/Controls:** 8 компонентов (interactive)
- **Inputs/Selectors:** 15 компонентов (form elements)
- **Filters:** 5 компонентов (filtering)
- **States:** 3 компонента (empty/error/loading)
- **Containers:** 4 компонента (layout)
- **Specialized:** 16 компонентов (specific features)

### Последние улучшения
- ✅ **UI Components Refactoring Complete** (2026-02-14)
- ✅ **10 новых компонентов** создано
- ✅ **150+ lines** дублированного кода удалено
- ✅ **100% локализация** (no hard-coded strings)
- ✅ **Design System Integration** во всех компонентах

---

## 🎨 Компоненты по категориям

## 1. Shared Components (24) — Переиспользуемые

**Расположение:** `/Tenra/Views/Shared/Components/`

### Cards & Display
| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `AnalyticsCard` | `AnalyticsCard.swift` | Сводочная карточка income/expense с progress bar | ✅ |
| `TransactionsSummaryCard` | `TransactionsSummaryCard.swift` | Сводка транзакций | ✅ |
| `FormattedAmountText` | `FormattedAmountText.swift` | Форматированное отображение суммы | ✅ |

### Form Elements
| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `FormSection` | `FormSection.swift` | Container для form секций | ⭐ New |
| `FormTextField` | `FormTextField.swift` | Text input для форм | ✅ |
| `DescriptionTextField` | `DescriptionTextField.swift` | Многострочное поле описания | ✅ |
| `ColorPickerRow` | `ColorPickerRow.swift` | Row для выбора цвета | ✅ |
| `DatePickerRow` | `DatePickerRow.swift` | Row для выбора даты | ⭐ New |
| `DateButtonsView` | `DateButtonsView.swift` | Кнопки навигации по датам | ✅ |
| `SegmentedPickerView` | `SegmentedPickerView.swift` | Generic segmented picker | ✅ |
| `CurrencySelectorView` | `CurrencySelectorView.swift` | Выбор валюты | ✅ |

### Icons & Pickers
| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| **`IconView`** | `IconView.swift` | ⭐ Unified icon/logo display с Design System интеграцией | ⭐ Refactored |
| **`IconPickerView`** | `IconPickerView.swift` | ⭐ Modal picker для иконок с категориями сервисов | ⭐ Enhanced |
| **`IconPickerRow`** | `IconPickerRow.swift` | ⭐ Row для выбора иконки | ⭐ New |
| **`MenuPickerRow`** | `MenuPickerRow.swift` | ⭐ Universal menu picker для single-select | ⭐ New |

### Headers & Info
| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `SectionHeaderView` | `SectionHeaderView.swift` | Section header | ✅ |
| `DateSectionHeaderView` | `DateSectionHeaderView.swift` | Date section header | ✅ |
| `InfoRow` | `InfoRow.swift` | Label + value display row | ✅ |

### States & Messages
| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `ErrorMessageView` | `ErrorMessageView.swift` | Error message banner | ✅ |
| `WarningMessageView` | `WarningMessageView.swift` | Warning message banner | ✅ |
| `SuccessMessageView` | `SuccessMessageView.swift` | Success message banner | ✅ |
| `SkeletonView` | `SkeletonView.swift` | Loading skeleton animation | ✅ |

### Specialized
| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `EditSheetContainer` | `EditSheetContainer.swift` | Generic container для edit sheets | ⭐ Reusable |
| `HighlightedText` | `HighlightedText.swift` | Text с подсветкой NLP entities | ✅ |

---

## 2. Settings Components (13)

**Расположение:** `/Tenra/Views/Settings/Components/`

| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `ActionSettingsRow` | `ActionSettingsRow.swift` | Row с action button | ✅ |
| `NavigationSettingsRow` | `NavigationSettingsRow.swift` | Row с navigation link | ✅ |
| `BankLogoRow` | `BankLogoRow.swift` | Row отображения bank logo | ✅ |
| `BrandLogoView` | `BrandLogoView.swift` | Brand logo display | ✅ |
| `WallpaperPickerRow` | `WallpaperPickerRow.swift` | Row выбора wallpaper | ✅ |
| `SettingsGeneralSection` | `SettingsGeneralSection.swift` | General settings section | ✅ |
| `SettingsDataManagementSection` | `SettingsDataManagementSection.swift` | Data management section | ✅ |
| `SettingsExportImportSection` | `SettingsExportImportSection.swift` | Export/import section | ✅ |
| `SettingsDangerZoneSection` | `SettingsDangerZoneSection.swift` | Danger zone section | ✅ |
| `SettingsSectionHeaderView` | `SettingsSectionHeaderView.swift` | Settings section header | ✅ |
| `ImportFlowSheetsContainer` | `ImportFlowSheetsContainer.swift` | Container для import flow | ✅ |
| `ImportProgressSheet` | `ImportProgressSheet.swift` | Import progress display | ✅ |
| `ExportActivityView` | `ExportActivityView.swift` | Export activity wrapper | ✅ |

---

## 3. Categories Components (8)

**Расположение:** `/Tenra/Views/Categories/Components/`

### Display & Selection
| Component | File | Responsibility | Props | Actions | Used In |
|-----------|------|----------------|-------|---------|---------|
| `CategoryChip` | `CategoryChip.swift` | Монетка категории с иконкой + budget ring | `category: String`, `type: TransactionType`, `customCategories`, `isSelected: Bool`, `budgetProgress`, `budgetAmount` | `onTap` | QuickAdd, CategorySelector |
| `CategoryRow` | `CategoryRow.swift` | Row категории с budget progress | `category: CustomCategory`, `isDefault: Bool`, `budgetProgress`, `onEdit`, `onDelete` | Edit/Delete | CategoriesManagement |
| `CategorySelectorView` | `CategorySelectorView.swift` | Modal выбора категории | `categories`, `type`, `customCategories`, `selectedCategory`, `budgetProgressMap`, `budgetAmountMap` | `onSelectionChange` | Edit forms |
| `SubcategoryRow` | `SubcategoryRow.swift` | Row подкатегории | `subcategory: Subcategory`, `isSelected: Bool` | `onToggle` | SubcategorySelector |
| `SubcategorySelectorView` | `SubcategorySelectorView.swift` | Modal выбора подкатегорий | `categoriesViewModel`, `categoryId`, `selectedSubcategoryIds` | `onSearchTap` | Edit forms |

### Filtering
| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `CategoryFilterButton` | `CategoryFilterButton.swift` | Button фильтра категорий | ✅ |
| `CategoryFilterView` | `CategoryFilterView.swift` | Modal multi-select фильтрации | ✅ |

### Progress
| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `ExpenseIncomeProgressBar` | `ExpenseIncomeProgressBar.swift` | Двойной progress bar income/expense | ✅ |

---

## 4. Accounts Components (7)

**Расположение:** `/Tenra/Views/Accounts/Components/`

| Component | File | Responsibility | Type | Status |
|-----------|------|----------------|------|--------|
| `AccountCard` | `AccountCard.swift` | Карточка счёта в carousel | Card | ✅ |
| `AccountRow` | `AccountRow.swift` | Row счёта в management list | Row | ✅ |
| `AccountsCarousel` | `AccountsCarousel.swift` | Horizontal carousel счетов | Container | ✅ |
| `AccountSelectorView` | `AccountSelectorView.swift` | Modal выбора счёта | Selector | ✅ |
| `AccountRadioButton` | `AccountRadioButton.swift` | Radio button для счёта | Control | ✅ |
| `AccountFilterMenu` | `AccountFilterMenu.swift` | Menu фильтрации по счёту | Filter | ✅ |
| `EmptyAccountsPrompt` | `EmptyAccountsPrompt.swift` | Empty state для счетов | State | ✅ |

---

## 5. Transactions Components (5)

**Расположение:** `/Tenra/Views/Transactions/Components/`

| Component | File | Responsibility | Props | Status |
|-----------|------|----------------|-------|--------|
| `TransactionCard` | `TransactionCard.swift` | Основная карточка транзакции | `transaction`, `currency`, `customCategories`, `accounts`, `viewModel` | ✅ |
| `TransactionRowContent` | `TransactionRowContent.swift` | Reusable base для transaction rows | `transaction`, `currency`, `customCategories`, `accounts`, `showIcon`, `showDescription` | ✅ |
| `TransactionCardComponents` | `TransactionCardComponents.swift` | Sub-components для TransactionCard | — | ✅ |
| `AmountInputView` | `AmountInputView.swift` | Input для суммы + currency selector | `@Binding amount`, `@Binding selectedCurrency`, `errorMessage` | ✅ |
| `FormattedAmountView` | `FormattedAmountView.swift` | Форматированное отображение суммы | `amount`, `currency`, `type` | ✅ |

---

## 6. Subscriptions Components (4)

**Расположение:** `/Tenra/Views/Subscriptions/Components/`

| Component | File | Responsibility | Props | Status |
|-----------|------|----------------|-------|--------|
| `SubscriptionCard` | `SubscriptionCard.swift` | Карточка подписки в grid | `subscription: RecurringSeries`, `nextChargeDate: Date?` | ✅ Refactored P2 |
| `SubscriptionCalendarView` | `SubscriptionCalendarView.swift` | Calendar view подписок | `subscriptions`, `selectedDate` | ✅ |
| `StaticSubscriptionIconsView` | `StaticSubscriptionIconsView.swift` | Overlapping иконки подписок | `subscriptions: [RecurringSeries]` | ✅ Phase 3 (-67%) |
| `NotificationPermissionView` | `NotificationPermissionView.swift` | Permission prompt для notifications | — | ✅ |

---

## 7. History Components (3)

**Расположение:** `/Tenra/Views/History/Components/`

| Component | File | Responsibility | Props | Status |
|-----------|------|----------------|-------|--------|
| `HistoryFilterSection` | `HistoryFilterSection.swift` | Container всех фильтров history | `transactionsViewModel`, `accountsViewModel`, `categoriesViewModel`, `timeFilterManager` | ✅ |
| `DateSectionHeader` | `DateSectionHeader.swift` | Header группы транзакций по дате | `dateKey: String`, `dayExpenses: Double`, `currency: String` | ✅ |
| `FilterChip` | `FilterChip.swift` | Pill-shaped filter chip | `title: String`, `icon: String?`, `isSelected: Bool` | ✅ |

---

## 8. Deposits Components (2)

**Расположение:** `/Tenra/Views/Deposits/Components/`

| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `DepositRateChangeView` | `DepositRateChangeView.swift` | Отображение изменения ставки | ✅ |
| `DepositTransferView` | `DepositTransferView.swift` | Transfer между депозитными счетами | ✅ |

---

## 9. VoiceInput Components (1)

**Расположение:** `/Tenra/Views/VoiceInput/Components/`

| Component | File | Responsibility | Props | Status |
|-----------|------|----------------|-------|--------|
| `SiriWaveView` | `SiriWaveView.swift` | Анимация волны для voice recording | `amplitude: Double`, `frequency: Double`, `color: Color`, `animationSpeed: Double` | ✅ |

---

## 10. Root Components (1)

**Расположение:** `/Tenra/Views/Components/`

| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| **`CategoryGridView`** | `CategoryGridView.swift` | ⭐ Grid layout для категорий | ⭐ Reference |

---

## 🆕 Недавние изменения

### UI Components Refactoring (2026-02-14)
**Статус:** ✅ Complete

#### Phase 1: Core Components (6)
- ✅ `FormSection` - Reusable form section container
- ✅ `IconPickerRow` - Row для выбора иконки
- ✅ `IconPickerView` - Enhanced с service categories
- ✅ `FrequencyPickerView` - Frequency selection
- ✅ `DatePickerRow` - Date picker row
- ✅ `ReminderPickerView` - Reminder selection

#### Phase 2: Form Components (4)
- ✅ Additional form building blocks
- ✅ Standardized form inputs
- ✅ Consistent validation patterns

#### Phase 3: View Migrations (3)
- ✅ `SubscriptionEditView`: 343 → 270 lines (-21%)
- ✅ `DepositEditView`: Refactored
- ✅ `CategoryEditView`: Refactored

### New Components (2026-02-12 - 2026-02-15)

#### ⭐ MenuPickerRow (Latest)
**File:** `Views/Shared/Components/MenuPickerRow.swift`
**Purpose:** Universal menu picker для single-select scenarios
**Replaces:** Multiple custom picker implementations

**Usage:**
```swift
MenuPickerRow(
    title: "Frequency",
    selectedValue: frequency,
    options: FrequencyOption.allCases,
    optionLabel: { $0.localizedName }
) { newFrequency in
    frequency = newFrequency
}
```

#### ⭐ IconView (Refactored)
**File:** `Views/Shared/Components/IconView.swift`
**Purpose:** Unified icon/logo display с полной Design System интеграцией
**Features:**
- Supports SF Symbols, Custom Icons, Brand Logos, Bank Logos
- Full AppIconSize support
- Consistent styling across app
- Performance optimized

**Usage:**
```swift
IconView(
    systemName: "creditcard",
    size: .medium,
    color: .blue
)

IconView(
    customIcon: "MyCustomIcon",
    size: .large
)
```

#### ⭐ CategoryGridView
**File:** `Views/Components/CategoryGridView.swift`
**Purpose:** Grid layout reference для категорий
**Features:**
- Adaptive grid layout
- Lazy loading
- Optimized for large datasets

### Recent Git History
```
61b2b99 MenuPicker Usage
a6fc643 MenuPicker Update
b5f9526 UI Components Update
a62531d Subscriptions Update
1b8d1a4 IconView Refactoring
a84b97b Добавлены категории сервисов в IconPickerView
83a0b77 Переделан выбор логотипов в grid layout
6735b38 Улучшен UI IconPickerView
311d371 Унифицированный компонент выбора иконок/логотипов
```

---

## 🎨 Design System Integration

### AppTheme Integration
Все компоненты используют централизованную систему дизайна:

#### Colors
```swift
AppColors.primary
AppColors.secondary
AppColors.background
AppColors.cardBackground
AppColors.textPrimary
AppColors.textSecondary
AppColors.success
AppColors.warning
AppColors.error
```

#### Spacing
```swift
AppSpacing.xs   // 4pt
AppSpacing.sm   // 8pt
AppSpacing.md   // 16pt
AppSpacing.lg   // 24pt
AppSpacing.xl   // 32pt
```

#### Typography
```swift
AppTypography.largeTitle
AppTypography.title
AppTypography.headline
AppTypography.body
AppTypography.caption
AppTypography.footnote
```

#### Icon Sizes
```swift
AppIconSize.small   // 16pt
AppIconSize.medium  // 24pt
AppIconSize.large   // 32pt
AppIconSize.xlarge  // 48pt
```

#### Border Radius
```swift
AppRadius.sm  // 8pt
AppRadius.md  // 12pt
AppRadius.lg  // 16pt
AppRadius.xl  // 24pt
```

### Локализация
- ✅ **100% локализация** - no hard-coded strings
- ✅ **EN + RU** поддержка
- ✅ **String catalogs** использование
- ✅ **Pluralization rules** для EN/RU

---

## 📖 Component Usage Guide

### Best Practices

#### 1. Использование существующих компонентов
```swift
// ✅ GOOD - Use existing component
FormSection(title: "Basic Information") {
    FormTextField(
        title: "Name",
        text: $name,
        placeholder: "Enter name"
    )
}

// ❌ BAD - Creating custom form section
VStack {
    Text("Basic Information")
        .font(.caption)
    TextField("Name", text: $name)
}
```

#### 2. Props + Callbacks Pattern
```swift
// ✅ GOOD - Clean separation of concerns
AccountCard(
    account: account,
    onTap: { selectedAccount = account }
)

// ❌ BAD - Direct ViewModel access
AccountCard(
    account: account,
    viewModel: accountsViewModel
)
```

#### 3. Design System Compliance
```swift
// ✅ GOOD - Using Design System
Text("Title")
    .font(AppTypography.headline)
    .foregroundStyle(AppColors.textPrimary)
    .padding(AppSpacing.md)

// ❌ BAD - Hard-coded values
Text("Title")
    .font(.system(size: 17, weight: .semibold))
    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
    .padding(16)
```

#### 4. Локализация
```swift
// ✅ GOOD - Localized strings
Text(String(localized: "account.title"))

// ❌ BAD - Hard-coded strings
Text("Account")
```

### Component Selection Guide

**Для form inputs:**
- Simple text → `FormTextField`
- Multi-line → `DescriptionTextField`
- Amount → `AmountInputView`
- Date → `DatePickerRow`
- Color → `ColorPickerRow`
- Single-select menu → `MenuPickerRow` ⭐
- Icon/Logo → `IconPickerRow` + `IconPickerView` ⭐

**Для display:**
- Icon/Logo → `IconView` ⭐
- Card → `AccountCard`, `AnalyticsCard`, `SubscriptionCard`
- Row → `AccountRow`, `CategoryRow`, `InfoRow`
- Summary → `TransactionsSummaryCard`, `AnalyticsCard`

**Для states:**
- Error → `ErrorMessageView`
- Warning → `WarningMessageView`
- Success → `SuccessMessageView`
- Loading → `SkeletonView`
- Empty → `EmptyAccountsPrompt` (или создать custom)

**Для layout:**
- Edit form → `EditSheetContainer`
- Form section → `FormSection`
- Section header → `SectionHeaderView`

---

## 📈 Metrics

### Code Reduction
- **Phase 1-3:** 150+ lines eliminated
- **SubscriptionEditView:** 343 → 270 lines (-21%)
- **IconView refactor:** Consolidated 6 implementations
- **MenuPickerRow:** Replaced 4 custom implementations

### Reusability
- **Shared components:** 24 (35% of total)
- **Cross-feature usage:** High
- **DRY violations:** Minimal

### Maintenance
- **Localization coverage:** 100%
- **Design System compliance:** 100%
- **Documentation:** Complete
- **Test coverage:** Growing

---

## 🔮 Future Improvements

### Planned Components
- [ ] `LoadingButton` - Button с loading state
- [ ] `SearchBar` - Unified search component
- [ ] `EmptyStateView` - Generic empty state
- [ ] `PullToRefresh` - Pull-to-refresh wrapper
- [ ] `ToastView` - Toast notifications

### Refactoring Candidates
- [ ] Transaction list pagination
- [ ] Image caching optimization
- [ ] Animation performance
- [ ] Accessibility improvements

---

**Last Updated:** 2026-02-15
**Version:** 4.0
**Components:** 68
**Status:** ✅ Production Ready
