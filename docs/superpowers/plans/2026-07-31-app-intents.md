# App Intents & Siri Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user log a transaction by speaking one phrase to Siri, without opening Tenra, and ship it to the App Store as version 1.1.

**Architecture:** App Intents are declared in the **main app target** (no extension, no App Group, no entitlement change) so they execute in the app's own process. All decision logic lives in plain services under `Services/Intents/` operating on value types; the intents are thin adapters. A headless process bootstraps via `AppCoordinator.initializeFastPath()` (<50 ms, accounts + settings only, no transactions) and writes through `TransactionStore.add`, whose balance update is incremental against the persisted `account.balance`.

**Tech Stack:** Swift 5 / SwiftUI (iOS 26), AppIntents framework, CoreData, swift-testing (`import Testing`), App Store Connect API via `asc-mcp`.

**Source spec:** [docs/superpowers/specs/2026-07-31-app-intents-design.md](../specs/2026-07-31-app-intents-design.md)

## Global Constraints

- **No new target, no App Group, no entitlement change.** Intents live in the main `Tenra` target.
- **Test framework: swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`). 75 of 78 existing test files use it. Do not add XCTest files.
- **Any suite constructing MainActor-isolated types must be annotated `@MainActor`** (project default is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Otherwise: "call to main actor-isolated initializer in a synchronous nonisolated context".
- **Any test building a `TransactionStore` must retain it** — `AccountsViewModel.transactionStore` is `weak`.
- **Filter tests at suite level only:** `-only-testing:TenraTests/SuiteTypeName` using the **type name**, not the `@Suite("display name")`. Method-level filtering silently runs zero tests and still prints `** TEST SUCCEEDED **`.
- **Parse test output with** `grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"`. Never grep `expect` (matches `#expect` compiler warnings).
- A full-suite run can print `** TEST FAILED **` with zero failing cases (parallel-clone flake). **Re-run once before investigating.**
- **11 in-app locales**, all must be updated together: `en, ru, de, es, fr, tr, pt-BR, it, uk, ja, ko` under `Tenra/<locale>.lproj/`. A missing key renders the raw key.
- **Never use `perl -CSD`** to edit `.strings` files (mojibake in non-ASCII locales). Use `python3` with `io.open(encoding="utf-8")`, then grep-verify `ru` and `ja`.
- **No em dashes (—) in any user-facing text**: `Localizable.strings`, `AppShortcuts.strings`, What's New, promo text, App Review notes.
- **Money rendering:** never `Text("\(amount) \(currency)")` or ad-hoc `NumberFormatter`. Use `FormattedAmountText`, or `Formatting.formatCurrencySmart(_:currency:)` when a `String` is needed.
- **Money math:** convert via `CurrencyConverter.convertSync(amount:from:to:)` to the base currency. **Never sum `Transaction.convertedAmount` across currencies** — it is in *account* currency, not base currency.
- **Date parsing over transactions:** use `FastDateParser`, never `DateFormatter.date(from:)` in a loop.
- **Xcode project uses file-system-synchronized groups.** New `.swift` and `.strings` files need **no** `project.pbxproj` edits; create them on disk and they are in the target.
- Build check: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
- If xcodebuild reports "accessing build database ... database is locked", wait ~5s and retry.
- **A green build does not mean `#Preview` blocks work.** They compile but never render. Any view file touched must have its previews opened by hand in Xcode.

**Version decision (assumption — flip here if wrong):** this ships as **1.1**. `docs/RELEASE_1.1_PLAN.md` reserves 1.1 for iPad; that workstream moves to **1.2**. If you would rather bundle iPad into the same release, the only affected task is Task 15 (ASC), which then additionally requires `TARGETED_DEVICE_FAMILY = "1,2"` and iPad 13" screenshots at 2064×2752.

---

## File Structure

**Create — services (all logic lives here, fully unit-tested):**

| File | Responsibility |
|---|---|
| `Tenra/Services/Intents/TransactionDraft.swift` | Value types only: `TransactionDraft`, `DraftWarning`, `DraftIssue`, `ConversionPolicy`, `CommitHooks`. No logic. |
| `Tenra/Services/Intents/TransactionDraftService.swift` | `makeDraft` (pure resolver) + `commit` (writes through the store). The single write path for both the voice screen and every intent. |
| `Tenra/Services/Intents/IntentEnvironment.swift` | Obtains live services in any process state; prevents a second `AppCoordinator`. |
| `Tenra/Services/Intents/SpendingQueryService.swift` | Bounded CoreData fetch for period totals, independent of `TransactionStore` load state. |
| `Tenra/Services/Intents/IntentUsageCounters.swift` | Local-only counters (intent adds vs manual adds vs fallbacks). |
| `Tenra/Services/Intents/IntentHandoff.swift` | Carries a pending `ParsedOperation` from an `openAppWhenRun` intent into the UI. |

**Create — intents (thin adapters, no logic):**

| File | Responsibility |
|---|---|
| `Tenra/Intents/LogTransactionIntent.swift` | Free-form phrase → parser → draft → confirm → commit. |
| `Tenra/Intents/AddExpenseIntent.swift` | Typed parameters for the Shortcuts app. |
| `Tenra/Intents/CheckSpendingIntent.swift` | Read-only period total. |
| `Tenra/Intents/TenraShortcuts.swift` | `AppShortcutsProvider`. |
| `Tenra/Intents/Entities/AccountAppEntity.swift` | `AppEntity` + `EntityQuery` for account pickers. |
| `Tenra/Intents/Entities/CategoryAppEntity.swift` | `AppEntity` + `EntityQuery` for category pickers. |
| `Tenra/Intents/Snippets/TransactionConfirmationSnippet.swift` | Confirmation UI. |
| `Tenra/Intents/Snippets/SpendingSummarySnippet.swift` | Spending answer UI. |

**Create — other:**
- `Tenra/Views/Settings/SettingsSiriSection.swift`
- `Tenra/<locale>.lproj/AppShortcuts.strings` × 11

**Create — tests:**
- `TenraTests/Services/Intents/TransactionDraftResolverTests.swift`
- `TenraTests/Services/Intents/TransactionDraftCommitTests.swift`
- `TenraTests/Services/Intents/SpendingQueryServiceTests.swift`
- `TenraTests/Services/Intents/IntentEnvironmentTests.swift`
- `TenraTests/Services/Intents/IntentUsageCountersTests.swift`

**Modify:**
- `Tenra/Views/VoiceInput/VoiceInputConfirmationView.swift:416-530` — replaced by a call into `TransactionDraftService`.
- `Tenra/TenraApp.swift:68` — register the coordinator with `IntentEnvironment`.
- `Tenra/Views/Home/MainTabView.swift` — present the confirmation sheet on handoff.
- `Tenra/Views/Settings/SettingsView.swift:67-76` — insert the Siri section.
- `Tenra/Views/Experiments/ExperimentsListView.swift` — counters row.
- `Tenra/<locale>.lproj/Localizable.strings` × 11
- `CLAUDE.md` — file-organization tree.
- `Tenra.xcodeproj/project.pbxproj` — `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`.

---

## Task 1: Draft value types and the resolver

The resolver encodes the behavior that exists today in `VoiceInputConfirmationView.saveTransaction` (`VoiceInputConfirmationView.swift:416-530`). Each test below cites the original lines it pins. **These tests must not be edited in Task 3.** If a test needs editing to keep passing after the refactor, that is a behavior change and needs an explicit decision.

**Files:**
- Create: `Tenra/Services/Intents/TransactionDraft.swift`
- Create: `Tenra/Services/Intents/TransactionDraftService.swift`
- Test: `TenraTests/Services/Intents/TransactionDraftResolverTests.swift`

**Interfaces:**
- Consumes: `ParsedOperation` (`Tenra/Models/ParsedOperation.swift`), `Account` / `TransactionType` (`Tenra/Models/Transaction.swift`), `CustomCategory` (`Tenra/Models/CustomCategory.swift`), `VoiceLearningStore` (`Tenra/Services/Voice/VoiceLearningStore.swift`), `CurrencyConverter.convertSync(amount:from:to:) -> Double?`.
- Produces:
  - `TransactionDraft` (struct, `Equatable`) with `type, amount, currency, convertedAmount, categoryName, subcategoryIds, accountId, date, note, warnings`
  - `enum DraftWarning: Equatable { case categorySubstituted(original: String?), accountInferred }`
  - `enum DraftIssue: Error, Equatable { case missingAmount, noEligibleAccount, noFallbackCategory, needsFXConversion(amount: Double, from: String, to: String) }`
  - `enum ConversionPolicy: Equatable { case cachedOnly, provided(Double?) }`
  - `TransactionDraftService.makeDraft(from:accounts:categories:learned:conversion:note:) -> Result<TransactionDraft, DraftIssue>`

- [ ] **Step 1: Write the failing tests**

Create `TenraTests/Services/Intents/TransactionDraftResolverTests.swift`:

