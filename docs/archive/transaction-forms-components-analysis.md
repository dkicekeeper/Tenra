# Анализ компонентов для форм транзакций

## Дата анализа
2024

## Проанализированные файлы
1. `VoiceInputConfirmationView.swift`
2. `AccountActionView.swift`
3. `EditTransactionView.swift`
4. `QuickAddTransactionView.swift`

---

## Существующие компоненты

### ✅ Уже используются
- **AmountInputView** - ввод суммы с выбором валюты
- **AccountRadioButton** - кнопка выбора счета
- **CategoryChip** - чип категории
- **CurrencySelectorView** - выбор валюты
- **FilterChip** - базовый чип для фильтров

---

## Элементы, требующие компонентизации

### 1. **SegmentedPickerView** (Приоритет: ВЫСОКИЙ)
**Использование:**
- `VoiceInputConfirmationView`: выбор типа операции (expense/income)
- `AccountActionView`: выбор типа действия (transfer/topUp)

**Текущая реализация:**
```swift
Picker(String(localized: "common.type"), selection: $selectedType) {
    Text(String(localized: "transactionType.expense")).tag(TransactionType.expense)
    Text(String(localized: "transactionType.income")).tag(TransactionType.income)
}
.pickerStyle(SegmentedPickerStyle())
.padding(.horizontal, AppSpacing.lg)
.padding(.vertical, AppSpacing.sm)
```

**Предлагаемый компонент:**
```swift
struct SegmentedPickerView<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(label: String, value: T)]
    
    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }
}
```

---

### 2. **AccountSelectorView** (Приоритет: ВЫСОКИЙ)
**Использование:**
- Все 4 файла используют одинаковый паттерн ScrollView с AccountRadioButton

**Текущая реализация:**
```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: AppSpacing.md) {
        ForEach(accounts) { account in
            AccountRadioButton(
                account: account,
                isSelected: selectedAccountId == account.id,
                onTap: { selectedAccountId = account.id }
            )
        }
    }
    .padding(.vertical, AppSpacing.xs)
    .padding(.horizontal, AppSpacing.lg)
}
.scrollClipDisabled()
.frame(maxWidth: .infinity)
```

**Предлагаемый компонент:**
```swift
struct AccountSelectorView: View {
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    let onSelectionChange: ((String?) -> Void)?
    let emptyStateMessage: String?
    
    var body: some View {
        if accounts.isEmpty {
            if let message = emptyStateMessage {
                EmptyStateView(message: message)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    ForEach(accounts) { account in
                        AccountRadioButton(
                            account: account,
                            isSelected: selectedAccountId == account.id,
                            onTap: {
                                selectedAccountId = account.id
                                onSelectionChange?(account.id)
                            }
                        )
                    }
                }
                .padding(.vertical, AppSpacing.xs)
                .padding(.horizontal, AppSpacing.lg)
            }
            .scrollClipDisabled()
            .frame(maxWidth: .infinity)
        }
    }
}
```

---

### 3. **CategorySelectorView** (Приоритет: ВЫСОКИЙ)
**Использование:**
- `VoiceInputConfirmationView`: выбор категории
- `AccountActionView`: выбор категории для пополнения
- `EditTransactionView`: выбор категории

**Текущая реализация:**
```swift
LazyVGrid(columns: gridColumns, spacing: AppSpacing.md) {
    ForEach(availableCategories, id: \.name) { category in
        CategoryChip(
            category: category.name,
            type: selectedType,
            customCategories: categoriesViewModel.customCategories,
            isSelected: selectedCategoryName == category.name,
            onTap: { selectedCategoryName = category.name },
            budgetProgress: nil,
            budgetAmount: nil
        )
    }
}
.padding(.vertical, AppSpacing.sm)
.padding(.horizontal, AppSpacing.lg)
```

**Предлагаемый компонент:**
```swift
struct CategorySelectorView: View {
    let categories: [String]
    let type: TransactionType
    let customCategories: [CustomCategory]
    @Binding var selectedCategory: String?
    let onSelectionChange: ((String?) -> Void)?
    let emptyStateMessage: String?
    let warningMessage: String?
    
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 4)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if categories.isEmpty {
                if let message = emptyStateMessage {
                    EmptyStateView(message: message)
                }
            } else {
                LazyVGrid(columns: gridColumns, spacing: AppSpacing.md) {
                    ForEach(categories, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            type: type,
                            customCategories: customCategories,
                            isSelected: selectedCategory == category,
                            onTap: {
                                selectedCategory = category
                                onSelectionChange?(category)
                            },
                            budgetProgress: nil,
                            budgetAmount: nil
                        )
                    }
                }
                .padding(.vertical, AppSpacing.sm)
                .padding(.horizontal, AppSpacing.lg)
            }
            
            if let warning = warningMessage {
                WarningMessageView(message: warning)
            }
        }
    }
}
```

