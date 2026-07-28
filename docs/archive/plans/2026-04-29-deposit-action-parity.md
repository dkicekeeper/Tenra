# Deposit Action Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the deposit's `Top-up / Withdrawal` direction picker with the same `Перевод / Пополнение` picker used by regular accounts. `Top-up` creates a categorised `.income` transaction; deposit balance reconcile is extended so `.income/.expense` events on a deposit affect `principalBalance`.

**Architecture:** Reuse the already-shared `AccountActionView` / `AccountActionViewModel`. Drop the deposit-specific `transferDirection` parameter and all `if account.isDeposit` branches. Extend `DepositInterestService` so `.income/.expense` count toward principal, and recompute `principalBalance` unconditionally so same-day events show up immediately. Gate the incremental balance engine so it does not double-count `.income/.expense` on a deposit.

**Tech Stack:** Swift 6 (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), SwiftUI, Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), CoreData. Spec: [docs/superpowers/specs/2026-04-29-deposit-action-parity-design.md](../specs/2026-04-29-deposit-action-parity-design.md).

**Build verification command (used in many tasks):**
```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

**Test verification command (used in many tasks):**
```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests 2>&1 | tail -40
```

---

## File Map

**Modified:**
- `Tenra/Models/Transaction.swift` — add `TransactionType.affectsDepositPrincipal`.
- `Tenra/Services/Deposits/DepositInterestService.swift` — extend `principalDelta`; replace inline filters with `affectsDepositPrincipal`; hoist `principalBalance` recompute out of the `lastCalcDate >= today` early-exit; use `convertedAmount` when present.
- `Tenra/Services/Balance/BalanceCalculationEngine.swift` — gate `.income/.expense` for deposits in `applyTransaction` and `revertTransaction`.
- `Tenra/ViewModels/AccountActionViewModel.swift` — drop `transferDirection` + deposit branches; add `defaultAction: ActionType?` init parameter.
- `Tenra/Views/Accounts/AccountActionView.swift` — drop `transferDirection` parameter and the deposit branch in the segmented picker.
- `Tenra/Views/Deposits/DepositDetailView.swift` — delete `DepositTransferDirection` enum, drop secondary action, switch sheet to `isPresented`, change reconcile `.task {}` to `.task(id: refreshTrigger)`.

**Tests:**
- `TenraTests/Services/DepositInterestServiceTests.swift` — extend with cases for `.income/.expense/affectsDepositPrincipal/same-day reconcile/convertedAmount`.
- `TenraTests/Services/BalanceCalculationEngineTests.swift` — **new** file covering the deposit gate.
- `TenraTests/ViewModels/AccountActionViewModelTests.swift` — **new** file covering `defaultAction` and deposit `.income` save.

---

## Task 1: `TransactionType.affectsDepositPrincipal`

**Files:**
- Modify: `Tenra/Models/Transaction.swift` (extend the enum at line 10)
- Test: `TenraTests/Services/DepositInterestServiceTests.swift` (add a new `@Suite` block at the bottom)

- [ ] **Step 1: Write the failing test**

Append to `TenraTests/Services/DepositInterestServiceTests.swift` (after the closing `}` of `struct DepositInterestServiceTests`):

```swift
@Suite("TransactionType.affectsDepositPrincipal")
struct TransactionTypeDepositPrincipalTests {

    @Test("deposit-principal types return true")
    func depositPrincipalTypesReturnTrue() {
        #expect(TransactionType.depositTopUp.affectsDepositPrincipal)
        #expect(TransactionType.depositWithdrawal.affectsDepositPrincipal)
        #expect(TransactionType.depositInterestAccrual.affectsDepositPrincipal)
    }

    @Test("income and expense return true")
    func incomeAndExpenseReturnTrue() {
        #expect(TransactionType.income.affectsDepositPrincipal)
        #expect(TransactionType.expense.affectsDepositPrincipal)
    }

