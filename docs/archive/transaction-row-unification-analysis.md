# Анализ объединения TransactionRowContent и DepositTransactionRow

## Дата: 2026-02-13

---

## 📊 Текущая архитектура

### 1. TransactionRowContent.swift
**Назначение**: Базовый компонент для отображения содержимого строки транзакции

**Параметры**:
```swift
- transaction: Transaction
- currency: String
- customCategories: [CustomCategory] = []
- accounts: [Account] = []
- showIcon: Bool = true
- showDescription: Bool = true
- depositAccountId: String? = nil
- isPlanned: Bool = false
- linkedSubcategories: [Subcategory] = []
```

**Особенности**:
- ✅ Рендерит только содержимое (без стилизации контейнера)
- ✅ Поддерживает разные режимы отображения (showIcon, showDescription)
- ✅ Умеет отображать плановые транзакции (isPlanned)
- ✅ Поддерживает депозитный режим (depositAccountId)
- ✅ Сложная логика отображения сумм для переводов
- ✅ Поддержка мультивалютности

### 2. DepositTransactionRow.swift
**Назначение**: Wrapper для TransactionRowContent с депозитной стилизацией

**Параметры**:
```swift
- transaction: Transaction
- currency: String
- accounts: [Account] = []
- depositAccountId: String? = nil
- isPlanned: Bool = false
```

**Особенности**:
- ✅ Делегирует рендеринг TransactionRowContent
- ✅ Добавляет padding и фоновый стиль
- ✅ Специальный фон для плановых транзакций (blue.opacity(0.1))
- ✅ Hardcoded: `showDescription: false`

**Текущая реализация**:
```swift
var body: some View {
    TransactionRowContent(
        transaction: transaction,
        currency: currency,
        accounts: accounts,
        showIcon: true,
        showDescription: false, // ⚠️ Захардкожено
        depositAccountId: depositAccountId,
        isPlanned: isPlanned
    )
    .padding(AppSpacing.sm)
    .background(isPlanned ? Color.blue.opacity(0.1) : AppColors.secondaryBackground)
    .clipShape(.rect(cornerRadius: AppRadius.sm))
}
```

---

## 🔍 Анализ использования

### Где используется TransactionRowContent:
1. **DepositTransactionRow.swift** - обертка для депозитов
2. **Preview в TransactionRowContent.swift** - демонстрация

### Где используется DepositTransactionRow:
1. **SubscriptionDetailView.swift** - отображение транзакций подписки
   ```swift
   ForEach(subscriptionTransactions) { transaction in
       DepositTransactionRow(
           transaction: transaction,
           currency: transaction.currency,
           isPlanned: transaction.id.hasPrefix("planned-")
       )
   }
   ```

---

## 🤔 Вопросы для анализа

### ❓ Почему существует DepositTransactionRow?
1. **Стилизация**: Добавляет padding и фон
2. **Упрощенный API**: Скрывает параметры `showIcon`, `showDescription`
3. **Депозитная семантика**: Название подразумевает использование для депозитов

### ❓ Действительно ли нужен отдельный компонент?

**ЗА объединение**:
- ✅ DepositTransactionRow - это просто TransactionRowContent + стилизация
- ✅ Вся логика уже в TransactionRowContent
- ✅ Можно заменить модификатором `.transactionRowStyle()`
- ✅ Меньше файлов для поддержки
- ✅ Избавляемся от hardcoded `showDescription: false`

**ПРОТИВ объединения**:
- ⚠️ Название "DepositTransactionRow" семантически понятнее
- ⚠️ Упрощенный API для конкретного use case
- ⚠️ Возможно, в будущем появится специфичная логика для депозитов

---

## 💡 Варианты решения

### Вариант 1: Удалить DepositTransactionRow, заменить на модификатор ⭐ РЕКОМЕНДУЕТСЯ

**Идея**: TransactionRowContent + `.transactionRowStyle(isPlanned:)`

**Реализация**:
```swift
// Новый модификатор в extension View
extension View {
    func transactionRowStyle(isPlanned: Bool = false) -> some View {
        self
            .padding(AppSpacing.sm)
            .background(isPlanned ? Color.blue.opacity(0.1) : AppColors.secondaryBackground)
            .clipShape(.rect(cornerRadius: AppRadius.sm))
    }
}

// Использование
TransactionRowContent(
    transaction: transaction,
    currency: currency,
    showDescription: false
)
.transactionRowStyle(isPlanned: transaction.id.hasPrefix("planned-"))
```