---

### 4. **DescriptionTextField** (Приоритет: СРЕДНИЙ)
**Использование:**
- Все 4 файла используют TextField для описания

**Текущая реализация:**
```swift
TextField(String(localized: "quickAdd.descriptionPlaceholder"), text: $descriptionText, axis: .vertical)
    .font(AppTypography.body)
    .lineLimit(3...6)
    .padding(.horizontal, AppSpacing.lg)
```

**Предлагаемый компонент:**
```swift
struct DescriptionTextField: View {
    @Binding var text: String
    let placeholder: String
    let minLines: Int
    let maxLines: Int
    
    init(
        text: Binding<String>,
        placeholder: String = String(localized: "quickAdd.descriptionPlaceholder"),
        minLines: Int = 3,
        maxLines: Int = 6
    ) {
        self._text = text
        self.placeholder = placeholder
        self.minLines = minLines
        self.maxLines = maxLines
    }
    
    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(AppTypography.body)
            .lineLimit(minLines...maxLines)
            .padding(.horizontal, AppSpacing.lg)
    }
}
```

---

### 5. **SubcategoryRow** (Приоритет: СРЕДНИЙ)
**Использование:**
- `EditTransactionView`: список подкатегорий с чекбоксами
- `QuickAddTransactionView`: список подкатегорий с чекбоксами

**Текущая реализация:**
```swift
HStack {
    Text(subcategory.name)
        .font(AppTypography.body)
    Spacer()
    if selectedSubcategoryIds.contains(subcategory.id) {
        Image(systemName: "checkmark")
            .foregroundColor(.blue)
            .font(AppTypography.body)
    }
}
.contentShape(Rectangle())
.onTapGesture {
    if selectedSubcategoryIds.contains(subcategory.id) {
        selectedSubcategoryIds.remove(subcategory.id)
    } else {
        selectedSubcategoryIds.insert(subcategory.id)
    }
}
```

**Предлагаемый компонент:**
```swift
struct SubcategoryRow: View {
    let subcategory: Subcategory
    @Binding var isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Text(subcategory.name)
                .font(AppTypography.body)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .font(AppTypography.body)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}
```

---

### 6. **SubcategorySearchButton** (Приоритет: НИЗКИЙ)
**Использование:**
- `EditTransactionView`: кнопка поиска подкатегорий
- `QuickAddTransactionView`: кнопка поиска подкатегорий

**Текущая реализация:**
```swift
Button(action: {
    showingSubcategorySearch = true
}) {
    HStack {
        Image(systemName: "magnifyingglass")
        Text(String(localized: "transactionForm.searchSubcategories"))
    }
    .font(AppTypography.body)
    .foregroundColor(.blue)
}
```

**Предлагаемый компонент:**
```swift
struct SubcategorySearchButton: View {
    let title: String
    let action: () -> Void
    
    init(
        title: String = String(localized: "transactionForm.searchSubcategories"),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "magnifyingglass")
                Text(title)
            }
            .font(AppTypography.body)
            .foregroundColor(.blue)
        }
    }
}
```

---

### 7. **RecurringToggleView** (Приоритет: СРЕДНИЙ)
**Использование:**
- `EditTransactionView`: Toggle + Picker для recurring
- `QuickAddTransactionView`: Toggle + Picker для recurring

**Текущая реализация:**
```swift
VStack(alignment: .leading, spacing: AppSpacing.sm) {
    Toggle(String(localized: "transactionForm.makeRecurring"), isOn: $isRecurring)
        .font(AppTypography.body)
    
    if isRecurring {
        Picker(String(localized: "transaction.frequency"), selection: $selectedFrequency) {
            ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                Text(frequency.displayName).tag(frequency)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .font(AppTypography.body)
        .padding(.top, AppSpacing.sm)
    }
}
.padding(.horizontal, AppSpacing.lg)
```

