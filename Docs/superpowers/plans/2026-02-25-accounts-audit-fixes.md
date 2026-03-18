# Accounts Audit Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 21 issues found in the Accounts SwiftUI audit — dead code, SSOT violations, accessibility gaps, non-localized strings, and a 312-line business-logic extraction from AccountActionView.

**Architecture:** Quick mechanical fixes first (Tasks 1–8), then the major ViewModel extraction (Tasks 9–11). Each task targets one file or one concern. No new external dependencies — all fixes use existing patterns from the codebase.

**Tech Stack:** SwiftUI, @Observable, @MainActor, TransactionStore (SSOT), AppSettings.availableCurrencies, AmountFormatter, os.Logger

---

## Исправленные находки аудита (ref)

| # | Файл | Проблема |
|---|------|---------|
| 1 | AccountsViewModel | `@ObservationIgnored` отсутствует на `repository`; мёртвый Combine импорт + `accountsSubscription`; пустые no-op методы |
| 2 | AccountsCarousel | Нестабильный `.id()` с балансом ломает анимации |
| 3 | AccountRow | `.onTapGesture` вместо `Button`; мёртвый параметр `currency`; хрупкий `replacingOccurrences` |
| 4 | AccountEditView | Хардкод `["USD","EUR","KZT","RUB","GBP"]` вместо `AppSettings.availableCurrencies`; `String(format:)` вместо `AmountFormatter` |
| 5 | AccountsManagementView | Дублирование `sortedByOrder()`; force-unwrap `balanceCoordinator!`; молчаливое проглатывание ошибок |
| 6 | TransactionStore + AccountsManagementView | SSOT-нарушение: прямая мутация `transactionsViewModel.allTransactions` |
| 7 | AccountActionView | Бессмысленный тернарный; неверный alert-ключ `voice.error`; force-unwrap `balanceCoordinator!` |
| 8 | AccountActionView | 7 хардкод русских строк ошибок |
| 9 | AccountActionView | `CategoriesViewModel` создаётся при каждом открытии Sheet |
| 10–11 | AccountActionView | 312 строк бизнес-логики в View; вложенный `Task {}` внутри `await MainActor.run {}` |

---

### Task 1: AccountsViewModel — мёртвый код и @ObservationIgnored

**Files:**
- Modify: `AIFinanceManager/ViewModels/AccountsViewModel.swift`

**Step 1: Удалить `import Combine`, `import CoreData`, `accountsSubscription`**

Убрать строки 11–12 (`import CoreData`, `import Combine`) и строку 39 (`private var accountsSubscription: AnyCancellable?`).

**Step 2: Добавить `@ObservationIgnored` на `repository`**

```swift
// БЫЛО:
private let repository: DataRepositoryProtocol

// СТАЛО:
@ObservationIgnored private let repository: DataRepositoryProtocol
```

**Step 3: Удалить no-op методы и пустые else-блоки**

Удалить:
- `setupTransactionStoreObserver()` (строка 50–52) — пустое тело
- `syncAccountsFromStore()` (строка 54–56) — пустое тело
- `saveAllAccounts()` (строка 287–288) — пустое тело
- `saveAllAccountsSync()` (строка 291–293) — пустое тело
- `transfer()` (строки 154–172) — тело содержит только `let _ =` мусор и возврат без действия

Убрать пустые `else {}` в:
- `addAccount()` строка 97: `} else { }`
- `syncInitialBalancesToCoordinator()` строки 262–264: `} else { }`

**Step 4: Собрать проект**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: `Build succeeded`

**Step 5: Commit**

```bash
git add AIFinanceManager/ViewModels/AccountsViewModel.swift
git commit -m "refactor(accounts): remove dead Combine code and add @ObservationIgnored to repository"
```

---

### Task 2: AccountsCarousel — стабильный ID

**Files:**
- Modify: `AIFinanceManager/Views/Accounts/Components/AccountsCarousel.swift`

**Контекст:** `.id("\(account.id)-\(balanceCoordinator.balances[account.id] ?? 0)")` уничтожает и пересоздаёт `AccountCard` при каждом изменении баланса, ломая `.matchedTransitionSource` и `.glassEffectID`. `@Observable` на `BalanceCoordinator` сам отслеживает изменения и обновляет `AccountCard` без пересоздания.

**Step 1: Заменить составной ID на стабильный**

```swift
// БЫЛО:
AccountCard(...)
    .id("\(account.id)-\(balanceCoordinator.balances[account.id] ?? 0)")

// СТАЛО:
AccountCard(...)
    .id(account.id)
```

