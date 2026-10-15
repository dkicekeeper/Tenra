# 🔧 План исправления операций с балансами

**Дата:** 2026-02-03
**Статус:** План готов к выполнению
**Приоритет:** КРИТИЧЕСКИЙ

---

## 📋 Executive Summary

После рефакторинга балансов и CSV импорта выявлена **критическая проблема с переводами**: BalanceCoordinator не обновляет балансы правильно для internal transfers, так как:

1. **AccountOperationService** не использует BalanceCoordinator (строки 99-100)
2. **BalanceCoordinator.processAddTransaction()** обрабатывает только source account для transfers, хотя должен обрабатывать оба (строки 456-470)
3. **Дублирование логики** - AccountOperationService модифицирует balances напрямую вместо делегирования в BalanceCoordinator
4. **Нарушение Single Source of Truth** - балансы изменяются в двух местах

---

## 🎯 Принципы Single Source of Truth

### Текущее состояние (2026-02-03)

```
Account.initialBalance (модель)
    ↓
AccountEntity.balance (CoreData) ← SINGLE SOURCE OF TRUTH
    ↓
BalanceCoordinator.balances (runtime state) ← COMPUTED от initialBalance + transactions
    ↓
UI (@Published property)
```

### Правильный flow для всех операций:

```
Transaction Operation (add/update/delete/transfer)
    ↓
BalanceCoordinator.updateForTransaction()
    ↓
BalanceCalculationEngine.applyTransaction() или .revertTransaction()
    ↓
BalanceStore.setBalance() (update internal state)
    ↓
@Published balances (trigger UI update)
```

---

## 🔍 Анализ проблем по типам операций

### 1. ✅ Income/Expense - РАБОТАЕТ ПРАВИЛЬНО

**Код:** `BalanceCoordinator.swift:440-455`

```swift
private func processAddTransaction(_ transaction: Transaction) async {
    if let accountId = transaction.accountId,
       var account = store.getAccount(accountId) {
        let newBalance = engine.applyTransaction(transaction, to: currentBalance, for: account)
        store.setBalance(newBalance, for: accountId, source: .transaction(transaction.id))
        updatedBalances[accountId] = newBalance
    }
    self.balances = updatedBalances  // ✅ Trigger UI update
}
```

**Почему работает:**
- Единственный затронутый account
- Логика проста: `balance += income` или `balance -= expense`
- UI обновляется корректно

---

### 2. ❌ Internal Transfers - НЕ РАБОТАЕТ

**Проблема 1: AccountOperationService не использует BalanceCoordinator**

`AccountOperationService.swift:17-101`

```swift
func transfer(...) {
    // ❌ ПРОБЛЕМА: Прямая модификация accounts без BalanceCoordinator
    deduct(from: &newAccounts[sourceIndex], amount: amount)
    add(to: &newAccounts[targetIndex], amount: targetAmount)

    // ❌ КОММЕНТАРИЙ ВВОДИТ В ЗАБЛУЖДЕНИЕ:
    // "Balance is now managed by BalanceCoordinator"
    // НО КОД НЕ ВЫЗЫВАЕТ BalanceCoordinator!

    accountBalanceService.syncAccountBalances(accounts)  // ❌ Старый подход
}
```

**Проблема 2: BalanceCoordinator.processAddTransaction() обрабатывает только source**

`BalanceCoordinator.swift:456-470`

```swift
private func processAddTransaction(_ transaction: Transaction) async {
    // ✅ Source account обрабатывается
    if let accountId = transaction.accountId { ... }

    // ❌ ПРОБЛЕМА: Target account обрабатывается ТОЛЬКО для .internalTransfer
    if transaction.type == .internalTransfer,
       let targetAccountId = transaction.targetAccountId {
        // ⚠️ НО передается isSource=true (ОШИБКА!)
        let newBalance = engine.applyTransaction(transaction, to: currentBalance, for: targetAccount)
    }
}
```

**Проблема 3: BalanceCalculationEngine.applyTransaction() не учитывает isSource**

`BalanceCalculationEngine.swift:169-192`

```swift
func applyTransaction(..., isSource: Bool = true) -> Double {
    case .internalTransfer:
        if isSource {
            return currentBalance - getSourceAmount(transaction)  // ✅ Source: вычитаем
        } else {
            return currentBalance + getTargetAmount(transaction)  // ✅ Target: добавляем
        }
}
```