```swift
//
//  TransactionDraftResolverTests.swift
//  TenraTests
//
//  Pins the resolution rules that shipped inside
//  VoiceInputConfirmationView.saveTransaction (lines 416-530) before that
//  logic was extracted. Do not edit these tests during the extraction: a
//  test that must change to keep passing is a behavior change, not a
//  refactor.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite struct TransactionDraftResolverTests {

    // MARK: - Fixtures

    private func account(
        _ id: String,
        currency: String = "KZT",
        deposit: DepositInfo? = nil,
        loan: LoanInfo? = nil
    ) -> Account {
        Account(
            id: id,
            name: id,
            currency: currency,
            depositInfo: deposit,
            loanInfo: loan,
            balance: 0
        )
    }

    private func category(_ name: String, type: TransactionType = .expense) -> CustomCategory {
        // Matches the convenience initializer used by
        // TenraTests/Services/Voice/VoiceInputParserTests.swift:44
        CustomCategory(
            name: name,
            iconSource: .sfSymbol("circle"),
            colorHex: "#f97316",
            type: type
        )
    }

    /// Learning store backed by an ephemeral suite so production defaults stay clean.
    private func emptyLearningStore(_ suite: String) -> VoiceLearningStore {
        UserDefaults().removePersistentDomain(forName: suite)
        return VoiceLearningStore(defaults: UserDefaults(suiteName: suite)!)
    }

    private var otherName: String { String(localized: "category.other") }

    // MARK: - Amount (pins lines 431-434)

    @Test("No amount parsed is a blocking issue")
    func missingAmount() {
        let op = ParsedOperation(type: .expense, amount: nil, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.1")
        )
        #expect(result == .failure(.missingAmount))
    }

    @Test("Zero or negative amount is a blocking issue")
    func nonPositiveAmount() {
        let op = ParsedOperation(type: .expense, amount: 0, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.2")
        )
        #expect(result == .failure(.missingAmount))
    }

    // MARK: - Account (pins lines 436-445)

    @Test("Named account is used verbatim and produces no warning")
    func namedAccount() throws {
        let op = ParsedOperation(type: .expense, amount: 3000, accountId: "a2", categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1"), account("a2")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.3")
        )
        let draft = try #require(try result.get())
        #expect(draft.accountId == "a2")
        #expect(draft.warnings.isEmpty)
    }

    @Test("Loan and deposit accounts are never eligible")
    func loanAndDepositExcluded() {
        let deposit = account("d1", deposit: DepositInfo())
        let loan = account("l1", loan: LoanInfo())
        let op = ParsedOperation(type: .expense, amount: 3000, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [deposit, loan],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.4")
        )
        #expect(result == .failure(.noEligibleAccount))
    }

    @Test("No accounts at all is a blocking issue")
    func noAccounts() {
        let op = ParsedOperation(type: .expense, amount: 3000, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.5")
        )
        #expect(result == .failure(.noEligibleAccount))
    }

    @Test("Learned account wins over first-regular when no account is named")
    func learnedAccountPreferred() throws {
        let learned = emptyLearningStore("draft.tests.6")
        // confidenceThreshold is 2, so record twice.
        learned.recordSave(category: "Food", accountId: "a2")
        learned.recordSave(category: "Food", accountId: "a2")

        let op = ParsedOperation(type: .expense, amount: 3000, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1"), account("a2")],
            categories: [category("Food")],
            learned: learned
        )
        let draft = try #require(try result.get())
        #expect(draft.accountId == "a2")
        #expect(draft.warnings.contains(.accountInferred))
    }

    @Test("Falls back to the first eligible account and warns")
    func firstEligibleAccountFallback() throws {
        let op = ParsedOperation(type: .expense, amount: 3000, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1"), account("a2")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.7")
        )
        let draft = try #require(try result.get())
        #expect(draft.accountId == "a1")
        #expect(draft.warnings.contains(.accountInferred))
    }

    // MARK: - Category (pins lines 447-464)

    @Test("Unknown category is substituted with Other and warns")
    func unknownCategorySubstituted() throws {
        let op = ParsedOperation(type: .expense, amount: 3000, accountId: "a1", categoryName: "Nonexistent")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Food"), category(otherName)],
            learned: emptyLearningStore("draft.tests.8")
        )
        let draft = try #require(try result.get())
        #expect(draft.categoryName == otherName)
        #expect(draft.warnings.contains(.categorySubstituted(original: "Nonexistent")))
    }

    @Test("Category of the wrong transaction type does not match")
    func categoryTypeMustMatch() throws {
        // "Salary" exists only as income; an expense operation must not use it.
        let op = ParsedOperation(type: .expense, amount: 3000, accountId: "a1", categoryName: "Salary")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Salary", type: .income), category(otherName)],
            learned: emptyLearningStore("draft.tests.9")
        )
        let draft = try #require(try result.get())
        #expect(draft.categoryName == otherName)
    }

    @Test("Unknown category with no Other fallback is a blocking issue")
    func noFallbackCategory() {
        let op = ParsedOperation(type: .expense, amount: 3000, accountId: "a1", categoryName: "Nonexistent")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.10")
        )
        #expect(result == .failure(.noFallbackCategory))
    }

    // MARK: - Currency (pins lines 466-491)

    @Test("Matching currency needs no conversion")
    func sameCurrencyNoConversion() throws {
        let op = ParsedOperation(type: .expense, amount: 3000, currencyCode: "KZT", accountId: "a1", categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1", currency: "KZT")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.11")
        )
        let draft = try #require(try result.get())
        #expect(draft.convertedAmount == nil)
        #expect(draft.currency == "KZT")
    }

    @Test("Mismatched currency with a cold cache is a blocking issue")
    func coldCacheBlocks() {
        CurrencyRateStore.shared.clearAll()
        let op = ParsedOperation(type: .expense, amount: 10, currencyCode: "USD", accountId: "a1", categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1", currency: "KZT")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.12"),
            conversion: .cachedOnly
        )
        #expect(result == .failure(.needsFXConversion(amount: 10, from: "USD", to: "KZT")))
    }

    @Test("A caller-provided conversion is used verbatim")
    func providedConversionUsed() throws {
        let op = ParsedOperation(type: .expense, amount: 10, currencyCode: "USD", accountId: "a1", categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1", currency: "KZT")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.13"),
            conversion: .provided(5400)
        )
        let draft = try #require(try result.get())
        #expect(draft.convertedAmount == 5400)
    }
}
```

Note: this suite is `@MainActor` (required — it constructs MainActor-isolated types) and it touches `CurrencyRateStore.shared`, which is a process-global singleton. `@MainActor` also serializes its synchronous tests against other rate-mutating suites, which is why the annotation is mandatory here and not merely conventional.

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/TransactionDraftResolverTests 2>&1 | grep -aE "error:|Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: compile errors — `cannot find 'TransactionDraftService' in scope`, `cannot find type 'DraftIssue' in scope`. That is the correct RED state for a not-yet-existing type.

- [ ] **Step 3: Create the value types**

Create `Tenra/Services/Intents/TransactionDraft.swift`:

```swift
//
//  TransactionDraft.swift
//  Tenra
//
//  Value types for the single transaction-write path shared by the voice
//  confirmation screen and every App Intent. No logic lives here.
//

import Foundation

/// A fully resolved transaction, ready to commit.
struct TransactionDraft: Equatable {
    var type: TransactionType
    var amount: Double
    var currency: String
    /// Amount expressed in the destination account's currency, or nil when
    /// `currency` already equals the account currency.
    var convertedAmount: Double?
    var categoryName: String
    var subcategoryIds: [String]
    var accountId: String
    var date: Date
    var note: String
    var warnings: [DraftWarning]
}

/// A value the resolver had to guess. Non-blocking: the caller must surface it
/// (a marked field in an intent snippet, or the existing warning labels on the
/// voice confirmation screen) so the user sees the guess before confirming.
enum DraftWarning: Equatable {
    case categorySubstituted(original: String?)
    case accountInferred
}

/// A condition the resolver cannot resolve on its own. Intents treat these as
/// "open the app with the operation prefilled".
enum DraftIssue: Error, Equatable {
    case missingAmount
    case noEligibleAccount
    case noFallbackCategory
    case needsFXConversion(amount: Double, from: String, to: String)
}

/// How to obtain a cross-currency amount. `makeDraft` is synchronous and pure,
/// so it can only read the FX cache; callers that may perform a network
/// conversion pass the result back in via `.provided`.
enum ConversionPolicy: Equatable {
    case cachedOnly
    case provided(Double?)
}

/// Side effects `commit` performs, injectable so they can be asserted in tests
/// without protocol ceremony around two singletons.
struct CommitHooks {
    var recordLearning: (String?, String?) -> Void
    var recordRating: () -> Void

    static let production = CommitHooks(
        recordLearning: { category, accountId in
            VoiceLearningStore.shared.recordSave(category: category, accountId: accountId)
        },
        recordRating: {
            RatingPromptService.shared.recordTransactionAdded()
        }
    )
}
```

- [ ] **Step 4: Implement the resolver**

Create `Tenra/Services/Intents/TransactionDraftService.swift`:

```swift
//
//  TransactionDraftService.swift
//  Tenra
//
//  The single write path for transactions created from a ParsedOperation.
//  Extracted from VoiceInputConfirmationView.saveTransaction so that the voice
//  confirmation screen and the App Intents cannot drift apart.
//
//  makeDraft is pure and synchronous: everything it decides is testable without
//  a store, a container or a network.
//

import Foundation

@MainActor
enum TransactionDraftService {

    // MARK: - Resolve

    static func makeDraft(
        from operation: ParsedOperation,
        accounts: [Account],
        categories: [CustomCategory],
        learned: VoiceLearningStore,
        conversion: ConversionPolicy = .cachedOnly,
        note: String = ""
    ) -> Result<TransactionDraft, DraftIssue> {

        var warnings: [DraftWarning] = []

        // 1. Amount — must be present and positive.
        guard let parsedAmount = operation.amount else { return .failure(.missingAmount) }
        let amount = NSDecimalNumber(decimal: parsedAmount).doubleValue
        guard amount > 0 else { return .failure(.missingAmount) }

        // 2. Account — named, else learned for this category, else first eligible.
        //    Loan and deposit accounts are never eligible for a plain expense/income.
        let eligible = accounts.filter { !$0.isLoan && !$0.isDeposit }
        guard let firstEligible = eligible.first else { return .failure(.noEligibleAccount) }

        let account: Account
        if let namedId = operation.accountId,
           let named = eligible.first(where: { $0.id == namedId }) {
            account = named
        } else {
            warnings.append(.accountInferred)
            let eligibleIds = Set(eligible.map(\.id))
            if let learnedId = learned.preferredAccountID(
                forCategory: operation.categoryName,
                where: { eligibleIds.contains($0) }
            ), let match = eligible.first(where: { $0.id == learnedId }) {
                account = match
            } else {
                account = firstEligible
            }
        }

        // 3. Category — must exist AND match the operation type, else fall back
        //    to the localized "Other" of the same type.
        let categoryName: String
        if let parsedName = operation.categoryName,
           categories.contains(where: { $0.name == parsedName && $0.type == operation.type }) {
            categoryName = parsedName
        } else {
            let fallback = String(localized: "category.other")
            guard categories.contains(where: { $0.name == fallback && $0.type == operation.type }) else {
                return .failure(.noFallbackCategory)
            }
            warnings.append(.categorySubstituted(original: operation.categoryName))
            categoryName = fallback
        }

        // 4. Currency — convert only when it differs from the account currency.
        let currency = operation.currencyCode ?? account.currency
        var convertedAmount: Double?
        if currency != account.currency {
            switch conversion {
            case .provided(let value):
                convertedAmount = value
            case .cachedOnly:
                guard let cached = CurrencyConverter.convertSync(
                    amount: amount,
                    from: currency,
                    to: account.currency
                ) else {
                    return .failure(.needsFXConversion(
                        amount: amount,
                        from: currency,
                        to: account.currency
                    ))
                }
                convertedAmount = cached
            }
        }

        return .success(TransactionDraft(
            type: operation.type,
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmount,
            categoryName: categoryName,
            subcategoryIds: [],
            accountId: account.id,
            date: operation.date,
            note: note.isEmpty ? operation.note : note,
            warnings: warnings
        ))
    }
}
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/TransactionDraftResolverTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: 13 passed, `** TEST SUCCEEDED **`.

If a fixture fails to compile because `DepositInfo()` or `LoanInfo()` require arguments, read `Tenra/Models/Transaction.swift` for their initializers and supply the minimum required values. Do not change the assertions to work around it.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Services/Intents/ TenraTests/Services/Intents/
git commit -m "feat(intents): extract transaction draft resolver with pinned behavior tests"
```

---

## Task 2: Commit path

**Files:**
- Modify: `Tenra/Services/Intents/TransactionDraftService.swift`
- Test: `TenraTests/Services/Intents/TransactionDraftCommitTests.swift`