**Плюсы**:
- ✅ Единый компонент для всех транзакций
- ✅ Явный и гибкий API
- ✅ Модификатор можно переиспользовать
- ✅ Убираем дублирование кода

**Минусы**:
- ⚠️ Немного более многословный вызов
- ⚠️ Нужно обновить все использования

---

### Вариант 2: Оставить как есть, добавить больше пресетов

**Идея**: Создать enum `TransactionRowStyle` с пресетами

**Реализация**:
```swift
enum TransactionRowStyle {
    case plain
    case deposit(isPlanned: Bool)
    case subscription(isPlanned: Bool)
}

// В TransactionRowContent
func styled(_ style: TransactionRowStyle) -> some View {
    // ...
}

// Использование
TransactionRowContent(...)
    .styled(.deposit(isPlanned: true))
```

**Плюсы**:
- ✅ Сохраняется семантика
- ✅ Легко добавлять новые стили

**Минусы**:
- ⚠️ Все равно не решает проблему дублирования DepositTransactionRow
- ⚠️ Более сложный API

---

### Вариант 3: Превратить DepositTransactionRow в алиас/convenience init

**Идея**: DepositTransactionRow становится typealias или фабрикой

**Реализация**:
```swift
// Вариант A: Extension на TransactionRowContent
extension TransactionRowContent {
    static func depositRow(
        transaction: Transaction,
        currency: String,
        accounts: [Account] = [],
        depositAccountId: String? = nil,
        isPlanned: Bool = false
    ) -> some View {
        TransactionRowContent(
            transaction: transaction,
            currency: currency,
            accounts: accounts,
            showIcon: true,
            showDescription: false,
            depositAccountId: depositAccountId,
            isPlanned: isPlanned
        )
        .transactionRowStyle(isPlanned: isPlanned)
    }
}

// Использование
TransactionRowContent.depositRow(
    transaction: transaction,
    currency: currency,
    isPlanned: true
)
```

**Плюсы**:
- ✅ Сохраняется удобство API
- ✅ Семантически понятно
- ✅ Нет отдельного файла

**Минусы**:
- ⚠️ Смешиваем фабричные методы с компонентом

---

## 🎯 Рекомендация: Вариант 1 (Модификатор)

### Почему именно Вариант 1?

1. **SwiftUI-идиоматично**:
   - Модификаторы - стандартный способ стилизации в SwiftUI
   - Примеры: `.buttonStyle()`, `.listRowBackground()`, `.cardStyle()`

2. **Гибкость**:
   - Модификатор можно применить к любому View
   - Легко комбинировать с другими модификаторами

3. **Чистота кода**:
   - Один компонент - одна ответственность
   - TransactionRowContent отвечает за контент
   - `.transactionRowStyle()` отвечает за стилизацию

4. **Расширяемость**:
   - Легко добавить вариации: `.transactionRowStyle(.compact)`, `.transactionRowStyle(.card)`

---

## 📋 План миграции

### Шаг 1: Создать модификатор `.transactionRowStyle()`
```swift
// В AppTheme.swift или новый файл TransactionRowModifiers.swift
extension View {
    /// Стилизует view как строку транзакции
    func transactionRowStyle(
        isPlanned: Bool = false,
        variant: TransactionRowVariant = .default
    ) -> some View {
        self
            .padding(AppSpacing.sm)
            .background(backgroundForVariant(isPlanned: isPlanned, variant: variant))
            .clipShape(.rect(cornerRadius: AppRadius.sm))
    }

    private func backgroundForVariant(isPlanned: Bool, variant: TransactionRowVariant) -> Color {
        if isPlanned {
            return Color.blue.opacity(0.1)
        }

        switch variant {
        case .default:
            return AppColors.secondaryBackground
        case .transparent:
            return .clear
        case .card:
            return AppColors.surface
        }
    }
}

enum TransactionRowVariant {
    case `default`
    case transparent
    case card
}
```

### Шаг 2: Обновить SubscriptionDetailView.swift
```swift
// Было:
DepositTransactionRow(
    transaction: transaction,
    currency: transaction.currency,
    isPlanned: transaction.id.hasPrefix("planned-")
)

// Стало:
TransactionRowContent(
    transaction: transaction,
    currency: transaction.currency,
    showDescription: false,
    isPlanned: transaction.id.hasPrefix("planned-")
)
.transactionRowStyle(isPlanned: transaction.id.hasPrefix("planned-"))
```

