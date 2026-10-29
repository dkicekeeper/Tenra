# App Intents & Siri

Domain reference for `Tenra/Intents/**` (thin App Intents adapters) and `Services/Intents/**`
(the logic they call), and the widget extension (§8). The intents live in the main app target
and run in the app's own process. The only extension is `TenraWidgets`, which reads one JSON
file the app writes into the App Group; the CoreData store stays the app's.

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

### 1.4 `LogBankNotificationIntent`

The action for the iOS 27 notification automation (§7): the notification's title, subtitle, text,
app and date. Silent like the Wallet action (`supportedModes = .background`), records through the
same path.

### 1.5 `CheckSpendingIntent`

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
  `LogBankNotificationIntent` neither, for the same reason: the bank says the money moved (§7).

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

- Settings → **Siri & Shortcuts** (`SettingsSiriSection`): one row, the step-by-step guide to
  the Wallet automation (§6.1). Right under it, Settings → **Wallet** (`SettingsWalletSection`):
  To review, the merchants and cards lists (§6) and the merchant logos switch. No example
  phrases and no `ShortcutsLink` (owner's decision, 2026-10-21): the system surfaces the App
  Shortcuts itself (`TenraShortcuts`).
- `VoiceInputConfirmationView` donates `LogTransactionIntent` after a successful in-app voice
  save (`LogTransactionIntent.donate(phrase:)`).
- `TenraShortcuts` (`AppShortcutsProvider`) surfaces the shortcuts in Spotlight and Siri
  suggestions. The system caches the provider: edited phrases apply only after a reinstall.

---

## 3. Architecture

### 3.1 Files

- `Tenra/Intents/`: the five intents, `TenraShortcuts`, `Entities/` (account, category,
  subcategory `AppEntity`s with their queries), `Snippets/` (`TransactionConfirmationSnippet`,
  `TransactionConfirmationSnippetIntent`, `SpendingSummarySnippet`).
- `Services/Intents/`: `IntentEnvironment`, `TransactionDraft` + `TransactionDraftService`,
  `IntentAccountSuggester`, `IntentSubcategoryStore`, `SpendingQueryService`, `IntentHandoff`,
  `IntentUsageCounters`, the Wallet action's `WalletPaymentResolver`, `WalletPaymentRecorder`,
  `WalletCaptureStore`, `CardAccountMemory`, the bank notification action's
  `BankNotificationParser`. `Services/Notifications/WalletReviewNotifier`
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
for declined payments. The plan it was built from (in 1.7): [archive/plans/plan-auto-capture.md](../archive/plans/plan-auto-capture.md).

Where the setup is offered: onboarding's last step (`OnboardingAutoCaptureStep`, the Wallet
guide and on iOS 27 the bank notification guide in sheets), Home's card under the history
(`AutoCaptureSetupCard`, until `WalletCaptureStore.hasEverCaptured` or its ✕, key
`home.autoCaptureCard.hidden`), and once Ten's message after the first entries for someone who
hid the card ([assistant.md](assistant.md) §6). Settings → Siri & Shortcuts keeps the guides.

### 6.1 `LogWalletPaymentIntent` (silent)

`WalletPaymentRecorder.record`:

1. Amount ≤ 0 (a transit gate, a lost payload) → nothing recorded.
2. The same amount, currency, normalized merchant and card within 90 seconds
   (`WalletCaptureStore.isDuplicate`, captures and queue) → the terminal fired twice; an expense
   of the same amount (and currency, when both have one) from the other source within 5 minutes
   (`crossSourceWindow`: Apple Pay at a terminal also makes the bank send a notification, §7)
   → one payment, whichever came first. The
   payment's time is taken when the intent starts, before the queue drains. Right after this
   check the payment goes into `WalletCaptureStore.pending` (before the first await, so a second
   run of the same tap sees it) and leaves it only once saved: a run the system ends mid-save
   (a slow rate request) leaves it queued, never lost. `inFlight` keeps a drain off it meanwhile,
   and a drain drops a queued payment a capture already shows (saved by a run that ended before
   taking it off the queue).
3. Category (`WalletPaymentResolver.category`): `MerchantCategoryMemory` with its subcategories,
   else `CategorySuggestionProvider.suggestion` over a bounded fetch of the merchant's history
   (descriptions containing the first word of its clean name, so not "ИП" or "ТОО", 200 newest)
   plus brands and the voice keywords, else
   "Other". Everything but the memory is a guess.
4. Account (`WalletPaymentResolver.account`): fixed in the automation → `CardAccountMemory` for
   the card → the only account a card can pay from → `IntentAccountSuggester` for the category →
   the first one. The last two are guesses; loans and deposits never qualify.