**Step 2: Изменить `var namespace` → `let namespace`**

```swift
// БЫЛО:
var namespace: Namespace.ID

// СТАЛО:
let namespace: Namespace.ID
```

**Step 3: Собрать проект, убедиться `Build succeeded`**

**Step 4: Commit**

```bash
git add AIFinanceManager/Views/Accounts/Components/AccountsCarousel.swift
git commit -m "fix(accounts): use stable id in AccountsCarousel, prevent view recreation on balance update"
```

---

### Task 3: AccountRow — доступность, мёртвый параметр, хрупкая строка

**Files:**
- Modify: `AIFinanceManager/Views/Accounts/Components/AccountRow.swift`

**Step 1: Убрать неиспользуемый параметр `currency: String`**

Удалить строку `let currency: String` из тела структуры. Найти все места вызова `AccountRow(... currency: ...)` и убрать этот аргумент.

Вызовы в `AccountsManagementView.swift` (строка 83):
```swift
// БЫЛО:
AccountRow(
    account: account,
    currency: baseCurrency,
    ...
)

// СТАЛО:
AccountRow(
    account: account,
    ...
)
```

И в preview внутри `AccountsManagementView.swift` и `AccountRow.swift` — аналогично.

**Step 2: Заменить `.onTapGesture` на `Button`**

```swift
// БЫЛО:
HStack(spacing: AppSpacing.md) { ... }
.onTapGesture { onEdit() }
.swipeActions(...) { ... }

// СТАЛО:
Button(action: onEdit) {
    HStack(spacing: AppSpacing.md) { ... }
}
.buttonStyle(.plain)
.swipeActions(...) { ... }
```

**Step 3: Исправить хрупкий `replacingOccurrences`**

Текущий код строит "Проценты сегодня: 123.45" ручной манипуляцией строки. Использовать `Text` concatenation:

```swift
// БЫЛО:
HStack(spacing: 0) {
    Text(String(localized: "account.interestToday").replacingOccurrences(of: "%@", with: ""))
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
    FormattedAmountText(amount: interest, ...)
}

// СТАЛО:
// Нужен ключ без %@, создать отдельный ключ "account.interestTodayPrefix"
// (см. Step 4 ниже)
HStack(spacing: 0) {
    Text("account.interestTodayPrefix")
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
    FormattedAmountText(amount: interest, ...)
}
```

**Step 4: Добавить ключ локализации `account.interestTodayPrefix`**

В `en.lproj/Localizable.strings`:
```
"account.interestTodayPrefix" = "Interest today: ";
```

В `ru.lproj/Localizable.strings`:
```
"account.interestTodayPrefix" = "Проценты сегодня: ";
```

> Примечание: проверить существующий ключ `account.interestToday` — если он содержит `%@`, он остаётся для других мест. Новый ключ только для prefix в AccountRow.

**Step 5: Собрать проект, убедиться `Build succeeded`**

**Step 6: Commit**

```bash
git add AIFinanceManager/Views/Accounts/Components/AccountRow.swift \
        AIFinanceManager/Views/Accounts/AccountsManagementView.swift \
        AIFinanceManager/AIFinanceManager/en.lproj/Localizable.strings \
        AIFinanceManager/AIFinanceManager/ru.lproj/Localizable.strings
git commit -m "fix(accounts): replace onTapGesture with Button, remove unused currency param, fix interest string"
```

---

### Task 4: AccountEditView — правильный список валют и AmountFormatter

**Files:**
- Modify: `AIFinanceManager/Views/Accounts/AccountEditView.swift`

**Step 1: Заменить хардкод-список валют на `AppSettings.availableCurrencies`**

```swift
// БЫЛО:
private let currencies = ["USD", "EUR", "KZT", "RUB", "GBP"]

// СТАЛО: удалить строку — передавать динамически
```

В `EditableHeroSection(... currencies: currencies ...)` заменить на:
```swift
EditableHeroSection(
    ...
    currencies: AppSettings.availableCurrencies
)
```

**Step 2: Заменить `String(format:)` на `AmountFormatter`**

```swift
// БЫЛО (строка 68):
balanceText = String(format: "%.2f", balanceValue)

// СТАЛО:
balanceText = AmountFormatter.format(balanceValue)
```

> `AmountFormatter.format(_:)` находится в `Utils/AmountFormatter.swift`. Проверить сигнатуру метода перед заменой.

