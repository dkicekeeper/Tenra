# Plan 003: Changing a transaction's category offers to apply it to the other transactions from the same merchant

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 84fbabdf..HEAD -- Tenra/Views/Transactions/TransactionEditCoordinator.swift Tenra/Views/Transactions/TransactionEditView.swift Tenra/ViewModels/TransactionStore.swift Tenra/Models/Transaction.swift Tenra/*.lproj/Localizable.strings`
> Plan 002 is expected to have landed (it creates
> `Tenra/Services/Categories/CategorySuggestionService.swift`). Any OTHER change
> to the files above: compare with the "Current state" excerpts; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M (about one day including 11 locales)
- **Risk**: MED (bulk writes to saved transactions; a wrong filter would recategorize the wrong rows)
- **Depends on**: plans/002-import-category-suggestions.md (uses `CategorySuggestionService.normalizedMerchant`)
- **Category**: direction
- **Planned at**: commit `84fbabdf`, 2026-09-24

## Why this matters

Statement import saves rows the user left "Uncategorized", and History has no
multi-select, so fixing 40 rows of "MAGNUM" means 40 separate edits. After this
plan, when the user edits ONE transaction and changes its category, Tenra finds
the other saved transactions with the same merchant (same normalized
description), the same type and the SAME previous category, and asks once:
"Move 39 more to Groceries?". This is a narrower and safer tool than a general
multi-select: it only proposes rows that look exactly like the one the user
just fixed.

## Current state

- `Tenra/Views/Transactions/TransactionEditCoordinator.swift` —
  `@Observable @MainActor final class TransactionEditCoordinator`. Holds
  `let transaction: Transaction` (the ORIGINAL, pre-edit value),
  `var formData: EditTransactionFormData`, `var errorMessage: String?`, and a
  private `transactionStore: TransactionStore`. `save(onSuccess:)` validates and
  then runs `performSave(onSuccess:)`; its tail (around lines 294-310) is:
  ```swift
  do {
      try await transactionStore.update(updatedTransaction, allowSeriesDetach: detachesFromSeries)

      // Link subcategories
      categoriesViewModel.linkSubcategoriesToTransaction(
          transactionId: transaction.id,
          subcategoryIds: Array(formData.selectedSubcategoryIds)
      )

      HapticManager.success()
      onSuccess()
  } catch {
      errorMessage = error.localizedDescription
      HapticManager.error()
  }
  ```
  `onSuccess` is `{ dismiss() }` from `TransactionEditView` (it closes the edit sheet).

- `Tenra/Views/Transactions/TransactionEditView.swift` — holds the coordinator
  as `@State private var coordinator` (plus a `@Bindable` alias
  `bindableCoordinator`), calls `coordinator.save { dismiss() }` from the
  toolbar checkmark and from `.dateButtonsSafeArea`. It has `.sheet` modifiers
  around lines 180-201 and no `.alert` yet.

- Alert pattern to copy — `Tenra/Views/Settings/SettingsView.swift:103-115`:
  ```swift
  .alert(
      String(localized: "alert.deleteAllData.title"),
      isPresented: $showingResetConfirmation
  ) {
      Button(String(localized: "alert.deleteAllData.confirm"), role: .destructive) { ... }
      Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
  } message: {
      Text(String(localized: "alert.deleteAllData.message"))
  }
  ```

- `Tenra/ViewModels/TransactionStore.swift`:
  - `var transactions: [Transaction]` (line 74), all saved transactions (~19k for heavy users).
  - `@ObservationIgnored private(set) var transactionById: [String: Transaction]` (line 90).
  - `@ObservationIgnored var subcategoryIdsByTransactionId: [String: [String]]` (line 219): subcategory links per transaction.
  - `func update(_ transaction: Transaction, allowSeriesDetach: Bool = false) async throws` (line 816) —
    THE canonical write path (updates state, balances, caches, persistence). Always use it.
  Store logic lives in `TransactionStore+<Topic>.swift` extension files in
  `Tenra/ViewModels/` (e.g. `TransactionStore+CategoryCRUD.swift`); follow that.

- `Tenra/Models/Transaction.swift` — `struct Transaction` with ALL `let`
  fields. Its init (line 117) takes, in order: `id, date, description, amount,
  currency, convertedAmount, type, category, subcategory, accountId,
  targetAccountId, accountName, targetAccountName, targetCurrency,
  targetAmount, recurringSeriesId, recurringOccurrenceId, createdAt`.
  There is no copy-with helper. Note `TransactionEditCoordinator` rebuilds a
  transaction WITHOUT `accountName`/`targetAccountName`/`targetCurrency`/`targetAmount`
  (it has its own reasons); the bulk path must preserve every field.

- From plan 002: `nonisolated enum CategorySuggestionService` in
  `Tenra/Services/Categories/CategorySuggestionService.swift` with
  `static func normalizedMerchant(_ text: String) -> String`
  (lowercased, non-letters → spaces, collapsed). If this file or function does
  not exist, STOP: plan 002 has not landed.

- Project rules that apply:
  - Heavy sweeps over all transactions go off the main actor via
    `Task.detached` on `Sendable` values (CLAUDE.md Red Flag 9). `Transaction`
    is `Sendable`; `[String: [String]]` is `Sendable`.
  - Editing a transaction must never mutate its `RecurringSeries`
    (Red Flag 10). This plan excludes series-linked transactions entirely.
  - 11 locales; every new key goes into all 11 `Localizable.strings`
    (Red Flag 13). A translation that reorders format arguments must use
    positional specifiers, and one string must never mix positional and plain
    specifiers (Red Flag 14). The strings below are positional in every locale.
  - No em dashes (—) in user-facing strings.
  - Test harness exemplar for a real `TransactionStore`:
    `TenraTests/ViewModels/TransactionSeriesDetachTests.swift` (`makeStore()`,
    `@MainActor struct`). Tests must retain the store.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | `** BUILD SUCCEEDED **` |
| New suites | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/SimilarTransactionsTests -only-testing:TenraTests/TransactionRecategorizeTests 2>&1 \| grep -aE "Test run with .* (passed\|failed)\|\*\* TEST (SUCCEEDED\|FAILED)"` | `** TEST SUCCEEDED **` |
| All unit tests | same with `-only-testing:TenraTests` and also grep `Executed [0-9]+ tests` | `** TEST SUCCEEDED **` |
| Locale parity | `for L in ru de es fr tr pt-BR it uk ja ko; do diff <(grep -oE '^"[^"]+"' Tenra/en.lproj/Localizable.strings) <(grep -oE '^"[^"]+"' Tenra/$L.lproj/Localizable.strings) > /dev/null && echo "$L ok" \|\| echo "$L MISMATCH"; done` | all `ok` |

## Scope

**In scope**:
- `Tenra/Services/Categories/CategorySuggestionService.swift` (ADD one function)
- `Tenra/Extensions/Transaction+WithCategory.swift` (create)
- `Tenra/ViewModels/TransactionStore+Recategorize.swift` (create)
- `Tenra/Views/Transactions/TransactionEditCoordinator.swift`
- `Tenra/Views/Transactions/TransactionEditView.swift`
- `Tenra/*.lproj/Localizable.strings` (all 11, append 4 keys)
- `TenraTests/Services/Categories/SimilarTransactionsTests.swift` (create)
- `TenraTests/ViewModels/TransactionRecategorizeTests.swift` (create)

**Out of scope**:
- History multi-select / bulk edit UI.
- Subcategory changes: transactions that have subcategory links are excluded, never relinked.
- Recurring series and their transactions (`recurringSeriesId != nil` are excluded).
- The add-transaction flow (`TransactionAddCoordinator`) — only edits of existing transactions trigger the prompt.
- `TransactionStore.update` itself and any batch-write optimization of it.

## Git workflow

- Commit directly on the current branch (`main`); do not push.
- Conventional commit, e.g. `feat(transactions): offer to recategorize same-merchant transactions after an edit`.

## Steps

### Step 1: Copy helper

Create `Tenra/Extensions/Transaction+WithCategory.swift`:

```swift
extension Transaction {
    /// Same transaction, different category. Every other stored field is
    /// carried over unchanged (including accountName/targetAccountName/
    /// targetCurrency/targetAmount and createdAt). Subcategory is cleared,
    /// because it belonged to the old category.
    nonisolated func withCategory(_ category: String) -> Transaction {
        Transaction(
            id: id, date: date, description: description, amount: amount,
            currency: currency, convertedAmount: convertedAmount, type: type,
            category: category, subcategory: nil, accountId: accountId,
            targetAccountId: targetAccountId, accountName: accountName,
            targetAccountName: targetAccountName, targetCurrency: targetCurrency,
            targetAmount: targetAmount, recurringSeriesId: recurringSeriesId,
            recurringOccurrenceId: recurringOccurrenceId, createdAt: createdAt
        )
    }
}
```

**Verify**: Build command → `** BUILD SUCCEEDED **`.

### Step 2: Pure candidate finder

Add to `CategorySuggestionService` (plan 002's file):

```swift
/// Saved transactions that look like `edited` and still carry `previousCategory`.
/// Rules (ALL must hold for a candidate):
///  - candidate.id != edited.id
///  - edited.type is .expense or .income, and candidate.type == edited.type
///  - normalizedMerchant(candidate.description) == normalizedMerchant(edited.description),
///    and that normalized string has at least 3 characters
///  - candidate.category == previousCategory
///  - candidate.recurringSeriesId == nil
///  - subcategoryLinks[candidate.id] is nil or empty
/// Result is sorted by date descending, then id, for determinism.
static func similarTransactionIds(
    to edited: Transaction,
    previousCategory: String,
    in transactions: [Transaction],
    subcategoryLinks: [String: [String]]
) -> [String]
```

Write `TenraTests/Services/Categories/SimilarTransactionsTests.swift`
(plain struct) with Test plan items 1-8.

**Verify**: New suites command (only the first suite exists yet; drop the second flag) → `** TEST SUCCEEDED **`.

### Step 3: Store-level recategorize

Create `Tenra/ViewModels/TransactionStore+Recategorize.swift`:

```swift
extension TransactionStore {
    /// Moves the given transactions from `from` to `to`, one canonical
    /// `update` each. Re-checks every row against the live store first and
    /// skips rows that disappeared or whose category is no longer `from`
    /// (the user may have edited them meanwhile). Returns the number updated.
    func recategorize(ids: [String], from: String, to: String) async -> Int {
        var updated = 0
        for id in ids {
            guard let current = transactionById[id], current.category == from else { continue }
            do {
                try await update(current.withCategory(to))
                updated += 1
            } catch {
                continue
            }
        }
        return updated
    }
}
```

Write `TenraTests/ViewModels/TransactionRecategorizeTests.swift`, `@MainActor`,
copying the `makeStore()` harness from `TransactionSeriesDetachTests.swift`
(add a second expense category "Groceries" to `store.categories`), covering
Test plan items 9-12. Seed rows with `try await store.add(...)` and keep the
returned ids (add may assign ids; read them from the returned transaction).

**Verify**: New suites command → `** TEST SUCCEEDED **`.

### Step 4: Coordinator — propose after a category change

In `TransactionEditCoordinator.swift`:

1. Add, near the Edit Form Data types:
   ```swift
   struct BulkCategoryProposal: Identifiable, Equatable {
       let id = UUID()
       let merchant: String          // edited description, trimmed, max 40 characters
       let previousCategory: String
       let newCategory: String
       let transactionIds: [String]
   }
   ```
2. Add state to the coordinator: `var bulkCategoryProposal: BulkCategoryProposal?`
   and `@ObservationIgnored private var pendingSuccess: (() -> Void)?`.
3. In `performSave`, inside the `do` block, replace the two lines
   `HapticManager.success()` / `onSuccess()` with:
   ```swift
   HapticManager.success()
   if let proposal = await makeBulkCategoryProposal(saved: updatedTransaction) {
       pendingSuccess = onSuccess
       bulkCategoryProposal = proposal
   } else {
       onSuccess()
   }
   ```
4. Add:
   ```swift
   private func makeBulkCategoryProposal(saved: Transaction) async -> BulkCategoryProposal? {
       let previous = transaction.category          // original, pre-edit value
       guard saved.type == .expense || saved.type == .income,
             !saved.category.isEmpty,
             saved.category != previous else { return nil }
       let all = transactionStore.transactions
       let links = transactionStore.subcategoryIdsByTransactionId
       let ids = await Task.detached(priority: .userInitiated) {
           CategorySuggestionService.similarTransactionIds(
               to: saved, previousCategory: previous, in: all, subcategoryLinks: links)
       }.value
       guard !ids.isEmpty else { return nil }
       let merchant = String(saved.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
       return BulkCategoryProposal(merchant: merchant, previousCategory: previous,
                                   newCategory: saved.category, transactionIds: ids)
   }

   func applyBulkCategory(_ proposal: BulkCategoryProposal) async {
       _ = await transactionStore.recategorize(
           ids: proposal.transactionIds, from: proposal.previousCategory, to: proposal.newCategory)
       finishBulkPrompt()
   }

   func finishBulkPrompt() {
       bulkCategoryProposal = nil
       let done = pendingSuccess
       pendingSuccess = nil
       done?()
   }
   ```

**Verify**: Build command → `** BUILD SUCCEEDED **`.

### Step 5: Edit view — the alert

In `TransactionEditView.swift`, add after the existing `.sheet` modifiers:

```swift
.alert(
    String(localized: "transaction.applySimilar.title"),
    isPresented: Binding(
        get: { coordinator.bulkCategoryProposal != nil },
        set: { if !$0 { coordinator.bulkCategoryProposal = nil } }
    ),
    presenting: coordinator.bulkCategoryProposal
) { proposal in
    Button(String(localized: "transaction.applySimilar.apply")) {
        Task { await coordinator.applyBulkCategory(proposal) }
    }
    Button(String(localized: "transaction.applySimilar.skip"), role: .cancel) {
        coordinator.finishBulkPrompt()
    }
} message: { proposal in
    Text(String(
        format: String(localized: "transaction.applySimilar.message"),
        proposal.merchant, proposal.transactionIds.count, proposal.newCategory
    ))
}
```

The button actions take the `proposal` value from the closure parameter, so
the binding clearing `bulkCategoryProposal` first cannot lose it.
`finishBulkPrompt()` is what finally dismisses the edit sheet (it runs the
stored `onSuccess`).

**Verify**: Build command → `** BUILD SUCCEEDED **`.

### Step 6: Localize (all 11 locales)

Append to the END of every `Tenra/<L>.lproj/Localizable.strings` using
`python3` with `io.open(path, "a", encoding="utf-8")` (never `perl -CSD`).
Translate the 9 other locales naturally. Every locale's `message` MUST contain
exactly `%1$@`, `%2$lld`, `%3$@` (positional, each once; order inside the
sentence may change) and no other `%` specifiers. No em dashes.

| Key | en | ru |
|---|---|---|
| `transaction.applySimilar.title` | Update similar transactions? | Изменить похожие операции? |
| `transaction.applySimilar.message` | “%1$@”: %2$lld more with the same category. Move them to “%3$@” as well? | «%1$@»: ещё %2$lld с той же категорией. Перенести их тоже в «%3$@»? |
| `transaction.applySimilar.apply` | Update all | Изменить все |
| `transaction.applySimilar.skip` | Only this one | Только эту |

**Verify**:
- Locale parity command → all `ok`.
- `for f in Tenra/*.lproj/Localizable.strings; do grep '^"transaction.applySimilar.message"' "$f" | grep -oE '%[0-9]\$(@|lld)' | sort | tr '\n' ' '; echo " $f"; done` → every line reads `%1$@ %2$lld %3$@`.
- `grep -n "applySimilar.title" Tenra/ru.lproj/Localizable.strings Tenra/ja.lproj/Localizable.strings` → readable text, no mojibake.
- Build command → `** BUILD SUCCEEDED **`.

### Step 7: Full test run

**Verify**: All unit tests command → `** TEST SUCCEEDED **` (re-run once on a zero-failure `TEST FAILED` flake).

## Test plan

`SimilarTransactionsTests` (plain struct):
1. Same merchant (punctuation/digit variants, e.g. "MAGNUM 01" vs "Magnum-02"), same type, same previous category → included.
2. Different merchant → excluded.
3. Same merchant, different current category → excluded.
4. Same merchant, different type (income vs expense) → excluded.
5. The edited transaction itself → excluded.
6. `recurringSeriesId != nil` → excluded.
7. Has subcategory links → excluded; empty link array → included.
8. Edited type `.internalTransfer`, or a description normalizing to fewer than 3 characters (e.g. "12 34") → empty result.

`TransactionRecategorizeTests` (`@MainActor`, real store):
9. Three uncategorized "MAGNUM" rows → `recategorize(ids:from:"",to:"Groceries")` returns 3 and all three now have category "Groceries".
10. A row whose category changed to something else before the call is skipped (return value excludes it; its category is untouched).
11. Unknown id is skipped without throwing.
12. All non-category fields (amount, currency, accountId, date, createdAt, description) are identical before and after.

## Done criteria

- [ ] Build command prints `** BUILD SUCCEEDED **`
- [ ] Both new suites pass (12+ tests); full `TenraTests` prints `** TEST SUCCEEDED **`
- [ ] Locale parity all `ok`; specifier check prints `%1$@ %2$lld %3$@` for all 11 files
- [ ] `grep -rn '—' Tenra/*.lproj/Localizable.strings | grep applySimilar` → no output
- [ ] `git status --short` lists only in-scope files (plus `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 003 updated

## STOP conditions

- `CategorySuggestionService.normalizedMerchant` does not exist (plan 002 not landed).
- The `performSave` tail no longer matches the excerpt, or `onSuccess` is no longer the thing that dismisses the edit sheet.
- `TransactionStore.update` requires extra parameters or throws for a category-only change in your tests.
- The alert does not appear or appears twice in a way you cannot explain from the code (report; do not add delays or `DispatchQueue.main.asyncAfter` hacks).
- A pre-existing test fails twice for reasons unrelated to your change.

## Maintenance notes

- Human device check: import a statement, leave several same-merchant rows uncategorized, open one from History, set a category, save: the alert must name the merchant and the count; "Update all" closes the sheet and the other rows now show the category; "Only this one" changes just the edited row.
- `recategorize` does one canonical `update` per row. For hundreds of rows this is sequential and may take a second or two; if users hit that, add a batch event to `TransactionStore` rather than bypassing `update`.
- If a merchant-keyed "rule" feature is ever built (auto-assign on future imports), it should reuse `similarTransactionIds`' matching rules so the two never disagree.
