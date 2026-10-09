# Анализ архитектуры и план интеграции депозитов

## Часть 1: Анализ текущей архитектуры

### 1.1 Модель Account

**Файл**: `Tenra/Models/Transaction.swift` (строки 145-183)

**Текущая структура**:
```swift
struct Account: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var balance: Double
    var currency: String
    var bankLogo: BankLogo
}
```

**Особенности**:
- НЕТ enum AccountType - все счета одинаковые по структуре
- Баланс хранится как `Double`
- Логотип банка через enum `BankLogo`
- Поддерживает обратную совместимость через кастомный decoder (bankLogo опционален в старых данных)

### 1.2 Модель Transaction

**Файл**: `Tenra/Models/Transaction.swift` (строки 16-121)

**Текущая структура**:
```swift
struct Transaction: Identifiable, Codable, Equatable {
    let id: String
    let date: String // YYYY-MM-DD
    let description: String
    let amount: Double
    let currency: String
    let convertedAmount: Double?
    let type: TransactionType // income, expense, internalTransfer
    let category: String
    let subcategory: String?
    let accountId: String?
    let targetAccountId: String?
    let recurringSeriesId: String?
    let recurringOccurrenceId: String?
    let createdAt: TimeInterval
}
```

**Типы транзакций**:
```swift
enum TransactionType: String, Codable {
    case income
    case expense
    case internalTransfer = "internal"
}
```

### 1.3 Storage слой

**Файл**: `Tenra/ViewModels/TransactionsViewModel.swift`

**Механизм хранения**:
- **UserDefaults** + **JSON encoding/decoding**
- Каждая сущность хранится в отдельном ключе:
  - `storageKeyAccounts = "accounts"`
  - `storageKeyTransactions = "allTransactions"`
  - `storageKeyCustomCategories = "customCategories"`
  - и т.д.

**Методы сохранения/загрузки**:
- `saveToStorage()` - асинхронное сохранение через `Task.detached`
- `loadFromStorage()` - синхронная загрузка в init

**Важно**: НЕТ миграций - используется кастомный decoder для обратной совместимости

### 1.4 ViewModel

**Файл**: `Tenra/ViewModels/TransactionsViewModel.swift`

**Структура**:
- `@MainActor class TransactionsViewModel: ObservableObject`
- `@Published var accounts: [Account] = []`
- `@Published var allTransactions: [Transaction] = []`

**Методы работы со счетами**:
- `addAccount(name:balance:currency:bankLogo:)` - создание счета
- `updateAccount(_ account: Account)` - обновление счета
- `deleteAccount(_ account: Account)` - удаление счета + связанных транзакций
- `recalculateAccountBalances()` - пересчет балансов на основе транзакций

**Методы работы с транзакциями**:
- `addTransaction(_ transaction: Transaction)`
- `updateTransaction(_ transaction: Transaction)`
- `deleteTransaction(_ transaction: Transaction)`

### 1.5 UI компоненты

**Список счетов**:
- `Tenra/Views/ContentView.swift` - главный экран с `AccountCard`
- `Tenra/Views/Components/AccountCard.swift` - компонент карточки счета
- `Tenra/Views/AccountsManagementView.swift` - управление счетами

**История транзакций**:
- `Tenra/Views/HistoryView.swift` - общий список транзакций
- Фильтрация по `accountId` происходит через `transaction.accountId`

### 1.6 BankLogo

**Файл**: `Tenra/Utils/BankLogo.swift`

**Структура**:
- Enum `BankLogo: String, Codable, CaseIterable`
- Каждый кейс имеет `displayName` и метод `image(size:)`
- Логотипы хранятся в Assets как изображения по имени rawValue

---

## Часть 2: План интеграции депозита

### 2.1 Выбор подхода

