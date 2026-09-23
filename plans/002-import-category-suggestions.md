# Plan 002: Imported statement rows and scanned receipts get a category (suggested, editable) instead of landing uncategorized

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 84fbabdf..HEAD -- Tenra/Views/Import Tenra/Services/Import/ParsedTransactionMapper.swift Tenra/Services/Voice/VoiceInputParser.swift Tenra/Services/Intents/TransactionDraftService.swift Tenra/Services/ML docs/domains/import.md`
> If any of these changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M (1.5-2 days)
- **Risk**: MED (touches the import save path; a wrong mapping could save a transaction with the wrong category, never the wrong amount or account)
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `84fbabdf`, 2026-09-24

## Why this matters

PDF statement import and the receipt scanner are the headline Pro features of
release 1.2, and both save every transaction with an EMPTY category.
Category aggregates skip empty categories, so imported spending is invisible in
the home category breakdown and never counts toward any budget: a user who pays
for Pro and imports a month of spending sees their budgets say "within limit"
while they are not. Fixing a 100-row import today means 100 separate edits.

After this plan: every expense/income row in the import review screen and the
receipt confirmation screen shows a category picker, pre-filled with a
suggestion from (1) the user's own history for the same merchant, (2) a small
curated list of well-known merchants, (3) the existing voice-input keyword
dictionary. Choosing a category for one row fills the other rows of the same
merchant in that import. Rows with no suggestion stay "Uncategorized", exactly
as today, so the change can only add information.

## Current state

- `Tenra/Services/Import/ParsedTransactionMapper.swift:53-55` — every statement row gets an empty category:
  ```swift
  private static func category(for type: TransactionType) -> String {
      type == .internalTransfer ? TransactionType.transferCategoryName : ""
  }
  ```
  Leave this file unchanged: the mapper stays "recognition output → Transaction";
  suggestions are applied in the review UI.

- `Tenra/Views/Import/PDFImportCoordinator.swift` — orchestrates import. Holds
  `transactionsViewModel`, `categoriesViewModel`, `accountsViewModel`.
  Lines 198-204 build the rows and open the review sheet:
  ```swift
  } else {
      parsedTransactions = ParsedTransactionMapper.transactions(
          from: outcome.statement,
          defaultCurrency: baseCurrency
      )
      showingTransactionPreview = true
  }
  ```
  Lines 145-151 create the review sheet:
  ```swift
  private var transactionPreviewSheet: some View {
      ImportTransactionPreviewView(
          transactionsViewModel: transactionsViewModel,
          accountsViewModel: accountsViewModel,
          transactions: parsedTransactions
      )
  }
  ```
  Lines 74-81 create the receipt sheet:
  ```swift
  ReceiptConfirmationView(
      draft: draft,
      baseCurrency: transactionsViewModel.transactionStore?.baseCurrency ?? "KZT",
      transactionsViewModel: transactionsViewModel,
      accountsViewModel: accountsViewModel
  )
  ```

- `Tenra/Views/Import/ImportTransactionPreviewView.swift` — review screen.
  State: `@State private var selectedTransactions: Set<String>` and
  `@State private var accountMapping: [String: String] // transactionId -> accountId`.
  Save (lines 181-220) rebuilds each transaction with the chosen account and
  `category: transaction.category`. The row type `ImportTransactionPreviewRow`
  (same file, line 225+) shows a checkbox, a `TransactionCardView`, and a
  per-row account `Picker` with `.pickerStyle(MenuPickerStyle())` (lines 299-310) —
  **copy that picker's shape for the category picker**. The row's style is
  computed with an empty category list on purpose today:
  ```swift
  private var styleData: CategoryStyleData {
      CategoryStyleHelper.cached(category: transaction.category, type: transaction.type, customCategories: [])
  }
  ```
  The screen is only constructed by `PDFImportCoordinator` and by 2 `#Preview`
  blocks at the bottom of the file.

