# Tenra — App Intents & Siri (design spec)

> Created: 2026-07-31
> Status: approved for planning
> Goal of the release: **retention**. Remove the friction of logging a transaction.

---

## 1. Why

Tenra is a manual-first tracker. The dominant failure mode for manual trackers is that the
user skips two or three days, the data stops matching reality, and the app is abandoned.
No analytics exist (App Privacy = Data Not Collected, ~40 lifetime installs), so this is a
first-principles bet on the highest-prior cause rather than a data-driven one.

Two facts make App Intents the cheapest high-value move available:

1. **`VoiceInputParser` already exists** — 1386 lines, multilingual keyword maps across the
   11 in-app locales, `parse()` / `parseMulti()` / `parseEntitiesLive()`. The expensive part
   of "log a transaction from a spoken phrase" is written and currently has exactly one
   surface (the in-app Voice tab, which is Pro-gated).
2. **App Intents declared in the main app target run in the app's own process.** No app
   extension, no App Group, no entitlement change, no provisioning work.

### Verified technical preconditions

| Question | Finding |
|---|---|
| Can a headless process write a transaction without corrupting balances? | **Yes.** `TransactionStore.add` → `apply(.added)` → `BalanceCoordinator.updateForTransaction(.add)` is **incremental** (`TransactionStore.swift:1068-1107`). The base is the persisted `account.balance`, kept accurate by `persistIncremental` on every mutation (`BalanceCoordinator.swift:63-95`). No full recalc over the transactions array is involved, so an empty in-memory array is harmless. |
| Is there a cheap bootstrap? | **Yes.** `AppCoordinator.initializeFastPath()` (`AppCoordinator.swift:265-302`) loads accounts + settings + `registerAccounts`, documented at <50 ms, and deliberately does **not** load transactions. |
| Where does the store live? | Default app container, **no App Group** (`CoreDataStack.swift`). Irrelevant for intents; would matter for a widget (out of scope here). |
| Is the ParsedOperation → Transaction logic reusable? | **Not yet.** It is embedded in a SwiftUI view: `VoiceInputConfirmationView.saveTransaction` (`VoiceInputConfirmationView.swift:416-530`). It must be extracted. |

---

## 2. Scope

Three intents, plus discoverability, plus the refactor that makes them possible.

### 2.1 `LogTransactionIntent` — primary

One free-form phrase, one shot. The whole phrase is passed to `VoiceInputParser.parse`.

App Shortcut phrase shape: `"Добавь \(\.$phrase) в \(.applicationName)"` — the parameter is
embedded in the spoken phrase itself, so `«Добавь 3000 на кофе в Tenra»` completes without
Siri interrogating the user field by field. This one-shot property is the entire point; a
three-turn Siri dialogue is slower than opening the app and defeats the purpose.

### 2.2 `AddExpenseIntent` — parameterized

Typed parameters (amount, currency, category, account, date, note) for the Shortcuts app:
automations, Action Button, Shortcuts widget, Control Center. Uses `AppEntity` parameters so
categories and accounts are pickable lists, not free text.

### 2.3 `CheckSpendingIntent` — read-only

"How much did I spend today / this week / this month." Returns a spoken dialog plus a
snippet. Gives the user a reason to consult Tenra without opening it.

**Critical constraint:** it must NOT read `TransactionStore` — in a cold intent process the
in-memory array is empty and loading 19k transactions is exactly what the fast path avoids.
It performs a narrow `NSFetchRequest` bounded by a date predicate.

### 2.4 Out of scope (explicitly deferred)

- WidgetKit / Lock Screen widgets / Control Center controls — next milestone, needs an App
  Group or a snapshot pipeline.
- Apple Watch, Live Activities.
- Savings goals.
- Editing or deleting transactions via intents. Creation only.

---

## 3. UX model

### 3.1 Confirmation

A financial write must never happen silently on a misheard phrase. The rule is:

> **Confirmation is required whenever any field was inferred rather than explicitly supplied.**

- `LogTransactionIntent` always confirms — every field comes from parsing a phrase. The
  snippet (`requestConfirmation(result:)`) renders amount, currency, category, account and
  date, and marks any field the resolver had to guess.
- `AddExpenseIntent` confirms only if a field was defaulted. When the user supplied every
  parameter (the normal case in a Shortcuts automation or an Action Button binding) it
  commits directly, because forcing a prompt would make automations unusable.

This rule simplifies the fallback logic: a guessed value is acceptable as long as it is
visible and marked.

### 3.2 Resolution rules

**Account selection**, in order:
1. Account explicitly named in the phrase.
2. `VoiceLearningStore` learned account for that category (already fed by
   `VoiceInputConfirmationView` via `recordSave`).
3. First `accountsViewModel.regularAccounts` entry.

Loan and deposit accounts are excluded, matching the existing guard in `saveTransaction`
(`!acc.isLoan, !acc.isDeposit`).

**Category:** if unresolved, fall back to the localized `category.other` for the resolved
transaction type. This is safe precisely because the snippet displays it.