**Interfaces:**
- Consumes: `TransactionDraft`, `CommitHooks` (Task 1); `TransactionStore.add(_:) async throws -> Transaction`; `CategoriesViewModel.linkSubcategoriesToTransaction(transactionId:subcategoryIds:)`.
- Produces: `TransactionDraftService.commit(_:store:categoriesViewModel:hooks:) async throws -> Transaction`

Why the hooks matter: `RatingPromptService.recordTransactionAdded()` is called today from `TransactionsViewModel.addTransaction` (`TransactionsViewModel.swift:186`), which intents bypass entirely. Without an explicit call here, Siri-logged transactions would never count toward rating eligibility.

- [ ] **Step 1: Write the failing tests**

Create `TenraTests/Services/Intents/TransactionDraftCommitTests.swift`:

```swift
//
//  TransactionDraftCommitTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite struct TransactionDraftCommitTests {

    private func makeDraft(accountId: String = "a1") -> TransactionDraft {
        TransactionDraft(
            type: .expense,
            amount: 3000,
            currency: "KZT",
            convertedAmount: nil,
            categoryName: "Food",
            subcategoryIds: [],
            accountId: accountId,
            date: Date(),
            note: "coffee",
            warnings: []
        )
    }

    @Test("Commit writes the transaction through the store")
    func commitWritesTransaction() async throws {
        let harness = try IntentTestHarness()
        let saved = try await TransactionDraftService.commit(
            makeDraft(),
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(!saved.id.isEmpty)
        #expect(saved.amount == 3000)
        #expect(saved.category == "Food")
        #expect(saved.accountId == "a1")
    }

    @Test("Commit records the category-to-account pair for learning")
    func commitRecordsLearning() async throws {
        let harness = try IntentTestHarness()
        _ = try await TransactionDraftService.commit(
            makeDraft(),
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(harness.learningCalls.count == 1)
        #expect(harness.learningCalls.first?.category == "Food")
        #expect(harness.learningCalls.first?.accountId == "a1")
    }

    @Test("Commit feeds the rating prompt counter")
    func commitRecordsRating() async throws {
        let harness = try IntentTestHarness()
        _ = try await TransactionDraftService.commit(
            makeDraft(),
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(harness.ratingCallCount == 1)
    }
}
```

- [ ] **Step 2: Write the shared test harness**

`IntentTestHarness` is used by this suite and Task 4. It must **retain** the store: `AccountsViewModel.transactionStore` is `weak`, and `accounts` empties when the store deallocates.

Create `TenraTests/Services/Intents/IntentTestHarness.swift`:

```swift
//
//  IntentTestHarness.swift
//  TenraTests
//
//  In-memory CoreData stack plus the collaborators the intent services need.
//  Holds a STRONG reference to the store: AccountsViewModel.transactionStore is
//  weak, and accounts empty out the moment the store deallocates.
//

import Foundation
import CoreData
@testable import Tenra

@MainActor
final class IntentTestHarness {

    let store: TransactionStore
    let categories: CategoriesViewModel

    private(set) var learningCalls: [(category: String?, accountId: String?)] = []
    private(set) var ratingCallCount = 0

    var hooks: CommitHooks {
        CommitHooks(
            recordLearning: { [weak self] category, accountId in
                self?.learningCalls.append((category, accountId))
            },
            recordRating: { [weak self] in
                self?.ratingCallCount += 1
            }
        )
    }

    init() throws {
        // Store assembly copied from
        // TenraTests/ViewModels/TransactionStoreNewIndexesTests.swift:23-34.
        // UserDefaultsRepository is the preview/test repository — no CoreData
        // container is needed for the commit path.
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "intent.tests.\(UUID().uuidString)")!
        )
        let recurring = RecurringStore(repository: repo)
        let balance = BalanceCoordinator(repository: repo)

        self.store = TransactionStore(
            repository: repo,
            balanceCoordinator: balance,
            recurringStore: recurring
        )
        self.categories = CategoriesViewModel(repository: repo)

        // Seed one regular account and the Food category.
        self.store.accounts = [
            Account(id: "a1", name: "Wallet", currency: "KZT", balance: 0)
        ]
        self.categories.addCategory(CustomCategory(
            name: "Food",
            iconSource: .sfSymbol("fork.knife"),
            colorHex: "#f97316",
            type: .expense
        ))
    }
}
```

If `TransactionStore.accounts` has no public setter, seed the account through the repository instead (`repo.saveAccounts([...])` or the equivalent method on `AccountRepositoryProtocol`) and then call the store's account-loading entry point. Read `Tenra/ViewModels/TransactionStore+AccountCRUD.swift` to find the right one; do not add a new setter to production code for the sake of a test.

- [ ] **Step 3: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/TransactionDraftCommitTests 2>&1 | grep -aE "error:|Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: `type 'TransactionDraftService' has no member 'commit'`.

- [ ] **Step 4: Implement commit**

Append to `Tenra/Services/Intents/TransactionDraftService.swift`, inside the enum:

```swift
    // MARK: - Commit

    /// Writes the draft through TransactionStore and performs the side effects
    /// that the manual add path performs, so an intent-created transaction is
    /// indistinguishable from a hand-entered one.
    @discardableResult
    static func commit(
        _ draft: TransactionDraft,
        store: TransactionStore,
        categoriesViewModel: CategoriesViewModel,
        hooks: CommitHooks = .production
    ) async throws -> Transaction {

        let dateString = DateFormatters.dateFormatter.string(from: draft.date)

        let transaction = Transaction(
            id: "",
            date: dateString,
            description: draft.note,
            amount: draft.amount,
            currency: draft.currency,
            convertedAmount: draft.convertedAmount,
            type: draft.type,
            category: draft.categoryName,
            subcategory: nil,
            accountId: draft.accountId,
            targetAccountId: nil,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil
        )

        let saved = try await store.add(transaction)

        if !saved.id.isEmpty, !draft.subcategoryIds.isEmpty {
            categoriesViewModel.linkSubcategoriesToTransaction(
                transactionId: saved.id,
                subcategoryIds: draft.subcategoryIds
            )
        }

        hooks.recordLearning(saved.category, saved.accountId)
        // Records the success moment only. The native prompt is never presented
        // from here: this path can run in a background, UI-less process.
        hooks.recordRating()

        return saved
    }
```

If `Transaction.subcategory` must carry the first subcategory *name* for backward compatibility (as `VoiceInputConfirmationView.swift:476-480` does), resolve it from `categoriesViewModel.subcategories` before constructing the transaction and pass it as `subcategory:` — check that file and match its behavior exactly.

- [ ] **Step 5: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/TransactionDraftCommitTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Services/Intents/TransactionDraftService.swift TenraTests/Services/Intents/
git commit -m "feat(intents): add commit path with learning and rating hooks"
```

---

## Task 3: Refactor the voice confirmation screen onto the service

This is the task that proves the extraction. **No test written in Tasks 1 or 2 may be edited here.**

**Files:**
- Modify: `Tenra/Views/VoiceInput/VoiceInputConfirmationView.swift:416-530`

**Interfaces:**
- Consumes: `TransactionDraftService.makeDraft`, `.commit`, `DraftIssue`, `DraftWarning`, `ConversionPolicy`.
- Produces: nothing new. Behavior is unchanged by construction.

- [ ] **Step 1: Read the current implementation end to end**

Read `Tenra/Views/VoiceInput/VoiceInputConfirmationView.swift:416-530` in full and list every user-visible effect it produces: `amountWarning`, `accountWarning`, `categoryWarning`, the silent selection repairs (`selectedAccountId = defaultAccount.id`, `selectedCategoryName = otherCategory.name`), `HapticManager.success()`, `dismiss()`. Each must still happen after the refactor.

- [ ] **Step 2: Replace the body of `saveTransaction`**

The view still owns its own edited state (the user may have changed the amount or account in the sheet), so it builds a `ParsedOperation` from that state and hands it to the service rather than re-deriving anything:

```swift
    private func saveTransaction() {
        validateAmount()

        let cleanedAmountText = amountText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "₸", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .trimmingCharacters(in: .whitespaces)

        let operation = ParsedOperation(
            type: selectedType,
            amount: Decimal(string: cleanedAmountText),
            currencyCode: selectedCurrency,
            date: selectedDate,
            accountId: selectedAccountId,
            categoryName: selectedCategoryName,
            subcategoryNames: [],
            note: noteText.isEmpty ? originalText : noteText
        )

        Task { await resolveAndCommit(operation) }
    }

    private func resolveAndCommit(_ operation: ParsedOperation) async {
        var result = TransactionDraftService.makeDraft(
            from: operation,
            accounts: accountsViewModel.accounts,
            categories: categoriesViewModel.customCategories,
            learned: .shared,
            conversion: .cachedOnly
        )

        // The user is present, so a cache miss is worth a network round trip
        // here, unlike in an intent.
        if case .failure(.needsFXConversion(let amount, let from, let to)) = result {
            let converted = await CurrencyConverter.convert(amount: amount, from: from, to: to)
            result = TransactionDraftService.makeDraft(
                from: operation,
                accounts: accountsViewModel.accounts,
                categories: categoriesViewModel.customCategories,
                learned: .shared,
                conversion: .provided(converted)
            )
        }

        switch result {
        case .failure(let issue):
            applyWarning(for: issue)

        case .success(var draft):
            applyWarnings(draft.warnings, to: &draft)
            draft.subcategoryIds = Array(selectedSubcategoryIds)
            do {
                _ = try await TransactionDraftService.commit(
                    draft,
                    store: transactionStore,
                    categoriesViewModel: categoriesViewModel
                )
                HapticManager.success()
                dismiss()
            } catch {
                amountWarning = error.localizedDescription
            }
        }
    }

    /// Reproduces the pre-refactor warning copy for each blocking condition.
    private func applyWarning(for issue: DraftIssue) {
        switch issue {
        case .missingAmount:
            amountWarning = String(localized: "voiceConfirmation.warning.enterValidAmount")
        case .noEligibleAccount:
            accountWarning = String(localized: "voiceConfirmation.warning.selectAccount")
        case .noFallbackCategory:
            categoryWarning = String(localized: "voiceConfirmation.warning.categoryNotFound")
        case .needsFXConversion:
            // Unreachable: resolveAndCommit retries with .provided before this point.
            amountWarning = String(localized: "voiceConfirmation.warning.enterValidAmount")
        }
    }

    /// Mirrors the pre-refactor silent repairs: the screen used to fix its own
    /// selection and show an explanatory warning at the same time.
    private func applyWarnings(_ warnings: [DraftWarning], to draft: inout TransactionDraft) {
        for warning in warnings {
            switch warning {
            case .accountInferred:
                selectedAccountId = draft.accountId
                accountWarning = String(localized: "voiceConfirmation.warning.accountNotSelected")
            case .categorySubstituted:
                selectedCategoryName = draft.categoryName
                categoryWarning = String(localized: "voiceConfirmation.warning.categoryNotSelected")
            }
        }
    }