    @Test("transfers and loan types return false")
    func transfersAndLoanReturnFalse() {
        #expect(!TransactionType.internalTransfer.affectsDepositPrincipal)
        #expect(!TransactionType.loanPayment.affectsDepositPrincipal)
        #expect(!TransactionType.loanEarlyRepayment.affectsDepositPrincipal)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/TransactionTypeDepositPrincipalTests 2>&1 | tail -20
```

Expected: BUILD FAILED with `value of type 'TransactionType' has no member 'affectsDepositPrincipal'`.

- [ ] **Step 3: Implement `affectsDepositPrincipal`**

Edit `Tenra/Models/Transaction.swift`. Locate the closing `}` of the `TransactionType` enum at the line containing `nonisolated static let loanPaymentCategoryName = "Loan Payment"` (currently line 24). After that line and before the enum's closing `}`, add:

```swift

    /// `true` for transaction types that move a deposit's `principalBalance`
    /// when the transaction lives on a deposit account. `.income/.expense` are
    /// included so the new "Top-up from income category" flow on deposits is
    /// reflected in the deposit's principal walk.
    nonisolated var affectsDepositPrincipal: Bool {
        switch self {
        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual,
             .income, .expense:
            return true
        case .internalTransfer, .loanPayment, .loanEarlyRepayment:
            return false
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/TransactionTypeDepositPrincipalTests 2>&1 | tail -20
```

Expected: `Test Suite 'TransactionTypeDepositPrincipalTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Models/Transaction.swift TenraTests/Services/DepositInterestServiceTests.swift
git commit -m "feat(deposit): add TransactionType.affectsDepositPrincipal"
```

---

## Task 2: Extend `principalDelta` for `.income / .expense`

**Files:**
- Modify: `Tenra/Services/Deposits/DepositInterestService.swift:120-132`
- Test: `TenraTests/Services/DepositInterestServiceTests.swift` (extend)

- [ ] **Step 1: Write the failing test**

Append a new test to the existing `DepositInterestServiceTests` suite (inside the `struct DepositInterestServiceTests { ... }` block, just before the closing `}`):

```swift
    // MARK: - principalDelta tests (Task 2)

    @Test("principalDelta: income adds amount")
    func principalDelta_income_addsAmount() {
        let tx = Transaction(
            id: "t1", date: dateString(offsetDays: -1), description: "",
            amount: 1_000, currency: "KZT", convertedAmount: nil,
            type: .income, category: "Salary", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )
        let delta = DepositInterestService.principalDelta(for: tx, capitalizationEnabled: true)
        #expect(delta == Decimal(1_000))
    }

    @Test("principalDelta: expense subtracts amount")
    func principalDelta_expense_subtractsAmount() {
        let tx = Transaction(
            id: "t2", date: dateString(offsetDays: -1), description: "",
            amount: 500, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Other", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )
        let delta = DepositInterestService.principalDelta(for: tx, capitalizationEnabled: true)
        #expect(delta == Decimal(-500))
    }

    @Test("principalDelta: income prefers convertedAmount when present")
    func principalDelta_income_usesConvertedAmount() {
        // Source amount is in USD; convertedAmount is the value already in deposit currency.
        let tx = Transaction(
            id: "t3", date: dateString(offsetDays: -1), description: "",
            amount: 100, currency: "USD", convertedAmount: 47_000,
            type: .income, category: "Salary", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )
        let delta = DepositInterestService.principalDelta(for: tx, capitalizationEnabled: true)
        #expect(delta == Decimal(47_000))
    }

    @Test("principalDelta: expense prefers convertedAmount when present")
    func principalDelta_expense_usesConvertedAmount() {
        let tx = Transaction(
            id: "t4", date: dateString(offsetDays: -1), description: "",
            amount: 100, currency: "USD", convertedAmount: 47_000,
            type: .expense, category: "Other", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )
        let delta = DepositInterestService.principalDelta(for: tx, capitalizationEnabled: true)
        #expect(delta == Decimal(-47_000))
    }
```

`principalDelta` is currently `private`. To call it from the test we expose it as `internal`. (No production callers outside the file currently.)

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/DepositInterestServiceTests 2>&1 | tail -30
```

Expected: BUILD FAILED with `'principalDelta' is inaccessible due to 'private' protection level` and / or test failures for `.income`/`.expense` cases (returns `0`).

- [ ] **Step 3: Make `principalDelta` internal and add `.income / .expense` cases**

Edit `Tenra/Services/Deposits/DepositInterestService.swift`. Replace the existing `principalDelta` (currently lines 119-132) with:

```swift
    /// Signed amount by which the given deposit-related transaction moves the running principal.
    /// Uses `convertedAmount` when present (already in deposit currency) and falls back to
    /// `amount`. Internal so unit tests can drive it directly.
    static func principalDelta(for tx: Transaction, capitalizationEnabled: Bool) -> Decimal {
        let raw = tx.convertedAmount ?? tx.amount
        let amt = Decimal(raw)
        switch tx.type {
        case .depositTopUp, .income:
            return amt
        case .depositWithdrawal, .expense:
            return -amt
        case .depositInterestAccrual:
            return capitalizationEnabled ? amt : 0
        default:
            return 0
        }
    }
```

Note the access change: `private static` → `static` (internal default). The existing call sites inside the same file remain unchanged.

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/DepositInterestServiceTests 2>&1 | tail -30
```

Expected: all tests pass (existing tests + the four new `principalDelta` tests).

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Deposits/DepositInterestService.swift TenraTests/Services/DepositInterestServiceTests.swift
git commit -m "feat(deposit): principalDelta handles .income/.expense with convertedAmount"
```

---

## Task 3: Update reconcile filter and hoist principal recompute

**Files:**
- Modify: `Tenra/Services/Deposits/DepositInterestService.swift` (function `reconcileDepositInterest`, currently lines 16-117)
- Test: `TenraTests/Services/DepositInterestServiceTests.swift` (extend)

- [ ] **Step 1: Write the failing tests**

Append to the `DepositInterestServiceTests` suite (inside the struct):

```swift
    // MARK: - reconcileDepositInterest tests (Task 3)

    /// Constructs a deposit-bearing Account for tests.
    private func makeDepositAccount(
        id: String = "d1",
        currency: String = "KZT",
        depositInfo: DepositInfo
    ) -> Account {
        Account(
            id: id,
            name: "Deposit",
            currency: currency,
            iconSource: nil,
            depositInfo: depositInfo,
            initialBalance: NSDecimalNumber(decimal: depositInfo.initialPrincipal).doubleValue
        )
    }

    private func makeIncomeTx(
        id: String = "i1",
        amount: Double,
        currency: String = "KZT",
        convertedAmount: Double? = nil,
        date: String,
        accountId: String = "d1"
    ) -> Transaction {
        Transaction(
            id: id, date: date, description: "Salary",
            amount: amount, currency: currency, convertedAmount: convertedAmount,
            type: .income, category: "Salary", subcategory: nil,
            accountId: accountId, targetAccountId: nil
        )
    }

    @Test("reconcile counts .income on deposit toward principal")
    func reconcile_incomeAddsToPrincipal() {
        // Deposit started 5 days ago at 100k, last reconciled yesterday.
        var info = makeDepositInfo(
            principal: 100_000,
            annualRate: 0,            // disable interest accrual to isolate principal math
            lastCalcDateOffset: -1,
            accruedForPeriod: 0
        )
        info.initialPrincipal = 100_000
        info.startDate = dateString(offsetDays: -5)

        var account = makeDepositAccount(depositInfo: info)
        // .income for 25k three days ago — must move principal to 125k.
        let income = makeIncomeTx(amount: 25_000, date: dateString(offsetDays: -3))

        DepositInterestService.reconcileDepositInterest(
            account: &account,
            allTransactions: [income],
            onTransactionCreated: { _ in }
        )

        #expect(account.depositInfo?.principalBalance == Decimal(125_000))
    }

    @Test("reconcile counts .expense on deposit subtractively")
    func reconcile_expenseSubtractsFromPrincipal() {
        var info = makeDepositInfo(principal: 100_000, annualRate: 0, lastCalcDateOffset: -1)
        info.initialPrincipal = 100_000
        info.startDate = dateString(offsetDays: -5)

        var account = makeDepositAccount(depositInfo: info)
        let expense = Transaction(
            id: "e1", date: dateString(offsetDays: -3), description: "",
            amount: 10_000, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Other", subcategory: nil,
            accountId: "d1", targetAccountId: nil
        )

        DepositInterestService.reconcileDepositInterest(
            account: &account,
            allTransactions: [expense],
            onTransactionCreated: { _ in }
        )

        #expect(account.depositInfo?.principalBalance == Decimal(90_000))
    }

    @Test("reconcile uses convertedAmount when income currency differs")
    func reconcile_incomeUsesConvertedAmount() {
        var info = makeDepositInfo(principal: 100_000, annualRate: 0, lastCalcDateOffset: -1)
        info.initialPrincipal = 100_000
        info.startDate = dateString(offsetDays: -5)

        var account = makeDepositAccount(depositInfo: info, currency: "KZT") // deposit is KZT
        // Source: USD 100; converted to deposit currency = 47k KZT.
        let income = makeIncomeTx(
            amount: 100, currency: "USD", convertedAmount: 47_000,
            date: dateString(offsetDays: -2)
        )

        DepositInterestService.reconcileDepositInterest(
            account: &account,
            allTransactions: [income],
            onTransactionCreated: { _ in }
        )

        #expect(account.depositInfo?.principalBalance == Decimal(147_000))
    }

    @Test("reconcile recomputes principalBalance even when already reconciled today")
    func reconcile_sameDayPrincipalRecompute() {
        // First pass: reconcile yesterday — sets lastCalcDate to today.
        var info = makeDepositInfo(principal: 100_000, annualRate: 0, lastCalcDateOffset: -1)
        info.initialPrincipal = 100_000
        info.startDate = dateString(offsetDays: -5)

        var account = makeDepositAccount(depositInfo: info)
        DepositInterestService.reconcileDepositInterest(
            account: &account, allTransactions: [], onTransactionCreated: { _ in }
        )
        // After first pass: principal == 100k, lastCalcDate == today.
        #expect(account.depositInfo?.principalBalance == Decimal(100_000))

        // Now user adds a same-day income transaction. Re-reconcile.
        let todayIncome = makeIncomeTx(amount: 30_000, date: dateString(offsetDays: 0))
        DepositInterestService.reconcileDepositInterest(
            account: &account,
            allTransactions: [todayIncome],
            onTransactionCreated: { _ in }
        )
        #expect(account.depositInfo?.principalBalance == Decimal(130_000))
    }

    @Test("reconcile ignores .internalTransfer (filtered out by affectsDepositPrincipal)")
    func reconcile_ignoresInternalTransfer() {
        var info = makeDepositInfo(principal: 100_000, annualRate: 0, lastCalcDateOffset: -1)
        info.initialPrincipal = 100_000
        info.startDate = dateString(offsetDays: -5)

        var account = makeDepositAccount(depositInfo: info)
        let transfer = Transaction(
            id: "t1", date: dateString(offsetDays: -2), description: "",
            amount: 50_000, currency: "KZT", convertedAmount: nil,
            type: .internalTransfer, category: TransactionType.transferCategoryName,
            subcategory: nil, accountId: "other", targetAccountId: "d1"
        )

        DepositInterestService.reconcileDepositInterest(
            account: &account,
            allTransactions: [transfer],
            onTransactionCreated: { _ in }
        )
        // Principal unchanged because .internalTransfer is not in affectsDepositPrincipal.
        #expect(account.depositInfo?.principalBalance == Decimal(100_000))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/DepositInterestServiceTests 2>&1 | tail -40
```

Expected: the new `reconcile_*` tests fail. The `.income/.expense` ones fail because the reconcile filter currently excludes them. The same-day test fails because of the `lastCalcDate >= today` early-exit.

- [ ] **Step 3: Refactor `reconcileDepositInterest`**

Edit `Tenra/Services/Deposits/DepositInterestService.swift`. Replace the entire body of `reconcileDepositInterest` (currently lines 16-117) with the version below. The two semantic changes:

1. The events filter uses `tx.type.affectsDepositPrincipal` instead of the inline OR list.
2. Principal recomputation is hoisted out of the early-exit so today's events show in `principalBalance`.

```swift
    /// Рассчитывает проценты за период и обновляет информацию депозита.
    /// Идемпотентный: можно вызывать многократно без дублирования транзакций.
    ///
    /// `principalBalance` is recomputed on every call so same-day events
    /// (e.g. a Top-up made today after this morning's reconcile) are reflected
    /// immediately. The day-by-day interest accrual loop only runs when there
    /// are new days to walk.
    static func reconcileDepositInterest(
        account: inout Account,
        allTransactions: [Transaction],
        onTransactionCreated: (Transaction) -> Void
    ) {
        guard var depositInfo = account.depositInfo else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let lastCalcDate = DateFormatters.dateFormatter.date(from: depositInfo.lastInterestCalculationDate) else {
            return
        }
        let lastCalcDateNormalized = calendar.startOfDay(for: lastCalcDate)

        // Principal events that change the historical principal over time.
        // Events dated on or before `startDate` are baked into `initialPrincipal`.
        let events = allTransactions
            .filter { tx in
                tx.accountId == account.id &&
                tx.type.affectsDepositPrincipal &&
                tx.date > depositInfo.startDate
            }
            .sorted { $0.date < $1.date }

        if lastCalcDateNormalized < today {
            // Day-by-day interest accrual walk — only runs when there are new days.
            let walkStart = calendar.date(byAdding: .day, value: 1, to: lastCalcDateNormalized)!
            let walkStartStr = DateFormatters.dateFormatter.string(from: walkStart)

            var runningPrincipal: Decimal = depositInfo.initialPrincipal
            var eventIdx = 0
            while eventIdx < events.count && events[eventIdx].date < walkStartStr {
                runningPrincipal += principalDelta(for: events[eventIdx], capitalizationEnabled: depositInfo.capitalizationEnabled)
                eventIdx += 1
            }

            var currentDate = walkStart
            var totalAccrued: Decimal = depositInfo.interestAccruedForCurrentPeriod

            while currentDate < today {
                let currentDateStr = DateFormatters.dateFormatter.string(from: currentDate)

                while eventIdx < events.count && events[eventIdx].date <= currentDateStr {
                    runningPrincipal += principalDelta(for: events[eventIdx], capitalizationEnabled: depositInfo.capitalizationEnabled)
                    eventIdx += 1
                }

                let rate = rateForDate(date: currentDate, history: depositInfo.interestRateHistory)
                let dailyInterest = runningPrincipal * (rate / 100) / 365
                totalAccrued += dailyInterest

                if shouldPostInterest(
                    date: currentDate,
                    postingDay: depositInfo.interestPostingDay,
                    lastPostingMonth: depositInfo.lastInterestPostingMonth
                ) {
                    let postingAmount = totalAccrued
                    if postingAmount > 0 {
                        let posted = postInterest(
                            account: &account,
                            depositInfo: &depositInfo,
                            amount: postingAmount,
                            date: currentDate,
                            allTransactions: allTransactions,
                            onTransactionCreated: onTransactionCreated
                        )
                        if posted, depositInfo.capitalizationEnabled {
                            runningPrincipal += postingAmount
                        }
                        totalAccrued = 0
                    }
                }

                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }

            depositInfo.interestAccruedForCurrentPeriod = totalAccrued
            depositInfo.lastInterestCalculationDate = DateFormatters.dateFormatter.string(from: today)
        }

        // ALWAYS recompute principalBalance from `initialPrincipal` walking every event
        // up to and including today. This makes same-day events show in the displayed
        // balance immediately, regardless of whether the day-by-day walk ran above.
        let todayStr = DateFormatters.dateFormatter.string(from: today)
        var principal: Decimal = depositInfo.initialPrincipal
        for tx in events where tx.date <= todayStr {
            principal += principalDelta(for: tx, capitalizationEnabled: depositInfo.capitalizationEnabled)
        }
        depositInfo.principalBalance = principal

        account.depositInfo = depositInfo
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/DepositInterestServiceTests 2>&1 | tail -40
```

Expected: all tests pass — both the new `reconcile_*` tests and the existing tests in this suite.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Deposits/DepositInterestService.swift TenraTests/Services/DepositInterestServiceTests.swift
git commit -m "feat(deposit): reconcile counts .income/.expense and recomputes principal unconditionally"
```

---

## Task 4: Update `calculateInterestToToday(depositInfo:accountId:allTransactions:)` filter

**Files:**
- Modify: `Tenra/Services/Deposits/DepositInterestService.swift:184-232` (the historical-accurate overload of `calculateInterestToToday`)
- Test: `TenraTests/Services/DepositInterestServiceTests.swift` (extend)

- [ ] **Step 1: Write the failing test**

Append to the `DepositInterestServiceTests` suite:

```swift
    // MARK: - calculateInterestToToday(allTransactions:) tests (Task 4)

    @Test("calculateInterestToToday(allTransactions:) accrues on principal grown by .income")
    func calculateInterestToToday_walksIncome() {
        // Deposit at 100k, 12% APR, .income of 100k applied 3 days ago doubles the
        // running principal from that day. Validate that the historical walk picks
        // up the .income event.
        var info = makeDepositInfo(
            principal: 100_000,
            annualRate: 12,
            lastCalcDateOffset: -5,
            accruedForPeriod: 0
        )
        info.initialPrincipal = 100_000
        info.startDate = dateString(offsetDays: -10)

        let income = makeIncomeTx(
            id: "i1", amount: 100_000,
            date: dateString(offsetDays: -3),
            accountId: "d1"
        )

        let walked = DepositInterestService.calculateInterestToToday(
            depositInfo: info, accountId: "d1", allTransactions: [income]
        )
        let baseline = DepositInterestService.calculateInterestToToday(
            depositInfo: info, accountId: "d1", allTransactions: []
        )

        // Walked variant must accrue strictly more because principal doubled mid-period.
        #expect(walked > baseline)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/DepositInterestServiceTests/calculateInterestToToday_walksIncome 2>&1 | tail -20
```

Expected: FAIL — `walked == baseline` because the filter currently excludes `.income`.

- [ ] **Step 3: Update the filter**

Edit `Tenra/Services/Deposits/DepositInterestService.swift`. In the function `calculateInterestToToday(depositInfo:accountId:allTransactions:)` (currently around lines 184-232), find the events filter:

```swift
            .filter { tx in
                tx.accountId == accountId &&
                (tx.type == .depositTopUp || tx.type == .depositWithdrawal || tx.type == .depositInterestAccrual) &&
                tx.date > depositInfo.startDate
            }
```

Replace with:

```swift
            .filter { tx in
                tx.accountId == accountId &&
                tx.type.affectsDepositPrincipal &&
                tx.date > depositInfo.startDate
            }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/DepositInterestServiceTests 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Deposits/DepositInterestService.swift TenraTests/Services/DepositInterestServiceTests.swift
git commit -m "feat(deposit): calculateInterestToToday(allTransactions:) walks .income/.expense"
```

---

## Task 5: Gate `.income / .expense` for deposits in `BalanceCalculationEngine`

**Files:**
- Modify: `Tenra/Services/Balance/BalanceCalculationEngine.swift` (functions `applyTransaction` lines 153-182 and `revertTransaction` lines 191-224)
- Test: `TenraTests/Services/BalanceCalculationEngineTests.swift` (**new**)

Background: The engine is called from `BalanceCoordinator` via `engine.applyTransaction(_:to:for:)` and `engine.revertTransaction(_:from:for:)`. For deposits the displayed balance comes from `calculateDepositBalance(depositInfo:)` which reads `principalBalance`. If the incremental path also adds `.income` to the cached balance, the same event is counted twice — once incrementally and once via reconcile. Gate the deposit branch.

`calculateDelta` is dead public API (no production or test callers — see spec D6 note); we leave it alone.

- [ ] **Step 1: Create the test file with failing tests**

Create `TenraTests/Services/BalanceCalculationEngineTests.swift`:

```swift
//
//  BalanceCalculationEngineTests.swift
//  TenraTests
//
//  Unit tests for BalanceCalculationEngine deposit gating.
//

import Testing
import Foundation
@testable import Tenra

@Suite("BalanceCalculationEngine deposit gating")
struct BalanceCalculationEngineTests {

    private let engine = BalanceCalculationEngine()

    private func depositAccountBalance(
        id: String = "d1",
        currency: String = "KZT",
        currentBalance: Double = 100_000
    ) -> AccountBalance {
        AccountBalance(
            accountId: id,
            currentBalance: currentBalance,
            initialBalance: currentBalance,
            depositInfo: DepositInfo(
                bankName: "T",
                principalBalance: Decimal(currentBalance),
                capitalizationEnabled: false,
                interestAccruedNotCapitalized: 0,
                interestRateAnnual: 0,
                interestRateHistory: [RateChange(effectiveFrom: "2020-01-01", annualRate: 0)],
                interestPostingDay: 1,
                lastInterestCalculationDate: "2020-01-01",
                lastInterestPostingMonth: "2020-01-01",
                interestAccruedForCurrentPeriod: 0,
                initialPrincipal: Decimal(currentBalance),
                startDate: "2020-01-01"
            ),
            currency: currency,
            isDeposit: true
        )
    }

    private func nonDepositAccountBalance(
        id: String = "a1",
        currency: String = "KZT",
        currentBalance: Double = 100_000
    ) -> AccountBalance {
        AccountBalance(
            accountId: id,
            currentBalance: currentBalance,
            initialBalance: currentBalance,
            currency: currency,
            isDeposit: false
        )
    }

    private func incomeTx(amount: Double, accountId: String) -> Transaction {
        Transaction(
            id: "i", date: "2026-01-01", description: "",
            amount: amount, currency: "KZT", convertedAmount: nil,
            type: .income, category: "Salary", subcategory: nil,
            accountId: accountId, targetAccountId: nil
        )
    }

    @Test("applyTransaction: .income on deposit is a no-op")
    func applyIncome_onDeposit_noop() {
        let acct = depositAccountBalance(currentBalance: 100_000)
        let tx = incomeTx(amount: 25_000, accountId: acct.accountId)
        let new = engine.applyTransaction(tx, to: acct.currentBalance, for: acct)
        #expect(new == 100_000)
    }

    @Test("applyTransaction: .income on regular account adds amount")
    func applyIncome_onRegular_adds() {
        let acct = nonDepositAccountBalance(currentBalance: 100_000)
        let tx = incomeTx(amount: 25_000, accountId: acct.accountId)
        let new = engine.applyTransaction(tx, to: acct.currentBalance, for: acct)
        #expect(new == 125_000)
    }

    @Test("applyTransaction: .expense on deposit is a no-op")
    func applyExpense_onDeposit_noop() {
        let acct = depositAccountBalance(currentBalance: 100_000)
        let tx = Transaction(
            id: "e", date: "2026-01-01", description: "",
            amount: 10_000, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Other", subcategory: nil,
            accountId: acct.accountId, targetAccountId: nil
        )
        let new = engine.applyTransaction(tx, to: acct.currentBalance, for: acct)
        #expect(new == 100_000)
    }

    @Test("revertTransaction: .income on deposit is a no-op")
    func revertIncome_onDeposit_noop() {
        let acct = depositAccountBalance(currentBalance: 100_000)
        let tx = incomeTx(amount: 25_000, accountId: acct.accountId)
        let new = engine.revertTransaction(tx, from: acct.currentBalance, for: acct)
        #expect(new == 100_000)
    }

    @Test("revertTransaction: .income on regular account subtracts amount")
    func revertIncome_onRegular_subtracts() {
        let acct = nonDepositAccountBalance(currentBalance: 125_000)
        let tx = incomeTx(amount: 25_000, accountId: acct.accountId)
        let new = engine.revertTransaction(tx, from: acct.currentBalance, for: acct)
        #expect(new == 100_000)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/BalanceCalculationEngineTests 2>&1 | tail -40
```

Expected: the deposit-noop tests fail (currently `.income` adds 25k to a deposit's currentBalance even though balance is supposed to come from principal).

- [ ] **Step 3: Gate `.income / .expense` for deposits in `applyTransaction`**

Edit `Tenra/Services/Balance/BalanceCalculationEngine.swift`. Replace the `applyTransaction` body (currently lines 153-182). Gate `.income` and `.expense` on `!account.isDeposit`:

```swift
    func applyTransaction(
        _ transaction: Transaction,
        to currentBalance: Double,
        for account: AccountBalance,
        isSource: Bool = true
    ) -> Double {
        switch transaction.type {
        case .income:
            // For deposits, balance is sourced from `principalBalance` (kept fresh by
            // `DepositInterestService.reconcileDepositInterest`). Skipping incremental
            // updates here prevents double-counting.
            if account.isDeposit { return currentBalance }
            return currentBalance + getTransactionAmount(transaction, for: account.currency)

        case .expense:
            if account.isDeposit { return currentBalance }
            return currentBalance - getTransactionAmount(transaction, for: account.currency)

        case .internalTransfer:
            if isSource {
                return currentBalance - getSourceAmount(transaction)
            } else {
                return currentBalance + getTargetAmount(transaction)
            }

        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            return currentBalance

        case .loanPayment, .loanEarlyRepayment:
            if transaction.accountId == account.id || transaction.targetAccountId == account.id {
                return currentBalance - getTransactionAmount(transaction, for: account.currency)
            }
            return currentBalance
        }
    }
```

- [ ] **Step 4: Gate `.income / .expense` for deposits in `revertTransaction`**

In the same file, replace the `revertTransaction` body (currently lines 191-224):

```swift
    func revertTransaction(
        _ transaction: Transaction,
        from currentBalance: Double,
        for account: AccountBalance,
        isSource: Bool = true
    ) -> Double {
        switch transaction.type {
        case .income:
            if account.isDeposit { return currentBalance }
            return currentBalance - getTransactionAmount(transaction, for: account.currency)

        case .expense:
            if account.isDeposit { return currentBalance }
            return currentBalance + getTransactionAmount(transaction, for: account.currency)

        case .internalTransfer:
            if isSource {
                return currentBalance + getSourceAmount(transaction)
            } else {
                return currentBalance - getTargetAmount(transaction)
            }

        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            return currentBalance

        case .loanPayment, .loanEarlyRepayment:
            if transaction.accountId == account.id || transaction.targetAccountId == account.id {
                return currentBalance + getTransactionAmount(transaction, for: account.currency)
            }
            return currentBalance
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/BalanceCalculationEngineTests 2>&1 | tail -30
```

Expected: all 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Services/Balance/BalanceCalculationEngine.swift TenraTests/Services/BalanceCalculationEngineTests.swift
git commit -m "feat(balance): gate .income/.expense incremental updates for deposits"
```

---

## Task 6: Refactor `AccountActionViewModel`

**Files:**
- Modify: `Tenra/ViewModels/AccountActionViewModel.swift`
- Test: `TenraTests/ViewModels/AccountActionViewModelTests.swift` (**new**)

Goal: Drop `transferDirection` and all `if account.isDeposit` branches. Add a `defaultAction: ActionType?` init parameter. When `nil`, default `.income` for deposits and `.transfer` for regular accounts.

`DepositTransferDirection` itself is referenced from `Tenra/Views/Deposits/DepositDetailView.swift` (defined there) and from `AccountActionView.swift`. The enum is **deleted in Task 8** so it stays compilable through the intermediate state — `AccountActionViewModel` simply stops using it in this task.

- [ ] **Step 1: Create the test file with failing tests**

Create `TenraTests/ViewModels/AccountActionViewModelTests.swift`:

```swift
//
//  AccountActionViewModelTests.swift
//  TenraTests
//
//  Unit tests for AccountActionViewModel default-action selection.
//

import Testing
import Foundation
@testable import Tenra

@Suite("AccountActionViewModel.defaultAction")
@MainActor
struct AccountActionViewModelTests {

    private func regularAccount(id: String = "a1") -> Account {
        Account(id: id, name: "Bank", currency: "KZT", iconSource: nil, initialBalance: 100_000)
    }

    private func depositAccount(id: String = "d1") -> Account {
        Account(
            id: id, name: "Savings", currency: "KZT", iconSource: nil,
            depositInfo: DepositInfo(
                bankName: "T",
                principalBalance: 100_000,
                capitalizationEnabled: false,
                interestAccruedNotCapitalized: 0,
                interestRateAnnual: 0,
                interestRateHistory: [RateChange(effectiveFrom: "2020-01-01", annualRate: 0)],
                interestPostingDay: 1,
                lastInterestCalculationDate: "2020-01-01",
                lastInterestPostingMonth: "2020-01-01",
                interestAccruedForCurrentPeriod: 0,
                initialPrincipal: 100_000,
                startDate: "2020-01-01"
            ),
            initialBalance: 100_000
        )
    }

    @Test("regular account defaults to .transfer when defaultAction is nil")
    func regularAccount_defaultsToTransfer() {
        let coord = AppCoordinator()
        let vm = AccountActionViewModel(
            account: regularAccount(),
            accountsViewModel: coord.accountsViewModel,
            transactionsViewModel: coord.transactionsViewModel,
            defaultAction: nil
        )
        #expect(vm.selectedAction == .transfer)
    }

    @Test("deposit defaults to .income when defaultAction is nil")
    func depositAccount_defaultsToIncome() {
        let coord = AppCoordinator()
        let vm = AccountActionViewModel(
            account: depositAccount(),
            accountsViewModel: coord.accountsViewModel,
            transactionsViewModel: coord.transactionsViewModel,
            defaultAction: nil
        )
        #expect(vm.selectedAction == .income)
    }

    @Test("explicit defaultAction overrides per-account default")
    func explicitDefaultActionOverrides() {
        let coord = AppCoordinator()
        let vm = AccountActionViewModel(
            account: depositAccount(),
            accountsViewModel: coord.accountsViewModel,
            transactionsViewModel: coord.transactionsViewModel,
            defaultAction: .transfer
        )
        #expect(vm.selectedAction == .transfer)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/AccountActionViewModelTests 2>&1 | tail -30
```

Expected: BUILD FAILED — `AccountActionViewModel` has no `defaultAction` parameter.

- [ ] **Step 3: Refactor `AccountActionViewModel`**

Replace the entire contents of `Tenra/ViewModels/AccountActionViewModel.swift` with:

```swift
//
//  AccountActionViewModel.swift
//  Tenra
//

import Foundation
import OSLog

@Observable
@MainActor
final class AccountActionViewModel {

    // MARK: - Observable State

    var selectedAction: ActionType
    var amountText: String = ""
    var selectedCurrency: String
    var descriptionText: String = ""
    var selectedCategory: String? = nil
    var selectedTargetAccountId: String? = nil
    var selectedDate: Date = Date()
    var showingError: Bool = false
    var errorMessage: String = ""
    var shouldDismiss: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored let account: Account
    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored private let logger = Logger(subsystem: "Tenra", category: "AccountActionViewModel")

    // MARK: - Nested Types

    enum ActionType {
        case income
        case transfer
    }

    // MARK: - Computed Properties

    var availableAccounts: [Account] {
        accountsViewModel.accounts.filter { $0.id != account.id }
    }

    var incomeCategories: [String] {
        let validNames = Set(
            transactionsViewModel.customCategories
                .filter { $0.type == .income }
                .map { $0.name }
        )
        return transactionsViewModel.incomeCategories.filter { validNames.contains($0) }
    }

    var navigationTitleText: String {
        selectedAction == .income
            ? String(localized: "transactionForm.accountTopUp")
            : String(localized: "transactionForm.transfer")
    }

    var headerForAccountSelection: String {
        String(localized: "transactionForm.toAccount")
    }

    // MARK: - Init

    /// `defaultAction == nil` selects a per-account default: deposits open in `.income`
    /// (Top-up is the most common deposit operation); regular accounts open in `.transfer`
    /// (matches the existing entry point from AccountDetailView's secondary "Transfer" button).
    init(
        account: Account,
        accountsViewModel: AccountsViewModel,
        transactionsViewModel: TransactionsViewModel,
        defaultAction: ActionType? = nil
    ) {
        self.account = account
        self.accountsViewModel = accountsViewModel
        self.transactionsViewModel = transactionsViewModel
        self.selectedCurrency = account.currency
        self.selectedAction = defaultAction ?? (account.isDeposit ? .income : .transfer)
    }

    // MARK: - Save

    func saveTransaction(date: Date, transactionStore: TransactionStore) async {
        guard !amountText.isEmpty,
              let amount = Double(AmountInputFormatting.cleanAmountString(amountText)),
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

    // MARK: - Private: Income (Top-up)

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

    // MARK: - Private: Transfer

    private func saveTransfer(
        amount: Double,
        transactionDate: String,
        finalDescription: String,
        transactionStore: TransactionStore
    ) async {
        guard let targetAccountId = selectedTargetAccountId else {
            errorMessage = String(localized: "transactionForm.selectTargetAccount")
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

        // The current account is always the source — deposit transfers are always
        // outgoing (Variant A). To put money INTO a deposit, the user goes from the
        // source account's screen.
        let sourceId = account.id
        let targetId = targetAccountId

        let sourceCurrency = account.currency

        if selectedCurrency != sourceCurrency {
            guard await CurrencyConverter.convert(
                amount: amount,
                from: selectedCurrency,
                to: sourceCurrency
            ) != nil else {
                errorMessage = String(localized: "currency.error.conversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

        let targetAccount = accountsViewModel.accounts.first(where: { $0.id == targetId })
        let targetCurrency = targetAccount?.currency ?? selectedCurrency
        let currenciesToLoad = Set([selectedCurrency, account.currency, targetCurrency])

        for currency in currenciesToLoad where currency != "KZT" {
            if await CurrencyConverter.getExchangeRate(for: currency) == nil {
                errorMessage = String(localized: "currency.error.ratesUnavailable")
                showingError = true
                HapticManager.error()
                return
            }
        }

        if selectedCurrency != account.currency {
            guard await CurrencyConverter.convert(amount: amount, from: selectedCurrency, to: account.currency) != nil else {
                errorMessage = String(localized: "currency.error.sourceConversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

        if selectedCurrency != targetCurrency {
            guard await CurrencyConverter.convert(amount: amount, from: selectedCurrency, to: targetCurrency) != nil else {
                errorMessage = String(localized: "currency.error.targetConversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

        if account.currency != targetCurrency {
            guard await CurrencyConverter.convert(amount: amount, from: account.currency, to: targetCurrency) != nil else {
                errorMessage = String(localized: "currency.error.crossConversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

        var precomputedTargetAmount: Double?
        if selectedCurrency != targetCurrency {
            precomputedTargetAmount = await CurrencyConverter.convert(
                amount: amount,
                from: selectedCurrency,
                to: targetCurrency
            )
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
}
```

- [ ] **Step 4: Run the new tests to verify they pass**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/AccountActionViewModelTests 2>&1 | tail -30
```

Expected: 3 tests pass.

- [ ] **Step 5: Verify the rest of the build still compiles**

`AccountActionView` and `DepositDetailView` still pass `transferDirection:` to the old init signature. After this task they will fail to compile — that is expected and is fixed in Task 7 / Task 8. Run a build to verify the failure is exactly that and nothing else:

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected errors are limited to:
- `Extra argument 'transferDirection' in call` (in `AccountActionView.swift` and `DepositDetailView.swift`)
- references to `DepositTransferDirection` from `AccountActionView` or `AccountActionViewModel` callsites

If any unrelated errors appear, stop and investigate.

- [ ] **Step 6: Commit**

```bash
git add Tenra/ViewModels/AccountActionViewModel.swift TenraTests/ViewModels/AccountActionViewModelTests.swift
git commit -m "refactor(account-action-vm): drop transferDirection, add defaultAction"
```

---

## Task 7: Refactor `AccountActionView`

**Files:**
- Modify: `Tenra/Views/Accounts/AccountActionView.swift`

Drop the `transferDirection: DepositTransferDirection?` init parameter. Drop the `if account.isDeposit { ... } else { ... }` branch in `safeAreaBar` so there is a single `Transfer / Top-up` picker for all account types. The `categoriesViewModel` field already exists and is unused beyond DI passthrough — leave it alone.

- [ ] **Step 1: Replace the file**

Overwrite `Tenra/Views/Accounts/AccountActionView.swift` with:

```swift
//
//  AccountActionView.swift
//  Tenra
//

import SwiftUI

struct AccountActionView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(AppCoordinator.self) private var appCoordinator
    let account: Account
    let namespace: Namespace.ID
    @Environment(\.dismiss) var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @State private var viewModel: AccountActionViewModel
    @State private var showingAccountHistory = false

    init(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        account: Account,
        namespace: Namespace.ID,
        categoriesViewModel: CategoriesViewModel,
        defaultAction: AccountActionViewModel.ActionType? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.account = account
        self.namespace = namespace
        self.categoriesViewModel = categoriesViewModel
        _viewModel = State(initialValue: AccountActionViewModel(
            account: account,
            accountsViewModel: accountsViewModel,
            transactionsViewModel: transactionsViewModel,
            defaultAction: defaultAction
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Color.clear
                    .frame(height: 0)
                    .glassEffectID("account-card-\(account.id)", in: namespace)

                AmountInputView(
                    amount: $viewModel.amountText,
                    selectedCurrency: $viewModel.selectedCurrency,
                    errorMessage: viewModel.showingError ? viewModel.errorMessage : nil,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency,
                    accountCurrencies: Set(accountsViewModel.accounts.map(\.currency)),
                    appSettings: transactionsViewModel.appSettings
                )

                // Target account picker — shown for Transfer mode only.
                if viewModel.selectedAction == .transfer {
                    if let coordinator = accountsViewModel.balanceCoordinator {
                        AccountSelectorView(
                            accounts: viewModel.availableAccounts,
                            selectedAccountId: $viewModel.selectedTargetAccountId,
                            emptyStateMessage: String(localized: "transactionForm.noAccountsForTransfer"),
                            balanceCoordinator: coordinator
                        )
                    }
                }

                // Income category picker — shown for Top-up mode only.
                if viewModel.selectedAction == .income {
                    CategorySelectorView(
                        categories: viewModel.incomeCategories,
                        type: .income,
                        customCategories: transactionsViewModel.customCategories,
                        selectedCategory: $viewModel.selectedCategory,
                        emptyStateMessage: String(localized: "transactionForm.noCategories")
                    )
                }

                FormTextField(
                    text: $viewModel.descriptionText,
                    placeholder: String(localized: "transactionForm.descriptionPlaceholder"),
                    style: .multiline(min: 2, max: 6)
                )
            }
        }
        .safeAreaBar(edge: .top) {
            SegmentedPickerView(
                title: String(localized: "common.type"),
                selection: $viewModel.selectedAction,
                options: [
                    (label: String(localized: "transactionForm.transfer"), value: AccountActionViewModel.ActionType.transfer),
                    (label: String(localized: "transactionForm.topUp"), value: AccountActionViewModel.ActionType.income)
                ]
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(Color.clear)
        }
        .navigationTitle(viewModel.navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAccountHistory = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .dateButtonsSafeArea(selectedDate: $viewModel.selectedDate, onSave: { date in
            Task { await viewModel.saveTransaction(date: date, transactionStore: transactionStore) }
        })
        .sheet(isPresented: $showingAccountHistory) {
            NavigationStack {
                HistoryView(
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: accountsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    paginationController: appCoordinator.transactionPaginationController,
                    initialAccountId: account.id
                )
                    .environment(timeFilterManager)
            }
        }
        .onChange(of: viewModel.shouldDismiss) { _, should in
            if should { dismiss() }
        }
        .alert(String(localized: "common.error"), isPresented: $viewModel.showingError) {
            Button(String(localized: "voice.ok"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

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
    .environment(coordinator)
    .environment(coordinator.transactionStore)
    .environment(TimeFilterManager())
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected errors are now limited to `DepositDetailView.swift` (still passes `transferDirection:` and references the old `DepositTransferDirection` enum). Task 8 fixes those.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Accounts/AccountActionView.swift
git commit -m "refactor(account-action): single Transfer/Top-up picker for all accounts"
```

---

## Task 8: Refactor `DepositDetailView`

**Files:**
- Modify: `Tenra/Views/Deposits/DepositDetailView.swift`

Changes:
1. Delete the file-level `enum DepositTransferDirection` (lines 15-20).
2. Replace `@State private var activeTransferDirection: DepositTransferDirection? = nil` with `@State private var showingAction: Bool = false`.
3. Set `secondaryAction: nil` in the scaffold call. Primary action toggles `showingAction = true`.
4. Replace `.sheet(item: $activeTransferDirection) { direction in ... }` with `.sheet(isPresented: $showingAction) { ... }` and drop the `transferDirection:` argument from `AccountActionView(...)`.
5. Change reconcile `.task { ... }` to `.task(id: refreshTrigger) { ... }` so it re-runs whenever a relevant transaction is added/edited/deleted.

- [ ] **Step 1: Delete the `DepositTransferDirection` enum**

Edit `Tenra/Views/Deposits/DepositDetailView.swift`. Delete lines 13-20:

```swift
// DepositTransferDirection is the shared enum for deposit transfer direction.
// Defined here (primary consumer) and visible to AccountActionView via module scope.
enum DepositTransferDirection: Identifiable {
    case toDeposit
    case fromDeposit

    var id: Int { self == .toDeposit ? 0 : 1 }
}
```

- [ ] **Step 2: Replace the state variable**

Find the line:

```swift
    @State private var activeTransferDirection: DepositTransferDirection? = nil
```

Replace with:

```swift
    @State private var showingAction: Bool = false
```

- [ ] **Step 3: Update the action buttons**

Find the `EntityDetailScaffold(` call and its `primaryAction` / `secondaryAction` parameters. Replace them with:

```swift
            primaryAction: ActionConfig(
                title: String(localized: "account.detail.actions.addTransaction", defaultValue: "Add transaction"),
                systemImage: "plus",
                action: {
                    HapticManager.light()
                    showingAction = true
                }
            ),
            secondaryAction: nil,
```

- [ ] **Step 4: Update the sheet**

Find:

```swift
        // Unified transfer sheet — replaces separate showingTransferTo / showingTransferFrom
        .sheet(item: $activeTransferDirection) { direction in
            NavigationStack {
                AccountActionView(
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: depositsViewModel.accountsViewModel,
                    account: account,
                    namespace: depositActionNamespace,
                    categoriesViewModel: appCoordinator.categoriesViewModel,
                    transferDirection: direction
                )
                .environment(timeFilterManager)
            }
        }
```

Replace with:

```swift
        .sheet(isPresented: $showingAction) {
            NavigationStack {
                AccountActionView(
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: depositsViewModel.accountsViewModel,
                    account: account,
                    namespace: depositActionNamespace,
                    categoriesViewModel: appCoordinator.categoriesViewModel
                )
                .environment(timeFilterManager)
            }
        }
```

- [ ] **Step 5: Move reconcile to `.task(id:)`**

Find:

```swift
        .task {
            // Reconcile only this deposit — not all deposits (targeted, not global).
            // Collect generated interest transactions synchronously in the callback,
            // then batch-persist after reconciliation completes. Never spawn Task {}
            // inside onTransactionCreated — it races on TransactionStore across days.
            var interestTransactions: [Transaction] = []
            depositsViewModel.reconcileDepositInterest(
                for: accountId,
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    interestTransactions.append(transaction)
                }
            )
            for tx in interestTransactions {
                do {
                    _ = try await transactionStore.add(tx)
                } catch {
                    logger.error("Failed to add deposit interest transaction: \(error.localizedDescription)")
                    reconciliationError = error.localizedDescription
                }
            }
        }
```

Replace with:

```swift
        .task(id: refreshTrigger) {
            // Reconcile re-runs whenever a deposit-relevant transaction is added/edited/deleted
            // (refreshTrigger counts them). Reconcile is idempotent and recomputes
            // principalBalance unconditionally — see DepositInterestService.reconcileDepositInterest.
            var interestTransactions: [Transaction] = []
            depositsViewModel.reconcileDepositInterest(
                for: accountId,
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    interestTransactions.append(transaction)
                }
            )
            for tx in interestTransactions {
                do {
                    _ = try await transactionStore.add(tx)
                } catch {
                    logger.error("Failed to add deposit interest transaction: \(error.localizedDescription)")
                    reconciliationError = error.localizedDescription
                }
            }
        }
```

- [ ] **Step 6: Build to verify**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected: no errors. If `DepositTransferDirection` is referenced from anywhere else, fix or delete that reference. Run:

```bash
grep -rn "DepositTransferDirection" Tenra/ TenraTests/ TenraUITests/ 2>/dev/null
```

Expected: no matches.

- [ ] **Step 7: Run the full test suite**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests 2>&1 | tail -20
```

Expected: all suites pass.

- [ ] **Step 8: Commit**

```bash
git add Tenra/Views/Deposits/DepositDetailView.swift
git commit -m "refactor(deposit-detail): drop DepositTransferDirection, single action button"
```

---

## Task 9: Manual UI verification

The pure-logic changes are covered by unit tests; the SwiftUI integration and end-to-end deposit balance flow need a hands-on pass on simulator.

- [ ] **Step 1: Launch the app on simulator**

```bash
open -a "Simulator"
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Open `Tenra.xcodeproj`, run on `iPhone 17 Pro`.

- [ ] **Step 2: Verify the deposit action sheet**

1. Open any existing deposit (or create one via the convert flow).
2. On the deposit detail screen, confirm there is **one** primary action button (`Add transaction`); the previous secondary "Transfer" button is gone.
3. Tap `Add transaction`. The action sheet must show the segmented picker `Перевод / Пополнение` (NOT `Top-up / Withdrawal`).
4. The default selected segment must be `Пополнение` (Top-up) since this is a deposit.

- [ ] **Step 3: Verify Top-up flow grows the deposit balance immediately**

1. Note the deposit's current balance.
2. Open `Add transaction` → `Пополнение`.
3. Pick an income category (e.g. Salary). Enter an amount (e.g. 25_000). Tap Save.
4. Sheet dismisses. Deposit detail re-renders.
5. The displayed balance must increase by exactly the entered amount within ~1 second (the `task(id: refreshTrigger)` re-runs reconcile, which now recomputes `principalBalance` unconditionally).
6. The transaction list must show the new income entry with the chosen category.

- [ ] **Step 4: Verify Transfer flow (deposit as source)**

1. Open `Add transaction` → switch segment to `Перевод`.
2. The form must show the target account picker (regular accounts), no income category picker.
3. Pick a target. Enter an amount. Save.
4. Confirm the deposit's balance decreases by the amount and the target account's balance increases.

- [ ] **Step 5: Verify regular account is unchanged**

1. Open any non-deposit account's detail.
2. Tap the secondary `Transfer` button (regular accounts still have it).
3. Confirm the segmented picker still defaults to `Перевод` and the flow works exactly as before.

- [ ] **Step 6: Verify Insights / income totals reflect the deposit Top-up**

1. Switch to the Insights / Analytics tab.
2. Confirm the `.income` transaction created in Step 3 is included in income totals (this is the parity goal — same as a regular-account top-up).

- [ ] **Step 7: Commit any docs / notes if needed**

If you need to update CLAUDE.md or other docs to reflect the new behavior, do so now and commit. Otherwise skip.

---

## Self-Review Checklist (run before declaring the plan done)

- [x] Spec D1 (component reuse) — Tasks 6, 7, 8.
- [x] Spec D2 (deposit always source in Transfer) — Task 6 (`saveTransfer` sourceId).
- [x] Spec D3 (Top-up creates `.income` with category) — Task 6 (`saveIncomeTransaction` unchanged).
- [x] Spec D4 (extend reconcile) — Tasks 1, 2, 3, 4.
- [x] Spec D5 (use `convertedAmount`) — Task 2.
- [x] Spec D6 (gate incremental for deposits) — Task 5.
- [x] Spec D7 (reconcile on add/edit/delete via `.task(id:)`) — Task 8 step 5.
- [x] Spec D7a (same-day principal recompute) — Task 3.
- [x] Spec D8 (single-button DepositDetailView) — Task 8.
- [x] Spec D9 (`defaultAction` parameter, deposit defaults to `.income`) — Task 6.