**Step 3: Собрать проект, убедиться `Build succeeded`**

**Step 4: Commit**

```bash
git add AIFinanceManager/Views/Accounts/AccountEditView.swift
git commit -m "fix(accounts): use AppSettings.availableCurrencies and AmountFormatter in AccountEditView"
```

---

### Task 5: AccountsManagementView — sortedByOrder, force-unwrap, логирование

**Files:**
- Modify: `AIFinanceManager/Views/Accounts/AccountsManagementView.swift`

**Step 1: Заменить дублирующий sort на `sortedByOrder()`**

```swift
// БЫЛО (строки 29–44):
private var sortedAccounts: [Account] {
    return accountsViewModel.accounts.sorted { acc1, acc2 in
        if let order1 = acc1.order, let order2 = acc2.order { return order1 < order2 }
        if acc1.order != nil { return true }
        if acc2.order != nil { return false }
        return acc1.name < acc2.name
    }
}

// СТАЛО:
private var sortedAccounts: [Account] {
    accountsViewModel.accounts.sortedByOrder()
}
```

**Step 2: Исправить force-unwrap `balanceCoordinator!`**

В строке 90:
```swift
// БЫЛО:
balanceCoordinator: accountsViewModel.balanceCoordinator!

// СТАЛО:
balanceCoordinator: accountsViewModel.balanceCoordinator ?? BalanceCoordinator()
```

> Или использовать `guard let balanceCoordinator = accountsViewModel.balanceCoordinator else { return EmptyView() }` — выбрать вариант, соответствующий контексту view.

**Step 3: Добавить логирование ошибок в пустые catch-блоки**

Добавить `import OSLog` в начало файла. Объявить логгер:
```swift
private let logger = Logger(subsystem: "AIFinanceManager", category: "AccountsManagementView")
```

Заменить пустые `catch {}` (строки 114–116 и 193–197):
```swift
} catch {
    logger.error("Failed to add deposit transaction: \(error.localizedDescription)")
}
```

**Step 4: Собрать проект, убедиться `Build succeeded`**

**Step 5: Commit**

```bash
git add AIFinanceManager/Views/Accounts/AccountsManagementView.swift
git commit -m "fix(accounts): use sortedByOrder(), fix force-unwrap, add error logging"
```

---

### Task 6: TransactionStore + AccountsManagementView — устранение SSOT-нарушения

**Files:**
- Modify: `AIFinanceManager/ViewModels/TransactionStore.swift`
- Modify: `AIFinanceManager/Views/Accounts/AccountsManagementView.swift`

**Контекст:** `AccountsManagementView` напрямую мутирует `transactionsViewModel.allTransactions.removeAll { ... }` при удалении счёта с транзакциями. Это обходит TransactionStore (SSOT). Нужно добавить метод в TransactionStore и использовать его.

**Step 1: Добавить `deleteAccountTransactions(_ accountId:)` в TransactionStore**

Найти `func deleteAccount(_ accountId: String)` в `TransactionStore.swift` (строка ~657). Добавить новый метод рядом:

```swift
/// Удаляет все транзакции, связанные со счётом (accountId или targetAccountId).
/// Вызывается перед deleteAccount при deleteTransactions: true.
func deleteTransactions(forAccountId accountId: String) {
    let toDelete = transactions.filter {
        $0.accountId == accountId || $0.targetAccountId == accountId
    }
    for transaction in toDelete {
        transactions.removeAll { $0.id == transaction.id }
        apply(.deleted(transaction))
    }
}
```

> Примечание: проверить существующий метод `delete(_ transaction:)` и паттерн `apply(.deleted(...))` в TransactionStore. Если паттерн отличается — использовать тот же подход, что и в существующем `delete()`.

**Step 2: Обновить AccountsManagementView — убрать прямую мутацию**

```swift
// БЫЛО (строки 259–271):
Button(String(localized: "account.deleteAccountAndTransactions"), role: .destructive) {
    HapticManager.warning()
    accountsViewModel.deleteAccount(account, deleteTransactions: true)

    // НАРУШЕНИЕ SSOT:
    transactionsViewModel.allTransactions.removeAll {
        $0.accountId == account.id || $0.targetAccountId == account.id
    }

    transactionsViewModel.cleanupDeletedAccount(account.id)
    transactionsViewModel.clearAndRebuildAggregateCache()
    transactionsViewModel.syncAccountsFrom(accountsViewModel)
    accountToDelete = nil
}

// СТАЛО:
Button(String(localized: "account.deleteAccountAndTransactions"), role: .destructive) {
    HapticManager.warning()
    transactionStore.deleteTransactions(forAccountId: account.id)
    accountsViewModel.deleteAccount(account, deleteTransactions: false) // транзакции уже удалены выше
    transactionsViewModel.cleanupDeletedAccount(account.id)
    transactionsViewModel.clearAndRebuildAggregateCache()
    accountToDelete = nil
}
```

