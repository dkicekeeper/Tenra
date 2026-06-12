# Plan 003: Add CSV export→import round-trip tests pinning the column contract

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 4392be3..HEAD -- Tenra/Services/CSV/ Tenra/Models/CSVRow.swift Tenra/Models/Transaction.swift`
> If any in-scope-adjacent file changed since this plan was written, compare
> the "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (test-only — no production code changes)
- **Depends on**: none (001 recommended first for CI coverage)
- **Category**: tests
- **Planned at**: commit `4392be3`, 2026-06-11

## Why this matters

CSV export/import is this app's only offline backup-and-migration path for transactions, and its column contract is intricate: **income rows deliberately swap columns** (the `account` column carries the category and `targetAccount` carries the account name — the import side reads them back through `CSVRow.effectiveAccountValue`/`effectiveCategoryValue`), transfers reuse `targetCurrency`/`targetAmount` differently than non-transfers, and subcategories are comma-joined inside an escaped field. None of this is round-trip tested — the only CSV tests are one durability-gate unit test and parse-type tests. A silent export/import asymmetry means users who export and re-import **lose or corrupt data** with no error. This plan adds string-level round-trip tests that pin the contract.

## Current state

Files (production — read, do not modify):

- `Tenra/Services/CSV/CSVExporter.swift` — `nonisolated class CSVExporter`, entry point:

```swift
// CSVExporter.swift:18
static func exportTransactions(
    _ transactions: [Transaction],
    accounts: [Account],
    subcategoryLinks: [TransactionSubcategoryLink] = [],
    subcategories: [Subcategory] = []
) -> String
```

Header row: `date,type,amount,currency,account,category,subcategories,note,targetAccount,targetCurrency,targetAmount`. Amounts exported as `String(format: "%.2f", ...)`. The income swap, verbatim:

```swift
// CSVExporter.swift:47-56
if transaction.type == .income {
    // Swap: account column = category (import reads as income category)
    accountName = escapeCSVField(transaction.category)
    category = ""
    // targetAccount = actual account name (import reads as income account)
    let resolvedAccount = transaction.accountId.flatMap { accountById[$0] } ?? ""
    targetAccountName = escapeCSVField(resolvedAccount)
}
```

- `Tenra/Services/CSV/CSVParsingService.swift` — `class CSVParsingService: CSVParsingServiceProtocol` with `func parseContent(_ content: String) async throws -> CSVFile` (line 25) — the import-side parser. (`CSVImporter.parseCSV(from url:)` is the URL-based sibling; use `parseContent` to avoid file I/O.)
- `Tenra/Models/CSVRow.swift` — `struct CSVRow` with `effectiveAccountValue` (line 66) and `effectiveCategoryValue` (line 90) — the import-side accessors that undo the income swap.
- `struct CSVFile` is declared in `Tenra/Services/CSV/CSVImporter.swift:11`.
- `Tenra/Models/Transaction.swift` — `Transaction`, `Account` structs (note: there is NO `Models/Account.swift`; `Account` lives here).
- `docs/domains/csv.md` — the round-trip rules doc. **Read it before writing any test** — it is the authority on intended behavior; where the doc and code disagree, that's a STOP condition.

Existing tests (patterns to follow):

- `TenraTests/Services/CSV/CSVImportDurabilityTests.swift` — swift-testing style exemplar: `@MainActor @Suite struct`, `@Test`, `#expect`.
- `TenraTests/Services/CSV/CSVParseTypeTests.swift` — existing type-parsing coverage; do not duplicate it.
- For `Transaction`/`Account` fixture construction: `grep -rn "Transaction(" TenraTests/ | head` and mirror an existing builder (e.g. in `SummaryContributionTests.swift` or `CoreDataRoundTripTests.swift`). Read `Tenra/Models/Transaction.swift` for the memberwise init — do not invent parameter names.

Repo conventions: swift-testing (`@Suite`/`@Test`/`#expect`); suites constructing MainActor-isolated types need `@MainActor`; test filenames unique in the target; files on disk auto-join the target (no pbxproj edits); suite-level `-only-testing` filtering only.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \| grep -E "error:" \| head -30` | no output |
| New suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/CSVRoundTripTests 2>&1 \| grep -aE "Test case .* (passed\|failed)\|\*\* TEST (SUCCEEDED\|FAILED)"` | all `passed` |
| Full unit suite | same with `-only-testing:TenraTests` | `** TEST SUCCEEDED **` |

## Scope

**In scope** (the only files you should create/modify):
- `TenraTests/Services/CSV/CSVRoundTripTests.swift` (create)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch):
- ALL production code, including `Tenra/Services/CSV/**` and `Tenra/Models/**`. If a round-trip test exposes a genuine export/import asymmetry, **report it as a finding** (STOP condition) — fixing the contract is a separate, deliberate change because existing exported files in the wild depend on current behavior.
- The full import pipeline (`CSVImportCoordinator`, `EntityMappingService`) — it requires a live `TransactionStore` + `ImportCacheManager`; integration-level round-trip is explicitly deferred (see Maintenance notes).

## Git workflow