- `Tenra/Views/Import/ReceiptConfirmationView.swift` — receipt confirmation.
  Shows merchant/total/date `InfoRow`s, an `AccountSelectorView`, and an Add
  button. Saves with `category: ""` (line 154, inside `makeTransaction(accountId:)`).
  Its `#Preview` (bottom of file) builds it with `coordinator.transactionsViewModel`
  and `coordinator.accountsViewModel`.

- `Tenra/Views/VoiceInput/VoiceInputConfirmationView.swift:150-164` — the
  exemplar for a category chooser on a confirmation screen:
  ```swift
  CategorySelectorView(
      categories: categoriesViewModel.customCategories
          .filter { $0.type == selectedType }
          .sortedByOrder()
          .map { $0.name },
      type: selectedType,
      customCategories: categoriesViewModel.customCategories,
      selectedCategory: $selectedCategoryName,
      onSelectionChange: { _ in validateCategory() },
      emptyStateMessage: String(localized: "transactionForm.noCategories"),
      warningMessage: categoryWarning
  )
  ```

- `Tenra/Services/Intents/TransactionDraftService.swift:161-196` —
  `static func resolveCategory(named:type:in:) -> CategoryResolution` maps a
  raw category name onto the user's own categories: exact, case-insensitive,
  substring (min 3 chars), then the localized "Other" category, then `""`.
  REUSE it; do not write another name matcher. Note it returns the "Other"
  category as a fallback: a suggestion that resolves to Other (or to `""`)
  must be treated as "no suggestion".

- `Tenra/Services/Voice/VoiceInputParser.swift` — `class VoiceInputParser`
  (MainActor by project default). Built with
  `VoiceInputParser(categoriesViewModel:accountsViewModel:transactionsViewModel:)`.
  Has a ~300-entry multilingual keyword map
  `private lazy var categoryMap: [String: (category: String, subcategory: String?)]`
  (line 84) and `private lazy var sortedCategoryKeys: [String]` (line 352,
  longest first). Its `parseCategory` uses plain `text.contains(keyword)` and
  falls back to "Other" — unusable as-is for suggestions. The map targets
  hardcoded names such as `"Транспорт"`. **Do not edit or reorder the map**:
  a duplicate key in a dictionary literal compiles but crashes at runtime
  (CLAUDE.md Red Flag 16).

- `Tenra/Services/Onboarding/CategoryPreset.swift` — `CategoryPreset.defaultExpense`,
  15 presets with stable ids (`groceries`, `dining`, `transport`, `housing`,
  `utilities`, `health`, `clothing`, `entertainment`, `travel`, `education`,
  `gifts`, `subscriptions`, `pets`, `services`, `other`) and `nameKey`
  (e.g. `"onboarding.preset.groceries"`). A user's categories created in
  onboarding carry the localized name:
  `String(localized: String.LocalizationValue(preset.nameKey))`
  (precedent: `Tenra/ViewModels/OnboardingViewModel.swift:145`).

- `Tenra/Services/ML/CategoryMLPredictor.swift` — dead stub: `predict` always
  returns `(nil, 0.0)`, and `grep -rn "CategoryMLPredictor" Tenra --include='*.swift'`
  finds only the file itself. It is replaced by this plan.

- Why empty categories are invisible: `Tenra/ViewModels/TransactionStore+CategoryIndex.swift:318`
  (`guard !tx.category.isEmpty else { return false }`) and
  `Tenra/ViewModels/TransactionStore+Computed.swift:54`.

- Concurrency conventions (read `docs/concurrency.md` §DataSnapshot if unsure):
  project default isolation is MainActor. Any sweep over all transactions
  (~19k) must run off the main actor via `Task.detached` on a `Sendable` value
  (CLAUDE.md Red Flag 9). `Transaction` is `Sendable`. Pure helper types that
  must run off-main are declared `nonisolated enum`, like
  `ParsedTransactionMapper` (`nonisolated enum ParsedTransactionMapper`).