**Step 3: Собрать проект, убедиться `Build succeeded`**

**Step 4: Commit**

```bash
git add AIFinanceManager/ViewModels/TransactionStore.swift \
        AIFinanceManager/Views/Accounts/AccountsManagementView.swift
git commit -m "fix(ssot): move account transaction deletion into TransactionStore, remove allTransactions direct mutation"
```

---

### Task 7: AccountActionView — минорные исправления (ternary, alert, force-unwrap)

**Files:**
- Modify: `AIFinanceManager/Views/Accounts/AccountActionView.swift`

**Step 1: Убрать бессмысленный ternary (строка 46)**

```swift
// БЫЛО:
_selectedAction = State(initialValue: account.isDeposit ? .transfer : .transfer)

// СТАЛО:
_selectedAction = State(initialValue: .transfer)
```

**Step 2: Исправить семантически неверный ключ alert (строка 153)**

```swift
// БЫЛО:
.alert(String(localized: "voice.error"), isPresented: $showingError) {

// СТАЛО:
.alert(String(localized: "common.error"), isPresented: $showingError) {
```

> Проверить существующие ключи: если `common.error` не существует — добавить в Localizable.strings. Альтернатива: использовать `String(localized: "transactionForm.error")` если такой ключ есть.

**Step 3: Исправить force-unwrap `balanceCoordinator!` (строка 91)**

```swift
// БЫЛО:
AccountSelectorView(
    ...
    balanceCoordinator: accountsViewModel.balanceCoordinator!
)

// СТАЛО:
if let coordinator = accountsViewModel.balanceCoordinator {
    AccountSelectorView(
        ...
        balanceCoordinator: coordinator
    )
}
```

**Step 4: Заменить `var namespace: Namespace.ID` → `let namespace: Namespace.ID` (строка 16)**

**Step 5: Собрать проект, убедиться `Build succeeded`**

**Step 6: Commit**

```bash
git add AIFinanceManager/Views/Accounts/AccountActionView.swift
git commit -m "fix(accounts): remove pointless ternary, fix alert key, fix balanceCoordinator force-unwrap"
```

---

### Task 8: AccountActionView — локализация 7 хардкод-строк

**Files:**
- Modify: `AIFinanceManager/Views/Accounts/AccountActionView.swift`
- Modify: `AIFinanceManager/AIFinanceManager/en.lproj/Localizable.strings`
- Modify: `AIFinanceManager/AIFinanceManager/ru.lproj/Localizable.strings`

**Step 1: Добавить ключи в Localizable.strings**

В `en.lproj/Localizable.strings` (в секцию `// MARK: - Currency Conversion`):
```
"currency.error.conversionFailed" = "Currency conversion failed. Please check your internet connection.";
"currency.error.ratesUnavailable" = "Failed to load exchange rates. Check your internet connection and try again.";
"currency.error.sourceConversionFailed" = "Failed to convert currency for source account. Check your internet connection.";
"currency.error.targetConversionFailed" = "Failed to convert currency for target account. Check your internet connection.";
"currency.error.crossConversionFailed" = "Failed to convert currency between accounts. Check your internet connection.";
```

В `ru.lproj/Localizable.strings`:
```
"currency.error.conversionFailed" = "Ошибка конвертации валюты. Проверьте подключение к интернету.";
"currency.error.ratesUnavailable" = "Не удалось загрузить курсы валют. Проверьте подключение к интернету и попробуйте снова.";
"currency.error.sourceConversionFailed" = "Не удалось конвертировать валюту для счета-источника. Проверьте подключение к интернету.";
"currency.error.targetConversionFailed" = "Не удалось конвертировать валюту для счета-получателя. Проверьте подключение к интернету.";
"currency.error.crossConversionFailed" = "Не удалось конвертировать валюту между счетами. Проверьте подключение к интернету.";
```

**Step 2: Заменить хардкод-строки в AccountActionView.saveTransaction()**

