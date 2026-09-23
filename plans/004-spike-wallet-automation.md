# Plan 004 (spike): Decide, with on-device evidence, whether Tenra should log Apple Pay payments automatically through the Shortcuts "Wallet" automation

> **Executor instructions**: This is a SPIKE, not a feature build. The output
> is a DEBUG-only probe plus a findings document with a go/no-go
> recommendation. Nothing in this plan may ship in a Release build, and the
> probe must never save a transaction. Follow the steps in order; steps marked
> **[HUMAN]** need the maintainer's physical iPhone and real payments — prepare
> everything for them, then stop and hand over. If anything in "STOP
> conditions" occurs, stop and report. When done, update the status row for
> this plan in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 84fbabdf..HEAD -- Tenra/Intents Tenra/Services/Intents Tenra/Views/Experiments`
> If `AddExpenseIntent.swift` or `ExperimentsListView.swift` changed, compare
> with the excerpts below before continuing.

## Status

- **Priority**: P2
- **Effort**: S for the executor (probe + doc skeleton, about half a day) + about 1 week of real-life payments by the maintainer
- **Risk**: LOW (DEBUG-only, no writes)
- **Depends on**: none to start. Plan 002 (`CategorySuggestionProvider`) is optional: if it has landed, the probe also records which category it would suggest.
- **Category**: direction (spike)
- **Planned at**: commit `84fbabdf`, 2026-09-24

## Why this matters

Tenra is a manual tracker positioned as "no bank login". The biggest cost of
manual tracking is forgetting to log. iOS Shortcuts has a personal automation
that fires right after an Apple Pay payment and passes the payment details to
an app action. Other trackers (BudgetBakers Wallet, TravelSpend, WalletPal,
CashJot) already use it. For Tenra this would mean "automatic logging without
giving a bank your password", which directly answers the Zenmoney-style bank
sync without its trust problem.

What is known from public sources (2026-09, to be verified on device, not assumed):
- The automation is called "Transaction" in iOS 17-18 and was renamed "Wallet" in iOS 26.
- It exposes these fields: Transaction, Card, Merchant, Amount, Name.
- With "Run Immediately" it can run without asking each time.
- There is an Apple Developer Forums thread reporting that Transaction automation plus an AppIntent is occasionally flaky (thread 797233).
- Unknown for Kazakhstan: which banks' cards fire it, and whether QR payments (Kaspi QR) or online Apple Pay payments trigger it at all (probably not for QR, which does not go through Apple Pay).

The spike exists because several design decisions (confirmation, card→account
mapping, duplicates with statement import, currency) cannot be settled from
the code alone.

## Current state

- `Tenra/Intents/AddExpenseIntent.swift` — parameterized expense intent,
  already usable from Shortcuts:
  ```swift
  static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

  @Parameter(title: "intent.addExpense.parameter.amount")
  var amount: Double
  @Parameter(title: "intent.addExpense.parameter.category")
  var category: CategoryAppEntity?
  @Parameter(title: "intent.addExpense.parameter.account")
  var account: AccountAppEntity?
  @Parameter(title: "intent.addExpense.parameter.note")
  var note: String?
  ```
  It builds a `ParsedOperation` with `currencyCode: account?.currency` (so the
  amount is always interpreted in the account's currency) and, when
  `TransactionDraftService.makeDraft` reports warnings, asks for confirmation
  (around line 89-98):
  ```swift
  case .success(let draft):
      if !draft.warnings.isEmpty {
          ...
          try await requestConfirmation(
              dialog: IntentDialog("intent.addExpense.confirm"),
              snippetIntent: TransactionConfirmationSnippetIntent(draft: draft, accountName: accountName)
          )
      }
  ```
  `DraftWarning` (`Tenra/Services/Intents/TransactionDraft.swift:30`) has
  `categorySubstituted(original:)` and `accountInferred`. For a Wallet payment
  the category and usually the account are inferred, so today EVERY automated
  run would stop for a confirmation. That is the central design question.

- `Tenra/Services/Intents/IntentEnvironment.swift` — `IntentEnvironment.shared.services()`
  gives an intent the live coordinator (`accounts`, `categories`, `makeParser()`),
  including when the intent runs in a cold background process.

- `Tenra/Services/Intents/IntentUsageCounters.swift` and
  `Tenra/Views/Experiments/ExperimentsListView.swift` — a DEBUG developer
  screen (reached from Settings → Experiments, compiled only in DEBUG via
  `#if DEBUG experimentsSection` in `SettingsView.swift`) that already shows
  local intent counters:
  ```swift
  Section("Intent usage (local only)") {
      LabeledContent("Added via intents", value: "\(snapshot.intentAdds)")
      ...
  }
  ```
  Its strings are deliberately unlocalized (developer-only). Follow that.

- Logging convention for intents: `Logger(subsystem: "Tenra", category: "<IntentName>")`,
  user content only with default (private) redaction, structural facts with
  `privacy: .public` (see `LogTransactionIntent.swift` top).