**Вариант 1: Расширить Account опциональными полями депозита**
- ✅ Минимальные изменения в существующем коде
- ✅ Депозиты будут в том же массиве `accounts`
- ✅ Существующие экраны продолжат работать (опциональные поля не влияют на Equatable)
- ⚠️ Account станет более "тяжелым" для обычных счетов

**Вариант 2: Отдельная модель Deposit + протокол**
- ❌ Требует значительных изменений в ViewModel и UI
- ❌ Нужно разделять массивы accounts/deposits
- ❌ Нарушает принцип "единый источник истины"

**Выбор: Вариант 1** - расширить Account опциональными полями депозита

### 2.2 Карта изменений файлов

#### Новые файлы:
1. `Tenra/Models/Deposit.swift` - модель депозита (опционально, если выносим в отдельную структуру)
2. `Tenra/Services/DepositInterestService.swift` - сервис расчета процентов
3. `Tenra/Views/DepositDetailView.swift` - детальная страница депозита
4. `Tenra/Views/DepositEditView.swift` - создание/редактирование депозита
5. `Tenra/Views/DepositInterestRateHistoryView.swift` - история ставок (опционально)

#### Изменяемые файлы:

**Модели**:
- `Tenra/Models/Transaction.swift`
  - Добавить новые типы в `TransactionType`: `depositTopUp`, `depositWithdrawal`, `depositInterestAccrual`
  - ИЛИ использовать существующие типы (`income` для пополнения, `expense` для снятия) + специальную категорию

**ViewModel**:
- `Tenra/ViewModels/TransactionsViewModel.swift`
  - Добавить `@Published var deposits: [Deposit]` (если отдельная модель)
  - ИЛИ расширить методы работы с accounts для поддержки депозитов
  - Добавить методы: `addDeposit`, `updateDeposit`, `deleteDeposit`
  - Добавить `reconcileDepositInterest()` - догонялка процентов
  - Добавить `storageKeyDeposits` (если отдельная модель)
  - Добавить сохранение/загрузку депозитов в `saveToStorage()`/`loadFromStorage()`

**UI**:
- `Tenra/Views/ContentView.swift` - отображение депозитов как карточек счетов
- `Tenra/Views/Components/AccountCard.swift` - поддержка отображения депозита (проценты на сегодня, дата начисления)
- `Tenra/Views/AccountsManagementView.swift` - добавить создание депозитов
- `Tenra/Views/HistoryView.swift` - транзакции депозитов уже будут в общей истории (через accountId)

**Сервисы**:
- `Tenra/Services/DepositInterestService.swift` (новый) - логика расчета процентов

### 2.3 Детальная структура данных

#### Модель Deposit (как расширение Account или отдельная структура)

**Подход: Добавить в Account опциональные поля**

```swift
struct Account: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var balance: Double
    var currency: String
    var bankLogo: BankLogo
    
    // Поля депозита (опциональные, nil для обычных счетов)
    var depositInfo: DepositInfo?
}

struct DepositInfo: Codable, Equatable {
    var bankName: String
    var principalBalance: Decimal // Тело депозита
    var capitalizationEnabled: Bool
    var interestAccruedNotCapitalized: Decimal
    var interestRateAnnual: Decimal
    var interestRateHistory: [RateChange]
    var interestPostingDay: Int // 1-31
    var lastInterestCalculationDate: Date
    var lastInterestPostingMonth: Date // Начало месяца последнего начисления
    var interestAccruedForCurrentPeriod: Decimal // Накоплено за текущий период
}

struct RateChange: Codable, Equatable {
    let effectiveFrom: Date
    let annualRate: Decimal
    let note: String?
}
```

**Альтернативный подход: Отдельная модель Deposit**

```swift
struct Deposit: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var currency: String // KZT, USD, EUR
    var bankLogo: BankLogo
    var bankName: String
    // ... все поля депозита
    
    // Метод для конвертации в Account для отображения
    func toAccount() -> Account {
        Account(
            id: id,
            name: name,
            balance: displayBalance, // principalBalance + accrued
            currency: currency,
            bankLogo: bankLogo
        )
    }
}
```