**Currency:** conversion is attempted **from cache only** (`CurrencyConverter.convertSync` /
`RateSnapshot`). No network call inside an intent. A cache miss is a blocking issue.

### 3.3 Blocking issues → open the app

Only three conditions abort the background path and open the app with the parsed operation
prefilled into the existing confirmation screen (`openAppWhenRun`):

| `DraftIssue` | Condition |
|---|---|
| `missingAmount` | Parser found no amount. |
| `noEligibleAccount` | No regular accounts exist (fresh install / onboarding incomplete) → open onboarding instead. |
| `needsFXConversion` | Phrase currency ≠ account currency and no cached rate. |

Opening the app is a normal branch, not a failure: it is still faster than manual entry.

### 3.4 Pro gate

Decided: **single-operation logging via Siri is free for everyone.** The release goal is
habit formation, and a habit is what later sells Pro. The existing Pro gate on the in-app
Voice tab stays as is.

`parseMulti` returning more than one operation for a non-Pro user: commit the **first**
operation and state plainly in the dialog what happened, e.g. "Added 3000 ₸, Coffee. The
phrase contained 2 more operations; logging several at once is part of Tenra Pro."
Nothing is silently dropped, and it is an earned paywall moment.

### 3.5 Discoverability

A feature nobody finds has zero retention effect. Therefore in scope:

- A **"Siri & Shortcuts"** section in Settings listing example phrases in the interface
  language, with a `ShortcutsLink` to the Shortcuts app.
- Intent donation after the first successful in-app voice entry.
- `AppShortcutsProvider` surfaces the shortcuts in Spotlight and the Siri suggestions
  automatically.

---

## 4. Architecture

### 4.1 New files

```
Tenra/Intents/                          # new top-level folder (platform surface, not a service)
├── LogTransactionIntent.swift
├── AddExpenseIntent.swift
├── CheckSpendingIntent.swift
├── TenraShortcuts.swift                # AppShortcutsProvider
├── Entities/
│   ├── AccountAppEntity.swift          # + EntityQuery
│   └── CategoryAppEntity.swift         # + EntityQuery
└── Snippets/
    ├── TransactionConfirmationSnippet.swift
    └── SpendingSummarySnippet.swift

Tenra/Services/Intents/
├── IntentEnvironment.swift
├── TransactionDraftService.swift
└── SpendingQueryService.swift
```

`Tenra/Intents/` is a new branch in the CLAUDE.md file-organization tree and must be added
there (App Intents are an entry point/adapter, not domain logic; the domain logic they call
lives under `Services/Intents/`).

### 4.2 `IntentEnvironment`

Single entry point for obtaining live services from an intent, whatever the process state.

- If the app already built an `AppCoordinator`, return it. `TenraApp` registers it
  immediately after construction (`TenraApp.swift:68`).
- Otherwise (process launched by the system solely to run the intent) lazily construct one
  and `await initializeFastPath()`.

The registration hook is what prevents a second `TransactionStore` / second coordinator in
the same process. `CoreDataStack.shared` already guards the container with an `NSLock`, but
two stores would still diverge in memory.

Exposes: `transactionStore`, `accountsViewModel`, `categoriesViewModel`, `settingsViewModel`,
`premium`.

### 4.3 `TransactionDraftService`

The extraction of `VoiceInputConfirmationView.saveTransaction`. Two responsibilities, split
so the first is pure and testable:

```
func makeDraft(from: ParsedOperation,
               accounts: [Account],
               categories: [CustomCategory],
               learned: VoiceLearningStore) -> Result<TransactionDraft, DraftIssue>

func commit(_ draft: TransactionDraft) async throws -> Transaction
```

`TransactionDraft` carries `warnings: [DraftWarning]` (`categorySubstituted`,
`accountInferred`, `dateAssumedToday`) alongside the resolved fields. `DraftIssue` is only
for the blocking conditions in §3.3; anything the resolver could guess becomes a warning
instead. Both consumers read the same warnings: the intent snippet marks the guessed field,
and `VoiceInputConfirmationView` renders them through its existing
`categoryWarning` / `accountWarning` labels, preserving today's on-screen behavior without
duplicating the logic.

`commit` performs `store.add`, links subcategories via
`categoriesViewModel.linkSubcategoriesToTransaction`, feeds `VoiceLearningStore.recordSave`,
and calls `RatingPromptService.shared.recordTransactionAdded()`.

That last call matters: the counter currently lives in
`TransactionsViewModel.addTransaction` (`TransactionsViewModel.swift:186`), which intents
bypass. Without it, Siri-logged transactions never count toward rating eligibility. The
counter only records — the native prompt is never presented from a background process.

**`VoiceInputConfirmationView` is refactored onto this same service.** One code path instead
of two, and roughly a hundred lines leave the view. This is the targeted cleanup that makes
the feature possible rather than unrelated refactoring.

### 4.4 `SpendingQueryService`

Bounded `NSFetchRequest` over `TransactionEntity` with a date predicate for the requested
period. Independent of `TransactionStore` load state by design.