### Шаг 3: Удалить DepositTransactionRow.swift
- Удалить файл
- Обновить документацию

### Шаг 4: Обновить Preview
- Добавить примеры с модификатором в TransactionRowContent Preview

---

## 📊 Сравнение: До и После

### До:
```swift
// 2 компонента
TransactionRowContent.swift       // 299 строк
DepositTransactionRow.swift       // 139 строк
Итого: 438 строк в 2 файлах

// Использование
DepositTransactionRow(
    transaction: transaction,
    currency: transaction.currency,
    isPlanned: true
)
```

### После:
```swift
// 1 компонент + 1 модификатор
TransactionRowContent.swift       // 299 строк
TransactionRowModifiers.swift     // ~50 строк
Итого: ~349 строк в 2 файлах

// Использование
TransactionRowContent(
    transaction: transaction,
    currency: transaction.currency,
    showDescription: false,
    isPlanned: true
)
.transactionRowStyle(isPlanned: true)
```

**Экономия**: ~89 строк кода, -1 файл компонента

---

## 🚀 Дополнительные улучшения (опционально)

### 1. Умный дефолт для `showDescription`
```swift
// В TransactionRowContent
init(
    transaction: Transaction,
    currency: String,
    customCategories: [CustomCategory] = [],
    accounts: [Account] = [],
    showIcon: Bool = true,
    showDescription: Bool? = nil, // nil = auto-detect
    depositAccountId: String? = nil,
    isPlanned: Bool = false,
    linkedSubcategories: [Subcategory] = []
) {
    // Auto: false для депозитов, true для остальных
    let autoShowDescription = depositAccountId == nil
    self.showDescription = showDescription ?? autoShowDescription
    // ...
}
```

### 2. Варианты стилизации
```swift
extension View {
    // Compact - для списков
    func transactionRowCompact(isPlanned: Bool = false) -> some View {
        self
            .padding(AppSpacing.xs)
            .background(isPlanned ? Color.blue.opacity(0.05) : .clear)
    }

    // Card - для выделения
    func transactionRowCard(isPlanned: Bool = false) -> some View {
        self
            .padding(AppSpacing.md)
            .background(isPlanned ? Color.blue.opacity(0.1) : AppColors.surface)
            .clipShape(.rect(cornerRadius: AppRadius.card))
            .shadow(color: .black.opacity(0.05), radius: 4)
    }
}
```

---

## ✅ Выводы

### Текущая ситуация:
- ✅ TransactionRowContent - мощный базовый компонент
- ⚠️ DepositTransactionRow - тонкая обертка без уникальной логики
- ⚠️ Дублирование кода и ответственности

### Решение:
- ✅ Удалить DepositTransactionRow
- ✅ Создать модификатор `.transactionRowStyle()`
- ✅ Единый компонент с гибкой стилизацией
- ✅ SwiftUI-идиоматичный подход

### Преимущества:
- 🎯 Меньше кода для поддержки
- 🎯 Гибче и расширяемее
- 🎯 Понятнее API
- 🎯 Соответствует SwiftUI best practices

---

## 📝 Примеры использования (после рефакторинга)

### Для подписок:
```swift
TransactionRowContent(
    transaction: transaction,
    currency: transaction.currency,
    showDescription: false,
    isPlanned: transaction.id.hasPrefix("planned-")
)
.transactionRowStyle(isPlanned: transaction.id.hasPrefix("planned-"))
```

### Для депозитов:
```swift
TransactionRowContent(
    transaction: transaction,
    currency: currency,
    accounts: accounts,
    showDescription: false,
    depositAccountId: depositId,
    isPlanned: isPlanned
)
.transactionRowStyle(isPlanned: isPlanned)
```

### Для обычных списков транзакций:
```swift
TransactionRowContent(
    transaction: transaction,
    currency: currency,
    customCategories: categories,
    accounts: accounts,
    linkedSubcategories: subcategories
)
.transactionRowStyle() // Дефолтный стиль
```

### Кастомная стилизация:
```swift
TransactionRowContent(...)
    .padding(AppSpacing.lg)
    .background(AppColors.accent.opacity(0.1))
    .clipShape(.rect(cornerRadius: AppRadius.lg))
```