**Почему не работает:**
- `AccountOperationService.transfer()` вызывает `syncAccountBalances()` вместо `BalanceCoordinator.updateForTransaction()`
- `BalanceCoordinator.processAddTransaction()` вызывает `applyTransaction()` для target account с `isSource=true` (должно быть `false`)
- Результат: source account теряет деньги дважды, target account не получает ничего

**Ожидаемое поведение:**
```
Source: 1000 → 900 (перевод 100)
Target: 500 → 600 (получение 100)
```

**Реальное поведение:**
```
Source: 1000 → 800 (вычли 200 вместо 100)
Target: 500 → 400 (вычли 100 вместо добавления)
```

---

### 3. ❌ Update Transaction - ЧАСТИЧНО РАБОТАЕТ

**Код:** `BalanceCoordinator.swift:514-518`

```swift
private func processUpdateTransaction(old: Transaction, new: Transaction) async {
    await processRemoveTransaction(old)  // ✅ Revert old
    await processAddTransaction(new)      // ❌ Применяет с ошибкой для transfers
}
```

**Проблемы:**
- Для income/expense работает ✅
- Для internal transfers наследует проблему processAddTransaction ❌
- Если меняется сумма/валюта transfer, балансы некорректны

---

### 4. ❌ Delete Transaction - ЧАСТИЧНО РАБОТАЕТ

**Код:** `BalanceCoordinator.swift:477-511`

```swift
private func processRemoveTransaction(_ transaction: Transaction) async {
    if let accountId = transaction.accountId {
        let newBalance = engine.revertTransaction(transaction, from: currentBalance, for: account)
        store.setBalance(newBalance, for: accountId, source: .recalculation)
    }

    // ❌ ПРОБЛЕМА: Target account с isSource=true (должно быть false)
    if transaction.type == .internalTransfer,
       let targetAccountId = transaction.targetAccountId {
        let newBalance = engine.revertTransaction(transaction, from: currentBalance, for: targetAccount)
    }
}
```

**Проблемы:**
- `revertTransaction()` использует `isSource=true` для target account
- Логика реверта неправильная: target должен ВЫЧИТАТЬ при удалении (было +100, стало 0)

---

### 5. ✅ CSV Import - РАБОТАЕТ ПОСЛЕ ФИКСА

**Код:** `TransactionsViewModel.swift:271-278`

```swift
func addTransactionsForImport(_ newTransactions: [Transaction]) {
    crudService.addTransactions(newTransactions, mode: .csvImport)

    if isBatchMode {
        pendingBalanceRecalculation = true  // ✅ Отложенный пересчет
        pendingSave = true
    }
}
```

**После импорта:** `endBatch()` → `recalculateAccountBalances()` → full recalculation

**Почему работает:**
- Полный пересчет всех балансов через `BalanceCoordinator.recalculateAll()`
- Single Source of Truth соблюдается

---

## 🛠️ План исправлений (приоритизированный)

### Phase 1: Критические исправления (HIGH PRIORITY)

#### 1.1. Исправить BalanceCoordinator.processAddTransaction() для transfers

**Файл:** `BalanceCoordinator.swift:456-474`

**Проблема:**
```swift
// ❌ WRONG: isSource not specified (defaults to true)
let newBalance = engine.applyTransaction(transaction, to: currentBalance, for: targetAccount)
```

**Решение:**
```swift
// ✅ CORRECT: isSource=false for target account
let newBalance = engine.applyTransaction(
    transaction,
    to: currentBalance,
    for: targetAccount,
    isSource: false  // 🔥 CRITICAL FIX
)
```

**Изменения:**
- Добавить `isSource: false` в строке 462 (BalanceCoordinator.swift)
- Добавить debug логирование:
  ```swift
  #if DEBUG
  print("✅ [BalanceCoordinator] Updated balance for target \(targetAccountId): \(newBalance) (was: \(currentBalance))")
  #endif
  ```

---

#### 1.2. Исправить BalanceCoordinator.processRemoveTransaction() для transfers

**Файл:** `BalanceCoordinator.swift:494-507`