**Рекомендация**: Использовать опциональные поля в Account для минимальных изменений.

### 2.4 Типы транзакций для депозита

**Вариант 1: Новые типы в TransactionType**
```swift
enum TransactionType: String, Codable {
    case income
    case expense
    case internalTransfer = "internal"
    case depositTopUp = "deposit_topup"
    case depositWithdrawal = "deposit_withdrawal"
    case depositInterestAccrual = "deposit_interest"
}
```

**Вариант 2: Использовать существующие типы + специальную категорию**
- Пополнение: `type = .income`, `category = "Пополнение депозита"`
- Снятие: `type = .expense`, `category = "Снятие с депозита"`
- Начисление: `type = .income`, `category = "Начисление процентов"`

**Рекомендация**: Вариант 2 для минимизации изменений, но Вариант 1 более явный.

### 2.5 Storage ключи

Если используем опциональные поля в Account:
- НЕТ новых ключей - депозиты хранятся в `storageKeyAccounts`

Если используем отдельную модель Deposit:
- Добавить `storageKeyDeposits = "deposits"`

### 2.6 Миграции данных

- НЕТ миграций схемы (используется UserDefaults + JSON)
- Обратная совместимость через кастомный decoder (пропускать отсутствующие поля)

---

## Часть 3: Точки интеграции

### 3.1 Инициализация и загрузка данных

**Файл**: `TransactionsViewModel.init()`

После `loadFromStorage()`:
- Вызвать `reconcileAllDeposits()` для догонялки процентов

### 3.2 Отображение счетов

**Файл**: `ContentView.swift`

- `AccountCard` автоматически покажет депозиты (они в `viewModel.accounts`)
- Нужно добавить логику в `AccountCard` для отображения специфичной информации депозита

### 3.3 Создание/редактирование депозитов

**Файл**: `AccountsManagementView.swift`

- Добавить кнопку/сегмент для выбора типа: "Счет" / "Депозит"
- Использовать `DepositEditView` вместо `AccountEditView` для депозитов

### 3.4 История транзакций

**Файл**: `HistoryView.swift`

- Транзакции депозитов автоматически попадут в историю (через `accountId`)
- Фильтрация по счету работает через `transaction.accountId`

### 3.5 Пересчет балансов

**Файл**: `TransactionsViewModel.recalculateAccountBalances()`

- Нужно добавить логику для депозитов:
  - Обычные счета: баланс = начальный баланс + сумма транзакций
  - Депозиты: баланс = principalBalance (+ interestAccruedNotCapitalized если капитализация выключена)

---

## Часть 4: Ключевые решения

### 4.1 Использование Decimal vs Double

- Для финансовых расчетов (проценты, балансы) использовать `Decimal`
- Для отображения можно конвертировать в `Double`
- Account.balance сейчас `Double` - возможно, нужно добавить `Decimal` версию для депозитов

### 4.2 Идемпотентность начислений

- Ключевое поле: `lastInterestPostingMonth` (начало месяца последнего начисления)
- При reconcile проверять: если начисление за месяц уже было - не создавать дубль
- Использовать `TransactionIDGenerator` с фиксированным ID для начислений (на основе depositId + month)

### 3.3 Таймзона и нормализация дат

- Использовать `Calendar.current.startOfDay(for: date)` для нормализации
- Таймзона: локальная (Asia/Almaty через `TimeZone.current`)

---

## Часть 5: Следующие шаги

1. ✅ Анализ архитектуры (этот документ)
2. ⏭️ Решение: расширить Account или создать Deposit?
3. ⏭️ Реализация модели депозита
4. ⏭️ Реализация сервиса расчета процентов
5. ⏭️ Интеграция в ViewModel
6. ⏭️ UI компоненты
7. ⏭️ Тесты
