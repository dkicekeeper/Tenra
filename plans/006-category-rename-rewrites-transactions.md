# Plan 006: Renaming a category renames it on its transactions and recurring series

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/ViewModels/TransactionStore.swift Tenra/ViewModels/TransactionStore+CategoryCRUD.swift Tenra/ViewModels/TransactionStore+CategoryIndex.swift Tenra/Services/Repository/TransactionRepository.swift Tenra/Services/Repository/CoreDataRepository.swift Tenra/Services/Core/DataRepositoryProtocol.swift Tenra/Services/Core/UserDefaultsRepository.swift Tenra/Extensions/Transaction+WithCategory.swift`
> On any change, compare with the excerpts below; a mismatch is a STOP condition.

## Status

- **Priority**: P1 (do before any other category work)
- **Effort**: M
- **Risk**: MED (writes many transactions; must keep indexes and CoreData consistent)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

Categories are referenced by NAME: `Transaction.category`, `TransactionEntity.category`
and `RecurringSeries.category` are plain strings. Renaming a category today only re-keys
in-memory indexes. The transactions keep the old name, which causes three visible bugs:

1. Editing any old transaction of the renamed category fails on save with
   `categoryNotFound`, because `TransactionStore.validate` requires a non-empty category
   to exist.
2. After relaunch the index is rebuilt from the stored (old) names: the renamed
   category's transaction list is empty and the old name appears in the History category
   filter as a "deleted category".
3. Recurring series keep generating transactions with the old name.

Also, the import category suggestions (history tier) and "apply to similar" rely on
category names being correct.

## Current state

- `Tenra/ViewModels/TransactionStore+CategoryCRUD.swift:65-105` — `updateCategory(_:)`:
  ```swift
  let old = categories[index]
  categories[index] = category
  categoryById[category.id] = category

  // Move the name → id pointer if the user renamed the category. ...
  if old.name != category.name {
      renameCategoryIndexKeys(from: old.name, to: category.name)
  }

  categoriesMutationVersion &+= 1
  persistCategoriesToRepository()
  ```
- `Tenra/ViewModels/TransactionStore+CategoryIndex.swift:181-219` — `renameCategoryIndexKeys`
  moves `transactionIdsByCategoryName[old]` → `[new]`, re-keys `categoryIdByName` and
  every `categoryAggregatesByKey` entry with prefix `"<old>_"`. It does not touch transactions.
- `Tenra/ViewModels/TransactionStore.swift`:
  - line 74 `var transactions: [Transaction]`, line 90
    `@ObservationIgnored private(set) var transactionById: [String: Transaction]`,
    line 116 `@ObservationIgnored private(set) var mutationVersion: Int`,
    line 276 `internal let recurringStore: RecurringStore`,
    line 270 `internal let cache: UnifiedTransactionCache` (has `invalidateAll()`),
    line 269 `internal let repository: DataRepositoryProtocol`.
  - Because `transactionById` and `mutationVersion` are `private(set)`, the new method
    MUST live in `TransactionStore.swift` itself (an extension in another file cannot set them).
  - `validate` (around lines 1062-1074) rejects a non-empty category missing from `categories`
    for every type except transfers and loan/deposit types.
- `Tenra/Models/Transaction.swift:84-94` — `TransactionType.categoryPickerSourceType`:
  loan/deposit-topup/withdrawal → `.expense`, deposit interest → `.income`, otherwise self.
  Use it to decide which transactions belong to an expense vs income category.
- `Tenra/Extensions/Transaction+WithCategory.swift` — `withCategory(_:)` copies every field
  but CLEARS `subcategory`. A rename must KEEP `subcategory`, so add a sibling helper.
- `Tenra/ViewModels/RecurringStore.swift:86-91` — `handleSeriesUpdated(old:new:)` replaces a
  series in memory without regenerating; `saveSeries()` (line 183) persists (debounced).
  `RecurringSeries.category` is a `var String` (`Tenra/Models/RecurringTransaction.swift`).
- Persistence: `DataRepositoryProtocol` (`Tenra/Services/Core/DataRepositoryProtocol.swift`)
  is implemented by `CoreDataRepository` (forwards to `TransactionRepository` through
  `TransactionRepositoryProtocol`, `Tenra/Services/Repository/TransactionRepository.swift:14-28`)
  and by `UserDefaultsRepository` (previews; its per-row methods are no-ops, e.g.
  `updateTransactionFields`). No test target type conforms to these protocols
  (verified with grep). The existing single-row writer to model the batch on is
  `TransactionRepository.updateTransactionFields` (line ~360): background context,
  `performAndWait`, fetch by `id`, set fields, one `save()`, log errors with `Self.logger`.
- Rule from CLAUDE.md: never `NSBatchDeleteRequest` then save on the same context (not
  relevant to an update, but do not introduce batch-delete here). Use a fetch-and-set on a
  background context, like `updateTransactionFields`.
- Test harness exemplar: `TenraTests/ViewModels/TransactionRecategorizeTests.swift`
  (`makeStore()` on `UserDefaultsRepository`, `@MainActor`).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | `** BUILD SUCCEEDED **` |
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/CategoryRenameTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | `** TEST SUCCEEDED **` |
| All tests | `-only-testing:TenraTests`, then count `' passed on'` / `' failed on'` in the log | 0 failed |

## Scope

**In scope**: `Tenra/ViewModels/TransactionStore.swift` (add one method),
`Tenra/ViewModels/TransactionStore+CategoryCRUD.swift` (call it from `updateCategory`),
`Tenra/Extensions/Transaction+WithCategory.swift` (add a helper),
`Tenra/Services/Core/DataRepositoryProtocol.swift`, `Tenra/Services/Repository/CoreDataRepository.swift`,
`Tenra/Services/Repository/TransactionRepository.swift`, `Tenra/Services/Core/UserDefaultsRepository.swift`
(one new batch method each), `TenraTests/ViewModels/CategoryRenameTests.swift` (create).

**Out of scope**: deleting a category (orphans stay as today); merging categories; subcategory
renames (subcategories are linked by id); `renameCategoryIndexKeys` itself (keep it: it moves
aggregates without recomputation); any repair of transactions already orphaned by past renames
(see Maintenance notes).

## Git workflow

Commit directly on `main`; do not push. Message:
`fix(categories): renaming a category renames it on its transactions and series`.

## Steps

### Step 1: Helper that keeps the subcategory

In `Transaction+WithCategory.swift` add:
```swift
/// Same transaction under a renamed category. Unlike `withCategory`, keeps
/// the legacy `subcategory`, because a rename does not change the category's content.
nonisolated func renamingCategory(to newName: String) -> Transaction
```
Implement it exactly like `withCategory` but pass `subcategory: subcategory`.

**Verify**: Build → SUCCEEDED.

### Step 2: Batch persistence method

Add `nonisolated func renameTransactionsCategory(ids: [String], to newName: String)` to
`TransactionRepositoryProtocol` and `DataRepositoryProtocol` (doc comment: "Rewrite the
category of the given transactions in one background save. Used by category rename.").
- `TransactionRepository`: background context, `performAndWait`, fetch
  `TransactionEntity` with `NSPredicate(format: "id IN %@", ids)`, set `entity.category = newName`
  on each, one `save()`, log failures like `updateTransactionFields` does. Return early for empty `ids`.
- `CoreDataRepository`: forward to `transactionRepository`.
- `UserDefaultsRepository`: no-op with the same comment style as `updateTransactionFields`.

**Verify**: Build → SUCCEEDED.

### Step 3: Store method (in `TransactionStore.swift`)

Add, next to `update(_:allowSeriesDetach:)`:
```swift
/// Rewrites a renamed category on every transaction and recurring series that
/// still carries the old name. Call AFTER `renameCategoryIndexKeys`, which has
/// already moved the name-keyed indexes and aggregates; this makes the stored
/// strings agree with them so relaunch, validation and series generation see the new name.
func renameCategoryInTransactions(from oldName: String, to newName: String, type: TransactionType)
```
Behavior:
1. Guard `oldName != newName`.
2. For every index in `transactions` where `tx.category == oldName`,
   `tx.type != .internalTransfer` and `tx.type.categoryPickerSourceType == type`:
   replace with `tx.renamingCategory(to: newName)` in `transactions[index]` and
   `transactionById[tx.id]`; collect the id.
3. For every series in `recurringStore.recurringSeries` with `category == oldName`, but only
   if no remaining category in `categories` is still named `oldName` (a same-named category
   of the other type would make the series ambiguous): build a copy with
   `category = newName`, call `recurringStore.handleSeriesUpdated(old:new:)`; if any changed,
   call `recurringStore.saveSeries()`.
4. If ids were collected: `repository.renameTransactionsCategory(ids:to:)`,
   `cache.invalidateAll()`, `mutationVersion &+= 1`.

Do NOT call `apply(.updated)` per row: it would re-run the category index update against
indexes `renameCategoryIndexKeys` already moved, and costs O(N) per row.

**Verify**: Build → SUCCEEDED.

### Step 4: Call it from `updateCategory`

In `TransactionStore+CategoryCRUD.swift`, inside `if old.name != category.name { ... }`,
after `renameCategoryIndexKeys(from:to:)`, call
`renameCategoryInTransactions(from: old.name, to: category.name, type: old.type)`.

**Verify**: Build → SUCCEEDED.

### Step 5: Tests

Create `TenraTests/ViewModels/CategoryRenameTests.swift` (`@MainActor`, harness copied from
`TransactionRecategorizeTests.makeStore()` with an expense category "Food" and an income
category "Salary"). Cases in the Test plan.

**Verify**: Suite → SUCCEEDED; All tests → 0 failed.

## Test plan

1. Rename "Food" → "Groceries": every expense transaction that had "Food" now has "Groceries"
   (`store.transactionById` and `store.transactions` agree).
2. After the rename, `store.update(oldTx with only amount changed)` succeeds (no `categoryNotFound`).
3. After the rename, `store.rebuildCategoryIndexes()` (simulates relaunch) puts the ids under
   `transactionIdsByCategoryName["Groceries"]` and nothing under `"Food"`.
4. An income transaction whose category string happens to be "Food" (type `.income`) is NOT renamed
   when the EXPENSE category "Food" is renamed.
5. A loan payment tagged "Food" (type `.loanPayment`, `categoryPickerSourceType == .expense`) IS renamed.
6. A recurring series with category "Food" gets "Groceries".
7. The legacy `subcategory` string on a renamed transaction is preserved.
8. `mutationVersion` increases after a rename that touched transactions, and is unchanged when nothing matched.

## Done criteria

- [ ] Build SUCCEEDED; CategoryRenameTests (8 tests) pass; full TenraTests 0 failed
- [ ] `grep -n "renameCategoryInTransactions" Tenra/ViewModels/TransactionStore+CategoryCRUD.swift` → 1 match
- [ ] `git status --short` lists only in-scope files (plus `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 006 updated

## STOP conditions

- `updateCategory` or `renameCategoryIndexKeys` no longer match the excerpts.
- A test target type turns out to conform to `DataRepositoryProtocol` or `TransactionRepositoryProtocol` (update it too if trivial; otherwise report).
- The rename needs to change `validate` or indexes other than described.
- Existing category/budget/insights tests fail.

## Maintenance notes

- Human device check: rename a category with many transactions, edit one old transaction's
  amount (must save), relaunch (the category detail must still list them).
- Transactions orphaned by renames done BEFORE this fix still carry the old name. They show
  in the History filter under "deleted categories". A follow-up could offer "move these to
  category X"; the old name → new name mapping was never stored, so it cannot be automatic.
- Any new place that stores a category NAME (e.g. a future merchant-rule table) must be added
  to `renameCategoryInTransactions`.