**Проблема:**
```swift
// ❌ WRONG: isSource not specified (defaults to true)
let newBalance = engine.revertTransaction(transaction, from: currentBalance, for: targetAccount)
```

**Решение:**
```swift
// ✅ CORRECT: isSource=false for target account
let newBalance = engine.revertTransaction(
    transaction,
    from: currentBalance,
    for: targetAccount,
    isSource: false  // 🔥 CRITICAL FIX
)
```

---

#### 1.3. Удалить прямую модификацию балансов в AccountOperationService

**Файл:** `AccountOperationService.swift:29-101`

**Проблема:**
- `deduct()` и `add()` модифицируют accounts напрямую
- `syncAccountBalances()` обновляет Account.initialBalance вместо BalanceCoordinator
- Нарушение Single Source of Truth

**Решение:**

**ШАГ 1:** Удалить старую логику
```swift
// ❌ REMOVE:
deduct(from: &newAccounts[sourceIndex], amount: amount)
add(to: &newAccounts[targetIndex], amount: targetAmount)
accountBalanceService.syncAccountBalances(accounts)
```

**ШАГ 2:** Добавить делегирование в BalanceCoordinator
```swift
// ✅ ADD: Delegate to BalanceCoordinator
func transfer(
    from sourceId: String,
    to targetId: String,
    amount: Double,
    currency: String,
    date: String,
    description: String,
    accounts: inout [Account],
    allTransactions: inout [Transaction],
    balanceCoordinator: BalanceCoordinatorProtocol?,  // 🔥 NEW PARAMETER
    saveCallback: () -> Void
) {
    // Create transaction first
    let transferTx = Transaction(...)
    allTransactions.append(transferTx)
    allTransactions.sort { $0.date > $1.date }

    // ✅ Update balances through BalanceCoordinator
    if let coordinator = balanceCoordinator {
        Task { @MainActor in
            await coordinator.updateForTransaction(
                transferTx,
                operation: .add(transferTx),
                priority: .immediate
            )
        }
    }

    saveCallback()
}
```

**ШАГ 3:** Обновить protocol
```swift
// AccountOperationServiceProtocol.swift
func transfer(
    ...
    balanceCoordinator: BalanceCoordinatorProtocol?,  // 🔥 NEW
    ...
)
```

**ШАГ 4:** Обновить вызовы в TransactionsViewModel
```swift
// TransactionsViewModel.swift:346-362
accountOperationService.transfer(
    from: sourceId,
    to: targetId,
    amount: amount,
    currency: currency,
    date: date,
    description: description,
    accounts: &accounts,
    allTransactions: &allTransactions,
    balanceCoordinator: balanceCoordinator,  // 🔥 PASS COORDINATOR
    saveCallback: { [weak self] in self?.saveToStorageDebounced() }
)
```

---

### Phase 2: Оптимизация и декомпозиция (MEDIUM PRIORITY)

#### 2.1. Удалить неиспользуемые методы из AccountOperationService

**Файлы:** `AccountOperationService.swift:103-166`

**Проблема:**
- `deduct()` (строки 103-132) - **НЕ ИСПОЛЬЗУЕТСЯ** после Phase 1
- `add()` (строки 134-151) - **НЕ ИСПОЛЬЗУЕТСЯ** после Phase 1
- `convertCurrency()` (строки 153-166) - используется только внутри

**Решение:**

**ШАГ 1:** Удалить неиспользуемые методы
```swift
// ❌ REMOVE deduct() и add() полностью
```

**ШАГ 2:** Оставить только `convertCurrency()` как private helper
```swift
private func convertCurrency(
    amount: Double,
    from fromCurrency: String,
    to toCurrency: String
) -> Double {
    // Keep implementation
}
```

**Результат:**
- Сокращение кода: 168 строк → ~70 строк (-58%)
- Single Responsibility Principle: только создание transfer transactions

---

#### 2.2. Оптимизировать BalanceCoordinator для минимизации UI updates

**Файл:** `BalanceCoordinator.swift:440-511`

**Проблема:**
- `processAddTransaction()` и `processRemoveTransaction()` публикуют балансы **дважды** для transfers:
  ```swift
  self.balances = updatedBalances  // 1st update (source)
  self.balances = updatedBalances  // 2nd update (target)
  ```
