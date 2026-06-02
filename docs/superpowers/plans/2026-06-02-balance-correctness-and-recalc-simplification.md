# Balance Correctness & Recalc Simplification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop balances from silently diverging across relaunch (the recurring "wrong number" bug class) and remove the per-launch full recalc over ~19k transactions that causes the startup lag.

**Architecture:** The codebase maintains every derived number (balance, aggregates) via TWO paths — an incremental maintainer (on each mutation) and a full rebuilder (on relaunch / day-change / currency-change). They diverge whenever the rebuilder's inputs differ from what the incremental path used. Phase 0 closes the one input gap that breaks deposit conversion (`initialBalance` not persisted to CoreData). Phase 1 removes the daily full balance recalc and replaces it with targeted maturation of the small set of transactions whose date crossed "today". Phases 2-3 (separate plans) unify the three Summary code paths and fix point-divergences.

**Tech Stack:** Swift 5 / SwiftUI (iOS 26), CoreData v12, Observation framework, swift-testing (`import Testing`, `@Test`, `#expect`). Build/test via `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

---

## Root Cause Recap (read before starting)

The "huge negative / zero balance days after converting an account to a deposit" bug has TWO layers:

1. **Already fixed:** the `.preserveImported` calc mode lived only in memory and was lost on relaunch (removed; replaced by `DepositInfo.conversionTimestamp` + a `createdAt <= conversionTimestamp` cutoff in `BalanceCalculationEngine.contribution`).
2. **NOT fixed (this plan, Phase 0):** the full recalc computes `balance = AccountBalance.initialBalance + Σ contribution`. At conversion, `AccountsViewModel.updateDeposit` sets the snapshot via `coordinator.setInitialBalance(...)`, but that writes ONLY the in-memory `BalanceStore` — `AccountRepository.saveAccountsInternal` explicitly refuses to overwrite `AccountEntity.initialBalance` (`AccountRepository.swift:225`: *"Don't overwrite initialBalance — it's set once at creation and never changes"*). On relaunch the recalc reads the creation-time `initialBalance` (often `0` for a transactions-derived account), and with the `conversionTimestamp` cutoff excluding all pre-conversion history, `balance → 0`. **The cutoff is correct and must stay; the gap is purely that the snapshot `initialBalance` never reaches CoreData.**

Verified by subagent exploration: the interest accrual path (`DepositInterestService`) has its OWN `tx.date > startDate` filter independent of the balance engine, so changing the balance base does not affect interest. `DepositInfo.initialPrincipal` is never mutated after creation, so capitalized interest (`.depositInterestAccrual` tx) is not double-counted.

**Until Phase 0 ships, do NOT re-convert Jusan/Kaspi — they will break again on day 2.**

---

## File Structure (Phase 0)

| File | Responsibility | Change |
|---|---|---|
| `Tenra/Services/Repository/AccountRepository.swift` | CoreData account persistence | Add `updateInitialBalancesSync` (mirrors `updateAccountBalancesSync`) + protocol decl |
| `Tenra/Services/Core/DataRepositoryProtocol.swift` | Facade protocol | Add `updateInitialBalancesSync` decl |
| `Tenra/Services/Repository/CoreDataRepository.swift` | Facade → AccountRepository forward | Forward `updateInitialBalancesSync` |
| `Tenra/Services/Core/UserDefaultsRepository.swift` | Preview/no-op repo | Add no-op stub |
| `Tenra/Services/Balance/BalanceCoordinator.swift` | Balance ops entry point | Add `persistInitialBalance(_:for:)` (in-memory + CoreData) |
| `Tenra/Protocols/BalanceCoordinatorProtocol.swift` | Balance coordinator protocol | Add `persistInitialBalance` decl |
| `Tenra/ViewModels/AccountsViewModel.swift` | Deposit conversion wiring | Conversion branch calls `persistInitialBalance` instead of `setInitialBalance` |
| `TenraTests/Services/AccountRepositoryTests.swift` | Repo unit tests + `MockAccountRepository` | Add round-trip test + mock stub |
| `TenraTests/ViewModels/TransactionStoreTests.swift` | `MockRepository` | Add no-op stub so it still conforms |

---

## Phase 0 — Persist `initialBalance` at conversion (UNBLOCKS RE-CONVERSION)

### Task 1: Repository method to persist `initialBalance` (real CoreData round-trip)

**Files:**
- Modify: `Tenra/Services/Repository/AccountRepository.swift` (protocol at lines 14-22; impl near line 170)
- Modify: `Tenra/Services/Core/DataRepositoryProtocol.swift:46-49`
- Modify: `Tenra/Services/Repository/CoreDataRepository.swift:97-102`
- Modify: `Tenra/Services/Core/UserDefaultsRepository.swift:111`
- Modify: `TenraTests/Services/AccountRepositoryTests.swift` (`MockAccountRepository` at line 53; new test near line 140)
- Modify: `TenraTests/ViewModels/TransactionStoreTests.swift` (`MockRepository` at line 432)

- [ ] **Step 1: Write the failing test** in `AccountRepositoryTests.swift` (after the `updateAccountBalances batch` test ~line 145). This uses the existing in-memory CoreData-backed test harness in that file (find how the suite builds a real `AccountRepository` — mirror the existing `updateAccountBalances`/round-trip test exactly; if the suite only has `MockAccountRepository`, instead add this test to `TenraTests/Services/AccountEntityRoundTripTests.swift`, which uses a real in-memory `NSPersistentContainer`):

```swift
@Test("updateInitialBalancesSync persists initialBalance to CoreData")
func updateInitialBalancesSyncPersists() async throws {
    // Arrange: a saved account whose initialBalance starts at 0 (transactions-derived).
    let account = Account(id: "conv", name: "Conv", currency: "KZT",
                          shouldCalculateFromTransactions: false, initialBalance: 0, balance: 1051.6)
    repo.saveAccounts([account])

    // Act: persist a new initialBalance (the conversion snapshot).
    await repo.updateInitialBalancesSync(["conv": 1051.6])

    // Assert: reload from store; initialBalance is the snapshot, not the creation 0.
    let reloaded = repo.loadAccounts().first { $0.id == "conv" }
    #expect(reloaded?.initialBalance == 1051.6)
}
```

- [ ] **Step 2: Run test to verify it fails (compile error — method doesn't exist yet)**

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/AccountRepositoryTests 2>&1 | grep -aE "error:|TEST (SUCCEEDED|FAILED)" | head`
Expected: FAIL — `error: value of type '...' has no member 'updateInitialBalancesSync'`

