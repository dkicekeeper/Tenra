# Plan 010: History's category filter applies every selected category and can find uncategorized transactions

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/ViewModels/TransactionPaginationController.swift Tenra/Views/History/HistoryView.swift Tenra/Views/Components/Input/CategoryFilterView.swift Tenra/Services/Transactions/TransactionQueryService.swift`
> On any change, compare with the excerpts; a mismatch is a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

The category filter sheet lets the user tick several categories and returns a `Set<String>`,
but History sends only `.first` of that Set to the fetch predicate. A Set has no order, so
with two categories ticked History shows one of them at random. Separately, the filter lists
transactions with an empty category under the localized label "Uncategorized", and History
queries `category == "Uncategorized"`, which never matches the stored empty string, so
uncategorized rows (for example after a statement import) cannot be found.

## Current state

- `Tenra/Views/Components/Input/CategoryFilterView.swift:15` `let onFilterChanged: (Set<String>?) -> Void`;
  it passes `nil` for "all" and `allSelected` (a Set) otherwise (~lines 200-206).
- `Tenra/Services/Transactions/TransactionQueryService.swift:236-240` builds the list:
  ```swift
  for transaction in transactions where transaction.type == .expense {
      let categoryName = transaction.category.isEmpty
          ? String(localized: "category.uncategorized")
          : transaction.category
      categories.insert(categoryName)
  }
  ```
  (`getIncomeCategories` does the same for income.)
- `Tenra/Views/History/HistoryView.swift:342-348`:
  ```swift
  paginationController.batchUpdateFilters(
      searchQuery: filterCoordinator.debouncedSearchText,
      searchMatchedTransactionIds: .some(matchedTxIds),
      selectedAccountId: .some(filterCoordinator.selectedAccountFilter),
      selectedCategoryId: .some(transactionsViewModel.selectedCategories?.first),
      dateRange: .some(resolvedDateRange)
  )
  ```
  and `resetFilters()` (~line 367) passes `selectedCategoryId: .some(nil)` (check the exact call).
- `Tenra/ViewModels/TransactionPaginationController.swift`:
  - lines 97-99 `var selectedCategoryId: String? { didSet { if selectedCategoryId != oldValue { scheduleFilterUpdate() } } }`
  - lines 232-252 `batchUpdateFilters(... selectedCategoryId: String?? = nil, ...)`
  - lines 285-288:
    ```swift
    if let categoryId = selectedCategoryId {
        // category stores the category name/id string on TransactionEntity
        predicates.append(NSPredicate(format: "category == %@", categoryId))
    }
    ```
  - No test references `TransactionPaginationController.selectedCategoryId`
    (the one match in `AccountActionViewModelTests` is a different type).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/HistoryCategoryPredicateTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |

## Scope

**In scope**: `Tenra/ViewModels/TransactionPaginationController.swift`, `Tenra/Views/History/HistoryView.swift`,
`TenraTests/ViewModels/HistoryCategoryPredicateTests.swift` (create).

**Out of scope**: `CategoryFilterView` UI; other screens using `TransactionFilterService.filterByCategories`
(same label issue exists there; note it, do not fix it here).

## Git workflow

Commit directly on `main`; do not push. Message:
`fix(history): apply every selected category and match uncategorized rows`.

## Steps

### Step 1: Multi-category predicate

In `TransactionPaginationController`:
- Replace `selectedCategoryId: String?` with `selectedCategoryNames: Set<String>?` (same `didSet` pattern)
  and the `batchUpdateFilters` parameter with `selectedCategoryNames: Set<String>?? = nil`.
- Add a pure helper:
  ```swift
  /// Stored names for a filter selection. The filter labels empty categories with the
  /// localized "Uncategorized" string; those rows are stored with category "".
  nonisolated static func categoryPredicate(for names: Set<String>, uncategorizedLabel: String) -> NSPredicate
  ```
  that maps `uncategorizedLabel` to `""` and returns `NSPredicate(format: "category IN %@", Array(mapped))`.
- In `applyCurrentFilters`, use it when `selectedCategoryNames` is non-nil and non-empty, with
  `uncategorizedLabel: String(localized: "category.uncategorized")`.

### Step 2: History passes the whole Set

In `HistoryView.applyFiltersToController` pass `selectedCategoryNames: .some(transactionsViewModel.selectedCategories)`;
update `resetFilters()` accordingly. Search the file for any other `selectedCategoryId` use and update it.

**Verify**: Build → SUCCEEDED; `grep -rn "selectedCategoryId" Tenra/Views/History Tenra/ViewModels/TransactionPaginationController.swift` → no output.

### Step 3: Tests

`TenraTests/ViewModels/HistoryCategoryPredicateTests.swift` (plain struct). Evaluate the predicate
against small objects with a `category` key (e.g. `NSDictionary`s: `predicate.evaluate(with: ["category": "Food"])`):
1. `{"Food","Taxi"}` matches "Food" and "Taxi", not "Gifts".
2. `{"Uncategorized"}` (the passed label) matches `""`, not "Food".
3. `{"Food","Uncategorized"}` matches both "Food" and `""`.

**Verify**: Suite → SUCCEEDED; full TenraTests → 0 failed.

## Done criteria

- [ ] Build SUCCEEDED; 3 predicate tests pass; full TenraTests 0 failed
- [ ] `grep -rn "selectedCategories?.first" Tenra/Views/History` → no output
- [ ] `git status --short` lists only in-scope files (plus `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 010 updated

## STOP conditions

- The FRC predicate is built somewhere other than `applyCurrentFilters`.
- Another screen depends on `TransactionPaginationController.selectedCategoryId` in a way that needs design changes.

## Maintenance notes

- Device check: tick two categories in History: both appear; tick "Uncategorized": imported
  rows without a category appear.
- `TransactionFilterService.filterByCategories` (used by other lists) has the same label issue;
  reuse the same mapping if those screens expose "Uncategorized".