- Test conventions: swift-testing. Exemplar:
  `TenraTests/Services/Import/StatementInterpreterTests.swift`. Suites that
  call MainActor APIs (`TransactionDraftService`, `VoiceInputParser`) must be
  `@MainActor`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | `** BUILD SUCCEEDED **` |
| Suite tests | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/CategorySuggestionServiceTests -only-testing:TenraTests/CategorySuggestionProviderTests 2>&1 \| grep -aE "Test run with .* (passed\|failed)\|\*\* TEST (SUCCEEDED\|FAILED)"` | `** TEST SUCCEEDED **` |
| All unit tests | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests 2>&1 \| grep -aE "Test run with .* (passed\|failed)\|Executed [0-9]+ tests\|\*\* TEST (SUCCEEDED\|FAILED)"` | `** TEST SUCCEEDED **` |

`-only-testing` takes suite TYPE names; method-level filters silently run 0
tests. A `** TEST FAILED **` with zero failing test names is a known harness
flake: re-run once.

## Suggested executor toolkit

- `swift-testing-expert:swift-testing-expert` for Steps 1-3.
- `swiftui-expert:swiftui-expert-skill` for Steps 5-6.
- `swift-concurrency:swift-concurrency` if the `Task.detached` capture in Step 3 produces isolation errors.

## Scope

**In scope**:
- `Tenra/Services/Categories/CategorySuggestionService.swift` (create)
- `Tenra/Services/Categories/CategorySuggestionProvider.swift` (create)
- `Tenra/Services/Voice/VoiceInputParser.swift` (ADD one internal method only)
- `Tenra/Views/Import/ImportTransactionPreviewView.swift`
- `Tenra/Views/Import/ReceiptConfirmationView.swift`
- `Tenra/Views/Import/PDFImportCoordinator.swift`
- `Tenra/Services/ML/CategoryMLPredictor.swift` (delete) and the then-empty `Tenra/Services/ML/` folder
- `TenraTests/Services/Categories/CategorySuggestionServiceTests.swift` (create)
- `TenraTests/Services/Categories/CategorySuggestionProviderTests.swift` (create)
- `docs/domains/import.md` (append a short section)

**Out of scope** (do NOT touch):
- `ParsedTransactionMapper.swift` and its tests — recognition output stays uncategorized.
- The CSV import flow (`Services/CSV/**`, `Views/CSV/**`) — it has its own category column mapping.
- `VoiceInputParser.categoryMap` contents, `parseCategory`, `parse`, `parseMulti` — voice behavior must not change.
- Subcategories — suggestions set the category only.
- Apple Intelligence / FoundationModels classification — deferred (see Maintenance notes).
- Any persistence of "learned" merchants: the history tier derives from saved transactions, so no new storage is needed.
- `Localizable.strings` — this plan needs no new keys (it reuses `"transaction.category"` and `"category.uncategorized"`, both present in all 11 locales). If you think you need a new string, STOP.

## Git workflow

- Commit directly on the current branch (`main`); do not push.
- Conventional commits, e.g. `feat(import): suggest categories for imported statement rows and receipts`.
- Suggested commits: (1) service + tests, (2) provider + parser method + tests, (3) UI wiring, (4) dead-code removal + docs.

## Steps

### Step 1: Pure suggestion core

Create `Tenra/Services/Categories/CategorySuggestionService.swift`:

```swift
import Foundation

/// Merchant → category suggestion core. Pure and `nonisolated` so the history
/// sweep can run in `Task.detached` (CLAUDE.md Red Flag 9).
nonisolated enum CategorySuggestionService {

    /// Lowercase, `ё`→`е`, every non-letter (digits, punctuation, symbols)
    /// becomes a space, whitespace collapsed, trimmed.
    /// "YANDEX.GO" → "yandex go"; "MAGNUM CASH&CARRY 123" → "magnum cash carry";
    /// "APPLE.COM/BILL" → "apple com bill"; "12345" → "".
    static func normalizedMerchant(_ text: String) -> String

    /// Word-aware keyword test on an already-normalized merchant string.
    /// The keyword is normalized with `normalizedMerchant` first; an empty
    /// keyword never matches. Keywords of <= 4 characters must equal a whole
    /// word ("abo" must not match "about", "cine" must not match "medicine");
    /// longer keywords must start at a word boundary ("yandex" matches
    /// "yandex go", "starbucks" matches "starbucks coffee").
    static func matches(keyword: String, inNormalized merchant: String) -> Bool

    struct HistoryIndex: Sendable, Equatable {
        /// key = "\(type.rawValue)|\(normalizedMerchant)" → category → stats
        var stats: [String: [String: Stat]] = [:]
        struct Stat: Sendable, Equatable { var count: Int; var latestDate: String }
    }

    /// Counts, per (type, normalized description), how often each non-empty
    /// category was used. Only `.expense` and `.income` rows count; rows whose
    /// normalized description is shorter than 3 characters are skipped.
    static func buildHistoryIndex(from transactions: [Transaction]) -> HistoryIndex

    /// Most-used category for this merchant and type; ties → the category with
    /// the later `latestDate` (dates are "yyyy-MM-dd", so string comparison
    /// works); still tied → alphabetically first. nil when unknown.
    static func historyCategory(for description: String, type: TransactionType, in index: HistoryIndex) -> String?

    /// Curated merchant keywords → CategoryPreset id. An ARRAY of pairs, not a
    /// dictionary literal: a duplicate key in a dictionary literal crashes at
    /// runtime (CLAUDE.md Red Flag 16).
    static let brandPresets: [(keyword: String, presetId: String)] = [ ... ]

    /// Longest matching brand keyword wins. Returns a preset id or nil.
    static func brandPresetId(for description: String) -> String?
}
```

Implementation notes:
- `normalizedMerchant`: map `unicodeScalars` with `CharacterSet.letters.contains($0)`
  to the scalar or to a space, then `split(separator: " ").joined(separator: " ")`.
- `brandPresetId`: normalize once, iterate `brandPresets` sorted by
  `keyword.count` descending (sort once into a `static let`), return the first
  `matches(keyword:inNormalized:)` hit.
- Seed `brandPresets` with exactly this list (lowercase; the matcher normalizes
  punctuation, so write them as plain words):
  - groceries: `magnum`, `galmart`, `anvar`, `arbuz`, `metro cash`, `carrefour`, `lidl`, `aldi`, `walmart`, `costco`, `kroger`, `whole foods`, `trader joe`, `auchan`, `ашан`, `пятерочка`, `перекресток`, `магнум`
  - dining: `starbucks`, `mcdonald`, `kfc`, `burger king`, `dodo pizza`, `додо пицца`, `domino`, `papa john`, `coffee boom`, `glovo`, `wolt`, `yandex eda`, `yandex eats`
  - transport: `yandex go`, `yandex taxi`, `uber`, `bolt`, `indrive`, `onay`, `shell`, `helios`, `qazaq oil`, `sinooil`
  - subscriptions: `netflix`, `spotify`, `apple com bill`, `icloud`, `youtube premium`, `google one`, `yandex plus`, `kinopoisk`, `openai`, `chatgpt`
  - utilities: `kazakhtelecom`, `beeline`, `kcell`, `tele2`, `altel`, `alseco`
  - health: `europharma`, `invitro`, `аптека`
  - entertainment: `kinopark`, `chaplin`, `steam`, `playstation`
  - travel: `air astana`, `fly arystan`, `airbnb`, `booking com`, `aviasales`
  - clothing: `zara`, `lc waikiki`, `defacto`, `uniqlo`, `bershka`

Then write `TenraTests/Services/Categories/CategorySuggestionServiceTests.swift`
(plain `struct`, not `@MainActor`) covering the cases in the Test plan, items 1-9.