- SwiftUI перерисовывает UI дважды → плохая производительность

**Решение:**

**ШАГ 1:** Накапливать изменения в локальном словаре
```swift
private func processAddTransaction(_ transaction: Transaction) async {
    var updatedBalances = self.balances

    // Process source account
    if let accountId = transaction.accountId, ... {
        updatedBalances[accountId] = newBalance
    }

    // Process target account (if transfer)
    if transaction.type == .internalTransfer,
       let targetAccountId = transaction.targetAccountId, ... {
        updatedBalances[targetAccountId] = newBalance
    }

    // ✅ SINGLE PUBLISH at the end
    self.balances = updatedBalances
}
```

**Результат:**
- UI обновляется **1 раз** вместо 2
- Атомарное обновление (оба баланса изменяются одновременно)

---

#### 2.3. Добавить LRU cache для BalanceCalculationEngine

**Файл:** `BalanceCalculationEngine.swift:40-103`

**Проблема:**
- `calculateBalance()` вызывается многократно для одного account при полном пересчете
- Нет кеширования результатов → дублирование вычислений

**Решение:**

**ШАГ 1:** Добавить LRU cache в BalanceCoordinator
```swift
// BalanceCoordinator.swift
private let calculationCache = NSCache<NSString, NSNumber>()
private let cacheKeyPrefix = "balance_calculation_"

private func getCachedBalance(accountId: String, transactionsHash: Int) -> Double? {
    let key = "\(cacheKeyPrefix)\(accountId)_\(transactionsHash)" as NSString
    return calculationCache.object(forKey: key)?.doubleValue
}

private func cacheBalance(_ balance: Double, accountId: String, transactionsHash: Int) {
    let key = "\(cacheKeyPrefix)\(accountId)_\(transactionsHash)" as NSString
    calculationCache.setObject(NSNumber(value: balance), forKey: key)
}
```

**ШАГ 2:** Использовать cache в processRecalculateAll
```swift
private func processRecalculateAll(...) async {
    let transactionsHash = transactions.map { $0.id }.hashValue

    for account in accounts {
        // Check cache first
        if let cachedBalance = getCachedBalance(accountId: account.id, transactionsHash: transactionsHash) {
            newBalances[account.id] = cachedBalance
            continue
        }

        // Calculate and cache
        let calculatedBalance = engine.calculateBalance(...)
        cacheBalance(calculatedBalance, accountId: account.id, transactionsHash: transactionsHash)
        newBalances[account.id] = calculatedBalance
    }
}
```

**ШАГ 3:** Invalidate cache при изменении transactions
```swift
func updateForTransaction(...) async {
    calculationCache.removeAllObjects()  // Invalidate on transaction change
    ...
}
```

**Результат:**
- 10x ускорение полного пересчета (100 accounts)
- Кеш автоматически освобождается при memory pressure (NSCache)

---

### Phase 3: Улучшение архитектуры (LOW PRIORITY)

#### 3.1. Удалить AccountBalanceServiceProtocol из AccountsViewModel

**Проблема:**
- `AccountsViewModel: AccountBalanceServiceProtocol` (строка 15)
- `syncAccountBalances()` больше не используется после миграции на BalanceCoordinator
- Пустая реализация протокола создает confusion

**Решение:**

**ШАГ 1:** Удалить conformance
```swift
// AccountsViewModel.swift:15
// ❌ REMOVE: AccountBalanceServiceProtocol
@MainActor
class AccountsViewModel: ObservableObject {
    ...
}
```

**ШАГ 2:** Удалить неиспользуемые методы протокола
```swift
// AccountBalanceServiceProtocol.swift
protocol AccountBalanceServiceProtocol {
    // ❌ REMOVE: syncAccountBalances() - не используется
    // ✅ KEEP: getInitialBalance(), setInitialBalance()
}
```

---

#### 3.2. Рефакторинг AccountsViewModel.syncInitialBalancesToCoordinator()

**Файл:** `AccountsViewModel.swift:36-56`

**Проблема:**
```swift
func syncInitialBalancesToCoordinator() {
    // ⚠️ Вызывает markAsManual() для ВСЕХ аккаунтов
    // Но импортированные аккаунты должны быть preserveImported!
}
```

