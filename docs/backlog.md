# Backlog: open items, ideas, decisions

What is still open, what could be built next, and what the owner decided not to do. When an
item lands, delete its line here (git and the commit message keep the record); when a decision
changes, edit it. Larger work gets a plan file next to this one while it is in flight, and that
plan moves to `docs/archive/plans/` when it lands.

History: the audit of 2026-09-24 (plans 001-019) and the findings of 2026-09-24 to 2026-10-10,
with the commit of every fix, are in
[archive/plans/2026-09-24-audit/findings-2026-09-24-to-10-10.md](archive/plans/2026-09-24-audit/findings-2026-09-24-to-10-10.md).

## Open

- **Assistant attachments after a relaunch.** A receipt or statement attached in the chat lives
  in memory: after a relaunch its card is gone from the kept thread (drafts too, by design).
  Plan §3.8 keeps the file in the app's container with the thread; only worth it if people come
  back to an unsaved attachment.

- **Automatic payment capture and merchants** (plan in flight:
  [plan-auto-capture.md](plan-auto-capture.md) §9): built; what is left is the device checks of
  §8, then the plan moves to the archive.
- **One merchant under several keys.** Every merchant store keys on
  `CategorySuggestionService.normalizedMerchant`, which keeps processor prefixes, legal forms and
  a trailing city: Wallet's "MAGNUM CASH&CARRY 123" and a statement's "ТОО MAGNUM CASH&CARRY
  ALMATY KZ" are two merchants (name, logo choice, merchant screen totals, subscription runs).
  Keying on the clean name (`MerchantName.displayName`, normalized) needs a migration of the stored
  keys in `MerchantCategoryMemory`, `MerchantLogoStore`, `WalletCaptureStore` and the candidate
  dismissals. Decide whether it is worth it.
- **Legacy converted deposits (DP1).** A read-only DEBUG diagnostic lists deposits converted
  before the `conversionTimestamp` fix (Settings → Experiments, `LegacyDepositDiagnostics`).
  Recovery waits for real data.
- **Performance left on the main actor:** `recalculateAll` for balances (one inverted O(N)
  pass); History's CoreData refetch after each debounced (300 ms) search change (the fetched
  results controller is bound to the view context).
- **All-accounts rescans on small edits:** `DepositDetailView`'s edit `onSave` and both
  `LoanDetailView` delete paths call `recalculateAccountBalances()` where
  `recalculateBalances(for:)` with the touched accounts would do.

- **Product audit of 2026-10-22** ([archive/product-audit-2026-10-22.md](archive/product-audit-2026-10-22.md)):
  its items are in [plan-ads-readiness.md](plan-ads-readiness.md) (the Pro page, activation,
  iCloud backups by default, auto-capture counters for 1.7; widgets and templates, Kazakh,
  money for today for 1.8).

Found by the design-system audit of 2026-10-15 (everything since 1.5):
- **Logic in `Views/Assistant`:** `AppStreak`, `AssistantChatter` and `AssistantDaydreams`
  hold rules and data, no views: they belong in `Services/Agent/`, as does the catalogue half
  of `AssistantWardrobe`. Move once the wardrobe settles (no change to it since 2026-10-16, so
  it may have).

Found by the release audit of 2026-10-15 (details and file references:
[archive/release-audit-1.6-2026-10-15.md](archive/release-audit-1.6-2026-10-15.md)):
- **Ten on Home keeps animating** while a notice is unread (`AssistantNoticeCard`'s live
  `ParticleCreature`; its `AmbientMotionGate` stops it only under Reduce Motion or iOS 27's
  low-resource mode): measure on device, else the still `CreatureGlyph` there.
- **Ten's privacy edges:** a forgotten fact stays in kept threads; FastPath messages typed before
  consent go out with the next cloud question; the Settings toggle skips the consent sheet; the
  cloud mode shows in the RU/BY storefronts (451 on every question).
- **Notices:** amounts ignore "hide amounts"; a notice outlives its deleted debt, goal or
  subscription.
- **Assistant performance:** full-resolution photo decode on the main thread; each streamed piece
  re-parses the reply and re-renders the chat; allowance Keychain calls on the main thread;
  FastPath runs the voice parser on questions; `forecast_balance` series O(days × occurrences).
- **Goals and debts:** goal screens ignore FX refreshes and a new day; `reachedAt` only while the
  goal's screen is open; Pro re-check and over-repayment at a draft's Save; the UI accepts a
  repayment above what is left and a due date before the loan.
- **Races:** fetch-or-insert without a uniqueness constraint (threads, goals, debts, facts); a
  load overwriting an `add`; FastPath vs `reset()`; a chat deleted during its save comes back.