```

Delete the old body from `saveTransaction` entirely. Do not leave the previous implementation behind a flag.

- [ ] **Step 3: Verify the pinned tests still pass, unedited**

```bash
git diff --stat TenraTests/Services/Intents/
```

Expected: **empty output**. If any test file changed, revert it and re-examine the refactor.

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/TransactionDraftResolverTests -only-testing:TenraTests/TransactionDraftCommitTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: 16 passed.

- [ ] **Step 4: Build and check previews**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

Expected: no output. Then open `VoiceInputConfirmationView.swift` in Xcode and render its `#Preview` blocks by hand — a green build compiles previews but never renders them, so preview-only breakage is invisible to every automated check available here.

- [ ] **Step 5: Manual check of the voice flow**

On the Simulator, add a transaction through the Voice tab and confirm: amount, account, category and date land correctly; the warning labels still appear when the account or category was not explicitly chosen; the sheet dismisses on success.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Views/VoiceInput/VoiceInputConfirmationView.swift
git commit -m "refactor(voice): route confirmation screen through TransactionDraftService"
```

---

## Task 4: IntentEnvironment

**Files:**
- Create: `Tenra/Services/Intents/IntentEnvironment.swift`
- Modify: `Tenra/TenraApp.swift` (around line 68, right after `let c = AppCoordinator()`)
- Test: `TenraTests/Services/Intents/IntentEnvironmentTests.swift`

**Interfaces:**
- Consumes: `AppCoordinator` and its `initializeFastPath() async`.
- Produces: `IntentEnvironment.shared`, `func register(_ coordinator: AppCoordinator)`, `func services() async -> IntentServices`, where `IntentServices` exposes `store: TransactionStore`, `accounts: AccountsViewModel`, `categories: CategoriesViewModel`, `settings: SettingsViewModel`.

- [ ] **Step 1: Write the failing tests**

Create `TenraTests/Services/Intents/IntentEnvironmentTests.swift`:

```swift
//
//  IntentEnvironmentTests.swift
//  TenraTests
//

import Testing
@testable import Tenra

@MainActor
@Suite struct IntentEnvironmentTests {

    @Test("A registered coordinator is reused rather than replaced")
    func reusesRegisteredCoordinator() async {
        let environment = IntentEnvironment()
        let coordinator = AppCoordinator()
        environment.register(coordinator)

        let services = await environment.services()

        #expect(services.store === coordinator.transactionStore)
    }

