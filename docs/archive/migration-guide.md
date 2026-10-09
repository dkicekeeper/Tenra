# Migration Guide: TransactionsViewModel → TransactionStore
## How to migrate UI Views to use the new architecture

> **Дата:** 2026-02-05
> **Цель:** Постепенная миграция с legacy TransactionsViewModel на новый TransactionStore
> **Статус:** Active migration in progress

---

## Общая стратегия миграции

### Принципы
1. ✅ **Постепенно** - мигрируем по одному View за раз
2. ✅ **Тестируем** - каждый View тестируется после миграции
3. ✅ **Откатываемся** - можно вернуться к старому коду в любой момент
4. ✅ **Безопасно** - старый и новый код работают параллельно

### Порядок миграции
```
Простые Views → Сложные Views → Удаление legacy
     ↓               ↓                 ↓
 QuickAdd       ContentView       Phase 8
 EditTx         HistoryView       Cleanup
 TransCard
```

---

## Шаг 1: Добавить @EnvironmentObject

### ДО:
```swift
struct MyView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel

    var body: some View {
        // ...
    }
}
```

### ПОСЛЕ:
```swift
struct MyView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel  // Temporary
    @EnvironmentObject var transactionStore: TransactionStore  // NEW

    var body: some View {
        // ...
    }
}
```

**Примечание:** `transactionsViewModel` остаётся временно для обратной совместимости.

---

## Шаг 2: Заменить операции CRUD

### 2.1 Add Transaction

#### ДО:
```swift
// ContentView.swift, QuickAddTransactionView.swift
transactionsViewModel.addTransaction(
    type: .expense,
    amount: 1000,
    currency: "KZT",
    category: "Food",
    description: "Groceries",
    date: "2026-02-05",
    accountId: accountId,
    subcategoryIds: []
)
```

#### ПОСЛЕ:
```swift
Task {
    do {
        let transaction = Transaction(
            id: "",  // Will be generated
            date: "2026-02-05",
            description: "Groceries",
            amount: 1000,
            currency: "KZT",
            type: .expense,
            category: "Food",
            accountId: accountId
        )

        try await transactionStore.add(transaction)

        // Success - UI updates automatically via @Published

    } catch {
        // Handle error
        errorMessage = error.localizedDescription
        showingError = true
    }
}
```

**Ключевые изменения:**
- ✅ Async/await вместо синхронного вызова
- ✅ Explicit error handling с try/catch
- ✅ Создание Transaction struct вместо параметров
- ✅ Автоматическое обновление UI через @Published

---

### 2.2 Update Transaction

#### ДО:
```swift
// EditTransactionView.swift
transactionsViewModel.updateTransaction(updatedTransaction)
```

#### ПОСЛЕ:
```swift
Task {
    do {
        try await transactionStore.update(updatedTransaction)
        dismiss()  // Close modal on success
    } catch {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
```

**Ключевые изменения:**
- ✅ Async/await
- ✅ Error handling
- ✅ Dismiss только при success

---

### 2.3 Delete Transaction

#### ДО:
```swift
// TransactionCard.swift
transactionsViewModel.deleteTransaction(transaction)
```

#### ПОСЛЕ:
```swift
Task {
    do {
        try await transactionStore.delete(transaction)
    } catch {
        // Show error alert
        alertMessage = error.localizedDescription
        showingAlert = true
    }
}
```

---

### 2.4 Transfer Between Accounts

#### ДО:
```swift
// AccountActionView.swift
transactionsViewModel.transfer(
    from: sourceId,
    to: targetId,
    amount: amount,
    date: date,
    description: description
)
```

#### ПОСЛЕ:
```swift
Task {
    do {
        try await transactionStore.transfer(
            from: sourceId,
            to: targetId,
            amount: amount,
            currency: currency,
            date: date,
            description: description
        )
        dismiss()
    } catch {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
```

---

## Шаг 3: Заменить computed properties

### 3.1 Summary

#### ДО:
```swift
// ContentView.swift
let summary = transactionsViewModel.summary(timeFilterManager: timeFilterManager)
```

#### ПОСЛЕ:
```swift
// ContentView.swift
let summary = transactionStore.summary
```

**Примечание:** Time filtering теперь делается на стороне View, если нужно:
```swift
let filteredTransactions = transactionStore.transactions.filter { tx in
    // Filter by timeFilterManager.currentFilter
}
let summary = calculateSummary(from: filteredTransactions)
```

---