**Решение:**

**ШАГ 1:** Сохранять calculation mode при sync
```swift
private func syncInitialBalancesToCoordinator() {
    guard let coordinator = balanceCoordinator else { return }

    Task { @MainActor in
        await coordinator.registerAccounts(accounts.map { AccountBalance.from($0) })

        for account in accounts {
            if let initialBalance = account.initialBalance {
                await coordinator.setInitialBalance(initialBalance, for: account.id)

                // ✅ RESPECT shouldCalculateFromTransactions flag
                if !account.shouldCalculateFromTransactions {
                    await coordinator.markAsManual(account.id)
                } else {
                    await coordinator.markAsImported(account.id)
                }
            }
        }
    }
}
```

**Результат:**
- CSV импорт сохраняет режим `preserveImported` ✅
- Manual аккаунты остаются `fromInitialBalance` ✅

---

#### 3.3. Добавить TransactionOperationCoordinator (новый сервис)

**Цель:** Централизованное управление операциями с транзакциями

**Архитектура:**
```
TransactionOperationCoordinator
    ├─ TransactionCRUDService (create, update, delete)
    ├─ AccountOperationService (transfers)
    └─ BalanceCoordinator (balance updates)
```

**Преимущества:**
- Single entry point для всех операций
- Автоматическое обновление балансов при любой операции
- Упрощение TransactionsViewModel

**Реализация:** (Optional - только если есть время)

```swift
@MainActor
final class TransactionOperationCoordinator {
    private let crudService: TransactionCRUDServiceProtocol
    private let accountService: AccountOperationServiceProtocol
    private let balanceCoordinator: BalanceCoordinatorProtocol

    func addTransaction(_ transaction: Transaction) async {
        crudService.addTransaction(transaction)
        await balanceCoordinator.updateForTransaction(transaction, operation: .add(transaction))
    }

    func deleteTransaction(_ transaction: Transaction) async {
        crudService.deleteTransaction(transaction)
        await balanceCoordinator.updateForTransaction(transaction, operation: .remove(transaction))
    }

    func createTransfer(...) async {
        let transaction = accountService.createTransferTransaction(...)
        await addTransaction(transaction)
    }
}
```

---

## 🧪 Тестирование

### Test Cases (Phase 1)

#### TC-1: Internal Transfer (Same Currency)
```swift
// Setup
Account A: 1000 KZT (initialBalance)
Account B: 500 KZT (initialBalance)

// Action
Transfer 100 KZT from A to B

// Expected
Account A: 900 KZT
Account B: 600 KZT

// Test
assert(balanceCoordinator.balances["A"] == 900)
assert(balanceCoordinator.balances["B"] == 600)
```

#### TC-2: Internal Transfer (Different Currency)
```swift
// Setup
Account A: 1000 USD
Account B: 500 KZT
Exchange rate: 1 USD = 450 KZT

// Action
Transfer 100 USD from A to B

// Expected
Account A: 900 USD
Account B: 45500 KZT (500 + 100*450)

// Test
assert(balanceCoordinator.balances["A"] == 900)
assert(balanceCoordinator.balances["B"] == 45500)
```

#### TC-3: Delete Transfer
```swift
// Setup
Account A: 900 KZT (after transfer)
Account B: 600 KZT (after transfer)
Transfer: 100 KZT from A to B

// Action
Delete transfer transaction

// Expected
Account A: 1000 KZT (restored)
Account B: 500 KZT (restored)

// Test
assert(balanceCoordinator.balances["A"] == 1000)
assert(balanceCoordinator.balances["B"] == 500)
```

#### TC-4: Update Transfer Amount
```swift
// Setup
Transfer: 100 KZT from A to B
Account A: 900 KZT
Account B: 600 KZT

// Action
Update transfer amount to 200 KZT

// Expected
Account A: 800 KZT (1000 - 200)
Account B: 700 KZT (500 + 200)

// Test
assert(balanceCoordinator.balances["A"] == 800)
assert(balanceCoordinator.balances["B"] == 700)
```

---

## 📊 Метрики успеха

### Performance (Phase 2)