    @Test("Registering twice keeps the first coordinator")
    func registrationIsIdempotent() async {
        let environment = IntentEnvironment()
        let first = AppCoordinator()
        let second = AppCoordinator()
        environment.register(first)
        environment.register(second)

        let services = await environment.services()

        #expect(services.store === first.transactionStore)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/IntentEnvironmentTests 2>&1 | grep -aE "error:|Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: `cannot find 'IntentEnvironment' in scope`.

- [ ] **Step 3: Implement IntentEnvironment**

Create `Tenra/Services/Intents/IntentEnvironment.swift`:

```swift
//
//  IntentEnvironment.swift
//  Tenra
//
//  Single entry point for obtaining live services from an App Intent, whatever
//  the process state.
//
//  When the app is already running (foreground or suspended), the system runs
//  the intent in that same process and we must reuse its AppCoordinator: a
//  second coordinator would mean a second TransactionStore, and the two would
//  diverge in memory. TenraApp registers its coordinator the moment it builds
//  one.
//
//  When the process was launched solely to run an intent, SwiftUI's App body
//  never runs, so nothing registers a coordinator. We build one and await only
//  initializeFastPath(): accounts + settings + persisted balances, documented
//  at under 50 ms, with no transaction load. That is sufficient because
//  TransactionStore.add updates balances incrementally against the persisted
//  account.balance rather than recomputing from the transactions array.
//

import Foundation

@MainActor
final class IntentEnvironment {

    static let shared = IntentEnvironment()

    private var coordinator: AppCoordinator?
    private var bootstrap: Task<AppCoordinator, Never>?

    init() {}

    /// Called by TenraApp immediately after it constructs its coordinator.
    func register(_ coordinator: AppCoordinator) {
        guard self.coordinator == nil else { return }
        self.coordinator = coordinator
    }

    func services() async -> IntentServices {
        IntentServices(coordinator: await resolveCoordinator())
    }

    private func resolveCoordinator() async -> AppCoordinator {
        if let coordinator { return coordinator }
        if let bootstrap { return await bootstrap.value }

        let task = Task { @MainActor () -> AppCoordinator in
            let created = AppCoordinator()
            await created.initializeFastPath()
            return created
        }
        bootstrap = task
        let created = await task.value
        if coordinator == nil { coordinator = created }
        return created
    }
}

@MainActor
struct IntentServices {
    let coordinator: AppCoordinator

    var store: TransactionStore { coordinator.transactionStore }
    var accounts: AccountsViewModel { coordinator.accountsViewModel }
    var categories: CategoriesViewModel { coordinator.categoriesViewModel }
    var settings: SettingsViewModel { coordinator.settingsViewModel }
}
```

Before writing this, open `Tenra/ViewModels/AppCoordinator.swift` and confirm the exact property names (`transactionStore`, `accountsViewModel`, `categoriesViewModel`, `settingsViewModel`) and their access level. Adjust the accessors to whatever the coordinator actually exposes; do not add new public surface to `AppCoordinator` unless a property is private.

- [ ] **Step 4: Register from TenraApp**

In `Tenra/TenraApp.swift`, immediately after `let c = AppCoordinator()` (line 68):

```swift
                IntentEnvironment.shared.register(c)
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/IntentEnvironmentTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Services/Intents/IntentEnvironment.swift Tenra/TenraApp.swift TenraTests/Services/Intents/IntentEnvironmentTests.swift
git commit -m "feat(intents): add IntentEnvironment bootstrap for headless intent runs"
```

---

## Task 5: SpendingQueryService

**Files:**
- Create: `Tenra/Services/Intents/SpendingQueryService.swift`
- Test: `TenraTests/Services/Intents/SpendingQueryServiceTests.swift`

**Interfaces:**
- Consumes: `NSManagedObjectContext`, `TransactionEntity`, `CurrencyConverter.convertSync`, `FastDateParser`.
- Produces: `enum SpendingPeriod { case today, thisWeek, thisMonth }` and `SpendingQueryService.total(period:baseCurrency:context:now:) throws -> SpendingTotal`, where `SpendingTotal` has `amount: Double`, `currency: String`, `transactionCount: Int`.

This service deliberately does **not** read `TransactionStore`: in a cold intent process the in-memory array is empty, and loading 19k transactions is exactly what the fast path avoids.

- [ ] **Step 1: Write the failing tests**

Create `TenraTests/Services/Intents/SpendingQueryServiceTests.swift`:

```swift
//
//  SpendingQueryServiceTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

/// `.serialized` is required: Swift Testing runs tests in parallel by default,
/// and parallel in-memory containers sharing a name can share backing stores.
/// This mirrors `TenraTests/CoreDataRoundTripTests.swift:22`.
@MainActor
@Suite(.serialized) struct SpendingQueryServiceTests {

    // MARK: - Fixtures

    /// Copied from CoreDataRoundTripTests.makeInMemoryContainer (lines 29-42).
    private func makeContext() throws -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "Tenra")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(string: "memory://\(UUID().uuidString)")
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError { throw error }
        return container.viewContext
    }

    private func seedExpense(
        in context: NSManagedObjectContext,
        amount: Double,
        currency: String,
        date: String
    ) throws {
        let entity = TransactionEntity(context: context)
        entity.id = UUID().uuidString
        entity.date = date
        entity.amount = amount
        entity.currency = currency
        entity.type = TransactionType.expense.rawValue
        entity.category = "Food"
        entity.accountId = "a1"
        try context.save()
    }

    /// 2026-07-31 12:00 UTC, a fixed "now" so period boundaries are deterministic.
    private var now: Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 7, day: 31, hour: 12
        ).date!
    }

    // MARK: - Tests

    @Test("An empty period totals zero, not nil")
    func emptyPeriod() throws {
        let context = try makeContext()
        let total = try SpendingQueryService.total(
            period: .today,
            baseCurrency: "KZT",
            context: context,
            now: now
        )
        #expect(total.amount == 0)
        #expect(total.transactionCount == 0)
        #expect(total.currency == "KZT")
    }

    @Test("Only expenses inside the period are counted")
    func periodBoundaries() throws {
        let context = try makeContext()
        try seedExpense(in: context, amount: 1000, currency: "KZT", date: "2026-07-31")
        try seedExpense(in: context, amount: 500, currency: "KZT", date: "2026-07-30")

        let today = try SpendingQueryService.total(
            period: .today,
            baseCurrency: "KZT",
            context: context,
            now: now
        )
        #expect(today.amount == 1000)
        #expect(today.transactionCount == 1)

        let month = try SpendingQueryService.total(
            period: .thisMonth,
            baseCurrency: "KZT",
            context: context,
            now: now
        )
        #expect(month.amount == 1500)
        #expect(month.transactionCount == 2)
    }

    @Test("Multi-currency totals are expressed in the base currency")
    func multiCurrencyTotal() throws {
        // Guards CLAUDE.md red flag #6: summing Transaction.convertedAmount
        // across currencies produces "$20 + $100 = 120 KZT". This test fails if
        // anyone reintroduces that.
        CurrencyRateStore.shared.clearAll()
        seedRates()

        let context = try makeContext()
        try seedExpense(in: context, amount: 1000, currency: "KZT", date: "2026-07-31")
        try seedExpense(in: context, amount: 10, currency: "USD", date: "2026-07-31")

        let total = try SpendingQueryService.total(
            period: .today,
            baseCurrency: "KZT",
            context: context,
            now: now
        )
        // 1000 KZT + (10 USD × 540) = 6400 KZT, not 1010.
        #expect(total.amount == 6400)
    }
}
```

Two things to resolve against the real code before this compiles:

1. **`seedRates()`** — write it using whatever rate-seeding API `TenraTests/Services/Currency/` already uses against `CurrencyRateStore.shared`; read one of those suites and copy the call. The rates needed are KZT and USD such that `convertSync(amount: 10, from: "USD", to: "KZT")` returns `5400`. `clearAll()` is confirmed to exist and is mandatory in any suite touching this singleton.
2. **`TransactionEntity` attribute names** — open `Tenra/CoreData/Entities/` and confirm `id`, `date`, `amount`, `currency`, `type`, `category`, `accountId` and their optionality; adjust the seeding accordingly.

Add `import CoreData` to the test file.

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/SpendingQueryServiceTests 2>&1 | grep -aE "error:|Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: `cannot find 'SpendingQueryService' in scope`.

- [ ] **Step 3: Implement the service**

Create `Tenra/Services/Intents/SpendingQueryService.swift`:

```swift
//
//  SpendingQueryService.swift
//  Tenra
//
//  Period totals for CheckSpendingIntent.
//
//  Reads CoreData directly with a bounded date predicate instead of going
//  through TransactionStore: an intent process has an empty in-memory
//  transactions array by design, and loading 19k rows is precisely the cost the
//  fast-path bootstrap exists to avoid.
//

import Foundation
import CoreData

enum SpendingPeriod {
    case today
    case thisWeek
    case thisMonth
}

struct SpendingTotal: Equatable {
    let amount: Double
    let currency: String
    let transactionCount: Int
}

enum SpendingQueryService {

    static func total(
        period: SpendingPeriod,
        baseCurrency: String,
        context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> SpendingTotal {

        let start = startDate(for: period, now: now, calendar: calendar)
        let formatter = DateFormatters.dateFormatter
        let startKey = formatter.string(from: start)
        let endKey = formatter.string(from: now)

        let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@ AND type == %@",
            startKey, endKey, TransactionType.expense.rawValue
        )

        let rows = try context.fetch(request)

        var sum: Double = 0
        for row in rows {
            let currency = row.currency ?? baseCurrency
            // Convert each row into the base currency. Never sum
            // convertedAmount across currencies: it is stored in ACCOUNT
            // currency, not base currency.
            if let converted = CurrencyConverter.convertSync(
                amount: row.amount,
                from: currency,
                to: baseCurrency
            ) {
                sum += converted
            } else {
                // Cold cache: fall back to the stored per-account conversion,
                // which is right whenever the account is already in the base
                // currency and is the closest available approximation otherwise.
                sum += row.convertedAmount?.doubleValue ?? row.amount
            }
        }

        return SpendingTotal(
            amount: sum,
            currency: baseCurrency,
            transactionCount: rows.count
        )
    }

    private static func startDate(
        for period: SpendingPeriod,
        now: Date,
        calendar: Calendar
    ) -> Date {
        switch period {
        case .today:
            return calendar.startOfDay(for: now)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
        }
    }
}
```

Open `Tenra/CoreData/Entities/` and confirm the attribute names and types on `TransactionEntity` (`date`, `amount`, `currency`, `convertedAmount`, `type`) before finalizing; adjust the predicate and the accessors to match. Note `date` is stored as the canonical `"yyyy-MM-dd"` string, which is why the predicate compares formatted strings and sorts correctly lexicographically. If you need to parse those keys anywhere, use `FastDateParser`, never `DateFormatter.date(from:)` in a loop.

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/SpendingQueryServiceTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Intents/SpendingQueryService.swift TenraTests/Services/Intents/
git commit -m "feat(intents): add bounded spending query for period totals"
```

---

## Task 6: Usage counters

**Files:**
- Create: `Tenra/Services/Intents/IntentUsageCounters.swift`
- Modify: `Tenra/Views/Experiments/ExperimentsListView.swift`
- Test: `TenraTests/Services/Intents/IntentUsageCountersTests.swift`

**Interfaces:**
- Produces: `IntentUsageCounters` with `record(_ event: Event)`, `snapshot() -> Snapshot`, `reset()`; `enum Event { case intentAdd, manualAdd, intentFallbackToApp }`; `struct Snapshot { let intentAdds, manualAdds, fallbacks: Int }`.

App Privacy stays "Data Not Collected". These counters are local only and nothing leaves the device.

- [ ] **Step 1: Write the failing tests**

Create `TenraTests/Services/Intents/IntentUsageCountersTests.swift`:

```swift
//
//  IntentUsageCountersTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@Suite struct IntentUsageCountersTests {

    private func makeCounters(_ suite: String) -> IntentUsageCounters {
        UserDefaults().removePersistentDomain(forName: suite)
        return IntentUsageCounters(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test("A fresh store reports zeros")
    func startsAtZero() {
        let counters = makeCounters("intent.counters.1")
        let snapshot = counters.snapshot()
        #expect(snapshot.intentAdds == 0)
        #expect(snapshot.manualAdds == 0)
        #expect(snapshot.fallbacks == 0)
    }

    @Test("Each event increments only its own counter")
    func incrementsIndependently() {
        let counters = makeCounters("intent.counters.2")
        counters.record(.intentAdd)
        counters.record(.intentAdd)
        counters.record(.manualAdd)
        counters.record(.intentFallbackToApp)

        let snapshot = counters.snapshot()
        #expect(snapshot.intentAdds == 2)
        #expect(snapshot.manualAdds == 1)
        #expect(snapshot.fallbacks == 1)
    }

    @Test("Counts survive a new instance over the same defaults")
    func persists() {
        let suite = "intent.counters.3"
        let first = makeCounters(suite)
        first.record(.intentAdd)

        let second = IntentUsageCounters(defaults: UserDefaults(suiteName: suite)!)
        #expect(second.snapshot().intentAdds == 1)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/IntentUsageCountersTests 2>&1 | grep -aE "error:|Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: `cannot find 'IntentUsageCounters' in scope`.

- [ ] **Step 3: Implement the counters**

Create `Tenra/Services/Intents/IntentUsageCounters.swift`:

```swift
//
//  IntentUsageCounters.swift
//  Tenra
//
//  Local-only usage counters. The app ships with App Privacy set to "Data Not
//  Collected" and has no analytics SDK, so this is the only way to see whether
//  intents are actually being used. Nothing leaves the device; the numbers are
//  read in ExperimentsListView.
//
//  The ratio that matters is fallbacks / (intentAdds + fallbacks): it is the
//  health metric for the parser. A rising share means phrases are failing to
//  resolve and users are being bounced into the app.
//

import Foundation

final class IntentUsageCounters: @unchecked Sendable {

    static let shared = IntentUsageCounters()

    enum Event: String {
        case intentAdd = "intent.usage.intentAdds"
        case manualAdd = "intent.usage.manualAdds"
        case intentFallbackToApp = "intent.usage.fallbacks"
    }

    struct Snapshot {
        let intentAdds: Int
        let manualAdds: Int
        let fallbacks: Int
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(_ event: Event) {
        defaults.set(defaults.integer(forKey: event.rawValue) + 1, forKey: event.rawValue)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            intentAdds: defaults.integer(forKey: Event.intentAdd.rawValue),
            manualAdds: defaults.integer(forKey: Event.manualAdd.rawValue),
            fallbacks: defaults.integer(forKey: Event.intentFallbackToApp.rawValue)
        )
    }

    func reset() {
        for event in [Event.intentAdd, .manualAdd, .intentFallbackToApp] {
            defaults.removeObject(forKey: event.rawValue)
        }
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/IntentUsageCountersTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: 3 passed.

- [ ] **Step 5: Surface the counters in Experiments**

Replace the body of `Tenra/Views/Experiments/ExperimentsListView.swift`:

```swift
import SwiftUI

struct ExperimentsListView: View {

    @State private var snapshot = IntentUsageCounters.shared.snapshot()

    var body: some View {
        List {
            NavigationLink {
                KeyboardToolbarExperiment()
            } label: {
                Label("Keyboard Toolbar", systemImage: "keyboard")
            }

            Section("Intent usage (local only)") {
                LabeledContent("Added via intents", value: "\(snapshot.intentAdds)")
                LabeledContent("Added manually", value: "\(snapshot.manualAdds)")
                LabeledContent("Fell back to app", value: "\(snapshot.fallbacks)")
                Button("Reset counters") {
                    IntentUsageCounters.shared.reset()
                    snapshot = IntentUsageCounters.shared.snapshot()
                }
            }
        }
        .navigationTitle("Эксперименты")
        .onAppear { snapshot = IntentUsageCounters.shared.snapshot() }
    }
}

#Preview {
    NavigationStack {
        ExperimentsListView()
    }
}
```

This screen is developer-only and already hard-codes a Russian title, so its strings stay unlocalized to match.

- [ ] **Step 6: Record manual adds**

In `Tenra/ViewModels/TransactionsViewModel.swift`, in `addTransaction` right beside the existing `RatingPromptService.shared.recordTransactionAdded()` call (line 186):

```swift
                IntentUsageCounters.shared.record(.manualAdd)
```

- [ ] **Step 7: Build and commit**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
git add Tenra/Services/Intents/IntentUsageCounters.swift Tenra/Views/Experiments/ExperimentsListView.swift Tenra/ViewModels/TransactionsViewModel.swift TenraTests/Services/Intents/IntentUsageCountersTests.swift
git commit -m "feat(intents): add local-only usage counters"
```

---

## Task 7: Handoff into the app

When a draft cannot be resolved, the intent opens the app with the parsed operation prefilled. This task builds the channel.

**Files:**
- Create: `Tenra/Services/Intents/IntentHandoff.swift`
- Modify: `Tenra/Views/Home/MainTabView.swift`

**Interfaces:**
- Produces: `IntentHandoff.shared` (`@Observable`, `@MainActor`) with `var pendingOperation: ParsedOperation?` and `func request(_ operation: ParsedOperation)`.

- [ ] **Step 1: Implement the handoff channel**

Create `Tenra/Services/Intents/IntentHandoff.swift`:

```swift
//
//  IntentHandoff.swift
//  Tenra
//
//  Carries a ParsedOperation from an intent that could not complete headlessly
//  into the running UI, where the existing voice confirmation screen finishes
//  the job. Set by the intent immediately before it returns .openAppWhenRun;
//  consumed and cleared by MainTabView.
//

import Foundation
import Observation

@MainActor
@Observable
final class IntentHandoff {
    static let shared = IntentHandoff()

    var pendingOperation: ParsedOperation?

    private init() {}

    func request(_ operation: ParsedOperation) {
        pendingOperation = operation
        IntentUsageCounters.shared.record(.intentFallbackToApp)
    }
}
```

- [ ] **Step 2: Present the confirmation sheet on handoff**

In `Tenra/Views/Home/MainTabView.swift`, add to the `TabView` modifier chain, next to the existing `.sheet` driven by `shouldShowSurvey`:

```swift
        .sheet(item: Binding(
            get: { IntentHandoff.shared.pendingOperation },
            set: { IntentHandoff.shared.pendingOperation = $0 }
        )) { operation in
            VoiceInputConfirmationView(operation: operation)
        }
```

`ParsedOperation` is already `Identifiable`. Read the current initializer of `VoiceInputConfirmationView` (it takes the parsed values plus its view-model dependencies) and pass exactly what it requires; if it needs environment objects that `MainTabView` already holds, thread them through here rather than changing the view's signature.

The single-operation path is free for all users, so **do not** put a Pro gate on this sheet. The Pro gate stays on the Voice tab itself.

- [ ] **Step 3: Build and check previews**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

Expected: no output. Open `MainTabView.swift` in Xcode and render its previews by hand.

- [ ] **Step 4: Commit**

```bash
git add Tenra/Services/Intents/IntentHandoff.swift Tenra/Views/Home/MainTabView.swift
git commit -m "feat(intents): add handoff channel for intents that must open the app"
```

---

## Task 8: LogTransactionIntent

The primary intent: one free-form phrase, one shot.

**Files:**
- Create: `Tenra/Intents/LogTransactionIntent.swift`
- Create: `Tenra/Intents/Snippets/TransactionConfirmationSnippet.swift`

**Interfaces:**
- Consumes: `IntentEnvironment.shared.services()`, `VoiceInputParser`, `TransactionDraftService`, `IntentHandoff.shared`, `IntentUsageCounters.shared`, `PremiumManager.shared.isPro`.
- Produces: `LogTransactionIntent` conforming to `AppIntent`, with `@Parameter var phrase: String`.

- [ ] **Step 1: Build the confirmation snippet**

Create `Tenra/Intents/Snippets/TransactionConfirmationSnippet.swift`:

```swift
//
//  TransactionConfirmationSnippet.swift
//  Tenra
//
//  Shown before an intent commits. Every guessed field is marked, which is what
//  makes it acceptable for the resolver to guess at all.
//

import SwiftUI

struct TransactionConfirmationSnippet: View {
    let draft: TransactionDraft
    let accountName: String

    private var categoryWasGuessed: Bool {
        draft.warnings.contains { if case .categorySubstituted = $0 { return true } else { return false } }
    }

    private var accountWasGuessed: Bool {
        draft.warnings.contains(.accountInferred)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            FormattedAmountText(
                amount: draft.amount,
                currency: draft.currency,
                type: draft.type
            )
            .font(.title2.weight(.semibold))

            row(label: String(localized: "intent.snippet.category"),
                value: draft.categoryName,
                guessed: categoryWasGuessed)

            row(label: String(localized: "intent.snippet.account"),
                value: accountName,
                guessed: accountWasGuessed)
        }
        .padding(AppSpacing.medium)
    }

    private func row(label: String, value: String, guessed: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(guessed ? "\(value) \(String(localized: "intent.snippet.guessed"))" : value)
        }
        .font(.subheadline)
    }
}
```

Check `FormattedAmountText`'s actual initializer in `Tenra/Views/Components/` and match it. Do **not** format the amount by hand: `Text("\(amount) \(currency)")` and ad-hoc `NumberFormatter` are forbidden in this codebase.

- [ ] **Step 2: Implement the intent**

Create `Tenra/Intents/LogTransactionIntent.swift`:

```swift
//
//  LogTransactionIntent.swift
//  Tenra
//
//  One spoken phrase, one transaction. Declared in the main app target, so it
//  runs in the app's own process: no extension, no App Group.
//
//  The phrase is embedded in the App Shortcut phrase itself (see
//  TenraShortcuts), which is what makes this one-shot rather than a multi-turn
//  Siri interrogation. A three-turn dialogue would be slower than opening the
//  app and would defeat the point.
//

import AppIntents
import SwiftUI

struct LogTransactionIntent: AppIntent {

    static var title: LocalizedStringResource = "intent.log.title"
    static var description = IntentDescription("intent.log.description")

    /// Blocking issues hand the parsed operation to the UI, so the app must come
    /// forward in that case. openAppWhenRun is toggled at runtime rather than
    /// declared, so the happy path stays fully headless.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "intent.log.parameter.phrase")
    var phrase: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {

        let services = await IntentEnvironment.shared.services()

        let parser = VoiceInputParser(
            categoriesViewModel: services.categories,
            accountsViewModel: services.accounts,
            transactionsViewModel: nil
        )

        let operations = parser.parseMulti(phrase)
        guard let first = operations.first else {
            return .result(dialog: "intent.log.notUnderstood")
        }

        let result = TransactionDraftService.makeDraft(
            from: first,
            accounts: services.accounts.accounts,
            categories: services.categories.customCategories,
            learned: .shared,
            conversion: .cachedOnly,
            note: phrase
        )

        switch result {
        case .failure:
            // Amount missing, no eligible account, no Other category, or a cold
            // FX cache. Hand it to the UI with the fields prefilled; no network
            // call is attempted here.
            IntentHandoff.shared.request(first)
            Self.openAppWhenRun = true
            return .result(dialog: "intent.log.openingApp")

        case .success(let draft):
            let accountName = services.accounts.accounts
                .first { $0.id == draft.accountId }?.name ?? ""

            try await requestConfirmation(
                result: .result(dialog: "intent.log.confirm") {
                    TransactionConfirmationSnippet(draft: draft, accountName: accountName)
                }
            )

            _ = try await TransactionDraftService.commit(
                draft,
                store: services.store,
                categoriesViewModel: services.categories
            )
            IntentUsageCounters.shared.record(.intentAdd)

            let amountText = Formatting.formatCurrencySmart(draft.amount, currency: draft.currency)

            if operations.count > 1, !PremiumManager.shared.isPro {
                // Nothing is silently dropped: say exactly what was saved and
                // what was not.
                return .result(dialog: IntentDialog(
                    LocalizedStringResource(
                        "intent.log.savedWithProHint",
                        defaultValue: "Added \(amountText), \(draft.categoryName). The phrase contained \(operations.count - 1) more operations. Logging several at once is part of Tenra Pro."
                    )
                ))
            }

            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "intent.log.saved",
                    defaultValue: "Added \(amountText), \(draft.categoryName)."
                )
            ))
        }
    }
}
```

Two things to verify against the real APIs before finalizing:
1. `VoiceInputParser`'s initializer — check `Tenra/Views/Home/TabViews.swift:87-99` for how it is constructed in production and mirror that argument list exactly.
2. `PremiumManager.shared.isPro` — confirm the property name in `Tenra/Services/Premium/PremiumManager.swift`. Only `PremiumManager` may import RevenueCat; do not import it here.

Multi-operation handling for **Pro** users is deliberately not implemented in this task. Committing every operation needs its own confirmation UX and belongs in a follow-up; for now Pro users get the same first-operation behavior without the hint line.

- [ ] **Step 3: Add the English strings**

Add to `Tenra/en.lproj/Localizable.strings` (other locales come in Task 11):

```
"intent.log.title" = "Log a transaction";
"intent.log.description" = "Say an amount and what it was for, and Tenra records it.";
"intent.log.parameter.phrase" = "Phrase";
"intent.log.notUnderstood" = "I could not find an amount in that.";
"intent.log.openingApp" = "Opening Tenra so you can finish this one.";
"intent.log.confirm" = "Add this transaction?";
"intent.snippet.category" = "Category";
"intent.snippet.account" = "Account";
"intent.snippet.guessed" = "(guessed)";
```

No em dashes in any of this copy.

- [ ] **Step 4: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Intents/ Tenra/en.lproj/Localizable.strings
git commit -m "feat(intents): add LogTransactionIntent with confirmation snippet"
```

---

## Task 9: AddExpenseIntent and app entities

**Files:**
- Create: `Tenra/Intents/Entities/AccountAppEntity.swift`
- Create: `Tenra/Intents/Entities/CategoryAppEntity.swift`
- Create: `Tenra/Intents/AddExpenseIntent.swift`

**Interfaces:**
- Consumes: `IntentEnvironment.shared.services()`, `TransactionDraftService`.
- Produces: `AccountAppEntity`, `CategoryAppEntity`, `AddExpenseIntent`.

Confirmation rule for this intent: **confirm only when a field was defaulted.** When the user supplied every parameter (the normal case in a Shortcuts automation or an Action Button binding) it commits directly, because forcing a prompt would make automations unusable.

- [ ] **Step 1: Implement the entities**

Create `Tenra/Intents/Entities/AccountAppEntity.swift`:

```swift
//
//  AccountAppEntity.swift
//  Tenra
//
//  Lets the Shortcuts app show a picker of real accounts instead of asking the
//  user to type an identifier.
//

import AppIntents

struct AccountAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "intent.entity.account"
    )
    static var defaultQuery = AccountEntityQuery()

    var id: String
    var name: String
    var currency: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(currency)")
    }
}

struct AccountEntityQuery: EntityQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [AccountAppEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountAppEntity] {
        let services = await IntentEnvironment.shared.services()
        return services.accounts.accounts
            .filter { !$0.isLoan && !$0.isDeposit }
            .map { AccountAppEntity(id: $0.id, name: $0.name, currency: $0.currency) }
    }
}
```

Create `Tenra/Intents/Entities/CategoryAppEntity.swift` with the same shape, backed by `services.categories.customCategories`, exposing `id`, `name` and `type: TransactionType`, and filtering `suggestedEntities()` to `.expense` categories.

- [ ] **Step 2: Implement the intent**

Create `Tenra/Intents/AddExpenseIntent.swift`:

```swift
//
//  AddExpenseIntent.swift
//  Tenra
//
//  Typed-parameter sibling of LogTransactionIntent, for the Shortcuts app:
//  automations, the Action Button, and the Shortcuts widget.
//