**Verify**: Suite tests command (only `CategorySuggestionServiceTests` exists so far; drop the second `-only-testing` flag) → `** TEST SUCCEEDED **`.

### Step 2: Keyword hook on the voice parser

In `Tenra/Services/Voice/VoiceInputParser.swift`, add ONE internal method
next to `parseCategory` (do not change any other code):

```swift
/// Suggestion-only lookup into `categoryMap` for imported merchant strings.
/// Unlike `parseCategory`, it never falls back to "Other" and matches whole
/// words (CategorySuggestionService.matches), so "medicine" does not hit "cine".
/// Returns the map's raw category name (e.g. "Транспорт"); the caller resolves
/// it against the user's categories.
func keywordCategory(in text: String) -> String? {
    let merchant = CategorySuggestionService.normalizedMerchant(text)
    guard !merchant.isEmpty else { return nil }
    for keyword in sortedCategoryKeys where CategorySuggestionService.matches(keyword: keyword, inNormalized: merchant) {
        if let entry = categoryMap[keyword] { return entry.category }
    }
    return nil
}
```

**Verify**: Build command → `** BUILD SUCCEEDED **`;
`git diff --stat -- Tenra/Services/Voice/VoiceInputParser.swift` → only insertions (no `-` lines apart from the stat header).

### Step 3: The provider (combines the three tiers)

Create `Tenra/Services/Categories/CategorySuggestionProvider.swift`:

```swift
import Foundation

@MainActor
enum CategorySuggestionProvider {

    /// Suggestions for a batch of not-yet-saved transactions, keyed by
    /// transaction id. Only `.expense` / `.income` rows get suggestions.
    /// `history` is the user's saved transactions (TransactionStore.transactions);
    /// the index is built off the main actor and NOT cached (it must reflect
    /// the store at import time).
    static func suggestions(
        for transactions: [Transaction],
        history: [Transaction],
        categories: [CustomCategory],
        keywordMatcher: (String) -> String?
    ) async -> [String: String]

    /// Single-row resolution. Order: history (only if that category still
    /// exists for this type) → brand preset (expense only) → voice keyword
    /// (expense only). Each candidate name goes through
    /// `TransactionDraftService.resolveCategory(named:type:in:)`; a result that
    /// is "" or equals `String(localized: "category.other")` is rejected.
    static func suggestion(
        for description: String,
        type: TransactionType,
        index: CategorySuggestionService.HistoryIndex,
        categories: [CustomCategory],
        keywordMatcher: (String) -> String?
    ) -> String?
}
```

- In `suggestions(...)`: `let index = await Task.detached(priority: .userInitiated) { CategorySuggestionService.buildHistoryIndex(from: history) }.value`, then loop on the main actor calling `suggestion(...)`.
- Brand tier: find `CategoryPreset.defaultExpense.first { $0.id == presetId }`, name = `String(localized: String.LocalizationValue(preset.nameKey))`, then resolve.
- History tier: accept only if `categories.contains { $0.type == type && $0.name == candidate }`.

Write `TenraTests/Services/Categories/CategorySuggestionProviderTests.swift`,
`@MainActor struct`, covering Test plan items 10-16. Build expected category
names in tests with `String(localized: String.LocalizationValue("onboarding.preset.groceries"))`
etc. so the tests pass in any simulator locale. Pass a closure as `keywordMatcher`
(e.g. `{ $0.lowercased().contains("taxi") ? "Transport" : nil }`) instead of
constructing a `VoiceInputParser`.

**Verify**: Suite tests command → `** TEST SUCCEEDED **`, both suites passing.

### Step 4: Review screen — category per row

In `Tenra/Views/Import/ImportTransactionPreviewView.swift`:

1. Add stored properties to `ImportTransactionPreviewView`:
   `let customCategories: [CustomCategory]` and
   `var suggestedCategories: [String: String] = [:]` (transactionId → category name).
