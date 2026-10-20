# App Intents & Siri

Domain reference for `Tenra/Intents/**` (thin App Intents adapters) and `Services/Intents/**`
(the logic they call). The intents live in the main app target and run in the app's own
process: no extension, no App Group. Future work (quick-add templates, widgets, Control
Center, savings goals) is tracked in [backlog.md](../backlog.md).

How a parsed operation becomes a transaction draft (category, account, currency) is shared
with the in-app voice flow and documented once, in
[voice.md §Account & category resolution](voice.md#account--category-resolution-shared-with-app-intents).

---

## 1. Intents

### 1.1 `LogTransactionIntent`

One free-form phrase, parsed by `VoiceInputParser.parseMulti`; the first operation goes
through `TransactionDraftService`.

App Shortcut phrases may only interpolate `AppEntity` and `AppEnum` parameters: a `String`
parameter is rejected at build time by `appintentsmetadataprocessor` ("Invalid parameter
type. AppEntity and AppEnum are the only allowed types for phrase."). So via Siri it takes
two turns: the user says "Log a transaction in Tenra", Siri asks for the phrase (the
parameter's `requestValueDialog`), and the user speaks it. In the Shortcuts app the
free-text parameter is filled in one step. A one-shot Siri phrase would need categories and
amounts modelled as `AppEnum` / `AppEntity` parameters, a fixed grammar instead of free
phrasing.

### 1.2 `AddExpenseIntent`

Typed parameters for the Shortcuts app (automations, Action Button, Shortcuts widget):
amount, category (`CategoryAppEntity`), subcategory (`SubcategoryAppEntity`), account
(`AccountAppEntity`) and note. Categories and accounts are pickable lists, not free text.
The currency is the account's, the date is now. With no category but a merchant in the note,
the category comes from the merchant memory (§6).

### 1.3 `LogWalletPaymentIntent`

The action for the Wallet automation (§6): amount, currency code, merchant, card and an
optional account. Never asks and never comes to the foreground (`supportedModes = .background`):
what Tenra cannot know is saved as a guess and journaled for review.

### 1.4 `CheckSpendingIntent`

Read-only: spending today / this week / this month (`SpendingPeriod`), as a spoken dialog
plus a snippet. `authenticationPolicy = .requiresAuthentication`: totals need an unlocked
iPhone, while logging stays allowed from the lock screen (pinned by
`IntentAuthenticationPolicyTests`).

It must NOT read `TransactionStore`: in a cold intent process the in-memory array is empty,
and loading all transactions is what the fast path avoids. `SpendingQueryService` runs a
narrow fetch instead (§3.4).

---

## 2. UX rules

### 2.1 Confirmation

A financial write must never happen silently on a misheard phrase:

> **Confirmation is required whenever any field was inferred rather than explicitly supplied.**

- `LogTransactionIntent` always confirms — every field comes from parsing a phrase. The
  snippet renders amount, currency, category, account and date, and marks any field the
  resolver had to guess (`TransactionDraft.warnings`).
- `AddExpenseIntent` confirms only when `draft.warnings` is not empty. When the user supplied
  every parameter (an automation or an Action Button binding) it commits directly, because a
  prompt would make automations unusable.
- `LogWalletPaymentIntent` never confirms (owner's decision 2026-10-19): a card payment did
  happen, so it is saved at once and what was guessed is journaled for review instead (§6.1).

### 2.2 Blocking issues → open the app

`makeDraft` returns a `DraftIssue` only when it cannot produce a draft at all; everything it
can guess becomes a warning instead.

| `DraftIssue` | Condition |
|---|---|
| `missingAmount` | Parser found no amount, or it is ≤ 0. |
| `noEligibleAccount` | No account other than loans and deposits exists. |
| `needsFXConversion` | Phrase currency ≠ account currency and no cached rate. |

On an issue the intent hands the parsed operation to `IntentHandoff.shared` and escalates
to the foreground; `MainTabView` picks up `pendingOperation` and opens the voice
confirmation screen prefilled. Opening the app is a normal branch, not a failure. Intents
never make a network call: they pass `ConversionPolicy.cachedOnly` and treat
`needsFXConversion` as blocking. The one exception is `LogWalletPaymentIntent`, which asks for
the exchange rate once on a cache miss and otherwise queues the payment (§6, owner's decision
2026-10-19).

### 2.3 Pro gate

Logging a single operation via Siri is free for everyone; the in-app Voice tab stays
Pro-gated. Only the first operation of a phrase is saved. When `parseMulti` returns more
than one and the user is not Pro, the dialog says what was saved and how many operations were
left out, and that logging several at once is part of Tenra Pro
(`intent.log.savedWithProHint`).

### 2.4 Discoverability

- Settings → **Siri & Shortcuts** (`SettingsSiriSection`): localized example phrases, To
  review, the Wallet merchants and cards lists (§6) and a `ShortcutsLink` to the Shortcuts app.
- `VoiceInputConfirmationView` donates `LogTransactionIntent` after a successful in-app voice
  save (`LogTransactionIntent.donate(phrase:)`).
- `TenraShortcuts` (`AppShortcutsProvider`) surfaces the shortcuts in Spotlight and Siri
  suggestions. The system caches the provider: edited phrases apply only after a reinstall.

---

## 3. Architecture

### 3.1 Files

- `Tenra/Intents/`: the four intents, `TenraShortcuts`, `Entities/` (account, category,
  subcategory `AppEntity`s with their queries), `Snippets/` (`TransactionConfirmationSnippet`,
  `TransactionConfirmationSnippetIntent`, `SpendingSummarySnippet`).
- `Services/Intents/`: `IntentEnvironment`, `TransactionDraft` + `TransactionDraftService`,
  `IntentAccountSuggester`, `IntentSubcategoryStore`, `SpendingQueryService`, `IntentHandoff`,
  `IntentUsageCounters`, the Wallet action's `WalletPaymentResolver`, `WalletPaymentRecorder`,
  `WalletCaptureStore`, `CardAccountMemory`. `Services/Notifications/WalletReviewNotifier`
  and the Settings screens `WalletReviewView`, `WalletCardsView`, `MerchantCategoriesView`.

### 3.2 `IntentEnvironment`

Single entry point for live services from an intent, whatever the process state:

- If the app already built an `AppCoordinator`, return it. `TenraApp` registers it right after
  construction (`IntentEnvironment.shared.register`).
- Otherwise (the system launched the process only for the intent) lazily build one and
  `await initializeFastPath()`: accounts, settings and categories, no transactions.

The registration is what prevents a second coordinator and a second `TransactionStore` in the
same process (two stores would diverge in memory). `services()` returns `IntentServices`:
`store`, `accounts`, `categories`, `settings`, `transactions`, plus `makeParser()`, wired as the
Voice tab wires its parser. Pro status is read from `PremiumManager.shared`.

A headless write is safe: `TransactionStore.add` updates balances incrementally through
`BalanceCoordinator`, from the persisted account balance, so an empty in-memory transaction
array does no harm.

### 3.3 `TransactionDraftService`

One write path for the intents and `VoiceInputConfirmationView`, split so resolution is pure
and testable:

```swift
static func makeDraft(from: ParsedOperation, accounts: [Account], categories: [CustomCategory],
                      learned: VoiceLearningStore, conversion: ConversionPolicy = .cachedOnly,
                      note: String = "", suggestAccount: ((String) -> String?)? = nil)
    -> Result<TransactionDraft, DraftIssue>

static func commit(_ draft: TransactionDraft, store: TransactionStore,
                   categoriesViewModel: CategoriesViewModel, hooks: CommitHooks? = nil)
    async throws -> Transaction
```

`TransactionDraft.warnings: [DraftWarning]` holds `categorySubstituted(original:)` and
`accountInferred`. The intent snippet marks the guessed field; `VoiceInputConfirmationView`
shows the same warnings through its `categoryWarning` / `accountWarning` labels. There is no
"date was assumed" warning: `ParsedOperation.date` defaults to `Date()` with no flag telling a
parsed date from the default.

`commit` performs `store.add`, links subcategories, and runs `CommitHooks.production`:
`VoiceLearningStore.recordSave` (skipped for `accountInferred`, see voice.md) and
`RatingPromptService.recordTransactionAdded()`, which only counts and never presents the
prompt from a background process. ⚠️ **Before the store's full load, subcategory links go
through `IntentSubcategoryStore`**, one insert at a time against CoreData: the in-memory link
list is still empty then, and saving it through `CategoriesViewModel` would delete every
other transaction's links. When the app's own load is in flight, `commit` waits for it and
links through memory.

Pinned by `TransactionDraftResolverTests`, `TransactionDraftCommitTests`,
`IntentSubcategoryStoreTests`, `IntentAccountSuggesterTests`.

### 3.4 `SpendingQueryService`

A bounded `NSFetchRequest` over `TransactionEntity`: `date` between the period start and now,
`type` in the types that `summaryContribution(isFuture: false)` counts as expense (expenses
and loan payments, so Siri agrees with the home summary). Independent of `TransactionStore`
load state by design.

Each row is converted to the base currency with `CurrencyConverter.convertSync` (red flag
#6), with `convertedAmount` (or `amount`) only as a cold-cache fallback; summing
`convertedAmount` across currencies is forbidden. `SpendingQueryServiceTests` pins the period
bounds, the empty period, the multi-currency total and the fetched types.

### 3.5 Concurrency

The project default isolation is `MainActor`, so intents and services are MainActor;
`TransactionStore` is MainActor anyway. No `nonisolated` work here.

### 3.6 SDK facts (iOS 26 / 27)

- **Foreground escalation.** `openAppWhenRun` is deprecated and unused (its static was read
  before the intent ran, so it could never express a per-invocation decision). The intents
  declare `supportedModes`: `[.background, .foreground(.dynamic)]` for `LogTransactionIntent`
  and `AddExpenseIntent` (`.dynamic` is what allows `continueInForeground(_:)`), `.background`
  for `CheckSpendingIntent`. The escalating branches first check
  `systemContext.currentMode.canContinueInForeground` and throw
  `needsToContinueInForegroundError(_:)` on surfaces that cannot foreground (voice-only Siri on
  HomePod or AirPods), where `continueInForeground` would throw.
- **The confirmation snippet is a `SnippetIntent`.**
  `requestConfirmation(dialog:snippetIntent:)` takes
  [TransactionConfirmationSnippetIntent](../../Tenra/Intents/Snippets/TransactionConfirmationSnippetIntent.swift)
  (`isDiscoverable = false`, so it stays out of the Shortcuts app), whose inputs travel as
  `@Parameter`s. The system may run its `perform()` repeatedly to redraw, so it only renders;
  any write there would repeat. `TransactionConfirmationSnippet` keeps an
  `init(draft:accountName:)` convenience for the non-intent call path.
- **The `.result(dialog:view:)` snippet factories are not in `AppIntents`.** They live in the
  `_AppIntents_SwiftUI` cross-import overlay, active only when both `AppIntents` and `SwiftUI`
  are imported: `import SwiftUI` in the intent files is load-bearing.

---

## 4. Localization

- **App Shortcut phrases** live in `AppShortcuts.strings` per locale (a system requirement;
  they cannot go in `Localizable.strings`). Every phrase must contain `${applicationName}`.
  Phrase authoring is not translation: each locale needs phrasings people would actually say.
- **Intent titles, parameter prompts, dialogs, snippet copy** use `LocalizedStringResource`
  from `Localizable.strings`.
- All 11 in-app locales, positional specifiers where a translation reorders arguments, no em
  dashes (CLAUDE.md red flags #13, #14). Check parity of `AppShortcuts.strings` the same way as
  `Localizable.strings`.

---

## 5. Local measurement and verification

App Privacy stays "Data Not Collected". `IntentUsageCounters` (UserDefaults) counts
transactions added via intents (`intentAdd`), added manually (`manualAdd`, from
`TransactionsViewModel`) and intent runs handed to the app (`intentFallbackToApp`, recorded by
`IntentHandoff`); the last ratio is the parser's health metric. Shown in
`Views/Experiments/ExperimentsListView.swift`; nothing leaves the device.

Not unit-testable, so checked on the physical device (the Simulator is unreliable for Siri):
Siri invocation, the Shortcuts app, Spotlight, the Action Button, a cold launch with the app
force-quit, the in-foreground case (Home must refresh after an intent-added transaction, per
the `mutationVersion` refresh contract), balance correctness after a background write
followed by a full relaunch, and the snippet views (their `#Preview` blocks do not render in
a green build).

---

## 6. Wallet automation and merchant memory

The Shortcuts "Wallet" trigger fires when a card is tapped at a terminal (iPhone or Apple Watch),
not for Apple Pay on websites and in apps. It passes Amount (a currency amount whose Currency
Code is nested: reachable only through a Set Variable step), Merchant, Card or Pass and Date; no
merchant category. It is known to time out, to send an empty merchant with amount 0, and to fire
for declined payments. Plan in flight: [plan-auto-capture.md](../plan-auto-capture.md).

### 6.1 `LogWalletPaymentIntent` (silent)

`WalletPaymentRecorder.record`:

1. Amount ≤ 0 (a transit gate, a lost payload) → nothing recorded.
2. The same amount, currency, normalized merchant and card within 90 seconds
   (`WalletCaptureStore.isDuplicate`, captures and queue) → the terminal fired twice.
3. Category (`WalletPaymentResolver.category`): `MerchantCategoryMemory` with its subcategories,
   else `CategorySuggestionProvider.suggestion` over a bounded fetch of the merchant's history
   (descriptions containing its first word, 200 newest) plus brands and the voice keywords, else
   "Other". Everything but the memory is a guess.
4. Account (`WalletPaymentResolver.account`): fixed in the automation → `CardAccountMemory` for
   the card → the only account a card can pay from → `IntentAccountSuggester` for the category →
   the first one. The last two are guesses; loans and deposits never qualify.
5. A subscription's charge (`WalletPaymentResolver.subscriptionOccurrence`): an expense of a
   recurring series in the same currency, within `ImportDuplicateDetector`'s 3 days and 5 %, whose
   description shares a brand word with the merchant ("Netflix" / "NETFLIX.COM"; generic words like
   com or bill don't count; a service counts its billing company too: iCloud+ and iTunes as Apple,
   YouTube as Google) → nothing new, the series already recorded it. Without a shared word
   the payment is recorded: a duplicate can be deleted, a dropped payment is lost.
6. Currency: the passed code, else the account's. Cache, then one `CurrencyConverter.convert`,
   else the payment waits in `WalletCaptureStore.pending` (saving without a rate would move the
   balance by the raw foreign amount). The queue is recorded, each payment with its own date,
   before the next payment and when the app comes to the front (`MainTabView`).
7. `TransactionDraftService.commit`; a guessed account does not reach `VoiceLearningStore`.
8. `WalletCaptureStore.record`: the transaction id with the payment and its guesses. A capture
   with a guess not yet looked at is "To review". Captures live 90 days.

Learning: `WalletPaymentRecorder.confirm` remembers a captured transaction's category and
subcategories for the merchant and its account for the card, and marks the capture reviewed. It
runs when the transaction is saved from the edit screen (`TransactionEditCoordinator`) and on
"Correct" / "All correct" in To review. An account fixed in the automation is remembered for the
card at once. Guesses are never remembered.

**To review** (`WalletReviewView`, Settings → Siri & Shortcuts, also a sheet over `MainTabView`):
`WalletCaptureStore.toReview` as `TransactionCard`s; tap edits (saving confirms), swipe right or
the toolbar confirms. Captures of deleted transactions are dropped once the store has loaded.

**Notification** (`WalletReviewNotifier`): after a save with a guess, "Check a payment" with the
merchant and the guessed category (or account), no amount (lock screen). One per merchant while
an earlier payment there still waits; never asks for the permission. A tap sets
`WalletCaptureStore.isReviewRequested` (`AppDelegate`), and `MainTabView` presents To review.

**A merchant's screen** (`MerchantDetailView`, from the Wallet merchants list and from the
storefront button in `TransactionEditView` of a transaction whose merchant is remembered or has a
logo or a given name, so a transfer to a person gets none; Edit in its menu opens
`MerchantCategoryEditView`, also for a merchant the memory does not hold yet, starting from its
usual expense category, which the save remembers): `EntityDetailScaffold` with the merchant's logo and name, spent
in the selected period, visits, average check, last visit, usual category, total, and every
transaction of the merchant whatever recorded it. `MerchantHistory.summary` sweeps the history off
the main actor through `SummaryCalculator`, keyed on `mutationVersion`, rates, base currency, the
filter and the day. Pinned by `MerchantHistoryTests`.

**Wallet cards** (`WalletCardsView`): `CardAccountMemory.cards`, the account picked with
`NavigationPickerRow(style: .list)`, swipe to forget.

Pinned by `WalletPaymentResolverTests`, `WalletCaptureStoreTests`, `CardAccountMemoryTests`.

### 6.2 `AddExpenseIntent` (asks once per merchant)

The older setup (When I tap my card → "Add an expense") runs `AddExpenseIntent` on every Apple
Pay payment. Setup that makes it silent after the first payment at a merchant:

- **Note ← Shortcut Input → Merchant.** The merchant is the memory's key; without it nothing is
  remembered and the payment falls back to "Other" with a confirmation.
- **Category and Subcategory left empty**, not "Ask Each Time": that prompt comes from Shortcuts
  before `perform()` runs, so the app cannot skip it.
- **Account fixed** to the card's account, else the inferred account adds a confirmation.
  "Open When Run" off, "Show When Run" on (the first-time question needs it).

`MerchantCategoryMemory` (`Services/Categories/`, `@Observable`, one `UserDefaults` blob under
`intent.merchantCategory.v1`): normalized merchant (`CategorySuggestionService.normalizedMerchant`,
letters only, so store numbers don't split a merchant) → category id, subcategory ids (nil = never
decided, empty = "no subcategory"), and the merchant as Wallet last wrote it, for display.

- An unknown merchant is asked once: `$category.requestValue`, then `$subcategory.requestDisambiguation`
  when the category has subcategories. The answer is remembered after the save.
- A remembered merchant resolves exactly: category and subcategories, no prompt. A deleted
  category reads as unknown, so the merchant is asked again.
- Changing the category or subcategory of such a transaction in the app corrects an already
  remembered merchant (`TransactionEditCoordinator` → `correct`).
- **Settings → Siri & Shortcuts → Wallet merchants** (`MerchantCategoriesView`) lists the
  remembered merchants with their category and subcategories. Tap to reassign
  (`MerchantCategoryEditView`, the transaction form's category and subcategory pickers →
  `reassign`), swipe or "Forget merchant" to forget (`forget`: the next payment asks again).
- Pinned by `MerchantCategoryMemoryTests` (normalization, subcategory decisions, the list,
  reassign, forget, entries saved before display names existed).