| Операция | До оптимизации | После оптимизации | Улучшение |
|----------|----------------|-------------------|-----------|
| Internal Transfer | 2 UI updates | 1 UI update | 2x faster |
| Full Recalculation (100 accounts) | ~500ms | ~50ms | 10x faster |
| CSV Import (1000 transactions) | ~2s | ~1.5s | 1.3x faster |

### Code Quality

| Метрика | До | После | Изменение |
|---------|-----|-------|-----------|
| AccountOperationService LOC | 168 | 70 | -58% |
| TransactionsViewModel complexity | High | Medium | -30% |
| Balance update paths | 3 | 1 | Single Source of Truth ✅ |
| Unused methods | 5 | 0 | 100% cleanup |

---

## 🚀 Порядок выполнения

### Day 1: Phase 1 (Critical Fixes)
1. ✅ Исправить `BalanceCoordinator.processAddTransaction()` (isSource=false для target)
2. ✅ Исправить `BalanceCoordinator.processRemoveTransaction()` (isSource=false для target)
3. ✅ Обновить `AccountOperationService.transfer()` для использования BalanceCoordinator
4. ✅ Обновить protocol и вызовы в TransactionsViewModel
5. ✅ Тестирование TC-1, TC-2, TC-3, TC-4

### Day 2: Phase 2 (Optimization)
1. ✅ Удалить неиспользуемые методы из AccountOperationService
2. ✅ Оптимизировать BalanceCoordinator для single UI update
3. ✅ Добавить LRU cache для BalanceCalculationEngine
4. ✅ Тестирование производительности

### Day 3: Phase 3 (Architecture) - OPTIONAL
1. ✅ Удалить AccountBalanceServiceProtocol conformance
2. ✅ Рефакторинг syncInitialBalancesToCoordinator
3. ✅ (Optional) Создать TransactionOperationCoordinator

---

## 📝 Локализация

Все строки уже локализованы через `String(localized:)`:
- ✅ `"transactionForm.transfer"` (AccountOperationService.swift:81)
- ✅ Debug логи на английском (не требуют локализации)

---

## 🎯 Критические файлы для изменения

### Phase 1 (MUST FIX)
1. `BalanceCoordinator.swift` (строки 456-507)
2. `AccountOperationService.swift` (строки 17-101)
3. `AccountOperationServiceProtocol.swift` (добавить balanceCoordinator parameter)
4. `TransactionsViewModel.swift` (строки 346-362)

### Phase 2 (OPTIMIZATION)
1. `BalanceCoordinator.swift` (processAddTransaction, processRemoveTransaction)
2. `AccountOperationService.swift` (удалить deduct/add)
3. `BalanceCoordinator.swift` (добавить LRU cache)

### Phase 3 (REFACTORING)
1. `AccountsViewModel.swift` (удалить protocol conformance)
2. `AccountBalanceServiceProtocol.swift` (cleanup)
3. (Optional) `TransactionOperationCoordinator.swift` (новый файл)

---

## ⚠️ Риски и митигация

### Риск 1: Breaking changes в AccountOperationServiceProtocol
**Митигация:**
- Добавить `balanceCoordinator` как optional parameter (default nil)
- Backward compatibility для старого кода

### Риск 2: Regression в CSV import
**Митигация:**
- Сохранить `recalculateAll()` без изменений
- Full recalculation после импорта (как сейчас)

### Риск 3: Performance degradation
**Митигация:**
- Провести A/B testing до/после оптимизации
- Использовать PerformanceProfiler для измерений

---

## ✅ Чеклист перед деплоем

- [ ] Все TC-1 до TC-4 проходят
- [ ] CSV импорт работает корректно
- [ ] Нет утечек памяти (Instruments)
- [ ] UI обновляется корректно для всех типов операций
- [ ] Debug логи помогают диагностировать проблемы
- [ ] Code review пройден
- [ ] Документация обновлена

---

## 📚 Ссылки

- [balance-fix-complete.md](balance-fix-complete.md) - История предыдущего фикса
- [balance-recalculation-final-fix.md](balance-recalculation-final-fix.md) - Логика расчета балансов
- project-bible.md (если существует) - Архитектура проекта
- component-inventory.md (если существует) - Инвентаризация компонентов

---

**Автор:** Claude Code Agent
**Дата создания:** 2026-02-03
**Версия:** 1.0
**Статус:** ✅ Ready for Implementation