2. Add state: `@State private var categoryMapping: [String: String] = [:]`
   and `@State private var manuallyCategorized: Set<String> = []`.
3. In the existing `.onAppear`, add `categoryMapping = suggestedCategories`.
4. Add helpers:
   - `effectiveCategory(for tx: Transaction) -> String`: for `.expense`/`.income`
     return `categoryMapping[tx.id] ?? tx.category`; otherwise `tx.category`.
   - `categoryOptions(for tx: Transaction) -> [String]`:
     `customCategories.filter { $0.type == tx.type }.sortedByOrder().map(\.name)`.
   - `selectCategory(_ name: String, for tx: Transaction)`: set
     `categoryMapping[tx.id] = name`, insert `tx.id` into `manuallyCategorized`,
     then for every OTHER transaction with the same `type` and the same
     `CategorySuggestionService.normalizedMerchant(description)` (non-empty)
     whose id is NOT in `manuallyCategorized`, set its mapping to `name` too.
     Wrap in `withAnimation(AppAnimation.contentSpring)` like the other mutations.
5. Pass to each `ImportTransactionPreviewRow`: `category: effectiveCategory(for:)`,
   `categoryOptions: categoryOptions(for:)`, `customCategories: customCategories`,
   `onCategorySelect: { selectCategory($0, for: transaction) }`.
6. In `addSelectedTransactions()`, replace `category: transaction.category`
   with `category: savableCategory(for: transaction)`, where
   `savableCategory` returns `effectiveCategory(for:)` BUT falls back to `""`
   for an `.expense`/`.income` row whose effective category is not the name of
   a `customCategories` entry of that type. Reason: `TransactionStore.validate`
   throws `categoryNotFound` for an unknown non-empty category, and this
   method's `catch {}` would then silently drop the row from the import.
   Change nothing else there.

In `ImportTransactionPreviewRow`:
1. Add `let category: String`, `let categoryOptions: [String]`,
   `let customCategories: [CustomCategory]`, `let onCategorySelect: (String) -> Void`.
2. Render the card from a copy of the transaction carrying the effective
   category (build a new `Transaction` passing every field of `transaction`
   through unchanged except `category:`; the full init parameter list is
   `id, date, description, amount, currency, convertedAmount, type, category, subcategory, accountId, targetAccountId, accountName, targetAccountName, targetCurrency, targetAmount, recurringSeriesId, recurringOccurrenceId, createdAt`).
3. `styleData`: use `category` and the real `customCategories` instead of `[]`
   (update the comment above it accordingly).
4. Under the existing account picker, when `isSelected && (transaction.type == .expense || transaction.type == .income)`,
   add a `Picker(String(localized: "transaction.category"), selection: Binding(get: { category }, set: { onCategorySelect($0) }))`
   with first option `Text(String(localized: "category.uncategorized")).tag("")`
   and then `ForEach(categoryOptions, id: \.self) { Text($0).tag($0) }`.
   Same modifiers as the account picker (`.pickerStyle(MenuPickerStyle())`,
   `.padding(.leading, AppSpacing.xl)`, same transition).
   If `category` is non-empty but not in `categoryOptions` (should not happen,
   but guards a stale suggestion), add it as an extra tagged option so the
   Picker never has an unmatched selection.

Update the 2 `#Preview` blocks to pass `customCategories: coordinator.categoriesViewModel.customCategories`.

**Verify**: Build command → `** BUILD SUCCEEDED **`.
Existing suite still green: `xcodebuild test ... -only-testing:TenraTests/ImportTransactionPreviewViewTests` → `** TEST SUCCEEDED **`.

### Step 5: Compute suggestions in the coordinator