### 3.2 Category Expenses

#### ДО:
```swift
// QuickAddCoordinator.swift
let expenses = transactionsViewModel.categoryExpensesByFilter(/* ... */)
```

#### ПОСЛЕ:
```swift
let expenses = transactionStore.categoryExpenses
```

**Кэширование:** Автоматически через UnifiedTransactionCache.

---

### 3.3 Daily Expenses

#### ДО:
```swift
// HistoryTransactionsList.swift
let dateCache = DateSectionExpensesCache()
let expenses = dateCache.getExpenses(for: date, transactions: transactions)
```

#### ПОСЛЕ:
```swift
let expenses = transactionStore.expenses(for: date)
```

**Упрощение:** Больше не нужно управлять DateSectionExpensesCache вручную.

---

## Шаг 4: Обработка ошибок

### Error Handling Pattern

```swift
// State for error handling
@State private var errorMessage: String = ""
@State private var showingError: Bool = false

// Usage in button action
Button("Save") {
    Task {
        do {
            try await transactionStore.add(transaction)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
.alert("Error", isPresented: $showingError) {
    Button("OK", role: .cancel) {}
} message: {
    Text(errorMessage)
}
```

### Локализованные ошибки

```swift
// Все ошибки TransactionStore уже локализованы:
enum TransactionStoreError: LocalizedError {
    case invalidAmount
    case accountNotFound
    // ...

    var errorDescription: String? {
        String(localized: "error.transaction.invalidAmount")
    }
}
```

---

## Примеры миграции

### Example 1: QuickAddTransactionView

#### ДО:
```swift
struct QuickAddTransactionView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel

    func saveTransaction() {
        transactionsViewModel.addTransaction(
            type: selectedType,
            amount: Double(amount) ?? 0,
            currency: selectedCurrency,
            category: selectedCategory,
            description: description,
            date: DateFormatters.dateFormatter.string(from: selectedDate),
            accountId: selectedAccountId,
            subcategoryIds: selectedSubcategoryIds
        )
        dismiss()
    }
}
```

#### ПОСЛЕ:
```swift
struct QuickAddTransactionView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel  // Keep for backward compat
    @EnvironmentObject var transactionStore: TransactionStore  // NEW

    @State private var errorMessage: String = ""
    @State private var showingError: Bool = false

    func saveTransaction() {
        Task {
            do {
                let transaction = Transaction(
                    id: "",
                    date: DateFormatters.dateFormatter.string(from: selectedDate),
                    description: description,
                    amount: Double(amount) ?? 0,
                    currency: selectedCurrency,
                    type: selectedType,
                    category: selectedCategory,
                    accountId: selectedAccountId
                )

                try await transactionStore.add(transaction)
                dismiss()

            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    var body: some View {
        // ... existing UI
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}
```

---

### Example 2: EditTransactionView

#### ДО:
```swift
struct EditTransactionView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let transaction: Transaction

    func saveChanges() {
        var updated = transaction
        updated.amount = Double(amount) ?? 0
        updated.description = description
        // ... other fields

        viewModel.updateTransaction(updated)
        dismiss()
    }
}
```

#### ПОСЛЕ:
```swift
struct EditTransactionView: View {
    @ObservedObject var viewModel: TransactionsViewModel  // Keep temporarily
    @EnvironmentObject var transactionStore: TransactionStore  // NEW
    let transaction: Transaction

    @State private var errorMessage: String = ""
    @State private var showingError: Bool = false

    func saveChanges() {
        Task {
            do {
                let updated = Transaction(
                    id: transaction.id,
                    date: DateFormatters.dateFormatter.string(from: selectedDate),
                    description: description,
                    amount: Double(amount) ?? 0,
                    currency: selectedCurrency,
                    type: selectedType,
                    category: selectedCategory,
                    accountId: selectedAccountId
                )

                try await transactionStore.update(updated)
                dismiss()

            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    var body: some View {
        // ... existing UI
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}
```

---

### Example 3: TransactionCard (with swipe-to-delete)

#### ДО:
```swift
struct TransactionCard: View {
    let transaction: Transaction
    @ObservedObject var viewModel: TransactionsViewModel

    var body: some View {
        // ... card UI
        .swipeActions {
            Button(role: .destructive) {
                viewModel.deleteTransaction(transaction)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
```