| Строка | Хардкод → Ключ |
|--------|----------------|
| ~219 | `"Ошибка конвертации валюты..."` → `String(localized: "currency.error.conversionFailed")` |
| ~269 | та же строка → `String(localized: "currency.error.conversionFailed")` |
| ~299 | `"Не удалось загрузить курсы валют..."` → `String(localized: "currency.error.ratesUnavailable")` |
| ~315 | `"Не удалось конвертировать... источника"` → `String(localized: "currency.error.sourceConversionFailed")` |
| ~324 | `"Не удалось конвертировать... получателя"` → `String(localized: "currency.error.targetConversionFailed")` |
| ~330 | та же → `String(localized: "currency.error.targetConversionFailed")` |
| ~344 | `"Не удалось конвертировать... между счетами"` → `String(localized: "currency.error.crossConversionFailed")` |

**Step 3: Собрать проект, убедиться `Build succeeded`**

**Step 4: Commit**

```bash
git add AIFinanceManager/Views/Accounts/AccountActionView.swift \
        AIFinanceManager/AIFinanceManager/en.lproj/Localizable.strings \
        AIFinanceManager/AIFinanceManager/ru.lproj/Localizable.strings
git commit -m "i18n(accounts): localize currency conversion error strings in AccountActionView"
```

---

### Task 9: AccountActionView — CategoriesViewModel injection

**Files:**
- Modify: `AIFinanceManager/Views/Accounts/AccountActionView.swift`

**Контекст:** `CategoriesViewModel(repository: transactionsViewModel.repository)` создаётся заново при каждом открытии Sheet (строка 143). `AppCoordinator` уже имеет `@ObservationIgnored let categoriesViewModel: CategoriesViewModel` — нужно использовать его.

**Step 1: Добавить параметр `categoriesViewModel` в `AccountActionView`**

```swift
// В struct AccountActionView:
let categoriesViewModel: CategoriesViewModel

// В init:
init(
    transactionsViewModel: TransactionsViewModel,
    accountsViewModel: AccountsViewModel,
    account: Account,
    namespace: Namespace.ID,
    transferDirection: DepositTransferDirection? = nil,
    categoriesViewModel: CategoriesViewModel   // ← новый параметр
) {
    ...
    self.categoriesViewModel = categoriesViewModel
}
```

**Step 2: Заменить inline создание в Sheet**

```swift
// БЫЛО (строка 143):
HistoryView(
    ...
    categoriesViewModel: CategoriesViewModel(repository: transactionsViewModel.repository),
    ...
)

// СТАЛО:
HistoryView(
    ...
    categoriesViewModel: categoriesViewModel,
    ...
)
```

**Step 3: Обновить все места вызова AccountActionView**

Найти все места где создаётся `AccountActionView(...)` в проекте:
```bash
grep -r "AccountActionView(" --include="*.swift" AIFinanceManager/
```

Добавить `categoriesViewModel: appCoordinator.categoriesViewModel` в каждый вызов. Типичный паттерн:
```swift
AccountActionView(
    transactionsViewModel: transactionsViewModel,
    accountsViewModel: accountsViewModel,
    account: account,
    namespace: namespace,
    categoriesViewModel: appCoordinator.categoriesViewModel  // ← добавить
)
```

**Step 4: Обновить Preview в AccountActionView.swift**

```swift
#Preview {
    @Previewable @Namespace var ns
    let coordinator = AppCoordinator()
    return NavigationStack {
        AccountActionView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            account: Account(name: "Main", currency: "USD", iconSource: nil, initialBalance: 1000),
            namespace: ns,
            categoriesViewModel: coordinator.categoriesViewModel
        )
    }
}
```

**Step 5: Собрать проект, убедиться `Build succeeded`**

**Step 6: Commit**

```bash
git add AIFinanceManager/Views/Accounts/AccountActionView.swift
git add $(git diff --name-only HEAD)  # Любые файлы с вызовами AccountActionView
git commit -m "fix(accounts): inject CategoriesViewModel instead of creating inline on each sheet open"
```

---

### Task 10: Создать AccountActionViewModel

**Files:**
- Create: `AIFinanceManager/ViewModels/AccountActionViewModel.swift`

**Контекст:** Вся логика `saveTransaction(date:)` из AccountActionView (~312 строк) переезжает сюда. Это `@Observable @MainActor` класс по стандарту проекта. `TransactionStore` передаётся в `saveTransaction` как параметр (не хранится в VM), чтобы не требовать его в `init` — его нет в момент init View.

**Step 1: Создать файл AccountActionViewModel.swift**