import AppIntents

struct AddExpenseIntent: AppIntent {

    static var title: LocalizedStringResource = "intent.addExpense.title"
    static var description = IntentDescription("intent.addExpense.description")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "intent.addExpense.parameter.amount")
    var amount: Double

    @Parameter(title: "intent.addExpense.parameter.category")
    var category: CategoryAppEntity?

    @Parameter(title: "intent.addExpense.parameter.account")
    var account: AccountAppEntity?

    @Parameter(title: "intent.addExpense.parameter.note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {

        let services = await IntentEnvironment.shared.services()

        let operation = ParsedOperation(
            type: .expense,
            amount: Decimal(amount),
            currencyCode: account?.currency,
            date: Date(),
            accountId: account?.id,
            categoryName: category?.name,
            subcategoryNames: [],
            note: note ?? ""
        )

        let result = TransactionDraftService.makeDraft(
            from: operation,
            accounts: services.accounts.accounts,
            categories: services.categories.customCategories,
            learned: .shared,
            conversion: .cachedOnly,
            note: note ?? ""
        )

        switch result {
        case .failure:
            IntentHandoff.shared.request(operation)
            Self.openAppWhenRun = true
            return .result(dialog: "intent.addExpense.openingApp")

        case .success(let draft):
            // Confirm only when something was defaulted. A fully specified call
            // from an automation must not stop and ask.
            if !draft.warnings.isEmpty {
                let accountName = services.accounts.accounts
                    .first { $0.id == draft.accountId }?.name ?? ""
                try await requestConfirmation(
                    result: .result(dialog: "intent.addExpense.confirm") {
                        TransactionConfirmationSnippet(draft: draft, accountName: accountName)
                    }
                )
            }

            _ = try await TransactionDraftService.commit(
                draft,
                store: services.store,
                categoriesViewModel: services.categories
            )
            IntentUsageCounters.shared.record(.intentAdd)

            let amountText = Formatting.formatCurrencySmart(draft.amount, currency: draft.currency)
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "intent.addExpense.saved",
                    defaultValue: "Added \(amountText), \(draft.categoryName)."
                )
            ))
        }
    }
}
```

- [ ] **Step 3: Add the English strings**

```
"intent.addExpense.title" = "Add an expense";
"intent.addExpense.description" = "Record an expense with a specific amount, category and account.";
"intent.addExpense.parameter.amount" = "Amount";
"intent.addExpense.parameter.category" = "Category";
"intent.addExpense.parameter.account" = "Account";
"intent.addExpense.parameter.note" = "Note";
"intent.addExpense.confirm" = "Add this expense?";
"intent.addExpense.openingApp" = "Opening Tenra so you can finish this one.";
"intent.entity.account" = "Account";
"intent.entity.category" = "Category";
```

- [ ] **Step 4: Build and commit**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
git add Tenra/Intents/ Tenra/en.lproj/Localizable.strings
git commit -m "feat(intents): add AddExpenseIntent with account and category entities"
```