In `Tenra/Views/Import/PDFImportCoordinator.swift`:
1. Add `@State private var suggestedCategories: [String: String] = [:]`.
2. Replace the block at lines 198-204 with: build `let mapped = ParsedTransactionMapper.transactions(...)`
   (same arguments), then
   ```swift
   let parser = VoiceInputParser(
       categoriesViewModel: categoriesViewModel,
       accountsViewModel: accountsViewModel,
       transactionsViewModel: transactionsViewModel
   )
   suggestedCategories = await CategorySuggestionProvider.suggestions(
       for: mapped,
       history: transactionsViewModel.transactionStore?.transactions ?? [],
       categories: categoriesViewModel.customCategories,
       keywordMatcher: { parser.keywordCategory(in: $0) }
   )
   parsedTransactions = mapped
   showingTransactionPreview = true
   ```
   (`analyzePDF` is already `async`.)
3. In `transactionPreviewSheet`, pass
   `customCategories: categoriesViewModel.customCategories` and
   `suggestedCategories: suggestedCategories`.

**Verify**: Build command → `** BUILD SUCCEEDED **`.

### Step 6: Receipt confirmation — category chooser

In `Tenra/Views/Import/ReceiptConfirmationView.swift`:
1. Add `let categoriesViewModel: CategoriesViewModel` (stored + init parameter,
   placed after `accountsViewModel`) and `@State private var selectedCategoryName: String?`.
2. Between the details `FormSection` and the `AccountSelectorView`, add a
   `CategorySelectorView` configured exactly like the exemplar in
   `VoiceInputConfirmationView.swift:150-164`, with `type: .expense`,
   `selectedCategory: $selectedCategoryName`, no `onSelectionChange`, no
   `warningMessage`, and `.screenPadding()`.
3. Add `.task` on the `NavigationStack` content: if `selectedCategoryName == nil`,
   build a `VoiceInputParser` (as in Step 5) and set
   `let result = await CategorySuggestionProvider.suggestions(for: [probe], history: transactionsViewModel.transactionStore?.transactions ?? [], categories: categoriesViewModel.customCategories, keywordMatcher: { parser.keywordCategory(in: $0) })`
   where `probe` is `Transaction(id: "receipt-probe", date: dateString, description: draft.merchant, amount: draft.total, currency: currency, type: .expense, category: "")` and you read the result for key `"receipt-probe"` (the probe is never saved). Assign only if `selectedCategoryName` is still nil when the result arrives, so a category the user picked meanwhile is never overwritten.
4. In `makeTransaction(accountId:)`, change `category: ""` to
   `category: selectedCategoryName ?? ""`. The Add button stays enabled with no
   category (uncategorized remains allowed).
5. Update the call site in `PDFImportCoordinator` (lines 74-81) and the file's
   own `#Preview` to pass `categoriesViewModel:`.

**Verify**: Build command → `** BUILD SUCCEEDED **`.

### Step 7: Remove the dead ML stub, document

1. Confirm no references: `grep -rn "CategoryMLPredictor" Tenra TenraTests --include='*.swift' | grep -v "Services/ML/CategoryMLPredictor.swift"` → no output. Then delete `Tenra/Services/ML/CategoryMLPredictor.swift` and the empty `Tenra/Services/ML` folder (file-system-synced project: no pbxproj edit).
2. Append to `docs/domains/import.md` a section `## Category suggestions` (5-10 lines): the three tiers and their order, that the history tier is derived from saved transactions (no separate learning store, not cached), the whole-word rule, that `brandPresets` is an array (Red Flag 16), and that FoundationModels classification was deliberately deferred.

**Verify**: Build command → `** BUILD SUCCEEDED **`; All unit tests command → `** TEST SUCCEEDED **`.

## Test plan

