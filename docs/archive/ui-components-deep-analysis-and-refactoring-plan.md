# UI Components Deep Analysis & Refactoring Plan

> **Created:** 2026-02-14
> **Scope:** Comprehensive analysis of all UI components with focus on reusability, consistency, and missing components
> **Goal:** Create a unified component library with proper design system integration and localization

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Design System Analysis](#design-system-analysis)
3. [Existing Components Audit](#existing-components-audit)
4. [Inconsistencies Found](#inconsistencies-found)
5. [Missing Components](#missing-components)
6. [Component Refactoring Plan](#component-refactoring-plan)
7. [New Components to Create](#new-components-to-create)
8. [Implementation Priority](#implementation-priority)

---

## Executive Summary

### Current State
- ✅ **Strong Design System Foundation:** `AppTheme.swift` provides comprehensive tokens (spacing, typography, colors, radius, icons)
- ✅ **Some Good Reusable Components:** `IconView`, `IconPickerView`, `SegmentedPickerView`, `RecurringToggleView`
- ⚠️ **Inconsistent Section Headers:** 3+ different approaches across the app
- ❌ **Missing Core Components:** Date pickers, frequency selectors, reminder pickers, form field wrappers
- ❌ **Inline Logic in Forms:** Repeated UI patterns not extracted into components

### Key Findings
1. **Section Headers:** Inconsistent styling (`.bodySmall` vs `.caption`, `.uppercase` inconsistently applied)
2. **Icon Selection:** Good unified `IconPickerView` but inconsistent usage patterns
3. **Date Selection:** `DateButtonsView` exists but date pickers are scattered and inconsistent
4. **Frequency Selection:** No dedicated component, logic duplicated in multiple views
5. **Reminders:** Inline implementation in `SubscriptionEditView` only, not reusable
6. **Form Fields:** No wrapper components for consistent field styling

---

## Design System Analysis

### ✅ What Works Well

```swift
// AppTheme.swift - Excellent foundation
enum AppSpacing { /* 4pt grid system */ }
enum AppRadius { /* Consistent corner radius */ }
enum AppTypography { /* Semantic typography */ }
enum AppIconSize { /* Icon sizing system */ }
enum AppColors { /* Semantic colors */ }
```

**Strengths:**
- Comprehensive token system with semantic aliases
- iOS 26+ Liquid Glass support with fallbacks
- View modifiers for consistency (`.cardStyle()`, `.glassCardStyle()`, `.filterChipStyle()`)
- Modern naming conventions

### ⚠️ Areas for Improvement

1. **Section Header Token Missing:**
   - No `AppTypography.sectionHeader` semantic token
   - Multiple views use different styles for the same purpose

2. **Form Field Tokens Missing:**
   - No semantic spacing for form field groups
   - No standard form field background/border tokens

3. **Icon Style Presets:**
   - `IconStyle.swift` has good presets but not consistently used

---

## Existing Components Audit

### 🟢 Excellent Components (Keep & Promote)

#### 1. **IconPickerView** ⭐
**Location:** `Views/Shared/Components/IconPickerView.swift`

**Strengths:**
- Unified picker for SF Symbols, bank logos, and brand services
- Segmented control for tabs (Icons/Logos)
- Online search integration (logo.dev)
- Full localization support
- Design system compliant

**Usage:** Used in `CategoryEditView`, `AccountEditView`, `SubscriptionEditView`

```swift
// Good pattern - reusable and consistent
IconPickerView(selectedSource: $selectedIconSource)
```

**Recommendation:** ✅ Keep as-is, ensure all entity edit views use it

---

#### 2. **SegmentedPickerView** ⭐
**Location:** `Views/Shared/Components/SegmentedPickerView.swift`

**Strengths:**
- Generic `<T: Hashable>` for any enum/value type
- iOS 26+ glass effect with fallback
- Clean API with `(label, value)` tuples
- Localization-friendly

```swift
SegmentedPickerView(
    title: "",
    selection: $selectedFrequency,
    options: RecurringFrequency.allCases.map {
        (label: $0.displayName, value: $0)
    }
)
```

**Recommendation:** ✅ Keep as-is, promote for all segmented selections

---

#### 3. **RecurringToggleView** ⭐
**Location:** `Views/Shared/Components/RecurringToggleView.swift`

**Strengths:**
- Combines toggle + frequency picker in one component
- Conditional rendering (shows picker only when toggled on)
- Parameterized titles for localization

**Issues:**
- Currently tied to `RecurringFrequency` type (could be more generic)
- Commented out background styling (inconsistent)

**Recommendation:** ✅ Keep, minor improvements needed

---

#### 4. **IconView** ⭐
**Location:** `Views/Shared/Components/IconView.swift`

**Strengths:**
- Unified rendering for all icon types (SF Symbols, bank logos, brand services)
- Full `IconStyle` integration
- Fallback handling
- Performance optimized

**Recommendation:** ✅ Keep as-is, ensure all icon rendering uses it

---

### 🟡 Good Components (Need Refinement)

#### 5. **DateButtonsView**
**Location:** `Views/Shared/Components/DateButtonsView.swift`

**Strengths:**
- Quick date selection (Yesterday/Today/Calendar)
- Sheet presentation for full date picker
- `safeAreaInset` integration for keyboard avoidance

**Issues:**
- ❌ **Hard-coded strings** ("Вчера", "Сегодня", "Дата", "Выберите дату", "Отмена", "Выбрать")
- No localization support
- Glass button style used but not consistently

**Current Usage:**
```swift
// Used via extension
.dateButtonsSafeArea(
    selectedDate: $selectedDate,
    isDisabled: false,
    onSave: { date in /* ... */ }
)
```

**Recommendation:** ⚠️ Needs localization refactor

---

#### 6. **DescriptionTextField**
**Location:** `Views/Shared/Components/DescriptionTextField.swift`

**Strengths:**
- Reusable multiline text field
- Configurable line limits
- Design system compliant

**Issues:**
- Hard-coded background styling (`.primary.opacity(0.03)`)
- Inconsistent with other text fields in forms
- No validation/error state support

**Recommendation:** ⚠️ Expand to general-purpose `FormTextField` with variants

---

### 🔴 Components with Issues

#### 7. **Section Headers** (Multiple Implementations)

**Problem:** 3+ different implementations for section headers

**Variant 1: SettingsSectionHeaderView**
```swift
// Views/Settings/Components/SettingsSectionHeaderView.swift
Text(title)
    .font(AppTypography.bodySmall)
    .foregroundStyle(AppColors.textSecondary)
    .textCase(.uppercase)
```

**Variant 2: DateSectionHeader**
```swift
// Views/History/Components/DateSectionHeader.swift
HStack {
    Text(dateKey)
        .font(AppTypography.bodySmall)
        .fontWeight(.semibold)  // ⚠️ Different weight
        .foregroundStyle(.primary)  // ⚠️ Different color
    Spacer()
    // Amount display
}
.textCase(nil)  // ⚠️ Explicitly removes uppercase
.glassCardStyle()
```

**Variant 3: Inline Headers (CategoryEditView, SubscriptionEditView)**
```swift
// Inline implementation
Text("Основная информация")
    .font(AppTypography.caption)  // ⚠️ Different font size
    .foregroundStyle(AppColors.textSecondary)
    .textCase(.uppercase)
    .padding(.horizontal, AppSpacing.lg)
```

**Variant 4: IconPickerView**
```swift
Text(category.0)
    .font(AppTypography.caption)  // ⚠️ caption instead of bodySmall
    .foregroundStyle(AppColors.textSecondary)
    .textCase(.uppercase)
    .padding(.horizontal, AppSpacing.lg)
```

**Issues:**
- ❌ 4 different font sizes for the same semantic purpose
- ❌ Inconsistent color usage (`.primary` vs `.textSecondary`)
- ❌ Inconsistent text casing
- ❌ Some with glass background, some without

**Recommendation:** 🔴 **CRITICAL** - Create unified `SectionHeaderView` component

---

## Inconsistencies Found

### 1. 🔴 Section Header Styles

| Location | Font | Color | Uppercase | Background |
|----------|------|-------|-----------|------------|
| **SettingsSectionHeaderView** | `.bodySmall` | `.textSecondary` | ✅ Yes | ❌ None |
| **DateSectionHeader** | `.bodySmall` + `.semibold` | `.primary` | ❌ No | ✅ Glass |
| **IconPickerView** | `.caption` | `.textSecondary` | ✅ Yes | ❌ None |
| **SubscriptionEditView** (inline) | `.caption` | `.textSecondary` | ✅ Yes | ❌ None |
| **CategoryEditView** (List Section) | Default List Style | System | System | System |

**Impact:** Users experience inconsistent visual hierarchy across screens

---

### 2. 🟡 Icon Picker Integration

**Problem:** Inconsistent button/navigation patterns for opening icon picker

**Pattern A: Direct Button (CategoryEditView)**
```swift
Button {
    showingIconPicker = true
} label: {
    HStack {
        IconView(source: selectedIconSource, ...)
        Text("Tap to Select")
        Spacer()
    }
}
```

**Pattern B: Navigation Row (AccountEditView)**
```swift
Button {
    showingIconPicker = true
} label: {
    HStack {
        Text("Icon Picker")
        Spacer()
        IconView(source: selectedIconSource, ...)
        Image(systemName: "chevron.right")
    }
}
```

**Recommendation:** Create `IconPickerRow` component for consistency

---

### 3. 🟡 Date Picker Patterns

**Problem:** Mix of inline DatePicker and DateButtonsView

**Pattern A: Inline DatePicker (SubscriptionEditView)**
```swift
DatePicker("Дата начала", selection: $startDate, displayedComponents: .date)
    .padding(AppSpacing.md)
    .background(AppColors.cardBackground)
```

**Pattern B: DateButtonsView (TransactionForms)**
```swift
.dateButtonsSafeArea(
    selectedDate: $selectedDate,
    onSave: { date in /* ... */ }
)
```

**Issue:** No clear guidance on when to use which pattern

**Recommendation:** Create both variants as reusable components with clear usage guidelines

---

### 4. 🟡 Form Field Backgrounds

**Problem:** Inconsistent backgrounds for form fields

- Some use `.background(AppColors.cardBackground)`
- Some use `.background(.primary.opacity(0.03))`
- Some use no background
- Some are inside List sections (system styling)

**Recommendation:** Create `FormFieldStyle` view modifier

---

### 5. 🔴 Localization Gaps

**Hard-coded strings found in:**

1. **DateButtonsView:**
   - "Вчера", "Сегодня", "Дата"
   - "Выберите дату", "Отмена", "Выбрать"

2. **SubscriptionEditView (inline):**
   - "Основная информация"
   - "Название подписки"
   - "Частота"
   - "Дата начала"
   - "Напоминания"

3. **Various section headers:**
   - Many inline Text() without localization keys

**Impact:** Russian-only UI, blocks internationalization

---

## Missing Components

### 🔴 Critical Missing Components

#### 1. **Unified Section Header Component**

**Current State:** 4+ different implementations
**Need:** Single component for all section headers

**Proposed API:**
```swift
SectionHeaderView(
    title: String,
    style: SectionHeaderStyle = .default
)

enum SectionHeaderStyle {
    case `default`      // Uppercase, secondary color, no background
    case emphasized     // Bold, primary color, glass background
    case list           // List section header style
}
```

**Usage:**
```swift
// Settings screens
SectionHeaderView(title: String(localized: "settings.general"))

// Form screens with glass cards
SectionHeaderView(
    title: String(localized: "subscription.basicInfo"),
    style: .emphasized
)

// Date sections in History
DateSectionHeaderView(  // Specialized variant
    dateKey: "Today",
    amount: 1250.50,
    currency: "USD"
)
```

---

#### 2. **ReminderPickerView Component**

**Current State:** Inline implementation only in SubscriptionEditView
**Need:** Reusable multi-select reminder picker

**Proposed API:**
```swift
ReminderPickerView(
    selectedOffsets: Binding<Set<Int>>,
    availableOffsets: [Int] = [1, 3, 7, 30],
    title: String = String(localized: "subscription.reminders")
)
```

**Features:**
- Multi-select toggles
- Localized reminder text ("За 1 день", "За 3 дня", etc.)
- Glass card styling
- Dividers between options

**Implementation:**
```swift
struct ReminderPickerView: View {
    @Binding var selectedOffsets: Set<Int>
    let availableOffsets: [Int]
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            SectionHeaderView(title: title)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xs)

            VStack(spacing: 0) {
                ForEach(availableOffsets, id: \.self) { offset in
                    ReminderToggleRow(
                        offset: offset,
                        isSelected: selectedOffsets.contains(offset),
                        onToggle: { isOn in
                            if isOn {
                                selectedOffsets.insert(offset)
                            } else {
                                selectedOffsets.remove(offset)
                            }
                        }
                    )
                }
            }
            .background(AppColors.cardBackground)
            .clipShape(.rect(cornerRadius: AppRadius.md))
        }
    }

    private func reminderText(_ offset: Int) -> String {
        String(localized: "reminder.daysBefore.\(offset)")
    }
}
```

---

#### 3. **FrequencyPickerView Component**

**Current State:** SegmentedPickerView used with manual mapping
**Need:** Dedicated frequency picker with proper semantics

**Proposed API:**
```swift
FrequencyPickerView(
    selection: Binding<RecurringFrequency>,
    title: String = String(localized: "transaction.frequency"),
    style: FrequencyPickerStyle = .segmented
)

enum FrequencyPickerStyle {
    case segmented  // Horizontal segmented control
    case list       // Vertical list with radio buttons
    case menu       // Dropdown menu picker
}
```

**Why separate component:**
- Frequency selection is a common pattern (subscriptions, recurring transactions, budgets)
- Encapsulates `RecurringFrequency` enum logic
- Can add future features (custom frequency, frequency preview)

---

#### 4. **DatePickerRow Component**

**Current State:** Mix of inline DatePicker and custom sheet patterns
**Need:** Consistent date selection UI

**Proposed API:**
```swift
DatePickerRow(
    title: String,
    selection: Binding<Date>,
    displayedComponents: DatePickerComponents = .date,
    style: DatePickerRowStyle = .inline
)

enum DatePickerRowStyle {
    case inline       // Standard iOS DatePicker
    case compact      // Shows formatted date, taps open sheet
    case quickButtons // Yesterday/Today/Calendar (existing DateButtonsView)
}
```

**Features:**
- Consistent styling across all forms
- Localized labels
- Optional min/max date constraints
- Glass card background option

---

#### 5. **IconPickerRow Component**

**Current State:** Inconsistent button patterns for opening IconPickerView
**Need:** Standardized row for icon selection

**Proposed API:**
```swift
IconPickerRow(
    selectedSource: Binding<IconSource?>,
    title: String = String(localized: "common.icon"),
    style: IconStyle? = nil  // Optional custom icon style
)
```

**Features:**
- Consistent navigation pattern (chevron right)
- Shows current icon preview
- Opens IconPickerView sheet on tap
- Haptic feedback

**Implementation:**
```swift
struct IconPickerRow: View {
    @Binding var selectedSource: IconSource?
    let title: String
    let style: IconStyle?
    @State private var showingPicker = false

    var body: some View {
        Button {
            HapticManager.light()
            showingPicker = true
        } label: {
            HStack(spacing: AppSpacing.md) {
                Text(title)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if let source = selectedSource {
                    IconView(
                        source: source,
                        style: style ?? .serviceLogo(size: AppIconSize.lg)
                    )
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(AppColors.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(AppSpacing.md)
        }
        .sheet(isPresented: $showingPicker) {
            IconPickerView(selectedSource: $selectedSource)
        }
    }
}
```

---

#### 6. **FormTextField Component**

**Current State:** DescriptionTextField is too specialized, inline TextFields are inconsistent
**Need:** General-purpose form text field with variants

**Proposed API:**
```swift
FormTextField(
    text: Binding<String>,
    placeholder: String,
    style: FormTextFieldStyle = .standard,
    keyboardType: UIKeyboardType = .default,
    errorMessage: String? = nil,
    helpText: String? = nil
)

enum FormTextFieldStyle {
    case standard      // Single line
    case multiline(minLines: Int, maxLines: Int)
    case compact       // Smaller padding
}
```

**Features:**
- Consistent padding/background
- Error state styling
- Optional help text
- Localization support
- Focus state management

---

#### 7. **FormSection Component**

**Current State:** Repeated VStack + header + background patterns
**Need:** Wrapper for form sections

**Proposed API:**
```swift
FormSection(
    header: String? = nil,
    footer: String? = nil,
    style: FormSectionStyle = .card
) {
    // Content
}

enum FormSectionStyle {
    case card        // Glass card background
    case list        // List-style section
    case plain       // No background
}
```

**Features:**
- Automatic header/footer styling
- Dividers between items
- Consistent spacing
- iOS 26+ glass effects

---

### 🟡 Nice-to-Have Components

#### 8. **AmountInput Component** (Exists but could be improved)

**Current State:** `AmountInputView` exists but has some issues
**Improvements needed:**
- Extract currency selector to separate component
- Better error state handling
- Support for different amount formats (integer, decimal)

---

#### 9. **ColorPickerRow Component**

**Current State:** Inline implementation in CategoryEditView
**Need:** Reusable color picker with preset palette

**Proposed API:**
```swift
ColorPickerRow(
    selectedColorHex: Binding<String>,
    title: String = String(localized: "common.color"),
    palette: [String] = CategoryColors.defaultPalette
)
```

---

#### 10. **ConfirmationDialog Component**

**Current State:** Inline `.confirmationDialog()` modifiers
**Need:** Reusable confirmation wrapper

**Proposed API:**
```swift
ConfirmationDialogButton(
    title: String,
    message: String,
    confirmTitle: String = String(localized: "common.confirm"),
    role: ButtonRole = .destructive,
    action: @escaping () -> Void
)
```

---

## Component Refactoring Plan

### Phase 1: Critical Fixes (Week 1)

#### Priority 1.1: Unified Section Headers
**Goal:** Fix inconsistent section headers across the app

**Tasks:**
1. Create `SectionHeaderView` component with 3 styles
2. Create `DateSectionHeaderView` specialized component
3. Replace all inline section headers
4. Add missing localization keys

**Files to Update:**
- `SubscriptionEditView.swift` (5 headers)
- `CategoryEditView.swift` (3 headers)
- `AccountEditView.swift` (3 headers)
- `DepositEditView.swift` (headers)
- `IconPickerView.swift` (category headers)
- `CSVColumnMappingView.swift` (headers)

**Design System Updates:**
```swift
// Add to AppTypography
extension AppTypography {
    /// Section header (uppercase, secondary color)
    static let sectionHeader = caption.weight(.medium)
}
```

**Component Implementation:**
```swift
// Views/Shared/Components/SectionHeaderView.swift
struct SectionHeaderView: View {
    let title: String
    let style: Style

    enum Style {
        case `default`    // List/settings style
        case emphasized   // Form section with glass background
        case compact      // Picker categories
    }

    init(
        _ title: String,
        style: Style = .default
    ) {
        self.title = title
        self.style = style
    }

    var body: some View {
        switch style {
        case .default:
            Text(title)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)

        case .emphasized:
            Text(title)
                .font(AppTypography.bodySmall)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

        case .compact:
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)
        }
    }
}

// Specialized variant
struct DateSectionHeaderView: View {
    let dateKey: String
    let amount: Double
    let currency: String

    var body: some View {
        HStack {
            SectionHeaderView(dateKey, style: .emphasized)
            Spacer()

            if amount > 0 {
                FormattedAmountText(
                    amount: amount,
                    currency: currency,
                    prefix: "-",
                    fontSize: AppTypography.bodySmall,
                    fontWeight: .semibold,
                    color: .gray
                )
            }
        }
        .glassCardStyle()
    }
}
```

**Localization Keys to Add:**
```swift
// Localizable.strings (ru)
"subscription.basicInfo" = "Основная информация";
"subscription.reminders" = "Напоминания";
"common.frequency" = "Частота";
"common.startDate" = "Дата начала";
"common.icon" = "Иконка";
"common.logo" = "Логотип";
```

---

#### Priority 1.2: DateButtonsView Localization
**Goal:** Fix hard-coded Russian strings

**Tasks:**
1. Extract all strings to localization keys
2. Test with English locale
3. Update documentation

**Changes:**
```swift
// Before
Text("Вчера")

// After
Text(String(localized: "date.yesterday"))
```

**New Localization Keys:**
```swift
// Localizable.strings (ru)
"date.yesterday" = "Вчера";
"date.today" = "Сегодня";
"date.selectDate" = "Дата";
"date.choose" = "Выберите дату";
"common.cancel" = "Отмена";
"common.select" = "Выбрать";

// Localizable.strings (en)
"date.yesterday" = "Yesterday";
"date.today" = "Today";
"date.selectDate" = "Date";
"date.choose" = "Choose Date";
"common.cancel" = "Cancel";
"common.select" = "Select";
```

---

### Phase 2: New Core Components (Week 2)

#### Priority 2.1: ReminderPickerView
**Goal:** Extract reminder selection logic from SubscriptionEditView

**Implementation:** See "Missing Components" section above

**Files to Update:**
- `SubscriptionEditView.swift` (replace inline implementation)
- `DepositEditView.swift` (add reminder support if needed)

**Testing:**
- Multi-select behavior
- Localization (English/Russian)
- Haptic feedback
- State persistence

---

#### Priority 2.2: IconPickerRow
**Goal:** Standardize icon selection UI

**Files to Update:**
- `CategoryEditView.swift`
- `AccountEditView.swift`
- `SubscriptionEditView.swift`

**Before:**
```swift
Button {
    showingIconPicker = true
} label: {
    // Inconsistent layout
}
.sheet(isPresented: $showingIconPicker) {
    IconPickerView(selectedSource: $selectedIconSource)
}
```

**After:**
```swift
IconPickerRow(
    selectedSource: $selectedIconSource,
    title: String(localized: "common.icon")
)
```

---

#### Priority 2.3: FrequencyPickerView
**Goal:** Dedicated frequency selection component

**Current Usage:**
```swift
// Repeated in multiple files
SegmentedPickerView(
    title: "",
    selection: $selectedFrequency,
    options: RecurringFrequency.allCases.map {
        (label: $0.displayName, value: $0)
    }
)
```

**Proposed Component:**
```swift
struct FrequencyPickerView: View {
    @Binding var selection: RecurringFrequency
    let style: Style

    enum Style {
        case segmented   // Current default
        case menu        // Compact dropdown
        case list        // Vertical list
    }

    var body: some View {
        switch style {
        case .segmented:
            SegmentedPickerView(
                title: "",
                selection: $selection,
                options: RecurringFrequency.allCases.map {
                    (label: $0.displayName, value: $0)
                }
            )

        case .menu:
            Picker(String(localized: "transaction.frequency"), selection: $selection) {
                ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }
            .pickerStyle(.menu)

        case .list:
            VStack(spacing: 0) {
                ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                    FrequencyOptionRow(
                        frequency: frequency,
                        isSelected: selection == frequency,
                        onSelect: { selection = frequency }
                    )
                }
            }
        }
    }
}
```

**Files to Update:**
- `SubscriptionEditView.swift`
- `RecurringToggleView.swift`
- Transaction forms with recurring support

---

### Phase 3: Form Components (Week 3)

#### Priority 3.1: FormTextField
**Goal:** Replace DescriptionTextField and standardize all text input

**Implementation:**
```swift
struct FormTextField: View {
    @Binding var text: String
    let placeholder: String
    let style: Style
    let keyboardType: UIKeyboardType
    let errorMessage: String?
    let helpText: String?
    @FocusState private var isFocused: Bool

    enum Style {
        case standard
        case multiline(min: Int, max: Int)
        case compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Group {
                switch style {
                case .standard:
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .focused($isFocused)

                case .multiline(let min, let max):
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(min...max)
                        .focused($isFocused)

                case .compact:
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .focused($isFocused)
                }
            }
            .padding(style == .compact ? AppSpacing.sm : AppSpacing.md)
            .background(errorMessage != nil ?
                Color.red.opacity(0.1) :
                AppColors.surface
            )
            .clipShape(.rect(cornerRadius: AppRadius.md))

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
            }

            // Help text
            if let help = helpText, errorMessage == nil {
                Text(help)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}
```

**Files to Update:**
- Replace `DescriptionTextField` usage
- Replace inline `TextField` in all edit views
- `CategoryEditView`, `AccountEditView`, `SubscriptionEditView`, etc.

---

#### Priority 3.2: FormSection
**Goal:** Standardize form section containers

**Implementation:**
```swift
struct FormSection<Content: View>: View {
    let header: String?
    let footer: String?
    let style: Style
    @ViewBuilder let content: Content

    enum Style {
        case card
        case list
        case plain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header
            if let header = header {
                SectionHeaderView(header)
                    .padding(.horizontal, AppSpacing.lg)
            }

            // Content
            Group {
                switch style {
                case .card:
                    VStack(spacing: 0) {
                        content
                    }
                    .background(AppColors.cardBackground)
                    .clipShape(.rect(cornerRadius: AppRadius.md))

                case .list:
                    VStack(spacing: 0) {
                        content
                    }

                case .plain:
                    content
                }
            }

            // Footer
            if let footer = footer {
                Text(footer)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.lg)
            }
        }
    }
}
```

**Usage:**
```swift
// Before (SubscriptionEditView)
VStack() {
    HStack {
        Text("Основная информация")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
        Spacer()
    }
    .padding(.horizontal, AppSpacing.lg)

    VStack() {
        TextField("Название подписки", text: $description)
            .padding(AppSpacing.lg)
        // ...
    }
    .background(AppColors.cardBackground)
    .clipShape(.rect(cornerRadius: AppRadius.md))
}

// After
FormSection(
    header: String(localized: "subscription.basicInfo"),
    style: .card
) {
    FormTextField(
        text: $description,
        placeholder: String(localized: "subscription.namePlaceholder")
    )

    Divider()

    IconPickerRow(selectedSource: $selectedIconSource)

    Divider()

    FrequencyPickerView(selection: $selectedFrequency)

    Divider()

    DatePickerRow(
        title: String(localized: "common.startDate"),
        selection: $startDate
    )
}
```

---

#### Priority 3.3: DatePickerRow
**Goal:** Standardize date selection across forms

**Implementation:**
```swift
struct DatePickerRow: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    let style: Style

    enum Style {
        case inline
        case compact
        case sheet
    }

    @State private var showingPicker = false

    var body: some View {
        switch style {
        case .inline:
            DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
                .padding(AppSpacing.md)

        case .compact:
            Button {
                showingPicker = true
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(selection, style: .date)
                        .foregroundStyle(AppColors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(AppSpacing.md)
            }
            .sheet(isPresented: $showingPicker) {
                DatePickerSheet(
                    title: title,
                    selection: $selection,
                    displayedComponents: displayedComponents
                )
            }

        case .sheet:
            // Uses DateButtonsView logic
            DateButtonsView(
                selectedDate: $selection,
                onSave: { _ in }
            )
        }
    }
}

private struct DatePickerSheet: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
                .datePickerStyle(.graphical)
                .padding()

            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.select")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
```

**Files to Update:**
- `SubscriptionEditView.swift` (inline DatePicker)
- `DepositEditView.swift`
- `DepositRateChangeView.swift`
- Any other views with date selection

---

### Phase 4: Polish & Documentation (Week 4)

#### Priority 4.1: Component Documentation
**Tasks:**
- Create component catalog/preview app
- Document usage guidelines for each component
- Create Xcode previews for all components
- Add inline documentation comments

#### Priority 4.2: Migration Guide
**Tasks:**
- Document migration from old patterns to new components
- Create automated refactoring scripts where possible
- Update project-bible.md with component guidelines

#### Priority 4.3: Design System Updates
**Tasks:**
- Add missing semantic tokens
- Update `AppTheme.swift` documentation
- Create component style presets

---

## Implementation Priority

### 🔴 **CRITICAL (Week 1)**
1. ✅ **SectionHeaderView** - Fixes visual inconsistency across 15+ screens
2. ✅ **DateButtonsView Localization** - Blocks internationalization

### 🟠 **HIGH (Week 2)**
3. ✅ **IconPickerRow** - Standardizes icon selection (used in 5+ views)
4. ✅ **ReminderPickerView** - Enables reminder feature across app
5. ✅ **FrequencyPickerView** - Reduces code duplication

### 🟡 **MEDIUM (Week 3)**
6. ✅ **FormTextField** - Improves form consistency
7. ✅ **FormSection** - Reduces boilerplate in forms
8. ✅ **DatePickerRow** - Standardizes date selection

### 🟢 **LOW (Week 4)**
9. ⚪ **ColorPickerRow** - Nice-to-have for category customization
10. ⚪ **Component Documentation** - Improves developer experience

---

## SwiftUI Best Practices Alignment

### ✅ Follows SwiftUI Expert Guidelines

1. **Property Wrappers:**
   - All new components use `@Binding` for parent-controlled state
   - No `@State` for passed values
   - Clear separation of owned vs injected state

2. **Modern APIs:**
   - Using `foregroundStyle()` instead of `foregroundColor()`
   - Using `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`
   - iOS 26+ glass effects with fallbacks

3. **View Composition:**
   - Components are small and focused (Single Responsibility)
   - Complex views extracted to separate files
   - `@ViewBuilder` used appropriately

4. **Performance:**
   - No object creation in `body`
   - Stable identities for `ForEach`
   - Minimal state updates

5. **Localization:**
   - All user-facing strings use `String(localized:)`
   - No hard-coded text

### ⚠️ Areas to Improve

1. **State Management:**
   - Some components could benefit from `@Observable` classes for complex state
   - Consider view models for complex form logic

2. **Animations:**
   - Add `.animation(_:value:)` with value parameter (not deprecated version)
   - Use `withAnimation` for event-driven changes

3. **Accessibility:**
   - Add `.accessibilityLabel()` to icon buttons
   - Ensure proper accessibility hierarchy

---

## Testing Strategy

### Unit Tests
- [ ] `SectionHeaderView` variants render correctly
- [ ] `ReminderPickerView` multi-select logic
- [ ] `FrequencyPickerView` selection state
- [ ] `FormTextField` validation states

### Integration Tests
- [ ] IconPickerRow opens sheet and updates binding
- [ ] DatePickerRow sheet presentation
- [ ] FormSection layout with multiple children

### UI Tests
- [ ] Localization (English/Russian switching)
- [ ] Dark mode / light mode
- [ ] Dynamic type (accessibility text sizes)
- [ ] iOS 25 fallbacks (no Liquid Glass)

### Manual Testing Checklist
- [ ] All edit views use new components
- [ ] No hard-coded strings remain
- [ ] Consistent styling across all forms
- [ ] Glass effects work on iOS 26+
- [ ] Fallbacks work on iOS 25

---

## Success Metrics

### Code Quality
- **Reduce code duplication:** Target 30% reduction in form UI code
- **Increase reusability:** 80%+ of form UIs use shared components
- **Localization coverage:** 100% of user-facing strings

### Developer Experience
- **Time to create new form:** Reduce from 2 hours to 30 minutes
- **Component discoverability:** All components in `Views/Shared/Components/`
- **Documentation:** Every component has preview + usage docs

### User Experience
- **Visual consistency:** Unified section headers across all screens
- **Internationalization:** Full English + Russian support
- **Accessibility:** VoiceOver support for all new components

---

## Files to Create

### New Component Files
```
Tenra/Views/Shared/Components/
├── SectionHeaderView.swift                    [NEW]
├── DateSectionHeaderView.swift                [NEW - specialized variant]
├── ReminderPickerView.swift                   [NEW]
├── IconPickerRow.swift                        [NEW]
├── FrequencyPickerView.swift                  [NEW]
├── FormTextField.swift                        [NEW - replaces DescriptionTextField]
├── FormSection.swift                          [NEW]
├── DatePickerRow.swift                        [NEW]
├── ColorPickerRow.swift                       [NEW]
└── FormFieldStyles.swift                      [NEW - view modifiers]
```

### Updated Files
```
Tenra/Utils/
└── AppTheme.swift                             [UPDATE - add semantic tokens]

Tenra/Views/Subscriptions/
├── SubscriptionEditView.swift                 [UPDATE - use new components]
└── Components/
    └── NotificationPermissionView.swift       [UPDATE - if needed]

Tenra/Views/Categories/
└── CategoryEditView.swift                     [UPDATE]

Tenra/Views/Accounts/
└── AccountEditView.swift                      [UPDATE]

Tenra/Views/Deposits/
├── DepositEditView.swift                      [UPDATE]
└── Components/
    ├── DepositRateChangeView.swift            [UPDATE]
    └── DepositTransferView.swift              [UPDATE]

Tenra/Views/Settings/Components/
└── SettingsSectionHeaderView.swift            [DEPRECATE - replace with SectionHeaderView]

Tenra/Views/History/Components/
└── DateSectionHeader.swift                    [UPDATE - use new DateSectionHeaderView]

Tenra/Views/Shared/Components/
├── DateButtonsView.swift                      [UPDATE - localization]
├── RecurringToggleView.swift                  [UPDATE - use FrequencyPickerView]
└── DescriptionTextField.swift                 [DEPRECATE - replace with FormTextField]
```

### Localization Files
```
Localizable.strings (ru)                       [UPDATE - add 50+ new keys]
Localizable.strings (en)                       [CREATE - add all keys]
```

### Documentation Files
```
Docs/
├── UI_COMPONENTS_CATALOG.md                   [NEW]
├── COMPONENT_MIGRATION_GUIDE.md               [NEW]
└── DESIGN_SYSTEM_UPDATES.md                   [NEW]
```

---

## Conclusion

This refactoring plan addresses **critical inconsistencies** in the UI component library while building a **scalable foundation** for future development. By creating unified, reusable components with proper design system integration and full localization support, we will:

1. **Improve code quality** through reduced duplication and better separation of concerns
2. **Accelerate development** with ready-to-use form components
3. **Enhance user experience** with consistent, accessible, and internationalized UI
4. **Enable future features** like custom themes, accessibility enhancements, and platform expansions

**Estimated Effort:** 4 weeks (1 engineer)
**Risk Level:** Low (incremental changes, backward compatible)
**Impact:** High (affects 20+ screens, enables internationalization)

**Next Steps:**
1. Review and approve this plan
2. Create GitHub issues for each component
3. Start Phase 1 (Week 1) implementation
4. Iterate based on feedback

---

*Document Version: 1.0*
*Last Updated: 2026-02-14*
*Author: SwiftUI Expert Analysis*
