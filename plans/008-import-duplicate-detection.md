# Plan 008: Statement import flags rows that are already in Tenra (including subscription occurrences) and leaves them unchecked

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/Views/Import Tenra/Services/Import Tenra/*.lproj/Localizable.strings`
> Plan 007 may have changed `addSelectedTransactions` in `ImportTransactionPreviewView.swift`;
> that is expected. Other changes: compare with the excerpts; a mismatch is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (false positives hide real rows by default; they stay selectable)
- **Depends on**: none (coordinate with 007: both edit `ImportTransactionPreviewView.swift`; run sequentially)
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

The CSV import skips duplicates (`TransactionFingerprint`), the PDF statement import does
not: importing an overlapping or the same statement twice doubles spending. Worse, a
subscription series auto-generates a transaction on each due date
(`RecurringTransactionGenerator` dedupes only its own occurrences), so the bank charge for the
same subscription arrives a second time through the statement. Every Pro user who has
subscriptions and imports statements over-reports those charges every month.
(Loans removed auto-generation for exactly this reason: `docs/domains/loans.md`, "No Auto-Reconciliation".)

After this plan the review screen marks such rows ("Looks already added" / "Already counted
as a subscription payment"), leaves them unchecked by default, and the user can still tick them.

## Current state

- `Tenra/Views/Import/PDFImportCoordinator.swift` — after `DocumentImportService.importStatement`
  it maps rows with `ParsedTransactionMapper.transactions(from:defaultCurrency:)`, computes
  `suggestedCategories` via `CategorySuggestionProvider.suggestions(...)` (history built in
  `Task.detached`), stores `parsedTransactions`, and presents `ImportTransactionPreviewView(
  transactionsViewModel:accountsViewModel:transactions:customCategories:suggestedCategories:)`.
  Mirror that pattern for duplicates: compute once in the coordinator, pass a dictionary in.
- `Tenra/Views/Import/ImportTransactionPreviewView.swift`:
  - `static func availableAccounts(for:regularAccounts:) -> [Account]` (currency match);
    the default account for a row is `availableAccounts(...).first`.
  - `.onAppear` preselects every row that has an account (`selectable = transactions.filter { !availableAccounts(for: $0).isEmpty }`)
    and fills `accountMapping`. "Select All" does the same.
  - `ImportTransactionPreviewRow` shows a warning line when there is no matching account:
    ```swift
    if hasNoMatchingAccount {
        Text(String(localized: "transactionPreview.noMatchingAccount"))
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.warning)
            .padding(.leading, AppSpacing.xl)
    }
    ```
    Copy this for the duplicate line.
- `Tenra/Models/TransactionFingerprint.swift` — the CSV rule (date, amount, lowercased description, accountId).
  Bank statement descriptions ("STARBUCKS 123") rarely equal manual ones ("Кофе"), so this plan
  matches on account + type + amount + date window instead, and does not require equal descriptions.
- Existing transactions: `TransactionStore.transactions` (~19k for heavy users). Any sweep must
  run off the main actor (`Task.detached` on the `Sendable` array; `Transaction` is `Sendable`), per CLAUDE.md Red Flag 9.
- `Transaction.recurringSeriesId` marks series occurrences; `Transaction.date` is `"yyyy-MM-dd"`.
  Use `FastDateParser.date(from:)` (`Tenra/Utils/FastDateParser.swift`) for date math in loops,
  never `DateFormatter` (Red Flag 15).
- Localization: 11 `Tenra/*.lproj/Localizable.strings`; append new keys with `python3`
  (`io.open(..., encoding="utf-8")`), never `perl -CSD`; no em dashes (—) in any value.
- Test exemplar: `TenraTests/Services/Categories/SimilarTransactionsTests.swift` (pure, plain struct).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/ImportDuplicateDetectorTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| Locale parity | `for L in ru de es fr tr pt-BR it uk ja ko; do diff <(grep -oE '^"[^"]+"' Tenra/en.lproj/Localizable.strings \| sort) <(grep -oE '^"[^"]+"' Tenra/$L.lproj/Localizable.strings \| sort) >/dev/null && echo "$L ok" \|\| echo "$L MISMATCH"; done` | all ok |

## Scope

**In scope**: `Tenra/Services/Import/ImportDuplicateDetector.swift` (create),
`Tenra/Views/Import/PDFImportCoordinator.swift`, `Tenra/Views/Import/ImportTransactionPreviewView.swift`,
`Tenra/*.lproj/Localizable.strings` (2 keys), `TenraTests/Services/Import/ImportDuplicateDetectorTests.swift` (create).

**Out of scope**: merging/linking the imported row into the series occurrence (direction item);
the CSV path; receipts; deleting anything.

## Git workflow

Commit directly on `main`; do not push. Message:
`feat(import): flag statement rows already in Tenra, including subscription occurrences`.

## Steps

### Step 1: Pure detector

`Tenra/Services/Import/ImportDuplicateDetector.swift`:
```swift
nonisolated enum ImportDuplicateDetector {
    enum Reason: Sendable, Equatable {
        case alreadyAdded(existingId: String)
        case subscriptionOccurrence(existingId: String, seriesId: String)
    }
    /// - importedAccounts: imported transaction id → the account the review screen will
    ///   assign by default. Rows without an account are never flagged.
    static func detect(
        imported: [Transaction],
        importedAccounts: [String: String],
        existing: [Transaction]
    ) -> [String: Reason]
}
```
Rules (an existing transaction can be claimed by at most one imported row; process imported
rows in date order and pick the closest-date unclaimed candidate):
- Candidate must have the same `accountId` as the imported row's assigned account, the same
  `type`, and the same `currency`.
- `.subscriptionOccurrence` if `candidate.recurringSeriesId != nil`, type `.expense`,
  `|amount diff| <= 5% of the imported amount`, and date within ±3 days.
- `.alreadyAdded` otherwise if `|amount diff| < 0.005` and date within ±1 day.
- Prefer a subscription match over a plain match when both exist.
Build a dictionary from `(accountId, type, currency)` to the existing transactions of that
bucket once, so the whole detection is O(existing + imported × bucket), not O(existing × imported).

**Verify**: Build → SUCCEEDED.

### Step 2: Tests

`TenraTests/Services/Import/ImportDuplicateDetectorTests.swift` (plain struct) with the Test plan cases.

**Verify**: Suite → SUCCEEDED.

### Step 3: Compute in the coordinator

In `PDFImportCoordinator.analyzePDF`, after `mapped` is built: compute
`importedAccounts` with `ImportTransactionPreviewView.availableAccounts(for:regularAccounts: accountsViewModel.regularAccounts).first?.id`,
then run `ImportDuplicateDetector.detect(...)` inside
`Task.detached(priority: .userInitiated) { ... }.value` with
`transactionsViewModel.transactionStore?.transactions ?? []`. Store the result in
`@State private var duplicateReasons: [String: ImportDuplicateDetector.Reason] = [:]` and pass it
to the preview as a new `var duplicateReasons: [String: ImportDuplicateDetector.Reason] = [:]`
property (default value keeps the two `#Preview`s compiling).

**Verify**: Build → SUCCEEDED.

### Step 4: Review screen

In `ImportTransactionPreviewView`:
- `.onAppear` and "Select All": do not preselect rows whose id is in `duplicateReasons`
  (they stay selectable by tapping).
- Pass `duplicateReason: duplicateReasons[transaction.id]` to the row. In the row, under the
  existing no-account warning, show one caption line in `AppColors.warning`:
  `.alreadyAdded` → `transactionPreview.possibleDuplicate`,
  `.subscriptionOccurrence` → `transactionPreview.coveredBySubscription`.

**Verify**: Build → SUCCEEDED; `-only-testing:TenraTests/ImportTransactionPreviewViewTests` → SUCCEEDED.

### Step 5: Strings (all 11 locales)

| Key | en | ru |
|---|---|---|
| `transactionPreview.possibleDuplicate` | Looks already added | Похоже, уже добавлена |
| `transactionPreview.coveredBySubscription` | Already counted as a subscription payment | Уже учтена как платёж по подписке |

Translate de, es, fr, tr, pt-BR, it, uk, ja, ko naturally (match each file's existing formality:
de uses "Sie", fr "vous", es/it "tú", pt-BR "você"). No format specifiers, no em dashes.

**Verify**: Locale parity → all ok; `grep -n "possibleDuplicate" Tenra/ru.lproj/Localizable.strings Tenra/ja.lproj/Localizable.strings` shows readable text; Build → SUCCEEDED; full TenraTests → 0 failed.

## Test plan

1. Same account/type/currency/amount, date +1 day → `.alreadyAdded`.
2. Same but date +2 days → not flagged.
3. Different account → not flagged.
4. Existing series occurrence (expense, `recurringSeriesId` set), amount +3%, date −2 days → `.subscriptionOccurrence`.
5. Series occurrence with amount +10% → not flagged as subscription (and not as plain duplicate).
6. Two identical imported rows vs one existing → only one flagged (claiming).
7. Row with no assigned account → never flagged.
8. Both a plain and a subscription candidate exist → `.subscriptionOccurrence` wins.

## Done criteria

- [ ] Build SUCCEEDED; detector suite (8 tests) passes; full TenraTests 0 failed
- [ ] Locale parity all ok; 2 new keys in each of the 11 files
- [ ] `git status --short` lists only in-scope files (plus `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 008 updated

## STOP conditions

- `PDFImportCoordinator` no longer builds rows via `ParsedTransactionMapper` before presenting the review.
- The detection cannot run off the main actor without making non-Sendable types Sendable.
- Existing import tests fail.

## Maintenance notes

- Device check: import the same PDF twice: the second time every row is unchecked and labelled.
  With a Netflix subscription on the same card account, the Netflix row is labelled as a subscription payment.
- Tolerances (±1 day plain, ±3 days / ±5% subscription) are guesses tuned for Kaspi posting delays;
  adjust in one place (`ImportDuplicateDetector`).
- The root fix for subscriptions (occurrences stay "expected" until a real charge merges in) is a
  separate design; this plan only prevents the double count at import time.