---

## Task 10: CheckSpendingIntent

**Files:**
- Create: `Tenra/Intents/CheckSpendingIntent.swift`
- Create: `Tenra/Intents/Snippets/SpendingSummarySnippet.swift`

**Interfaces:**
- Consumes: `SpendingQueryService.total(period:baseCurrency:context:now:)`, `IntentEnvironment`, `CoreDataStack.shared.persistentContainer.viewContext`.
- Produces: `CheckSpendingIntent`, `SpendingPeriodAppEnum`.

- [ ] **Step 1: Implement the intent**

Create `Tenra/Intents/CheckSpendingIntent.swift`:

```swift
//
//  CheckSpendingIntent.swift
//  Tenra
//
//  Read-only. Answers "how much did I spend today" without opening the app.
//  Goes through SpendingQueryService, which reads CoreData directly rather than
//  TransactionStore: an intent process has no transactions loaded.
//

import AppIntents
import SwiftUI

enum SpendingPeriodAppEnum: String, AppEnum {
    case today
    case thisWeek
    case thisMonth

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "intent.checkSpending.period"
    )

    static var caseDisplayRepresentations: [SpendingPeriodAppEnum: DisplayRepresentation] = [
        .today: "intent.checkSpending.period.today",
        .thisWeek: "intent.checkSpending.period.week",
        .thisMonth: "intent.checkSpending.period.month"
    ]

    var domain: SpendingPeriod {
        switch self {
        case .today: .today
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        }
    }
}

struct CheckSpendingIntent: AppIntent {

    static var title: LocalizedStringResource = "intent.checkSpending.title"
    static var description = IntentDescription("intent.checkSpending.description")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "intent.checkSpending.period", default: .today)
    var period: SpendingPeriodAppEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {

        let services = await IntentEnvironment.shared.services()
        let baseCurrency = services.settings.settings.baseCurrency

        let total = try SpendingQueryService.total(
            period: period.domain,
            baseCurrency: baseCurrency,
            context: CoreDataStack.shared.persistentContainer.viewContext
        )

        let amountText = Formatting.formatCurrencySmart(total.amount, currency: total.currency)

        return .result(
            dialog: IntentDialog(
                LocalizedStringResource(
                    "intent.checkSpending.answer",
                    defaultValue: "You have spent \(amountText)."
                )
            ),
            view: SpendingSummarySnippet(total: total, period: period)
        )
    }
}
```

Confirm `services.settings.settings.baseCurrency` against `SettingsViewModel`; `AppCoordinator.initializeFastPath` reads it at line 281 as `settingsViewModel.settings.baseCurrency`, so that path is known good.

- [ ] **Step 2: Implement the snippet**

Create `Tenra/Intents/Snippets/SpendingSummarySnippet.swift`:

```swift
//
//  SpendingSummarySnippet.swift
//  Tenra
//

import SwiftUI

struct SpendingSummarySnippet: View {
    let total: SpendingTotal
    let period: SpendingPeriodAppEnum

    private var periodLabel: String {
        switch period {
        case .today: String(localized: "intent.checkSpending.period.today")
        case .thisWeek: String(localized: "intent.checkSpending.period.week")
        case .thisMonth: String(localized: "intent.checkSpending.period.month")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(periodLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            FormattedAmountText(
                amount: total.amount,
                currency: total.currency,
                type: .expense
            )
            .font(.largeTitle.weight(.semibold))

            Text(String(
                format: String(localized: "intent.checkSpending.transactionCount"),
                total.transactionCount
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(AppSpacing.medium)
    }
}
```

`intent.checkSpending.transactionCount` is a plural and therefore belongs in `.stringsdict`, not `Localizable.strings`. Add it to `Tenra/en.lproj/Localizable.stringsdict` now and to every locale in Task 11 (ru/uk need one/few/many/other; ja/ko need other only; the rest need one/other).

- [ ] **Step 3: Add the English strings**

```
"intent.checkSpending.title" = "Check spending";
"intent.checkSpending.description" = "Ask Tenra how much you have spent.";
"intent.checkSpending.period" = "Period";
"intent.checkSpending.period.today" = "Today";
"intent.checkSpending.period.week" = "This week";
"intent.checkSpending.period.month" = "This month";
```

- [ ] **Step 4: Build and commit**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
git add Tenra/Intents/ Tenra/en.lproj/
git commit -m "feat(intents): add CheckSpendingIntent with period summary snippet"
```

---

## Task 11: App Shortcuts and full localization

The largest and most defect-prone task in the plan. Do not fold it into another one.

**Files:**
- Create: `Tenra/Intents/TenraShortcuts.swift`
- Create: `Tenra/<locale>.lproj/AppShortcuts.strings` × 11
- Modify: `Tenra/<locale>.lproj/Localizable.strings` × 11
- Modify: `Tenra/<locale>.lproj/Localizable.stringsdict` × 11

- [ ] **Step 1: Implement the shortcuts provider**

Create `Tenra/Intents/TenraShortcuts.swift`:

```swift
//
//  TenraShortcuts.swift
//  Tenra
//
//  Surfaces the intents in Siri, Spotlight and the Shortcuts app.
//
//  Every phrase MUST contain \(.applicationName) — the system rejects phrases
//  without it. The phrases themselves are localized in AppShortcuts.strings,
//  which is a separate file from Localizable.strings by system requirement.
//
//  The system caches this provider. Edited phrases do not take effect until the
//  app is reinstalled, which is expected and not a bug.
//

import AppIntents

struct TenraShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTransactionIntent(),
            phrases: [
                "Log \(\.$phrase) in \(.applicationName)",
                "Add \(\.$phrase) to \(.applicationName)",
                "\(.applicationName) \(\.$phrase)"
            ],
            shortTitle: "intent.log.title",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: CheckSpendingIntent(),
            phrases: [
                "How much did I spend in \(.applicationName)",
                "Check my spending in \(.applicationName)"
            ],
            shortTitle: "intent.checkSpending.title",
            systemImageName: "chart.pie.fill"
        )

        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)"
            ],
            shortTitle: "intent.addExpense.title",
            systemImageName: "plus.circle.fill"
        )
    }
}
```

- [ ] **Step 2: Author the localized phrases**

Create `Tenra/<locale>.lproj/AppShortcuts.strings` for all 11 locales. **This is authoring, not translation.** Each locale needs phrasings a person would actually say out loud in that language, and each must keep `${applicationName}`.

Russian, as the reference for the primary market:

```
"Log ${phrase} in ${applicationName}" = "Запиши ${phrase} в ${applicationName}";
"Add ${phrase} to ${applicationName}" = "Добавь ${phrase} в ${applicationName}";
"${applicationName} ${phrase}" = "${applicationName} ${phrase}";
"How much did I spend in ${applicationName}" = "Сколько я потратил в ${applicationName}";
"Check my spending in ${applicationName}" = "Проверь траты в ${applicationName}";
"Add an expense in ${applicationName}" = "Добавь трату в ${applicationName}";
```

Do the same for de, es, fr, tr, pt-BR, it, uk, ja, ko. The `en` file maps each key to itself.

- [ ] **Step 3: Translate the interface strings**

Add every `intent.*` key introduced in Tasks 8, 9 and 10 to the remaining 10 `Localizable.strings` files, and `intent.checkSpending.transactionCount` to all 11 `.stringsdict` files.

Use `python3` with `io.open(encoding="utf-8")` to insert them. **Never `perl -CSD`** — it re-encodes the script's own UTF-8 bytes and produces mojibake in non-ASCII locales.

Where a translation reorders arguments relative to English, use positional specifiers (`%1$@`, `%2$@`) and never mix positional and plain specifiers in one string.

- [ ] **Step 4: Verify parity**

For each locale, both files must have exactly the same key set as English:

```bash
for L in ru de es fr tr pt-BR it uk ja ko; do
  echo "== $L =="
  diff <(grep -oE '^"[^"]+"' Tenra/en.lproj/Localizable.strings | sort) \
       <(grep -oE '^"[^"]+"' Tenra/$L.lproj/Localizable.strings | sort)
  diff <(grep -oE '^"[^"]+"' Tenra/en.lproj/AppShortcuts.strings | sort) \
       <(grep -oE '^"[^"]+"' Tenra/$L.lproj/AppShortcuts.strings | sort)
done
```

Expected: no output at all. Any line printed is a missing or extra key.

- [ ] **Step 5: Verify encoding**

```bash
grep -n "intent.log.title" Tenra/ru.lproj/Localizable.strings Tenra/ja.lproj/Localizable.strings
```

Expected: readable Cyrillic and Japanese, no `Ð`/`Ñ` sequences. If mojibake appears, the file was written with the wrong encoding; revert it and redo Step 3 with `python3`.

- [ ] **Step 6: Build and commit**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
git add Tenra/Intents/TenraShortcuts.swift Tenra/*.lproj/
git commit -m "feat(intents): add App Shortcuts provider and localize to 11 locales"
```

---

## Task 12: Settings discoverability section

A feature nobody finds produces no retention. This is not optional polish.

**Files:**
- Create: `Tenra/Views/Settings/SettingsSiriSection.swift`
- Modify: `Tenra/Views/Settings/SettingsView.swift` (section list at lines 67-76)

- [ ] **Step 1: Build the section**

Create `Tenra/Views/Settings/SettingsSiriSection.swift`:

```swift
//
//  SettingsSiriSection.swift
//  Tenra
//
//  Teaches the Siri phrases. Without this, App Shortcuts are discoverable only
//  by accident, and an undiscovered feature has no effect on retention.
//

import SwiftUI
import AppIntents

struct SettingsSiriSection: View {
    var body: some View {
        Section {
            ForEach(Self.examplePhrases, id: \.self) { phrase in
                Label(phrase, systemImage: "quote.bubble")
                    .font(.subheadline)
            }
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
        } header: {
            Text("settings.siri.header")
        } footer: {
            Text("settings.siri.footer")
        }
    }

    private static var examplePhrases: [String] {
        [
            String(localized: "settings.siri.example1"),
            String(localized: "settings.siri.example2"),
            String(localized: "settings.siri.example3")
        ]
    }
}
```

English strings (translate into the other 10 in the same pass, and re-run the Task 11 parity check):

```
"settings.siri.header" = "Siri & Shortcuts";
"settings.siri.footer" = "Say one of these to Siri and Tenra records the transaction without opening.";
"settings.siri.example1" = "Hey Siri, log 3000 for coffee in Tenra";
"settings.siri.example2" = "Hey Siri, how much did I spend in Tenra";
"settings.siri.example3" = "Hey Siri, add an expense in Tenra";
```

- [ ] **Step 2: Insert it into SettingsView**

