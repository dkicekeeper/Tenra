# Balance Refactoring Plan - Single Source of Truth

## Цель
Создать настоящий Single Source of Truth для балансов счетов через `BalanceCoordinator`, удалив дублирование данных в `Account.balance`.

## Текущее состояние ✅

### Phase 1: Добавлен initialBalance (ЗАВЕРШЕНО)
- ✅ Добавлено поле `initialBalance: Double?` в `Account`
- ✅ Обновлен init, decoder, encoder с backward compatibility
- ✅ `AccountsViewModel.addAccount()` сохраняет `initialBalance` вместо `balance`
- ✅ `syncInitialBalancesToCoordinator()` использует `initialBalance`
- ✅ Депозиты сохраняют `initialBalance`

### Ключевое изменение
```swift
// Раньше:
Account(name: "Test", balance: 1000, ...)  // balance терялся после перезапуска

// Теперь:
Account(
    name: "Test",
    balance: 0,  // DEPRECATED - не используется
    initialBalance: 1000,  // Сохраняется!
    shouldCalculateFromTransactions: false
)
```

## Следующие шаги

### Phase 2: Обновить UI для использования BalanceCoordinator ⏳

#### 2.1 Найти все использования account.balance в UI

Команда для поиска:
```bash
grep -r "account\.balance" Tenra/Views/
```

Ожидаемые файлы:
- `AccountsManagementView.swift`
- `AccountCard.swift`
- `AccountRow.swift`
- `AccountsCarousel.swift`
- `ContentView.swift`
- И другие...

#### 2.2 Паттерн замены

```swift
// ❌ СТАРЫЙ КОД:
struct AccountCard: View {
    let account: Account

    var body: some View {
        Text("\(account.balance)")  // ❌ Прямое использование
    }
}

// ✅ НОВЫЙ КОД:
struct AccountCard: View {
    let account: Account
    @ObservedObject var balanceCoordinator: BalanceCoordinator

    var body: some View {
        Text("\(balanceCoordinator.balances[account.id] ?? 0)")  // ✅ Из coordinator
    }
}
```

#### 2.3 Передача BalanceCoordinator в Views

```swift
// В AppCoordinator или ContentView:
@StateObject private var balanceCoordinator: BalanceCoordinator

// Передача в дочерние views:
AccountsManagementView(
    accountsViewModel: accountsVM,
    balanceCoordinator: balanceCoordinator  // ✅ Добавить
)
```

### Phase 3: Удалить Account.balance полностью 🎯

После обновления всех UI можно удалить:

```swift
struct Account {
    // var balance: Double  ❌ УДАЛИТЬ
    var initialBalance: Double?  // ✅ Только для manual счетов
}
```

Также удалить из:
- `CodingKeys`
- `init(from decoder:)`
- `encode(to encoder:)`

### Phase 4: Оптимизация BalanceCoordinator 🚀

#### 4.1 Убрать BalanceCacheManager
`@Published balances` уже является кешем, `BalanceCacheManager` дублирует его.

```swift
// ❌ УДАЛИТЬ:
private let cache: BalanceCacheManager

// ✅ ОСТАВИТЬ:
@Published private(set) var balances: [String: Double] = [:]
```

#### 4.2 Упростить BalanceStore
Убрать промежуточные структуры, оставить только необходимое.

#### 4.3 Добавить Debouncing
Для множественных обновлений балансов:

```swift
private var recalculateTask: Task<Void, Never>?

func scheduleRecalculate() {
    recalculateTask?.cancel()
    recalculateTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        await recalculateAll()
    }
}
```

## Архитектура (финальная)

```
┌─────────────────────────────────────┐
│   Account (Storage)                  │
│   - id, name, currency               │
│   - shouldCalculateFromTransactions  │
│   - initialBalance (для manual)      │
│   ❌ БЕЗ balance!                     │
└─────────────────────────────────────┘
              │
              │ load/save
              ▼
┌─────────────────────────────────────┐
│   AccountsViewModel                  │
│   - accounts: [Account]              │
│   ❌ НЕ хранит балансы!               │
└─────────────────────────────────────┘
              │
              │ registers accounts
              ▼
┌─────────────────────────────────────┐
│   BalanceCoordinator                 │
│   @Published balances: [ID: Double]  │
│   ✅ ЕДИНЫЙ ИСТОЧНИК БАЛАНСОВ!        │
└─────────────────────────────────────┘
              │
              │ @ObservedObject
              ▼
┌─────────────────────────────────────┐
│   UI Views                           │
│   coordinator.balances[account.id]   │
└─────────────────────────────────────┘
```

## Преимущества после рефакторинга

1. **Single Source of Truth** ✅
   - Баланс хранится ТОЛЬКО в `BalanceCoordinator.balances`
   - Нет рассинхронизации данных

2. **Нет проблем с перезапуском** ✅
   - `Account` хранит только `initialBalance`
   - После загрузки баланс пересчитывается из транзакций

3. **Реактивность** ✅
   - `@Published balances` автоматически обновляет UI
   - Не нужно вручную обновлять `account.balance`

4. **Меньше багов** ✅
   - Один источник = меньше мест для ошибок
   - Проще отлаживать

5. **Производительность** ✅
   - Убран дублирующий кеш
   - Меньше копирований данных

## Риски и митигация

### Риск 1: Много изменений в UI
**Митигация:** Постепенная миграция, одна View за раз

### Риск 2: Backward compatibility
**Митигация:**
- Сохранён decoder для старых данных с `balance`
- Постепенное удаление через deprecation

### Риск 3: Производительность пересчета
**Митигация:**
- Debouncing множественных обновлений
- Батчинг операций
- Кеширование результатов расчета

## Метрики успеха

- [ ] Нет упоминаний `account.balance` в UI
- [ ] Все балансы через `balanceCoordinator.balances`
- [ ] Нет дублирования данных о балансе
- [ ] Балансы не обнуляются после перезапуска
- [ ] Нет race conditions в инициализации
- [ ] Тесты проходят успешно

## Текущий прогресс

✅ Phase 1: Добавлен initialBalance (ЗАВЕРШЕНО)
⏳ Phase 2: Обновление UI (TODO)
⏳ Phase 3: Удаление Account.balance (TODO)
⏳ Phase 4: Оптимизация (TODO)

## Следующий шаг

Начать с Phase 2.1: Найти все использования `account.balance` в UI и составить список файлов для обновления.