5. A subscription's charge (`WalletPaymentResolver.subscriptionOccurrence`): an expense of a
   recurring series on the payment's account, not yet taken for another payment
   (`WalletCaptureStore.noteMatched`, so one charge stands for one payment: a second payment at
   the same gym that week is recorded), in the same currency, within `ImportDuplicateDetector`'s
   3 days and 5 %, whose
   description shares a brand word with the merchant ("Netflix" / "NETFLIX.COM"; generic words like
   com or bill don't count; a service counts its billing company too: iCloud+ and iTunes as Apple,
   YouTube as Google) → nothing new, the series already recorded it. Without a shared word
   the payment is recorded: a duplicate can be deleted, a dropped payment is lost.
6. Currency: the passed code, else the account's. Cache (refreshed first when
   `CurrencyRateStore.hasFreshRates` is false; the stale rate stays if that fails), then one
   `CurrencyConverter.convert`, one request in all, else the payment waits in
   `WalletCaptureStore.pending` (saving without a rate would move the balance by the raw foreign
   amount). The queue is recorded, each payment with its own date and that day's rate
   (`convert(on:)`), before the next payment and when the app comes to the front (`MainTabView`).
7. `TransactionDraftService.commit`; a guessed account does not reach `VoiceLearningStore`.
8. `WalletCaptureStore.record`: the transaction id with the payment and its guesses. A capture
   with a guess not yet looked at is "To review". Captures live 90 days. `firstCaptureAt` outlives them
   (`hasEverCaptured`), and `activity(now:)` counts the kept captures by source for Diagnostics.

Learning: `WalletPaymentRecorder.confirm` remembers a captured transaction's category and
subcategories for the merchant and its account for the card, and marks the capture reviewed. On
"Correct" / "All correct" in To review it confirms everything shown. From the edit screen
(`TransactionEditCoordinator`, `editedFrom:`) only what the save changed, plus a guessed category
not reviewed yet: editing an old payment's note must not undo what the user set since, and a
guessed account kept as it was stays a guess. An account fixed in the automation is remembered for
the card at once. Guesses are never remembered on their own.

**To review** (`WalletReviewView`, Settings → Wallet, also a sheet over `MainTabView`):
`WalletCaptureStore.toReview` as `TransactionCard`s; tap edits (saving confirms), swipe right or
the toolbar confirms. Until the full load (`hasCompletedInitialLoad`) it shows `SkeletonRow`s and
no confirm: the partial index would flash an empty list, and a confirm would read the
subcategories before they load and remember none. Captures of deleted transactions are dropped
once the store has loaded.

**Notification** (`WalletReviewNotifier`): after a save with a guess, "Check a payment" with the
merchant and the guessed category (or account), no amount (lock screen). One per merchant while
an earlier payment there still waits (a deleted one no longer does, once the store has loaded); never asks for the permission. A tap sets
`WalletCaptureStore.isReviewRequested` (`AppDelegate`), and `MainTabView` presents To review.
A confirmed payment's notification leaves Notification Center (`removeDelivered`).

**A merchant's screen** (`MerchantDetailView`, from the Wallet merchants list and from the
storefront button in `TransactionEditView` of a transaction whose merchant is remembered or has a
logo or a given name, so a transfer to a person gets none; Edit in its menu opens
`MerchantCategoryEditView`, also for a merchant the memory does not hold yet, starting from its
usual expense category, which the save remembers): `EntityDetailScaffold` with the merchant's logo and name, spent
in the selected period, visits, average check, last visit, usual category, this month, this year,
total, the last 12 months as DesignKit's `BarChart` (`ChartValuePoint`, shown once something was
spent), and every transaction of the merchant whatever recorded it. `MerchantHistory.summary` sweeps the history off
the main actor through `SummaryCalculator`, keyed on `mutationVersion`, rates, base currency, the
filter and the day. Pinned by `MerchantHistoryTests`.

**Wallet cards** (`WalletCardsView`): `CardAccountMemory.cards`, the account picked with
a `UniversalRow` with `.picker` (`config: .settings`), swipe to forget.