- **Copy:** German Ten strings (`assistant.*`) say "du", the app "Sie"; mic and speech
  permission texts don't mention Ten.
- **Server before traffic** (sizing in [plan-ads-readiness.md](plan-ads-readiness.md) A5, the
  rest C5): Durable Objects counters, a Rate Limiting binding, separate free and Pro caps, a
  RevenueCat timeout, no count for a failed upstream call, abort on disconnect, a `protocol`
  range and an app build header.

Found by the docs audit of 2026-10-12, not verified on device yet:
- **Duplicate Siri submissions:** repeating a phrase can log the same transaction twice; the
  confirmation snippet is the only guard. Decide whether intents deduplicate. (Wallet payments get
  their own 90-second guard in [plan-auto-capture.md](plan-auto-capture.md).)
- **Health score budget adherence** uses the calendar month, not each budget's own period;
  **`largeTransaction`** counts `.expense` only, so loan payments never qualify. Design calls.
- **`SilenceDetector`** is created in `VoiceInputService` but never fed audio.
- **Dead code and stale comments:** `TransactionStore.getPlannedTransactions(for:horizon:)`,
  `RecurringTransactionCoordinatorProtocol` and `TransactionGroupingService.groupByMonth` (its
  month formatter is not POSIX either) have no callers or conformers;
  `AccountEntity.isDeposit` is written but never read (drop at the next schema bump); comments
  still name removed things (`principalBalance` in `DepositsViewModel` and `DepositDetailView`,
  aggregate services in `TransactionCacheManager`, the "no Other category" case in
  `LogTransactionIntent`).
- **DesignKit's docs/charts.md** repeats stale lines (`seriesKey`, the `.dual` banner, "~9
  switches", `ChartAxisLabelMapCache`): a DesignKit PR.

## Ideas, not planned yet

- **Statement import:** a one-tap "align the balance to the statement" after the closing-balance
  check (today it only shows the difference).
- **Subscriptions as expected payments**, merged with the real charges when they arrive.
- **Receipt photo straight to the on-device model (iOS 27)** once
  `IntelligenceAvailability.supportsVision` is true on real devices: either an optional image in
  `DocumentSnapshot` or a vision interpreter in front of `ReceiptInterpreter` that falls back to
  the text path.
- **Crash reports from users without an SDK:** after a launch that follows a crash MetricKit
  reported, offer once to mail the report to support (user-initiated, optional). Revisit when
  Apple Search Ads brings traffic; check Apple's optional-disclosure rule before shipping.

## Decisions (stand until the owner changes them)

- **Category tiles:** 3 per row, titles on one line (plan 018 reverted 2026-09-25: two-line
  titles made the grid jump).
- **Logo lookups** send brand names to Google favicons and logo.dev: accepted (2026-09-25).
  Merchant names from payments go to logo.dev's name lookup too, after the local sources
  (2026-10-19).
- **No SMS or email capture** (2026-10-19): every bank the owner uses notifies by push, which iOS
  never shows other apps. Payments outside Apple Pay come from statements, shared receipts or by
  hand ([plan-auto-capture.md](plan-auto-capture.md) §2).
- **No automatic repairs that move balances** (2026-10-06): a transfer out of a deposit lowers
  its interest base by the raw amount (pinned by a characterization test); changing an
  account's currency doesn't reconvert its transactions; transfers saved without a target
  amount before the edit fix stay as saved.
- **No family / shared budget**: it needs sync, and CloudKit sync was removed on 2026-04-22
  after data loss. Drop `семейный` from the ru keyword field in the next ASO pass. Up for review
  (product audit 2026-10-22, decision D6): both Qalta apps in KZ now offer a shared or family book.
- **No Create ML category model**: history, brand and keyword tiers are cheaper and explainable.
- **iPad deferred**: it matters for featuring, not for traffic
  ([promotion-plan.md](promotion-plan.md)).
- **The assistant runs on Claude through the proxy** (2026-10-15). Apple's Private Cloud
  Compute model and Siri on iOS 27 can come now: since 2026-10-21 CI and TestFlight build with
  Xcode 27 on GitHub's `xcode-27` runner ([asc.md](asc.md), [plan-assistant-ios27.md](plan-assistant-ios27.md)).
- **Minimum iOS stays 26** (2026-08-26): older iOS would add 15-18% installs at the cost of a
  second UI path.
- **No behavioural analytics SDK** (2026-10-12): crashes and usage come from App Analytics,
  Xcode Organizer, TestFlight and on-device Diagnostics; the App Privacy label lists only what Ten
  sends (since 1.6), no analytics.
  Screen-level analytics (TelemetryDeck or Aptabase) only once traffic makes it meaningful.