`CategorySuggestionServiceTests` (plain struct):
1. `normalizedMerchant`: the four examples in the doc comment, plus `"Кофе Ёлка"` → `"кофе елка"`.
2. `matches`: `"yandex"` in `"yandex go"` → true; `"abo"` in `"about us"` → false; `"abo"` in `"abo netflix"` → true; `"cine"` in `"medicine store"` → false; `"metro cash"` in `"metro cash carry"` → true; `""` → false.
3. `buildHistoryIndex` skips empty categories.
4. `buildHistoryIndex` skips `.internalTransfer` (and any type other than expense/income).
5. `historyCategory`: majority wins (2× "Food" vs 1× "Gifts" → "Food").
6. Tie broken by later date.
7. Same merchant, different type → independent (an income "Salary" row does not answer an expense query).
8. Punctuation/digit variants share a key ("MAGNUM 01" and "Magnum-02" → same suggestion).
9. `brandPresetId`: `"YANDEX.GO"` → `"transport"`, `"APPLE.COM/BILL"` → `"subscriptions"`, `"YANDEX EDA"` → `"dining"` (longest keyword beats `yandex`-style shorter ones), `"Random shop"` → nil.

`CategorySuggestionProviderTests` (`@MainActor`):
10. History beats brand: history says "Snacks" for "magnum", brand says groceries → "Snacks".
11. History category that no longer exists in `categories` is ignored → falls through to brand.
12. Brand resolves to the user's localized preset category name.
13. Brand preset whose category the user deleted → nil (does NOT return "Other").
14. Keyword tier used when no history/brand hit; its raw name is resolved via `resolveCategory` (e.g. raw "Transport" → user's "Transport").
15. Income rows get history suggestions only (brand/keyword ignored).
16. `suggestions(for:...)` returns entries only for expense/income ids and none for a transfer row.

Verification: Suite tests command → both suites pass, 16+ tests.

## Done criteria

- [ ] Build command prints `** BUILD SUCCEEDED **`
- [ ] Both new suites pass; full `TenraTests` prints `** TEST SUCCEEDED **`
- [ ] `grep -rn "CategoryMLPredictor" Tenra TenraTests` → no output; `ls Tenra/Services/ML` → "No such file or directory"
- [ ] `grep -n 'category: ""' Tenra/Views/Import/ReceiptConfirmationView.swift` → no output
- [ ] `grep -n "savableCategory(for: transaction)" Tenra/Views/Import/ImportTransactionPreviewView.swift` → 1 match inside `addSelectedTransactions`
- [ ] `git diff --stat -- Tenra/*.lproj` → empty (no string changes)
- [ ] `git status --short` lists only in-scope files (plus `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 002 updated

## STOP conditions

- The excerpts above do not match the live code (drift).
- `VoiceInputParser` no longer has `sortedCategoryKeys` / `categoryMap`, or adding the method requires changing existing parser code.
- `TransactionDraftService.resolveCategory(named:type:in:)` is gone or changed signature.
- You need a new localized string (this plan is designed to need none).
- A test that existed before this plan starts failing and the cause is not obviously your change.
- The `Task.detached` history build does not compile without making `CustomCategory`, `TransactionStore`, or a view model `Sendable` — report instead of annotating shared model types.

## Maintenance notes

- Human device check: import a real Kaspi PDF on the phone; expect common merchants (YANDEX.GO, MAGNUM, GLOVO...) pre-filled, the rest "Uncategorized"; set one uncategorized merchant and see same-merchant rows follow; import the same statement a month later and see the history tier fill what you set.
- Self-reinforcement: accepted suggestions become history. A wrong keyword/brand guess that the user does not correct at review will keep being suggested for that merchant. Acceptable because every suggestion is shown on the review screen; revisit if users report "stuck" categories.
- `brandPresets` is the place to add merchants. Keep it an array; add lowercase plain words; prefer >= 5-character keywords (short ones must be whole words).
- Deferred: an Apple Intelligence (FoundationModels) tier for unknown merchants. The primary market is Russian-speaking and on-device model language support there is uncertain, so it was not worth the complexity yet. If added, it slots in as tier 4 in `CategorySuggestionProvider.suggestion`, gated by `IntelligenceAvailability`.
- Follow-up plan 003 reuses `CategorySuggestionService.normalizedMerchant` to recategorize similar saved transactions from the edit screen.