**Setup guide** (`WalletSetupGuideView`, the row of Settings → Siri & Shortcuts): a pager, one
step per page (intro, the trigger, the cards, Tenra's action with a note on replacing "Add an
expense", its four fields one by one, Show When Run, and the optional currency step), moved on
with Next or a swipe; Shortcuts opens from the toolbar and from the last page's button. Each page
has "Step N of M", a title, the step's text in DesignKit's `ArticleBody` and a picture of the
Shortcuts screen the step is on (`WalletSetupIllustration`): a schema drawn with tokens, so it
follows the language and the theme, the words it names written out, the rest grey bars, what to
tap outlined in the accent. A screenshot in `Assets.xcassets` named `wallet-setup-<step id>`
(`trigger`, `cards`, `action`, `amount`, `merchant`, `card`, `account`, `quiet`, `currency`; a
localized image set for other languages) replaces the drawing with no code change. Tenra's own
action and field names come from the intent's strings (`intent.walletPayment.*`); of Shortcuts'
labels, the guide names only those the owner's screenshot confirmed in Russian (2026-10-20): the
input variable **Транзакция** (passed whole to the amount, as Shortcuts reads it as a number), its
**Продавец**, the trigger's **Любая категория** / **Любой продавец** and the action's **Показать
при запуске**; the pictures add **Задать переменную** (`walletSetup.mock.*`). The others are
described, and in the 9 other locales Apple's labels are best guesses.

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
- **Settings → Wallet → Merchants** (`MerchantCategoriesView`) lists the
  remembered merchants with their category and subcategories, each with its logo (found or
  picked, while the Settings switch is on, as on its transaction rows) or else its category's
  icon. Tap to reassign
  (`MerchantCategoryEditView`, the transaction form's category and subcategory pickers →
  `reassign`), swipe or "Forget merchant" to forget (`forget`: the next payment asks again).
- Pinned by `MerchantCategoryMemoryTests` (normalization, subcategory decisions, the list,
  reassign, forget, entries saved before display names existed).

---

## 7. Bank notifications (iOS 27)

The Shortcuts trigger "When I get a notification from <app>" (iOS 27, one or several apps, runs on
a locked phone) passes the variable **Notification**, whose properties come separately: Title,
Subtitle, Text, App, Date (and Urgent, Sender, Recipients, Related content, Name). The automation:
the bank apps, no filter, the action **Log a bank notification** with Title, Subtitle, Text, App
and Date. Plan and what is still open: [plan-notification-capture.md](../plan-notification-capture.md).

### 7.1 `BankNotificationParser` (bank-agnostic)

No bank's format is coded: every bank writes the same parts in its own words, read from the title,
subtitle and text as one list of lines.

- **Amount**: a number with a currency, the currency before it (a symbol, `R$`, an ISO code) or
  after it (a symbol, a code, a local word: тг, руб, TL, zł, 円 …). A number with no currency is
  never money (card numbers, times, percentages, a deposit's number). A currency in front ends the
  amount at its number, so the word after it stays the merchant ("$5 Uber").
- **Balance and fee** by the words in front of the amount on its line ("Доступно", "Available",
  "Bakiye" …; "Комиссия", "fee" …). A balance is never the amount; a fee is added to an expense.
  The signed amount wins, else the first one.
- **Operation word**: the first one, line by line (the line it is on names the operation, later
  lines are details such as "Списано с … **1234"); words of four letters and more match a
  word's start, shorter ones the whole word ("atm", not "atmosphere"); Japanese and Korean words
  match inside the text. Cash → `cashWithdrawal`; an own-account marker anywhere
  (`StatementOperationKind`, "между своими", "депозит") unless the word is an expense's →
  `ownTransfer`; then the sign; then the word (a transfer is an expense unless it came in: "от",
  "from", "входящий"). An unsigned amount needs a balance, a card mask, the word among its line's
  first three or on the amount's line, so a promo naming a sum is not an operation.
- **Never an operation**: codes, declined payments, cashback, promos ("получите", "скидка",
  "offer" …), a balance alone, no currency. Nil: nothing recorded beats a wrong record.
- **Counterparty**: what follows the operation word on its line, cut at a balance or fee word,
  without amounts, masks and leading prepositions or fillers ("от", "at", "aprovada em"); else the
  first later line that is not a detail.
- **Card**: the last four digits of a mask (`**1234`, `•• 1234`, "ending 1234").
- Lexicon: the app's 11 languages and Kazakh, arrays (a repeated word is harmless).

Pinned by `BankNotificationParserTests` (invented texts in the layouts of Kaspi, Freedom and other
banks' wording).

### 7.2 Recording

`LogBankNotificationIntent` turns an expense or an income into a `WalletPayment` with `bankApp`
(the App property, "" when missing) and `isIncome`, and records it through
`WalletPaymentRecorder.record` (§6.1): duplicates, currency and queue, To review and its
notification, learning on confirm. The "card" is the app plus the card's digits
(`BankNotificationParser.cardName`: "Freedom •• 1234", or "Kaspi.kz" without a mask), so
`CardAccountMemory` and Settings → Wallet → Cards hold one account per bank card. An income takes
an income category from the sender's history (the merchant memory holds expense categories), no
subscription matching.

Not recorded, with a dialog saying so: a cash withdrawal (the spending is logged later).

### 7.3 Transfers between own accounts

Each bank's notification shows one side ("−15 000" in one app, "+15 000 between own accounts" in
the other); recording either as an expense or an income would count the money twice. The parser
marks the direction (`BankNotification.isIncoming`: the sign, else the operation word), the intent
queues the side (`WalletCaptureStore.transferSides`, with the card key) and `OwnTransferRecorder`
pairs sides right away in the intent and again when the app comes to the front (MainTabView):
`OwnTransferMatcher.match` takes the same currency, the receiving amount equal to the sent one or
up to 1 % less (a fee), within 15 minutes, two different cards, the closest in time. A pair whose
cards both have an account (`CardAccountMemory`) in the sides' currencies becomes one
`TransactionStore.transfer`; otherwise it waits. A side alone for 48 hours is dropped. Pinned by
`OwnTransferMatcherTests`.

### 7.4 Setup guide and "Check a notification"

`BankNotificationGuideView` (Settings → Siri & Shortcuts and the onboarding's auto-capture step,
iOS 27 only: `BankNotificationGuideView.isAvailable`): the intro, the trigger (the bank apps, no
filters), Tenra's action and its five fields from the **Notification** variable, running without a
question, and a last page where a pasted notification shows what the parser finds (type, amount,
merchant or sender, card), nothing saved.

A bank notification's merchants are kept out of `WalletCaptureStore.merchants`, the list looked up
online for logos ([logos.md](logos.md)): they name people too (a transfer).

---

## 8. Widgets and Control Center (`TenraWidgets`)

A widget extension target (`TenraWidgetsExtension`, bundle id `dakacom.Tenra.TenraWidgets`,
folder `TenraWidgets/`, synchronized like the app's) embedded in the app. App Group
`group.dakacom.Tenra` in both entitlements. No DesignKit in the extension (its package uses
APIs an extension may not): system fonts, the accent from its own asset catalog, its own
`Localizable.strings` in 12 locales.

- **Data**: the app writes `widget-snapshot.json` into the App Group (`WidgetSnapshotStore`,
  `Services/Widgets/WidgetSnapshot.swift`) after the full load (ContentView) and when it goes to
  the background (TenraApp), only when it changed, then `WidgetCenter.reloadAllTimelines()`.
  Contents: the day, the base currency, "hide amounts", For today (`DailyAllowance`, the same
  number as Analytics and Ten's forecast), the income it runs to, realized expenses today
  (`summaryContribution`), the four expense categories used most in the last 30 days. The
  extension decodes it with its own copy of the type (`TenraWidgets/WidgetData.swift`); the keys
  are pinned by `WidgetSnapshotTests`. A snapshot from another day shows 0 spent; the timeline
  redraws after midnight.
- **For today** (`TodayWidget`): small, medium (with the four categories), Lock Screen
  rectangular, inline and circular. "Hide amounts" shows dots. Analytics shows the same figure under
  the period's stat cards as an insight like the others (`DailyAllowanceLink`, recomputed by
  `.task(id:)` on the history, accounts, series, categories, rates, base currency and the day):
  an `Insight` of type `.dailyAllowance` built on the main actor (the off-main generator has no
  forecast), the feed's `InsightsCardView`, and `InsightDetailView` through InsightsView's
  destination, with `.dailyAllowance(DailyAllowanceDetail)` as its detail: "How it's calculated"
  (`InsightFormulaCard`: the balance of the accounts that count, the payments set aside, what is
  free, the days, and the explanation), a warning naming a currency with no rate yet, whose
  payments are left out, and each payment set aside (`InsightAllowancePaymentsList`: the
  subscription's or the loan bank's logo, else the category's symbol on its colour, as in
  History); "Ask Ten" offers the `.allowance` topic. Whole units on the card: the allowance rounds
  down, what is set aside rounds up (`DailyAllowance.value`); the breakdown is exact, so its rows
  add up.
  - **Which money** (`Account.countsForToday`, the same set Ten's `forecast_balance` starts
    from): regular accounts counted in the balance, and a deposit only when its form's switch
    "Count in For today" is on (`DepositInfo.countsForToday`, off by default: a deposit is
    savings unless the person can take money out any time). Never a loan.
  - **Other currencies**: every amount is set aside in the base currency at today's rate.
    `FinanceToolkit.forecast` loads the rates of the accounts', the series' and the planned
    expenses' currencies first (dollars planned on a tenge card included); a planned expense
    whose own currency still has no rate counts what it takes from its account
    (`convertedAmount`); what can't be converted at all is listed in `missing_rates`.
- **Log an expense** (`QuickAddControl`, a `ControlWidgetButton` with `OpenURLIntent`): Control
  Center, the Lock Screen and the Action button.
- **Links**: `tenra://add` opens the assistant (Home where it does not run), `tenra://add?category=
  <name>` Home's add form for that expense category (`AppCoordinator.handleDeepLink` →
  `pendingQuickAdd`; MainTabView and ContentView take it). The scheme is in Info.plist
  `CFBundleURLTypes`; any other URL is a file handed over (`openAttachment`).
- **Signing**: the cloud archive registers the extension's id and the App Group through
  `-allowProvisioningUpdates` with the ASC key ([asc.md](../asc.md)).