```swift
//
//  AccountActionViewModel.swift
//  AIFinanceManager
//

import Foundation
import OSLog

@Observable
@MainActor
final class AccountActionViewModel {

    // MARK: - Observable State (tracked by @Observable)

    var selectedAction: ActionType = .transfer
    var amountText: String = ""
    var selectedCurrency: String
    var descriptionText: String = ""
    var selectedCategory: String? = nil
    var selectedTargetAccountId: String? = nil
    var showingError: Bool = false
    var errorMessage: String = ""
    var shouldDismiss: Bool = false

    // MARK: - Dependencies (@ObservationIgnored per Phase 23)

    @ObservationIgnored let account: Account
    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored let transferDirection: DepositTransferDirection?
    @ObservationIgnored private let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored private let logger = Logger(subsystem: "AIFinanceManager", category: "AccountActionViewModel")

    // MARK: - Computed (derived, not stored)

    enum ActionType { case income, transfer }

    var availableAccounts: [Account] {
        accountsViewModel.accounts.filter { $0.id != account.id }
    }

    var incomeCategories: [String] {
        transactionsViewModel.incomeCategories
    }

    var navigationTitleText: String {
        if account.isDeposit {
            if let direction = transferDirection {
                return direction == .toDeposit
                    ? String(localized: "transactionForm.depositTopUp")
                    : String(localized: "transactionForm.depositWithdrawal")
            }
            return String(localized: "transactionForm.depositTopUp")
        }
        return selectedAction == .income
            ? String(localized: "transactionForm.accountTopUp")
            : String(localized: "transactionForm.transfer")
    }

    var headerForAccountSelection: String {
        if account.isDeposit {
            if let direction = transferDirection {
                return direction == .toDeposit
                    ? String(localized: "transactionForm.fromAccount")
                    : String(localized: "transactionForm.toAccount")
            }
            return String(localized: "transactionForm.fromAccount")
        }
        return String(localized: "transactionForm.toAccount")
    }

    // MARK: - Init

    init(
        account: Account,
        accountsViewModel: AccountsViewModel,
        transactionsViewModel: TransactionsViewModel,
        transferDirection: DepositTransferDirection? = nil
    ) {
        self.account = account
        self.accountsViewModel = accountsViewModel
        self.transactionsViewModel = transactionsViewModel
        self.transferDirection = transferDirection
        self.selectedCurrency = account.currency
    }

    // MARK: - Save

    /// Validates, converts currency, and persists the transaction/transfer.
    /// `transactionStore` is passed from the View (injected via @Environment).
    func saveTransaction(date: Date, transactionStore: TransactionStore) async {
        guard !amountText.isEmpty,
              let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            errorMessage = String(localized: "transactionForm.enterPositiveAmount")
            showingError = true
            HapticManager.warning()
            return
        }

        let dateFormatter = DateFormatters.dateFormatter
        let transactionDate = dateFormatter.string(from: date)
        let finalDescription = descriptionText.isEmpty
            ? (selectedAction == .income ? String(localized: "transactionForm.accountTopUp") : "")
            : descriptionText

        if selectedAction == .income {
            await saveIncomeTransaction(
                amount: amount,
                transactionDate: transactionDate,
                finalDescription: finalDescription,
                transactionStore: transactionStore
            )
        } else {
            await saveTransfer(
                amount: amount,
                transactionDate: transactionDate,
                finalDescription: finalDescription,
                transactionStore: transactionStore
            )
        }
    }

    // MARK: - Private Save Helpers

    private func saveIncomeTransaction(
        amount: Double,
        transactionDate: String,
        finalDescription: String,
        transactionStore: TransactionStore
    ) async {
        guard let category = selectedCategory, !incomeCategories.isEmpty else {
            errorMessage = String(localized: "transactionForm.selectCategoryIncome")
            showingError = true
            HapticManager.warning()
            return
        }

        var convertedAmount: Double? = nil
        if selectedCurrency != account.currency {
            guard let converted = await CurrencyConverter.convert(
                amount: amount,
                from: selectedCurrency,
                to: account.currency
            ) else {
                errorMessage = String(localized: "currency.error.conversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
            convertedAmount = converted
        }

        let transaction = Transaction(
            id: "",
            date: transactionDate,
            description: finalDescription,
            amount: amount,
            currency: selectedCurrency,
            convertedAmount: convertedAmount,
            type: .income,
            category: category,
            subcategory: nil,
            accountId: account.id,
            targetAccountId: nil
        )

        do {
            _ = try await transactionStore.add(transaction)
            HapticManager.success()
            shouldDismiss = true
        } catch {
            logger.error("Failed to save income transaction: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
            HapticManager.error()
        }
    }

    private func saveTransfer(
        amount: Double,
        transactionDate: String,
        finalDescription: String,
        transactionStore: TransactionStore
    ) async {
        guard let targetAccountId = selectedTargetAccountId else {
            errorMessage = headerForAccountSelection
            showingError = true
            HapticManager.warning()
            return
        }

        guard targetAccountId != account.id else {
            errorMessage = String(localized: "transactionForm.cannotTransferToSame")
            showingError = true
            HapticManager.warning()
            return
        }

        guard accountsViewModel.accounts.contains(where: { $0.id == targetAccountId }) else {
            errorMessage = String(localized: "transactionForm.accountNotFound")
            showingError = true
            HapticManager.error()
            return
        }

        // Определяем направление для депозитов
        let (sourceId, targetId): (String, String)
        if account.isDeposit, let direction = transferDirection {
            switch direction {
            case .toDeposit:
                sourceId = targetAccountId
                targetId = account.id
            case .fromDeposit:
                sourceId = account.id
                targetId = targetAccountId
            }
        } else {
            sourceId = account.id
            targetId = targetAccountId
        }

        // Загрузка курсов и конвертация
        let sourceCurrency = resolveCurrency(for: sourceId)
        if selectedCurrency != sourceCurrency {
            guard await CurrencyConverter.convert(amount: amount, from: selectedCurrency, to: sourceCurrency) != nil else {
                errorMessage = String(localized: "currency.error.conversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

        let targetAccount = accountsViewModel.accounts.first(where: { $0.id == targetId })
        let targetCurrency = targetAccount?.currency ?? selectedCurrency

        // Предзагрузка всех нужных курсов
        let currenciesToLoad = Set([selectedCurrency, account.currency, targetCurrency])
        for currency in currenciesToLoad where currency != "KZT" {
            if await CurrencyConverter.getExchangeRate(for: currency) == nil {
                errorMessage = String(localized: "currency.error.ratesUnavailable")
                showingError = true
                HapticManager.error()
                return
            }
        }

        // Вычисляем targetAmount
        var precomputedTargetAmount: Double?
        if selectedCurrency != targetCurrency {
            guard let converted = await CurrencyConverter.convert(amount: amount, from: selectedCurrency, to: targetCurrency) else {
                errorMessage = String(localized: "currency.error.targetConversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
            precomputedTargetAmount = converted
        } else {
            precomputedTargetAmount = amount
        }

        do {
            try await transactionStore.transfer(
                from: sourceId,
                to: targetId,
                amount: amount,
                currency: selectedCurrency,
                targetAmount: precomputedTargetAmount,
                targetCurrency: targetCurrency,
                date: transactionDate,
                description: finalDescription
            )
            HapticManager.success()
            shouldDismiss = true
        } catch {
            logger.error("Failed to save transfer: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
            HapticManager.error()
        }
    }

    private func resolveCurrency(for accountId: String) -> String {
        if account.isDeposit, let direction = transferDirection {
            if direction == .fromDeposit { return account.currency }
            return accountsViewModel.accounts.first(where: { $0.id == accountId })?.currency ?? account.currency
        }
        return accountsViewModel.accounts.first(where: { $0.id == accountId })?.currency ?? account.currency
    }
}
```