- Work directly on `main` (owner's preference). Do **NOT** push.
- Single commit; message style: short descriptive line + `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Steps

### Step 1: Read the contract

Read `docs/domains/csv.md` end to end, then `CSVExporter.swift` (all ~150 lines), `CSVRow.swift`, and `CSVParsingService.parseContent`. Write down (as comments at the top of the new test file) the column contract for each transaction type: expense, income (swap!), internalTransfer (target columns = real target data), and whatever other types `exportTypeName` distinguishes.

**Verify**: you can state, per type, which CSV column carries account / category / target.

### Step 2: Build the fixture set

In `TenraTests/Services/CSV/CSVRoundTripTests.swift`, create a `@MainActor @Suite struct CSVRoundTripTests` with a static fixture builder producing:

- 2 accounts (`Account`), e.g. "Kaspi" (KZT) and "Wise" (USD) — names chosen to include a non-ASCII string ("Каспи") in at least one place, since the app is EN+RU.
- Transactions covering: plain expense; expense with 2 subcategories (via `TransactionSubcategoryLink` + `Subcategory` fixtures); income (the swap case); internal transfer KZT→USD with distinct `targetAmount`/`targetCurrency`; a note containing a comma and a double-quote (escaping case); an amount with non-trivial cents (e.g. `1234.56`).

Mirror the construction style of existing fixtures found via `grep -rn "Transaction(" TenraTests/`.

**Verify**: build → no errors.

### Step 3: Round-trip tests (export → parse → compare)

Each `@Test` follows the same shape:

```swift
let csv = CSVExporter.exportTransactions(fixtures, accounts: accounts,
                                         subcategoryLinks: links, subcategories: subs)
let file = try await CSVParsingService().parseContent(csv)
// then assert on file's rows / CSVRow accessors
```

Write these tests:

1. **Row count and header** — parsed row count == fixture count; header columns match the documented 11-column order exactly.
2. **Expense fidelity** — for the plain expense row: date, type, amount (`%.2f` string), currency, account name, category, note all survive the trip (compare via the parsed row / `CSVRow` accessors).
3. **Income swap round-trips** — for the income row: `effectiveAccountValue` returns the *account name* and `effectiveCategoryValue` returns the *category*, i.e. the import accessors exactly undo the export swap. This is the single most important test in the plan.
4. **Transfer target columns** — the transfer row's targetAccount resolves to the target account's name; targetCurrency/targetAmount match the fixture.
5. **Subcategories join/split** — the 2-subcategory expense exports a comma-joined field that parses back into the same 2 names (order-insensitive comparison is fine if the parser splits on commas).
6. **Escaping survives** — the comma-and-quote note round-trips byte-identical.
7. **Empty input** — exporting `[]` then parsing yields header-only / zero rows without throwing.

Note: if `CSVRow`'s init or `CSVFile`'s shape make the accessor-level assertions awkward, assert on raw parsed column values instead — the contract being pinned is *export column i ↔ import meaning i*, however it's most directly expressed.

**Verify**: suite-filter test command → 7 `passed`, `** TEST SUCCEEDED **`.

### Step 4: Full regression run + commit

**Verify**: full `TenraTests` run → `** TEST SUCCEEDED **`; `git status` shows only the new test file (+ plans/README.md).

## Test plan

This plan *is* a test plan — 7 new tests in `TenraTests/Services/CSV/CSVRoundTripTests.swift`, modeled structurally on `CSVImportDurabilityTests.swift`.

## Done criteria

- [ ] `TenraTests/Services/CSV/CSVRoundTripTests.swift` exists with ≥ 7 `@Test` functions
- [ ] Suite-filter run → `** TEST SUCCEEDED **` and the per-test lines show `passed` (not 0 tests run — if the output shows no `Test case` lines, the suite name filter is wrong; re-check the type name)
- [ ] Full `-only-testing:TenraTests` run → `** TEST SUCCEEDED **`
- [ ] Zero production files modified (`git diff --name-only` contains only `TenraTests/` and `plans/`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- A round-trip test fails because export and import genuinely disagree (e.g. the income swap is asymmetric, escaping is lossy, transfer columns don't map back). **That is the bug this plan exists to detect** — report the exact row in/out, do not "fix" either side and do not weaken the assertion to make it pass.
- `docs/domains/csv.md` contradicts the code's actual behavior — report the discrepancy.
- `Transaction`/`Account` fixture construction requires more than ~20 lines per fixture (the model may have grown required dependencies) — report instead of stubbing half-valid objects.
- `CSVParsingService.parseContent` requires actor/context setup the exemplar tests don't show.

## Maintenance notes

- These tests pin the **string-level** contract. The full pipeline (`EntityMappingService.convertRow` → `TransactionStore`) — where account/category *resolution and creation* happens — is still untested end-to-end; that's a deliberate deferral because it needs a live `TransactionStore` fixture (see CLAUDE.md's warning that `AccountsViewModel.transactionStore` is weak and stores must be retained by tests). A follow-up plan can build on these fixtures.
- Any future change to the CSV column order, the income swap, or `escapeCSVField` will (correctly) break these tests; the change must then ship with an import-side fallback for old files — `CSVRow` already has "legacy fallback chains" per the code comments, so extend those rather than breaking old exports.