- [ ] **Step 3: Add the method to `AccountRepositoryProtocol` and `AccountRepository`.** In `AccountRepository.swift` protocol block (next to line 21):

```swift
    nonisolated func updateInitialBalancesSync(_ balances: [String: Double]) async
```

In the impl (paste directly after `updateAccountBalancesSync`, ~line 194):

```swift
    /// Persist `initialBalance` for specific accounts. This is the ONE allowed path that
    /// overwrites `AccountEntity.initialBalance` after creation — used only when an account
    /// is converted to a deposit and its current balance is snapshotted as the new recalc
    /// base. saveAccountsInternal intentionally refuses to touch initialBalance; this method
    /// is the deliberate exception.
    func updateInitialBalancesSync(_ balances: [String: Double]) async {
        guard !balances.isEmpty else { return }
        let operationId = "updateInitialBalancesSync_\(UUID().uuidString)"
        do {
            try await saveCoordinator.performSave(operation: operationId) { context in
                let fetchRequest = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
                fetchRequest.predicate = NSPredicate(format: "id IN %@", Array(balances.keys))
                let accounts = try context.fetch(fetchRequest)
                for account in accounts {
                    if let accountId = account.id, let newInitial = balances[accountId] {
                        account.initialBalance = newInitial
                    }
                }
            }
        } catch {
            // Save failed — next-day recalc will use the stale base; surfaced as a balance
            // discrepancy, repaired when the conversion is re-saved.
        }
    }
```

- [ ] **Step 4: Forward through the facade.** In `DataRepositoryProtocol.swift` (next to line 49) add:

```swift
    nonisolated func updateInitialBalancesSync(_ balances: [String: Double]) async
```

In `CoreDataRepository.swift` (next to line 102) add:

```swift
    func updateInitialBalancesSync(_ balances: [String: Double]) async {
        await accountRepository.updateInitialBalancesSync(balances)
    }
```

(Confirm the property name `accountRepository` by reading how `updateAccountBalancesSync` is forwarded at `CoreDataRepository.swift:102`; mirror it exactly.)

- [ ] **Step 5: Add no-op stubs to keep all conformers compiling.** In `UserDefaultsRepository.swift` (after line 113):

```swift
    func updateInitialBalancesSync(_ balances: [String: Double]) async {
        // UserDefaults implementation: noop (initialBalance persistence is a CoreData-only path)
    }
```

In `TransactionStoreTests.swift` `MockRepository` (after its `updateAccountBalancesSync` stub):

```swift
    func updateInitialBalancesSync(_ balances: [String: Double]) async {}
```

In `AccountRepositoryTests.swift` `MockAccountRepository` (after its `updateAccountBalancesSync` at line 98):