**Предлагаемый компонент:**
```swift
struct RecurringToggleView: View {
    @Binding var isRecurring: Bool
    @Binding var selectedFrequency: RecurringFrequency
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Toggle(String(localized: "transactionForm.makeRecurring"), isOn: $isRecurring)
                .font(AppTypography.body)
            
            if isRecurring {
                Picker(String(localized: "transaction.frequency"), selection: $selectedFrequency) {
                    ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .font(AppTypography.body)
                .padding(.top, AppSpacing.sm)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
    }
}
```

---

### 8. **WarningMessageView** (Приоритет: НИЗКИЙ)
**Использование:**
- `VoiceInputConfirmationView`: предупреждения для account, amount, category

**Текущая реализация:**
```swift
if let warning = accountWarning {
    Text(warning)
        .font(AppTypography.caption)
        .foregroundColor(.orange)
        .padding(.top, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.lg)
}
```

**Предлагаемый компонент:**
```swift
struct WarningMessageView: View {
    let message: String
    let color: Color
    
    init(message: String, color: Color = .orange) {
        self.message = message
        self.color = color
    }
    
    var body: some View {
        Text(message)
            .font(AppTypography.caption)
            .foregroundColor(color)
            .padding(.top, AppSpacing.xs)
            .padding(.horizontal, AppSpacing.lg)
    }
}
```

---

### 9. **EmptyStateView** (Приоритет: НИЗКИЙ)
**Использование:**
- Все 4 файла: "No accounts", "No categories"

**Текущая реализация:**
```swift
Text(String(localized: "voiceConfirmation.noAccounts"))
    .font(AppTypography.bodySmall)
    .foregroundColor(.secondary)
    .padding(.vertical, AppSpacing.sm)
    .padding(.horizontal, AppSpacing.lg)
```

**Предлагаемый компонент:**
```swift
struct EmptyStateView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(AppTypography.bodySmall)
            .foregroundColor(.secondary)
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.lg)
    }
}
```

---

## Сводная таблица компонентов

| Компонент | Приоритет | Используется в | Статус |
|-----------|-----------|----------------|--------|
| SegmentedPickerView | ВЫСОКИЙ | 2 файла | ❌ Нужно создать |
| AccountSelectorView | ВЫСОКИЙ | 4 файла | ❌ Нужно создать |
| CategorySelectorView | ВЫСОКИЙ | 3 файла | ❌ Нужно создать |
| DescriptionTextField | СРЕДНИЙ | 4 файла | ❌ Нужно создать |
| SubcategoryRow | СРЕДНИЙ | 2 файла | ❌ Нужно создать |
| RecurringToggleView | СРЕДНИЙ | 2 файла | ❌ Нужно создать |
| SubcategorySearchButton | НИЗКИЙ | 2 файла | ❌ Нужно создать |
| WarningMessageView | НИЗКИЙ | 1 файл | ❌ Нужно создать |
| EmptyStateView | НИЗКИЙ | 4 файла | ❌ Нужно создать |

---

## Рекомендации

### Фаза 1 (Высокий приоритет)
1. **AccountSelectorView** - используется во всех 4 файлах
2. **CategorySelectorView** - используется в 3 файлах
3. **SegmentedPickerView** - используется в 2 файлах

### Фаза 2 (Средний приоритет)
4. **DescriptionTextField** - используется во всех 4 файлах
5. **SubcategoryRow** - используется в 2 файлах
6. **RecurringToggleView** - используется в 2 файлах

### Фаза 3 (Низкий приоритет)
7. **SubcategorySearchButton** - используется в 2 файлах
8. **WarningMessageView** - используется в 1 файле
9. **EmptyStateView** - используется во всех 4 файлах

---

## Дополнительные улучшения

### Общие паттерны
- Все формы используют одинаковую структуру ScrollView + VStack
- Все формы используют одинаковые отступы (AppSpacing.lg для горизонтальных)
- Все формы имеют одинаковый порядок полей

### Возможные улучшения
1. Создать общий `TransactionFormContainer` для единообразной структуры
2. Создать `FormSection` для группировки связанных полей
3. Унифицировать обработку ошибок и предупреждений

---

## Следующие шаги

После создания компонентов:
1. Заменить дублирующийся код в 4 файлах на новые компоненты
2. Убедиться, что все локализовано
3. Проверить соответствие дизайн-системе
4. Протестировать все формы