- The CoreData store uses `FileProtectionType.completeUntilFirstUserAuthentication`
  (`Tenra/CoreData/CoreDataStack.swift`), so a background intent can read it
  while the phone is locked, after the first unlock since boot.

- Spec with the App Intents design and its deferred list:
  `docs/superpowers/specs/2026-07-31-app-intents-design.md` (§2.4, §10).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Debug build (simulator, compile check) | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | `** BUILD SUCCEEDED **` |
| Release build (proves the probe is compiled out) | `xcodebuild build -scheme Tenra -configuration Release -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | `** BUILD SUCCEEDED **` |
| Device install (maintainer runs it, phone unlocked) | `xcodebuild build -scheme Tenra -destination 'platform=iOS,name=Dkicekeeper 17'` then run from Xcode | app installs |

## Scope

**In scope**:
- `Tenra/Intents/WalletPaymentProbeIntent.swift` (create; whole file inside `#if DEBUG`)
- `Tenra/Services/Intents/WalletPaymentProbeLog.swift` (create; whole file inside `#if DEBUG`)
- `Tenra/Views/Experiments/ExperimentsListView.swift` (add one `#if DEBUG` section)
- `docs/superpowers/specs/2026-10-wallet-automation-spike.md` (create)

**Out of scope**:
- Any change to `AddExpenseIntent`, `LogTransactionIntent`, `TenraShortcuts`,
  `TransactionDraftService`, or anything that saves a transaction.
- Localization files: the probe is developer-only and unlocalized.
- Any production UI (setup guide, card mapping screen). Those come from the
  follow-up plan the findings doc recommends.

## Git workflow

- Commit directly on the current branch (`main`); do not push.
- `chore(intents): DEBUG-only Wallet payment probe for the automation spike`, and later
  `docs: Wallet automation spike findings`.

## Steps

### Step 1: Probe log (DEBUG only)

Create `Tenra/Services/Intents/WalletPaymentProbeLog.swift`, the whole file
wrapped in `#if DEBUG ... #endif`:
- `struct WalletPaymentProbeEntry: Codable, Identifiable` with `id: UUID`,
  `receivedAt: Date`, `merchant: String?`, `rawAmount: String?`,
  `currencyAmountValue: Double?`, `currencyAmountCode: String?`, `card: String?`,
  `name: String?`, `ranInBackground: Bool`, `suggestedCategory: String?`,
  `historyCount: Int`.
- `@MainActor final class WalletPaymentProbeLog` with `static let shared`,
  backed by one JSON blob in `UserDefaults.standard` under key
  `"debug.walletProbe.entries"`, keeping the newest 50 entries:
  `func append(_:)`, `func entries() -> [WalletPaymentProbeEntry]`, `func clear()`.
  Model the UserDefaults blob handling on `VoiceLearningStore` (`Tenra/Services/Voice/VoiceLearningStore.swift`).

**Verify**: Debug build → `** BUILD SUCCEEDED **`.

### Step 2: Probe intent (DEBUG only, never writes)

Create `Tenra/Intents/WalletPaymentProbeIntent.swift`, whole file in `#if DEBUG`:
- `struct WalletPaymentProbeIntent: AppIntent`, title `"Tenra Wallet Probe (debug)"`
  (a plain `LocalizedStringResource` literal is fine; it is developer-only),
  `static var supportedModes: IntentModes { .background }`.
- Parameters, all optional so the maintainer can wire each Wallet field in
  independently: `merchant: String?`, `rawAmount: String?`,
  `currencyAmount: IntentCurrencyAmount?`, `card: String?`, `name: String?`.
- `perform()`:
  1. Build a `WalletPaymentProbeEntry` from the parameters
     (`currencyAmount?.amount` as Double via `NSDecimalNumber`, `currencyAmount?.currencyCode`,
     `ranInBackground: UIApplication.shared.applicationState != .active`).
  2. If a `CategorySuggestionProvider` type exists in the module (plan 002
     landed), compute the suggestion for `merchant` as `.expense` using
     `let services = await IntentEnvironment.shared.services()`: categories
     `services.categories.customCategories`, parser `services.makeParser()`,
     history `services.store.transactions`. In a cold background process only
     the fast path has run, so that history may be empty: add a
     `historyCount: Int` field to the entry and record
     `services.store.transactions.count` so the findings can tell the cases
     apart. Otherwise leave `suggestedCategory` nil. (If plan 002 has not landed, simply omit this part;
     do not write your own categorizer.)
  3. Append to `WalletPaymentProbeLog.shared`, log structural facts with
     `Logger(subsystem: "Tenra", category: "WalletPaymentProbe")` (merchant and
     amounts with default private redaction).
  4. Return `.result()` with no dialog. **Never** call `TransactionDraftService.commit`,
     `TransactionStore.add`, or any other write.

**Verify**:
- Debug build → `** BUILD SUCCEEDED **`.
- Release build → `** BUILD SUCCEEDED **`.
- `grep -c "#if DEBUG" Tenra/Intents/WalletPaymentProbeIntent.swift Tenra/Services/Intents/WalletPaymentProbeLog.swift` → `1` for each file.
- `grep -nE "\.add\(|commit\(|addTransaction" Tenra/Intents/WalletPaymentProbeIntent.swift` → no output.