In `Tenra/Views/Settings/SettingsView.swift`, add between `notificationsSection` and `cloudSection` (lines 69-70):

```swift
                SettingsSiriSection()
```

- [ ] **Step 3: Donate the intent after the first in-app voice save**

`AppShortcutsProvider` surfaces the phrases in Spotlight and Siri Suggestions on its own, but a donation after a real successful voice entry is what makes the system suggest it at the moment the user is likely to repeat the action.

In `Tenra/Views/VoiceInput/VoiceInputConfirmationView.swift`, in the success branch of `resolveAndCommit` (added in Task 3), right before `HapticManager.success()`:

```swift
                await LogTransactionIntent.donate(phrase: originalText)
```

And add the helper to `Tenra/Intents/LogTransactionIntent.swift`:

```swift
extension LogTransactionIntent {
    /// Tells the system this action just happened for real, so it can offer it
    /// as a suggestion next time. Failures are ignored on purpose: a donation
    /// is a hint, never a requirement for the save that already succeeded.
    @MainActor
    static func donate(phrase: String) async {
        let intent = LogTransactionIntent()
        intent.phrase = phrase
        try? await intent.donate()
    }
}
```

Verify `donate()` against the AppIntents SDK surface for iOS 26 before finalizing:

```bash
grep -n "func donate" "$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface"
```

If the signature differs, use whatever the interface actually declares. Do not guess from documentation: API names in this SDK have been wrong in docs before.

- [ ] **Step 4: Verify parity, build, check previews**

```bash
for L in ru de es fr tr pt-BR it uk ja ko; do
  diff <(grep -oE '^"[^"]+"' Tenra/en.lproj/Localizable.strings | sort) \
       <(grep -oE '^"[^"]+"' Tenra/$L.lproj/Localizable.strings | sort)
done
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

Expected: no output from either. Then open `SettingsView.swift` in Xcode and render its previews by hand.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Views/Settings/ Tenra/Views/VoiceInput/ Tenra/Intents/ Tenra/*.lproj/
git commit -m "feat(settings): add Siri discoverability section and intent donation"
```

---

## Task 13: Documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Extend the file-organization tree**

In the project structure block, add under `Tenra/`:

```
├── Intents/             # App Intents / Siri surface (adapters only, logic lives in Services/Intents)
```

And in the "File Organization Decision Tree", under "Business logic?", add:

```
   ├─ App Intents / Siri? → Services/Intents/
```

- [ ] **Step 2: Add a trigger-table row**

In the "When to Read Which Doc" table:

```
| `Tenra/Intents/**`, `Services/Intents/**`, Siri, App Shortcuts | [specs/2026-07-31-app-intents-design.md](docs/superpowers/specs/2026-07-31-app-intents-design.md) |
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: register Intents folders in the project guide"
```

---

## Task 14: Device verification and version bump

Siri cannot be verified in the Simulator. This task runs on the physical device `Dkicekeeper 17`.

**Files:**
- Modify: `Tenra.xcodeproj/project.pbxproj`

- [ ] **Step 1: Bump the version**

In `Tenra.xcodeproj/project.pbxproj`, set every `MARKETING_VERSION = 1.0.2;` to `MARKETING_VERSION = 1.1;` and every `CURRENT_PROJECT_VERSION` to `1`.

```bash
grep -n "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" Tenra.xcodeproj/project.pbxproj
```

Expected: every `MARKETING_VERSION` reads `1.1`.

- [ ] **Step 2: Run the full test suite**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | grep -aE "Test case .* failed|\*\* TEST (SUCCEEDED|FAILED)"
```

Expected: `** TEST SUCCEEDED **`. If it prints `** TEST FAILED **` with zero failing case lines, that is the known parallel-clone flake: re-run once before investigating.

- [ ] **Step 3: Build and run on the physical device**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS,name=Dkicekeeper 17' 2>&1 | grep -E "error:" | head -30
```

A Simulator build never reaches the device. Install to the device from Xcode.

- [ ] **Step 4: Work through the device checklist**

Confirm each:

- [ ] "Hey Siri, log 3000 for coffee in Tenra" with the app force-quit → confirmation appears → transaction is saved, app never opens.
- [ ] Relaunch the app: the transaction is present and the account balance reflects it correctly.
- [ ] Same phrase with the app in the foreground → the Home screen updates without navigating away (the `mutationVersion` refresh contract).
- [ ] A phrase with no amount → the app opens with the confirmation screen prefilled.
- [ ] A phrase naming a currency the cache does not hold → the app opens rather than guessing.
- [ ] "Hey Siri, how much did I spend in Tenra" → correct total, in the base currency.
- [ ] Shortcuts app: all three intents appear; `AddExpenseIntent` shows real accounts and categories in its pickers.
- [ ] Spotlight: typing "Tenra" surfaces the shortcuts.
- [ ] Action Button bound to `AddExpenseIntent` with every parameter filled → commits without prompting.
- [ ] Settings → Siri & Shortcuts shows localized examples; `ShortcutsLink` opens the Shortcuts app.
- [ ] Switch the device language to Russian and repeat the first and sixth checks.
- [ ] A free (non-Pro) account can log a single transaction by voice through Siri.

If phrase edits do not take effect, delete and reinstall the app: the system caches `AppShortcutsProvider`.

- [ ] **Step 5: Commit**

```bash
git add Tenra.xcodeproj/project.pbxproj
git commit -m "chore: bump marketing version to 1.1"
```

---

## Task 15: App Store Connect release

App ID **6761530361**. Current live version is **1.0.2** (`READY_FOR_SALE`); there is no version in preparation, so 1.1 must be created. All steps use the `asc-mcp` tools.

**Confirm before starting:** run `company_switch` if `company_current` is not already the right account.

- [ ] **Step 1: Create version 1.1**

```
app_versions_create(app_id: "6761530361", version_string: "1.1", platform: "IOS")
```

Record the returned version id; every metadata call below needs it.

- [ ] **Step 2: Write What's New for all 13 ASC locales**

ASC has 13 metadata locales: `de-DE, en-US, es-ES, es-MX, fr-CA, fr-FR, it, ja, ko, pt-BR, ru, tr, uk`. That is two more than the 11 in-app locales (`es-MX`, `fr-CA`), so do not reuse the in-app locale list here.

English:

```
Log expenses with Siri, without opening the app.

• Say "Hey Siri, log 3000 for coffee in Tenra" and it is recorded
• Ask Siri how much you have spent today, this week or this month
• New Shortcuts actions for automations and the Action Button
• Bug fixes and performance improvements

Enjoying Tenra? Leave a review, it helps a lot.
```

Russian:

```
Записывайте траты через Siri, не открывая приложение.

• Скажите «Привет, Siri, запиши 3000 на кофе в Tenra» и трата сохранится
• Спросите у Siri, сколько вы потратили за день, неделю или месяц
• Новые команды для автоматизаций и кнопки действия
• Исправления и улучшения производительности

Нравится Tenra? Оставьте отзыв, это очень помогает.
```

Translate for the remaining 11 locales. **No em dashes anywhere.** Apply with `apps_update_metadata` per locale.

- [ ] **Step 3: Update promotional text**

Promotional text does not require a new build and can be changed later without review. English:

```
Log expenses by talking to Siri, no bank login and no sign-up. Your data stays on your device. Try Tenra Pro free for 14 days.
```

Apply per locale with `apps_update_metadata`.

- [ ] **Step 4: Add `siri` to the keyword field**

Current en-US keywords are 95 of 100 characters:

```
finance,spending,bill,saving,planner,wallet,cash,debt,loan,deposit,account,currency,daily,saver
```

Appending `,siri` brings it to exactly 100, so nothing has to be dropped. The RU/KZ set is also 95, so the same append fits.

**Verify the length per locale before writing** — do not assume:

```bash
python3 -c "print(len('finance,spending,bill,saving,planner,wallet,cash,debt,loan,deposit,account,currency,daily,saver,siri'))"
```

Expected: `100`. For any locale where the append would exceed 100, drop the single weakest existing keyword rather than truncating.

Do not change titles or subtitles in this release. The current keyword set is documented as volume-unvalidated guesses; changing several ASO variables at once would make the result unreadable.

- [ ] **Step 5: Produce and upload the Siri screenshot**

Add one frame showing the Siri interaction, using the existing pipeline: the `-ScreenshotDemo` scheme plus `capture_screenshots.sh`, with captions from the Figma "Screenshots L10n" file. Suggested captions, matching the locked caption style:

- EN: "Log it by talking" / "Say it to Siri and Tenra records the expense, no need to open the app"
- RU: «Записывайте голосом» / «Скажите Siri, и трата сохранится, приложение открывать не нужно»

Upload with `screenshots_upload_batch`, then `screenshots_reorder` so the new frame sits second, right after Home.

- [ ] **Step 6: Write App Review notes**

This matters more than usual: a reviewer who cannot figure out how to trigger the feature may reject it as non-functional. Use `app_versions_set_review_details`:

```
This version adds Siri support through App Intents.

To test:
1. Open the app once and complete onboarding (create one account, currency KZT or USD).
2. Say to Siri: "Log 3000 for coffee in Tenra"
3. A confirmation card appears showing amount, category and account. Confirm it.
4. Open the app: the transaction is in the list on the Home screen.
5. Say to Siri: "How much did I spend in Tenra" to see the daily total.

All Siri features work without a Tenra Pro subscription.
No account, no login and no server are involved: all data is stored locally on the device.
```

- [ ] **Step 7: Confirm the privacy declaration is unchanged**

This release adds no data collection. Confirm in ASC that App Privacy still reads "Data Not Collected" and change nothing. The usage counters are local `UserDefaults` values that never leave the device.

- [ ] **Step 8: Upload the build and attach it**

Archive and upload build `1.1 (1)` from Xcode, then:

```
builds_get_processing_status → wait for VALID
app_versions_attach_build(version_id, build_id)
```

- [ ] **Step 9: Enable phased release and submit**

```
app_versions_create_phased_release(version_id)
app_versions_submit_for_review(version_id)
```

Phased release matters here because the intents write financial data from a background process. If something is wrong, a 1% first-day exposure is a far cheaper way to find out.

- [ ] **Step 10: Update the marketing context**

In `app-marketing-context.md`, set the current version to 1.1, and note in `docs/RELEASE_1.1_PLAN.md` that the iPad workstream has moved to 1.2.

```bash
git add app-marketing-context.md docs/RELEASE_1.1_PLAN.md
git commit -m "docs: record 1.1 release scope and move iPad workstream to 1.2"
```

---

## Post-release watch

- Check `reviews_list` and `reviews_stats` daily for the first week. A background writer touching money is the kind of thing users report immediately.
- Check `metrics_app_perf` for launch-time regressions: `IntentEnvironment` adds a registration call on the startup path.
- Read the local counters in Settings → Experiments on your own device after a week of use. A high `fallbacks` share means the parser is failing on real phrases, which is the signal to invest in the parser rather than in more surfaces.