```swift
    func updateInitialBalancesSync(_ balances: [String: Double]) async {
        for (id, bal) in balances { initialBalances[id] = bal }  // if the mock tracks state; else {}
    }
```

(Read the mock first — if it has no state dictionaries, an empty body is fine.)

- [ ] **Step 6: Run the test to verify it passes**

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/AccountRepositoryTests 2>&1 | grep -aE "TEST (SUCCEEDED|FAILED)|failed" | head`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Tenra/Services/Repository/AccountRepository.swift Tenra/Services/Core/DataRepositoryProtocol.swift Tenra/Services/Repository/CoreDataRepository.swift Tenra/Services/Core/UserDefaultsRepository.swift TenraTests/Services/AccountRepositoryTests.swift TenraTests/ViewModels/TransactionStoreTests.swift
git commit -m "feat(balance): persist initialBalance for deposit conversion (updateInitialBalancesSync)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `BalanceCoordinator.persistInitialBalance` (in-memory + CoreData)

**Files:**
- Modify: `Tenra/Services/Balance/BalanceCoordinator.swift` (near `setInitialBalance`, ~line 215)
- Modify: `Tenra/Protocols/BalanceCoordinatorProtocol.swift` (near `setInitialBalance` decl, ~line 127)

- [ ] **Step 1: Add the protocol decl** in `BalanceCoordinatorProtocol.swift` after the `setInitialBalance` decl:

```swift
    /// Persist a new initial balance both in-memory AND to CoreData. Used at deposit
    /// conversion to snapshot the current balance as the recalc base so the cold-launch
    /// full recalc reproduces it. Unlike `setInitialBalance` (in-memory only), this survives
    /// relaunch.
    func persistInitialBalance(_ balance: Double, for accountId: String) async
```

- [ ] **Step 2: Add the impl** in `BalanceCoordinator.swift` directly after `setInitialBalance` (~line 219):

```swift
    func persistInitialBalance(_ balance: Double, for accountId: String) async {
        store.setInitialBalance(balance, for: accountId)
        await repository.updateInitialBalancesSync([accountId: balance])
    }
```

(Confirm the repository property is named `repository` by reading `persistBalance` at `BalanceCoordinator.swift:389`; mirror it.)

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Tenra/Services/Balance/BalanceCoordinator.swift Tenra/Protocols/BalanceCoordinatorProtocol.swift
git commit -m "feat(balance): add BalanceCoordinator.persistInitialBalance (in-memory + CoreData)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Wire conversion to persist the snapshot

**Files:**
- Modify: `Tenra/ViewModels/AccountsViewModel.swift` (`updateDeposit` conversion branch, ~line 228-265)

- [ ] **Step 1: Change the conversion branch** to call `persistInitialBalance`. Replace the existing `Task { if isConversion, let snapshotBalance { await coordinator.setInitialBalance(snapshotBalance, for: account.id) } ... }` block with:

```swift
        if let coordinator = balanceCoordinator, let depositInfo = account.depositInfo {
            let snapshotBalance = account.initialBalance
            Task {
                if isConversion, let snapshotBalance {
                    // Snapshot is the conversion-time balance; persist it as the recalc base
                    // (CoreData + in-memory) so the cold-launch full recalc reproduces it.
                    // Inherited history is gated out by the conversionTimestamp createdAt cutoff.
                    await coordinator.persistInitialBalance(snapshotBalance, for: account.id)
                }
                await coordinator.updateDepositInfo(account, depositInfo: depositInfo)
            }
        }
```

- [ ] **Step 2: Verify the relaunch invariant test still passes** (it already models `initialBalance == snapshot`, which the app now actually persists):

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/BalanceLedgerInvariantTests 2>&1 | grep -aE "TEST (SUCCEEDED|FAILED)|failed" | head`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Full regression on balance/deposit/account suites**