**Step 2: Собрать проект, убедиться `Build succeeded`**

**Step 3: Commit**

```bash
git add AIFinanceManager/ViewModels/AccountActionViewModel.swift
git commit -m "feat(accounts): add AccountActionViewModel with extracted save/transfer business logic"
```

---

### Task 11: AccountActionView — подключить AccountActionViewModel

**Files:**
- Modify: `AIFinanceManager/Views/Accounts/AccountActionView.swift`

**Контекст:** Заменить 14 @State-свойств состояния на единый `@State private var viewModel: AccountActionViewModel`. Метод `saveTransaction` удаляется из View — делегируется в VM. Исправляется pattern вложенного `Task {} внутри await MainActor.run {}`.

**Step 1: Добавить `@State private var viewModel: AccountActionViewModel` и убрать отдельные @State**

```swift
// УДАЛИТЬ эти @State:
// @State private var selectedAction: ActionType = .transfer
// @State private var amountText: String = ""
// @State private var selectedCurrency: String
// @State private var descriptionText: String = ""
// @State private var selectedCategory: String? = nil
// @State private var selectedTargetAccountId: String? = nil
// @State private var showingError = false
// @State private var errorMessage = ""

// ДОБАВИТЬ:
@State private var viewModel: AccountActionViewModel
```

