# Анализ конфликтов обновления балансов счетов

## Содержание
1. [Обзор проблемы](#обзор-проблемы)
2. [Архитектура текущей системы](#архитектура-текущей-системы)
3. [Выявленные конфликты](#выявленные-конфликты)
4. [Детальный анализ проблем](#детальный-анализ-проблем)
5. [План рефакторинга](#план-рефакторинга)
6. [Рекомендации](#рекомендации)

---

## Обзор проблемы

При импорте CSV и ручном создании сущностей (транзакций, подписок) возникают конфликты в механизме обновления балансов счетов. Основная причина — **смешение двух парадигм расчета балансов**:

1. **Импортированные счета** — баланс уже включает транзакции, нужно вычислить `initialBalance`
2. **Ручные счета** — `initialBalance` задан пользователем, транзакции применяются сверху

---

## Архитектура текущей системы

### Ключевые компоненты

```
┌─────────────────────────────────────────────────────────────────┐
│                        CSVImportService                          │
│   - importTransactions()                                        │
│   - Создает счета, категории, транзакции                        │
│   - Вызывает endBatch() → recalculateAccountBalances()          │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    TransactionsViewModel                         │
│   - allTransactions: [Transaction]                              │
│   - accounts: [Account]                                         │
│   - accountsWithCalculatedInitialBalance: Set<String>           │
│   - initialAccountBalances: [String: Double]                    │
│   - recalculateAccountBalances()                                │
│   - applyTransactionToBalancesDirectly()                        │
└───────────────────┬─────────────────────────────────────────────┘
                    │ syncAccountBalances()
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                     AccountsViewModel                            │
│   - accounts: [Account]                                         │
│   - initialAccountBalances: [String: Double]                    │
│   - syncAccountBalances(_ accounts: [Account])                  │
│   - setInitialBalance(_ balance, for accountId)                 │
└─────────────────────────────────────────────────────────────────┘
```

### Потоки данных

#### CSV Import Flow
```
CSVImportService.importTransactions()
    ↓
beginBatch()
    ↓
addTransactionsForImport() [пакетами по 100]
    ↓
Создание счетов в AccountsViewModel (balance = 0)
    ↓
endBatch()
    ├── recalculateAccountBalances()
    │   ├── Вычисляет initialBalance = balance - Σtransactions
    │   ├── Добавляет в accountsWithCalculatedInitialBalance
    │   └── ПРОПУСКАЕТ транзакции для этих счетов
    ├── syncAccountBalances() → AccountsViewModel
    └── saveToStorageSync()
    ↓
Обновление initialAccountBalances в AccountsViewModel
    ↓
saveAllAccountsSync()
```

#### Manual Transaction Flow
```
TransactionsViewModel.addTransaction()
    ↓
Проверка дубликатов по ID
    ↓
insertTransactionsSorted()
    ↓
applyTransactionToBalancesDirectly()  ← КРИТИЧНО: для imported accounts
    ↓
scheduleBalanceRecalculation()
    ├── Если batch mode → defer
    └── Если normal mode → recalculateAccountBalances()
        └── ПРОПУСКАЕТ транзакции для accountsWithCalculatedInitialBalance
    ↓
scheduleSave()
```

#### Subscription Creation Flow
```
SubscriptionsViewModel.createSubscription()
    ↓
saveRecurringSeries()
    ↓
NotificationCenter.post(.recurringSeriesCreated)
    ↓
TransactionsViewModel.setupRecurringSeriesObserver()
    ↓
generateRecurringTransactions()
    ↓
scheduleBalanceRecalculation()
    ↓
scheduleSave()
```

---

## Выявленные конфликты

### Критический конфликт #1: Двойной источник правды для `initialAccountBalances`

**Проблема:** `initialAccountBalances` хранится в двух местах:
- `TransactionsViewModel.initialAccountBalances`
- `AccountsViewModel.initialAccountBalances`

**Где используется:**
```swift
// TransactionsViewModel.swift:1832
if let manualInitialBalance = accountBalanceService.getInitialBalance(for: account.id) {
    initialAccountBalances[account.id] = manualInitialBalance
}

// CSVImportService.swift:598
accountsVM.setInitialBalance(updatedAccount.balance, for: account.id)
```

**Результат:** При импорте `initialBalance` устанавливается в `AccountsViewModel`, но `TransactionsViewModel` не знает об этом изменении до следующего `recalculateAccountBalances()`.

### Критический конфликт #2: `accountsWithCalculatedInitialBalance` не сбрасывается

**Проблема:** После импорта счет добавляется в `accountsWithCalculatedInitialBalance` и **никогда не удаляется**.

**Код (TransactionsViewModel.swift:1843-1845):**
```swift
// КРИТИЧЕСКИ ВАЖНО: Только для импортированных данных
// Транзакции УЖЕ УЧТЕНЫ в current balance, поэтому НЕ должны обрабатываться снова
accountsWithCalculatedInitialBalance.insert(account.id)
```

**Результат:**
- Новые транзакции для импортированных счетов обрабатываются через `applyTransactionToBalancesDirectly()`
- Но если это метод не вызывается (например, при удалении транзакции), баланс не пересчитывается

### Критический конфликт #3: Race condition между notification и manual transaction

**Сценарий:**
1. Пользователь создает подписку → `NotificationCenter.post(.recurringSeriesCreated)`
2. Одновременно добавляет ручную транзакцию
3. Оба вызывают `scheduleBalanceRecalculation()`
4. Нет сериализации → возможен race condition

**Код (TransactionsViewModel.swift:102-123):**
```swift
NotificationCenter.default.addObserver(forName: .recurringSeriesCreated, ...) { [weak self] notification in
    // Runs on notification thread
    self?.generateRecurringTransactions()
    self?.invalidateCaches()
    self?.scheduleBalanceRecalculation()
    self?.scheduleSave()
}
```

### Критический конфликт #4: CSV Import перезаписывает initialBalance после расчета

**Код (CSVImportService.swift:596-598):**
```swift
// После endBatch() который уже пересчитал балансы:
accountsVM.accounts[index].balance = updatedAccount.balance
accountsVM.setInitialBalance(updatedAccount.balance, for: account.id) // ← ПЕРЕЗАПИСЬ!
```

**Проблема:** `setInitialBalance` вызывается с ТЕКУЩИМ балансом после пересчета, но это не правильный `initialBalance`. Правильный `initialBalance` был вычислен как `balance - Σtransactions`, а здесь устанавливается просто `balance`.

### Конфликт #5: Deprecated метод всё ещё используется

**Код (TransactionsViewModel.swift:978-983):**
```swift
/// ⚠️ DEPRECATED: This method modifies accounts in-place but changes are overwritten by recalculateAccountBalances()
/// Consider refactoring to avoid redundant calculations
private func updateDepositBalancesForTransfer(transaction: Transaction, sourceId: String, targetId: String) {
```

**Использование (TransactionsViewModel.swift:950-956):**
```swift
if sourceIsDeposit || targetIsDeposit {
    updateDepositBalancesForTransfer(
        transaction: transactionWithID,
        sourceId: sourceId,
        targetId: targetId
    )
}
```

**Результат:** Депозиты могут обновляться дважды.

---

## Детальный анализ проблем

### Проблема 1: Смешанная логика для imported vs manual accounts

**Текущий подход:**
```
Imported Account:
  initialBalance = currentBalance - Σtransactions
  ↓
  accountsWithCalculatedInitialBalance.insert(id)
  ↓
  recalculateAccountBalances() ПРОПУСКАЕТ транзакции
  ↓
  Новые транзакции через applyTransactionToBalancesDirectly()

Manual Account:
  initialBalance = задан пользователем
  ↓
  recalculateAccountBalances() ПРИМЕНЯЕТ транзакции
  ↓
  balance = initialBalance + Σtransactions
```

**Проблема:** Логика размазана по множеству методов и сложно отследить какой путь используется.

### Проблема 2: Отсутствие единого источника правды

| Данные | Где хранится | Кто обновляет |
|--------|--------------|---------------|
| `accounts` | TransactionsViewModel, AccountsViewModel | Оба |
| `initialAccountBalances` | TransactionsViewModel, AccountsViewModel | Оба |
| `accountsWithCalculatedInitialBalance` | TransactionsViewModel | Только TransactionsViewModel |

### Проблема 3: Несинхронизированные сохранения

**CSV Import:**
```swift
transactionsViewModel.endBatch()        // saves
accountsVM.saveAllAccountsSync()        // saves again
transactionsViewModel.saveToStorageSync() // saves third time
```

**Manual Transaction:**
```swift
scheduleSave() → saveToStorage()  // async save
```

---

## План рефакторинга

### Фаза 1: Унификация источника правды для балансов

#### 1.1 Создать BalanceCalculationService

```swift
protocol BalanceCalculationService {
    /// Рассчитать баланс счета на основе транзакций
    func calculateBalance(
        for accountId: String,
        initialBalance: Double,
        transactions: [Transaction]
    ) -> Double

    /// Определить тип расчета для счета
    func getCalculationMode(for accountId: String) -> BalanceCalculationMode

    /// Применить одну транзакцию к балансу
    func applyTransaction(_ transaction: Transaction, to balance: Double) -> Double
}

enum BalanceCalculationMode {
    case fromInitialBalance  // Manual accounts: balance = initial + Σtx
    case preserveImported    // Imported accounts: balance is already correct
}
```

#### 1.2 Убрать дублирование `initialAccountBalances`

- Хранить только в `AccountsViewModel`
- `TransactionsViewModel` обращается через `accountBalanceService.getInitialBalance()`

### Фаза 2: Разделение процессов импорта и ручного создания

#### 2.1 Рефакторинг CSV Import

```swift
class CSVImportService {
    func importTransactions(...) async -> ImportResult {
        // 1. Парсинг и валидация (без изменения state)
        let parsedData = parseCSV(...)

        // 2. Создание сущностей в изоляции
        await MainActor.run {
            transactionsVM.beginImportMode()  // Новый режим!
            // ... создание сущностей
            transactionsVM.endImportMode()
        }

        // 3. Финальный пересчет балансов
        await MainActor.run {
            transactionsVM.recalculateAllBalances(mode: .imported)
        }
    }
}
```

#### 2.2 Ввести явные режимы работы

```swift
enum TransactionOperationMode {
    case normal           // Обычные операции
    case batchImport      // CSV импорт
    case subscriptionSync // Генерация подписок
}

class TransactionsViewModel {
    private var operationMode: TransactionOperationMode = .normal

    func addTransaction(_ transaction: Transaction, mode: TransactionOperationMode = .normal) {
        switch mode {
        case .normal:
            // Текущая логика + immediate balance update
        case .batchImport:
            // Только добавление, без пересчета
        case .subscriptionSync:
            // Добавление + отложенный пересчет
        }
    }
}
```

### Фаза 3: Исправление механизма `accountsWithCalculatedInitialBalance`

#### 3.1 Переименовать и уточнить семантику

```swift
// Было:
var accountsWithCalculatedInitialBalance: Set<String>

// Стало:
var importedAccountIds: Set<String>  // Счета созданные при импорте
```

#### 3.2 Добавить возможность сброса

```swift
func markAccountAsManual(_ accountId: String) {
    importedAccountIds.remove(accountId)
    // Теперь баланс будет пересчитываться стандартным способом
}

func resetAllImportFlags() {
    importedAccountIds.removeAll()
    initialAccountBalances.removeAll()
    recalculateAccountBalances()
}
```

### Фаза 4: Сериализация операций с балансами

#### 4.1 Использовать Swift Actor

```swift
actor BalanceUpdateCoordinator {
    private var pendingUpdates: [BalanceUpdate] = []
    private var isProcessing = false

    func scheduleUpdate(_ update: BalanceUpdate) async {
        pendingUpdates.append(update)
        await processUpdatesIfNeeded()
    }

    private func processUpdatesIfNeeded() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        while !pendingUpdates.isEmpty {
            let update = pendingUpdates.removeFirst()
            await processUpdate(update)
        }
    }
}
```

### Фаза 5: Удаление deprecated кода

#### 5.1 Удалить `updateDepositBalancesForTransfer`

Перенести логику в `applyTransactionToBalancesDirectly()` с явной обработкой депозитов.

#### 5.2 Консолидировать методы сохранения

```swift
// Вместо:
saveToStorage()
saveToStorageSync()
accountsVM.saveAllAccounts()
accountsVM.saveAllAccountsSync()

// Один метод с опциями:
func save(options: SaveOptions = .default) {
    // options: .sync, .async, .immediate, .debounced
}
```

---

## Рекомендации

### Краткосрочные (быстрые фиксы)

1. **Исправить перезапись initialBalance в CSVImportService**
   - Удалить строку 598: `accountsVM.setInitialBalance(updatedAccount.balance, for: account.id)`
   - Или передавать правильный `initialBalance` из `TransactionsViewModel.initialAccountBalances`

2. **Добавить guard для concurrent notifications**
   ```swift
   private var isProcessingNotification = false

   @objc private func handleRecurringSeriesCreated(_ notification: Notification) {
       guard !isProcessingNotification else { return }
       isProcessingNotification = true
       defer { isProcessingNotification = false }
       // ... existing code
   }
   ```

3. **Удалить вызов deprecated метода**
   - Удалить `updateDepositBalancesForTransfer()` из `addTransaction()`
   - Убедиться что `applyTransactionToBalancesDirectly()` корректно обрабатывает депозиты

### Среднесрочные (рефакторинг)

1. **Создать `BalanceCalculationService`** — единая точка расчета балансов
2. **Убрать дублирование** `initialAccountBalances` между ViewModels
3. **Ввести явные режимы работы** для разных сценариев
4. **Добавить интеграционные тесты** для сценариев:
   - Import CSV → Manual transaction
   - Manual account → Import CSV with same account
   - Concurrent subscription + manual transaction

### Долгосрочные (архитектурные)

1. **Перейти на event-driven архитектуру**
   - Все изменения через events: `TransactionAdded`, `AccountCreated`, etc.
   - Один subscriber обрабатывает balance updates

2. **Использовать CQRS для балансов**
   - Write: транзакции пишутся немедленно
   - Read: балансы кэшируются и инвалидируются по событиям

3. **Рассмотреть миграцию на SwiftData**
   - Более предсказуемое поведение при concurrent updates
   - Встроенная поддержка транзакций

---

## Приложение: Диаграмма текущих конфликтов

```
                    ┌─────────────────┐
                    │  CSV Import     │
                    └────────┬────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  accountsWithCalculated-     │
              │  InitialBalance.insert(id)   │
              └──────────────┬───────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ Manual Add TX │   │ Subscription  │   │ Delete TX     │
│               │   │ Created       │   │               │
└───────┬───────┘   └───────┬───────┘   └───────┬───────┘
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ applyTxTo-    │   │ generate-     │   │ ❌ Balance    │
│ Balances-     │   │ Recurring-    │   │ NOT updated   │
│ Directly()    │   │ Transactions()│   │ (skip set)    │
└───────┬───────┘   └───────┬───────┘   └───────────────┘
        │                   │
        └─────────┬─────────┘
                  │
                  ▼
        ┌───────────────────┐
        │ RACE CONDITION    │
        │ Both call         │
        │ recalculate-      │
        │ AccountBalances() │
        └───────────────────┘
```

---

---

## Выполненные изменения (v1.1)

### 1. Исправлена перезапись initialBalance в CSVImportService

**Файл:** `CSVImportService.swift`

**Проблема:** После импорта текущий баланс устанавливался как initialBalance, что нарушало логику расчета.

**Решение:** Теперь используется правильный initialBalance из `TransactionsViewModel.getInitialBalance()`.

### 2. Добавлена защита от concurrent notifications

**Файл:** `TransactionsViewModel.swift`

**Проблема:** Race condition при одновременном создании подписки и добавлении транзакции.

**Решение:** Добавлен флаг `isProcessingRecurringNotification` для предотвращения concurrent execution.

### 3. Удален deprecated метод updateDepositBalancesForTransfer

**Файл:** `TransactionsViewModel.swift`

**Проблема:** Дублирование логики обновления депозитов.

**Решение:** Логика перенесена в `applyTransactionToBalancesDirectly()`, который теперь корректно обрабатывает депозиты.

### 4. Создан BalanceCalculationService

**Файл:** `Services/BalanceCalculationService.swift`

Новый сервис для унифицированного расчета балансов:
- `getCalculationMode()` - определяет режим расчета (imported/manual)
- `markAsImported()` / `markAsManual()` - управление флагами
- `calculateInitialBalance()` - расчет начального баланса
- `applyTransaction()` - применение транзакции к балансу
- `applyTransactionToDeposit()` - обработка депозитов

### 5. Создан BalanceUpdateCoordinator

**Файл:** `Services/BalanceUpdateCoordinator.swift`

Swift Actor для сериализации операций с балансами:
- Предотвращает race conditions
- Дебаунсинг дублирующих запросов
- Очередь с последовательным выполнением

### 6. Интеграция в TransactionsViewModel

**Изменения:**
- Добавлен `balanceCalculationService` как зависимость
- Добавлен `balanceUpdateCoordinator` для сериализации
- Синхронизация состояния между старым кодом и новым сервисом
- Новые методы: `getInitialBalance()`, `isAccountImported()`, `resetImportedAccountFlags()`

### 7. Добавлены интеграционные тесты

**Файл:** `TenraTests/BalanceCalculationTests.swift`

Тесты покрывают:
- Базовую функциональность BalanceCalculationService
- Обработку депозитов
- Сценарий "Import → Manual Transaction"
- Сценарий "Manual Account with Transactions"

---

### 8. Исправлен баг с нулевыми балансами при импорте CSV (v1.2)

**Файл:** `TransactionsViewModel.swift`

**Проблема:** При импорте CSV создавались счета с `balance = 0`. Затем в `recalculateAccountBalances()`:
1. `initialBalance = account.balance - transactionsSum` = `0 - X` = отрицательное число
2. Счет добавлялся в `accountsWithCalculatedInitialBalance`
3. Транзакции пропускались
4. Итоговый баланс = отрицательное число + 0 = 0 или отрицательный

**Решение:** Различаем два сценария:
1. **Новый счет с balance=0** → `initialBalance = 0`, транзакции ПРИМЕНЯЮТСЯ
2. **Существующий счет с balance>0** → `initialBalance = balance - transactions`, транзакции ПРОПУСКАЮТСЯ

---

## Версия документа

- **Версия:** 1.2
- **Дата:** 2026-01-27
- **Автор:** Claude Code Analysis