Run each and confirm `** TEST SUCCEEDED **`:
```bash
for s in BalanceLedgerInvariantTests BalanceCalculationEngineTests DepositInterestServiceTests DepositPrincipalDeltaCharacterizationTests DepositCrossCurrencyTransferTests AccountEntityRoundTripTests AccountActionViewModelTests AccountRepositoryTests; do echo "== $s =="; xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/$s 2>&1 | grep -aE "TEST (SUCCEEDED|FAILED)" | head -1; done
```
Expected: all `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Tenra/ViewModels/AccountsViewModel.swift
git commit -m "fix(balance): converted deposit persists snapshot initialBalance so relaunch recalc is correct

Closes the day-2 'balance drops to 0' regression: setInitialBalance only wrote the in-memory
store; the cold recalc read the creation-time initialBalance. Now persisted via CoreData.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Manual device verification (REQUIRED — automated tests can't cover the full relaunch cycle)**

1. On the physical device build, restore data from backup.
2. Convert one small account to a deposit. Note the balance.
3. Force-quit the app. Change the device date forward by one day (Settings → General → Date & Time, disable automatic). Relaunch.
4. Confirm the deposit balance is unchanged (NOT 0, NOT negative). Restore automatic date.

---

## Phase 0.5 — Update docs & memory

- [ ] Update `docs/domains/deposits.md` conversion section: note that conversion now persists `initialBalance` via `BalanceCoordinator.persistInitialBalance` / `updateInitialBalancesSync`, and that this is the ONE sanctioned overwrite of `AccountEntity.initialBalance`.
- [ ] Update the memory file `project_deposit_conversion_recovery_pending.md`: the fix is now complete; re-conversion is safe.
- [ ] Commit docs.

---

## Roadmap — Phases 1-3 (each ships as its OWN detailed plan)

These address the broader "why does it keep recalculating 19k / why do numbers diverge" concerns. Each is an independent, shippable subsystem and will get its own `writing-plans` pass before implementation. Listed here so the direction is agreed.

### Phase 1 — Replace the daily full recalc with targeted maturation (KILLS THE LAUNCH LAG)
- **Problem:** `TransactionStore.recalculateLedgerIfDayChanged` runs `recalculateAll` = `initialBalance + Σ(19k tx) × every account` on the MainActor once per day and on every first launch after an update (`TransactionStore.swift:528-541`, `BalanceCoordinator.processRecalculateAll`). Plus two O(N) index rebuilds in the same call stack. This is the startup hang.
- **Insight:** The ONLY thing a day-change genuinely changes is that future-dated transactions (`date > yesterday`) whose date is now `<= today` must be folded into realized balances/aggregates. That is a SMALL, identifiable set — not all 19k.
- **Approach:** Add a maturation pass that selects transactions whose `date` falls in `(lastRecalcDate, today]` (a bounded set, indexable by date), computes each one's `contribution`, and applies the delta to ONLY the affected accounts + aggregate buckets — then advances `lastLedgerRecalcKey`. No full scan. Keep `recalculateAll` only as an explicit user-triggered "repair" action in Settings.
- **Risk to design in the plan:** future-dated tx that were DELETED while still in the future; recurring occurrences generated ahead; correctness vs the existing `LedgerPolicyRule.isRealized` gate. Needs its own failing-test-first design (an invariant test: "incremental + maturation == full recalc" over a dataset spanning the date boundary).

### Phase 2 — Unify the three Summary code paths
- **Problem:** `SummaryCalculator` (ContentView), `TransactionStore.summary` (`+Computed`), and `TransactionQueryService.calculateSummary` (`TransactionsViewModel`) compute totals with DIFFERENT future-tx and deposit-type handling, so different screens can show different numbers simultaneously.
- **Approach:** Make `SummaryCalculator` the single source; route the other two call sites through it (or delete the dead `TransactionStore.summary` if unreferenced). Pin with a test asserting all UI summary entry points return identical figures for a fixture containing deposits + future recurring tx.

### Phase 3 — Point fixes for the remaining divergence/persistence gaps
- Flush category & account aggregate debounce (`scheduleAccountAggregatePersist`, the 500ms window) on `applicationWillResignActive` so a kill within 500ms of a mutation can't lose the write.
- Rebuild ACCOUNT aggregates (not just category) on `bumpCurrencyRatesVersion` when cross-currency legs were converted with a stale FX fallback (`TransactionStore.swift:131-136`).
- Reverse `LoanInfo.remainingPrincipal` / `totalInterestPaid` / `paymentsMade` when a linked loan-payment transaction is deleted through the generic history UI (currently only the dedicated LoanDetailView action keeps them in sync).
- Make `processRecalculateAccounts` persist its results (it updates in-memory + published `balances` but never calls `persistBalances`, so a targeted recalc is lost on relaunch — `BalanceCoordinator.swift:337-380`).

---

## Self-Review Notes
- **Spec coverage:** Phase 0 fully covers the urgent conversion-persistence gap (the only thing blocking safe re-conversion). Phases 1-3 cover the lag and the remaining divergence classes surfaced by the audit, scoped as separate plans per the writing-plans "one subsystem per plan" rule.
- **Type consistency:** new method name `updateInitialBalancesSync(_:)` used consistently across protocol/impl/forward/stub/mock; `persistInitialBalance(_:for:)` used consistently in coordinator + protocol + caller.
- **No placeholders:** every Phase 0 step shows exact code, file, command, and expected output. Phases 1-3 are intentionally roadmap-level (each gets its own placeholder-free plan before coding) — they are NOT to be implemented from this document.