**Step 2: Обновить `init`**

```swift
init(
    transactionsViewModel: TransactionsViewModel,
    accountsViewModel: AccountsViewModel,
    account: Account,
    namespace: Namespace.ID,
    transferDirection: DepositTransferDirection? = nil,
    categoriesViewModel: CategoriesViewModel
) {
    self.transactionsViewModel = transactionsViewModel
    self.accountsViewModel = accountsViewModel
    self.account = account
    self.namespace = namespace
    self.transferDirection = transferDirection
    self.categoriesViewModel = categoriesViewModel
    _viewModel = State(initialValue: AccountActionViewModel(
        account: account,
        accountsViewModel: accountsViewModel,
        transactionsViewModel: transactionsViewModel,
        transferDirection: transferDirection
    ))
}
```

**Step 3: Обновить body — заменить прямые @State на viewModel.***

```swift
// Было: $selectedAction → $viewModel.selectedAction
// Было: $amountText → $viewModel.amountText
// Было: $selectedCurrency → $viewModel.selectedCurrency
// Было: $selectedTargetAccountId → $viewModel.selectedTargetAccountId
// Было: $selectedCategory → $viewModel.selectedCategory
// Было: $descriptionText → $viewModel.descriptionText
// Было: showingError → viewModel.showingError
// Было: errorMessage → viewModel.errorMessage
// Было: navigationTitleText → viewModel.navigationTitleText
// Было: availableAccounts → viewModel.availableAccounts
// Было: incomeCategories → viewModel.incomeCategories
```

**Step 4: Заменить `saveTransaction` вызов**

```swift
// БЫЛО: .dateButtonsSafeArea(selectedDate: $selectedDate, onSave: { date in saveTransaction(date: date) })
// СТАЛО:
.dateButtonsSafeArea(selectedDate: $viewModel.selectedDate, onSave: { date in
    Task { await viewModel.saveTransaction(date: date, transactionStore: transactionStore) }
})
```

> Добавить `@State private var selectedDate: Date = Date()` → переместить в `AccountActionViewModel` (уже есть в VM выше). Если нет в VM — добавить.

**Step 5: Добавить `onChange` для автоматического dismiss при успехе**

```swift
.onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
    if shouldDismiss { dismiss() }
}
```

**Step 6: Удалить старый `saveTransaction(date:)` метод из AccountActionView и enum `ActionType`**

Enum `ActionType` теперь определён в `AccountActionViewModel`. Удалить дублирующий `enum ActionType` из `AccountActionView`.

**Step 7: Обновить alert**

```swift
.alert(String(localized: "common.error"), isPresented: $viewModel.showingError) {
    Button(String(localized: "voice.ok"), role: .cancel) {}
} message: {
    Text(viewModel.errorMessage)
}
```

**Step 8: Собрать проект, убедиться `Build succeeded`**

**Step 9: Commit**

```bash
git add AIFinanceManager/Views/Accounts/AccountActionView.swift \
        AIFinanceManager/ViewModels/AccountActionViewModel.swift
git commit -m "refactor(accounts): extract saveTransaction logic from AccountActionView into AccountActionViewModel"
```

---

## Итог изменений по файлам

| Файл | Тип изменения | Задача |
|------|--------------|--------|
| `ViewModels/AccountsViewModel.swift` | Удаление мёртвого кода | T1 |
| `Views/Accounts/Components/AccountsCarousel.swift` | 1-строчный fix | T2 |
| `Views/Accounts/Components/AccountRow.swift` | 3 fix | T3 |
| `Views/Accounts/AccountsManagementView.swift` | 4 fix | T5, T6 |
| `Views/Accounts/AccountEditView.swift` | 2 fix | T4 |
| `ViewModels/TransactionStore.swift` | Новый метод | T6 |
| `Views/Accounts/AccountActionView.swift` | Major refactor | T7–T11 |
| `ViewModels/AccountActionViewModel.swift` | New file | T10, T11 |
| `en.lproj/Localizable.strings` | +6 ключей | T3, T8 |
| `ru.lproj/Localizable.strings` | +6 ключей | T3, T8 |

**Итого: 11 задач, 10 коммитов, ~22 исправления аудита**