#### ПОСЛЕ:
```swift
struct TransactionCard: View {
    let transaction: Transaction
    @ObservedObject var viewModel: TransactionsViewModel  // Keep temporarily
    @EnvironmentObject var transactionStore: TransactionStore  // NEW

    @State private var showingDeleteError: Bool = false
    @State private var deleteError: String = ""

    var body: some View {
        // ... card UI
        .swipeActions {
            Button(role: .destructive) {
                Task {
                    do {
                        try await transactionStore.delete(transaction)
                    } catch {
                        deleteError = error.localizedDescription
                        showingDeleteError = true
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Error", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError)
        }
    }
}
```

---

## Checklist для миграции View

### Перед миграцией
- [ ] Прочитать этот guide
- [ ] Убедиться, что TransactionStore в @EnvironmentObject
- [ ] Понять, какие операции использует View

### Во время миграции
- [ ] Добавить `@EnvironmentObject var transactionStore: TransactionStore`
- [ ] Добавить error handling state (`@State errorMessage`, `showingError`)
- [ ] Заменить CRUD операции на async/await
- [ ] Обернуть в Task { }
- [ ] Добавить try/catch
- [ ] Добавить .alert для ошибок
- [ ] Заменить computed properties (summary, categoryExpenses, etc.)

### После миграции
- [ ] Протестировать все функции View
- [ ] Проверить error handling (invalid data, network errors, etc.)
- [ ] Убедиться, что UI обновляется автоматически
- [ ] Запустить unit tests
- [ ] Code review

---

## Troubleshooting

### Проблема: UI не обновляется после операции

**Причина:** Забыли добавить `@EnvironmentObject`

**Решение:**
```swift
@EnvironmentObject var transactionStore: TransactionStore
```

---

### Проблема: Compilation error "Cannot find transactionStore"

**Причина:** Не добавили `.environmentObject()` в parent view

**Решение:**
В `TenraApp.swift` или parent view:
```swift
ContentView()
    .environmentObject(coordinator.transactionStore)
```

---

### Проблема: Async/await errors "Expression is 'async' but is not marked with 'await'"

**Причина:** Забыли обернуть в Task { }

**Решение:**
```swift
Button("Save") {
    Task {  // ← Add this
        try await transactionStore.add(transaction)
    }
}
```

---

### Проблема: App crashes с "Fatal error: No ObservableObject"

**Причина:** TransactionStore не инициализирован в AppCoordinator

**Решение:**
Проверить `AppCoordinator.swift`:
```swift
let transactionStore: TransactionStore

init() {
    // ...
    self.transactionStore = TransactionStore(repository: repository)
}
```

---

## Timeline миграции

### Week 1: Foundation (Done ✅)
- [x] TransactionStore создан
- [x] Интеграция в AppCoordinator
- [x] Unit tests написаны
- [x] Migration guide создан

### Week 2: UI Migration
- [ ] QuickAddTransactionView
- [ ] EditTransactionView
- [ ] TransactionCard
- [ ] ContentView (add operations)

### Week 3: Advanced Features
- [ ] HistoryView (summary, expenses)
- [ ] AccountActionView (transfers)
- [ ] Recurring operations integration
- [ ] CSV import/export

### Week 4: Cleanup
- [ ] Remove legacy TransactionCRUDService
- [ ] Remove legacy cache managers
- [ ] Simplify TransactionsViewModel
- [ ] Update documentation

---

## Вопросы и ответы

### Q: Нужно ли мигрировать все Views сразу?
**A:** Нет! Мигрируйте постепенно, по одному View за раз. Старый и новый код работают параллельно.

### Q: Что делать, если нашёл баг в TransactionStore?
**A:** Откройте issue с описанием проблемы и steps to reproduce. Можно временно откатиться к старому коду.

### Q: Как тестировать после миграции?
**A:**
1. Unit tests - проверяют логику TransactionStore
2. Manual testing - тестируют UI flow
3. Integration tests - проверяют весь стек

### Q: Когда удалять legacy код?
**A:** Только после того, как **все** Views мигрированы и протестированы (Phase 8).

---

## Полезные ресурсы

### Документация
- `refactoring-plan-complete.md` - Полный план рефакторинга
- `refactoring-implementation-status.md` - Текущий статус
- `TransactionStoreTests.swift` - Примеры тестов

### Примеры кода
- `TransactionStore.swift` - API reference
- `TransactionEvent.swift` - Event types
- `UnifiedTransactionCache.swift` - Caching mechanism

---

**Конец Migration Guide**
**Дата:** 2026-02-05
**Версия:** 1.0
**Статус:** Active ✅