Money math must follow red flag #6: totals are produced by converting each transaction with
`CurrencyConverter.convertSync(amount:from:to:)` against the base currency (with
`convertedAmount ?? amount` as a cold-cache fallback only). Summing `convertedAmount` across
currencies is the documented bug shape and is forbidden here.

Date parsing over the fetched rows uses `FastDateParser`, never `DateFormatter` in a loop
(red flag #15).

### 4.5 Concurrency

Project default is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so intents are MainActor by
default; `TransactionStore` is MainActor anyway. No `nonisolated` work is introduced.

---

## 5. Localization

- **App Shortcut phrases** live in a dedicated `AppShortcuts.strings` per locale — a system
  requirement, they cannot go in `Localizable.strings`.
- **Intent titles, parameter prompts, dialogs, snippet copy** use `LocalizedStringResource`
  and resolve from `Localizable.strings`.
- All **11 in-app locales** (en, ru, de, es, fr, tr, pt-BR, it, uk, ja, ko). Missing keys
  render as raw keys (red flag #13).
- Positional format specifiers wherever a translation reorders arguments (red flag #14).
- Phrase authoring is not translation: each locale needs phrasings people would actually
  say, and every phrase must contain `\(.applicationName)`.
- No em dashes in any of this copy.
- Parity verified by the documented `diff <(grep -oE '^"[^"]+"' ...)` check, extended to
  `AppShortcuts.strings`.

---

## 6. Measurement without analytics

App Privacy stays "Data Not Collected". Measurement is local only:

- UserDefaults counters: transactions added via intents vs. added manually, and the count of
  intent runs that fell back to opening the app (that ratio is the health metric for the
  parser).
- Surfaced in the existing `Views/Experiments/ExperimentsListView.swift`. Nothing leaves the
  device, the ASC privacy label is unchanged.

---

## 7. Testing

| Suite | Covers |
|---|---|
| `TransactionDraftServiceTests` (`@MainActor`) | Full phrase; missing amount; no eligible account; unknown category → `category.other`; loan/deposit accounts excluded; learned-account preference; currency mismatch with cold cache → `needsFXConversion`. |
| `SpendingQueryServiceTests` (`@MainActor`) | Period boundaries; multi-currency total in base currency (must not sum `convertedAmount`); empty period. |
| `IntentEnvironmentTests` | In-memory container bootstrap; does not build a second coordinator when a live one is registered. |
| Localization parity script | `AppShortcuts.strings` + new `Localizable.strings` keys across all 11 locales; verify one non-ASCII locale (ru or ja) for mojibake. |

Suites constructing MainActor-isolated types must be annotated `@MainActor`. Any test
building a `TransactionStore` must retain it (`AccountsViewModel.transactionStore` is weak).

**Manual, on the physical device (`Dkicekeeper 17`), not the Simulator:** Siri invocation,
Shortcuts app, Spotlight, Action Button, cold launch with the app force-quit, and the
in-foreground case (Home must refresh after an intent-added transaction —
`mutationVersion` bump, per the entity-detail refresh contract).

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| Localization of phrases is the largest and most defect-prone chunk. | Treat as its own plan phase with a parity script gate before build. |
| `#Preview` blocks in snippet views break invisibly on a green build (CLAUDE.md). | Every snippet view's previews updated alongside; noted as a manual check. |
| `AppShortcutsProvider` is cached by the system; phrase edits do not apply immediately. | Reinstall during debugging; documented in the plan. |
| Intent execution budget. | Fast path is <50 ms and no network call is made; large margin. |
| Duplicate submissions (user repeats the phrase to Siri). | Verify `TransactionIDGenerator.generateID(for:)` behavior for identical field sets during implementation; the confirmation snippet is the primary guard. Open item, not a designed feature. |
| Refactoring `VoiceInputConfirmationView` touches a shipped path. | Covered by `TransactionDraftServiceTests`; the view keeps its current behavior by rendering `TransactionDraft.warnings` through its existing warning labels rather than duplicating resolution logic. |

---

## 9. Definition of done

- Three intents ship, discoverable from Siri, Spotlight and the Shortcuts app.
- A phrase with amount + category logs a transaction **without opening the app**, after one
  confirmation, with the account balance correct on next launch.
- `VoiceInputConfirmationView` and the intents share one write path.
- All 11 locales have phrases and strings; parity script clean.
- Settings has a "Siri & Shortcuts" section with localized example phrases.
- Tests above pass; manual device checklist passes.
- CLAUDE.md file-organization tree updated with `Tenra/Intents/` and `Services/Intents/`.

---

## 10. Next milestones (context, not scope)

1. Quick-add templates for frequent expenses (in-app, cheap, and the natural content source
   for a widget and a Control Center control).
2. WidgetKit: home + Lock Screen. Requires an App Group or a snapshot pipeline.
3. Control Center control / Action Button wired to the quick-add intent.
4. Savings goals (CoreData v13) — the "reason to come back" layer on top of the habit.