### Step 3: Show captured payloads in Experiments

In `ExperimentsListView.swift`, add under the existing "Intent usage" section,
inside `#if DEBUG`, a `Section("Wallet probe (local only)")` listing
`WalletPaymentProbeLog.shared.entries()` newest first: time, merchant, raw
amount, currency amount + code, card, name, background flag, suggested
category; plus a "Clear" button. Refresh it in the existing `.onAppear`.

**Verify**: Debug build → `** BUILD SUCCEEDED **`.

### Step 4: Findings document skeleton

Create `docs/superpowers/specs/2026-10-wallet-automation-spike.md` with these
sections, each question followed by an empty "Evidence:" and "Answer:" line
for the maintainer/reviewer to fill:

1. **Setup used** (iOS version, device, cards in Wallet and their banks).
2. **Q1 Trigger coverage**: does the Wallet automation fire for each card? Contactless in store? Online Apple Pay? Kaspi QR (expected: no)?
3. **Q2 Payload shape**: exact `rawAmount` text, whether `currencyAmount` arrives with a code, `merchant` samples vs the same payment's text in a Kaspi PDF statement, what `card` and `name` contain.
4. **Q3 Execution**: does it run with the app killed, with the phone locked, and how fast (receivedAt vs payment time)? Any missed runs over the week (compare the probe list with the bank history)?
5. **Q4 Confirmation behavior**: record what happens if a real intent asks for confirmation during an automation run (answer from Apple docs/forums if not tested; the probe itself never asks).
6. **Q5 Card → account mapping**: is the `card` string stable and unique enough to map to one Tenra account?
7. **Q6 Duplicates with statement import**: for 3-5 payments, compare probe merchant/amount/date with the imported statement rows; propose a dedupe rule (e.g. same account, same amount, date within 1 day, same `CategorySuggestionService.normalizedMerchant`).
8. **Q7 Currency**: one foreign-currency payment, if possible: which amount and code arrive?
9. **Q8 Categorization hit rate**: share of probe entries with a non-nil `suggestedCategory` (only if plan 002 landed).
10. **Recommendation**: GO / NO-GO, and for GO a design sketch: a dedicated `LogWalletPaymentIntent` (parameters, `supportedModes`), confirmation policy (e.g. save silently as "suggested" and post a local notification, instead of `requestConfirmation`), card mapping UX, dedupe in `ImportTransactionPreviewView`, the in-app setup guide (Settings → Siri section), and Free vs Pro options for the maintainer.

**Verify**: `test -f docs/superpowers/specs/2026-10-wallet-automation-spike.md && grep -c "^## \|^### \|^[0-9]*\. \*\*" docs/superpowers/specs/2026-10-wallet-automation-spike.md` → a count of at least 10.

### Step 5: [HUMAN] Run the probe for a week

Hand over with these instructions (put them at the top of the findings doc too):
1. Install the Debug build on "Dkicekeeper 17" from Xcode.
2. Shortcuts → Automation → New → **Wallet** (or "Transaction" on older iOS) → choose all cards → **Run Immediately**.
3. Action: "Tenra Wallet Probe (debug)". Wire Shortcut Input → Merchant to `merchant`, → Amount to BOTH `rawAmount` and `currencyAmount`, → Card to `card`, → Name to `name`.
4. Pay normally for about a week, including one online Apple Pay payment and, if possible, one foreign-currency payment.
5. Open Settings → Experiments → "Wallet probe" and fill the findings doc (or send the entries to the reviewer).
6. The probe never creates transactions: keep logging manually as usual.

Then STOP. The executor's part is done; the reviewer completes Q1-Q10 from the
maintainer's data and writes the recommendation.

## Done criteria (executor part)

- [ ] Debug and Release builds both print `** BUILD SUCCEEDED **`
- [ ] Both probe files are entirely inside `#if DEBUG`
- [ ] The probe intent contains no write path (grep in Step 2 is empty)
- [ ] The findings doc exists with all 10 sections and the [HUMAN] instructions
- [ ] `git status --short` lists only in-scope files (plus `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 004 set to `BLOCKED (waiting for device data)` with today's date

## STOP conditions

- The probe cannot be declared without changing `TenraShortcuts` or any production intent.
- `IntentCurrencyAmount` does not compile as an optional parameter: drop that parameter, keep `rawAmount`, note it in the doc, continue.
- Anything suggests the probe could save, edit, or delete a transaction.

## Maintenance notes

- Delete both probe files once the findings doc has a recommendation (they are debug-only scaffolding).
- If the answer is GO, the follow-up is a real plan, not an extension of the probe. Expected pieces: `LogWalletPaymentIntent`, a card→account mapping store, a dedupe check in statement import, a setup guide in Settings, localized strings in 11 locales, and a decision on Pro gating.
- Sources used to frame the spike (verify, do not trust blindly): BudgetBakers Apple Pay integration help article; TravelSpend and WalletPal automation setup guides; Apple Developer Forums thread 797233.
