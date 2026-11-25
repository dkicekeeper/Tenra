# Usage Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Status 2026-11-25: approved by the founder with its spec, [plan-sales.md](plan-sales.md) §4.
> Tasks 1-5 written for 1.10 (build around 02.12); the server deploy and the first `app-stats`
> run follow the merge and 1.10's release (Task 5 steps 3-5). Moves to `archive/plans/` once 1.10 ships; the rules
> settle in `domains/analytics.md` (Task 5).

**Goal:** Tenra counts how far new people get and whether they come back, anonymously and
without an install identifier, so the Saturday session can see where people are lost.

**Architecture:** The app keeps a small buffer of events of two kinds: milestones, each sent once
per install, and counters. It posts them in batches to the assistant's Cloudflare Worker
(`POST /v1/events`). The Worker checks every value against fixed lists and writes one Analytics
Engine point per event. `scripts/app_stats.py` (Actions → Assistant server → `app-stats`) turns
the counts into the funnel, "where they leave" and retention tables. One Settings switch turns
off the app's events and the labels of Ten's turns.

**Tech Stack:** Swift 6 patterns on iOS 26 (MainActor default isolation, swift-testing),
TypeScript Worker (vitest, Workers Analytics Engine, the Rate Limiting binding), Python 3 report
script.

**Spec:** [plan-sales.md](plan-sales.md) §4 (and §8, the founder's decisions).

## Global Constraints

- No identifier of the install, the person or the device in any event; no amounts, currencies,
  texts, names of categories, accounts or merchants; no country or region; the server does not
  keep IPs.
- Every value comes from a fixed list; the server drops a batch with any unknown value.
- The switch "Anonymous usage statistics" is **on by default**; off sends nothing and clears the
  buffer; it also stops Ten's turn labels (`stats: false` in the turn request).
- Silent in unit tests, UI tests and `-ScreenshotDemo` (`PremiumManager.isAutomatedRun`).
- At most 500 buffered events, batches of at most 100, at most 300 events per install per day;
  sending never on the main actor, never before the first screen.
- Analytics Engine keeps 90 days; the privacy policy says so.
- Every new UI string in all 12 locales; no em dashes in user-facing text.

## Review Focus

1. **The switch off mid-batch:** a flush already in flight finishes, nothing queued after the
   switch goes out, and the buffer is empty. Test in Task 3.
2. **Clock and calendar edges:** an install at 23:59 and an open at 00:01 is day 1; a phone set to
   another time zone or calendar still writes an ISO week `yyyy-Www` with Gregorian years. Tests in
   Task 3.
3. **Reinstall or a restored backup:** milestones are kept in UserDefaults, so a reinstall is a
   new install (expected); a backup restore must not resend `installed` or onboarding milestones
   that were already sent on this device. Test in Task 3.
4. **Offline for days:** the buffer caps at 500, the oldest go first, and each event keeps the
   `day` it happened on, not the day it is sent. Test in Task 3.
5. **A malformed or hostile batch:** oversized, unknown names, numbers out of range, a value with
   an amount in it: the Worker answers 400 and writes nothing. Tests in Task 1.

---

### Task 1: The Worker's `/v1/events` and the turn's `stats` flag

**Files:**
- Create: `server/assistant/src/events.ts`
- Modify: `server/assistant/src/index.ts` (route, before the model's enabled and country gates,
  like `/v1/feedback` but without App Attest), `server/assistant/src/config.ts` (`APP_EVENTS`,
  `EVENTS`, `EVENTS_LIMIT`), `server/assistant/src/validate.ts` (`TurnRequest.stats?: boolean`),
  `server/assistant/wrangler.toml`
- Test: `server/assistant/test/events.test.ts`, `server/assistant/test/index.test.ts`

**Interfaces:**
- Produces: the wire format the app sends, `{"events": [UsageEventWire]}` with
  `UsageEventWire = { kind: "m" | "c", name: string, value: string, cohort: string, day: number,
  plan: string, entries: string, reminder: boolean, capture: boolean, onboarding: string,
  furthest0: string, build: string, ios: string, lang: string }`.
- Produces: `parseEventsBatch(body: unknown): UsageEventWire[]` (throws `ValidationError`),
  `writeEvents(dataset: AnalyticsEngineDataset | undefined, events: UsageEventWire[]): void`,
  `ALLOWED: Record<string, readonly string[]>` (name → allowed values).

The allowed lists (one source for the app's enums in Task 3):
- milestones (`kind: "m"`): `installed` [""]; `onboarding` [welcome, currency, account,
  categories, capture]; `onboarding_done` [finished, skipped, restored]; `first_screen` [home,
  history, analytics, finances, assistant, add, import, settings, paywall, wardrobe]; `entries`
  [1, 5, 10, 50]; `reminder_on` [""]; `notifications` [granted, denied]; `capture_first` [""];
  `widget_on` [""]; `ten_opened` [""]; `paywall_first` [every `PaywallSource` raw value];
  `trial_started`, `renewal_off`, `converted` [""]; `returned` [1, 2, 3, 7, 14, 30, week2].
- counters (`kind: "c"`): `open` [cold, warm]; `entry` [""]; `paywall` [shown, closed,
  purchase_started, purchased, cancelled, failed, restored] with the gate and plan folded into
  `value` as `step:gate:plan` (plan: monthly, annual, lifetime, none); `feature` [budget, goal,
  debt, loan, deposit, asset, csv_export, year_review, voice, statement]; `ten` [asked,
  notice_opened, notice_hidden]; `moment` [goal, debt, loan, asset, budget, capture].
- fields: `cohort` `^\d{4}-W\d{2}$`; `day` integer 0-400; `plan` [free, trial, pro, founder];
  `entries` [0, 1, 2-4, 5-9, 10-49, 50+]; `onboarding` [none, finished, skipped, restored];
  `furthest0` [none, welcome, currency, account, categories, capture, onboarding_done, entry,
  reminder]; `build` `^\d{1,6}$`; `ios` `^\d{2}$`; `lang` `^[a-z]{2}(-[A-Z]{2})?$`.
- The data point: `indexes: [name]`, `blobs: [kind, name, value, cohort, plan, entries,
  reminder ? "on" : "off", capture ? "on" : "off", onboarding, furthest0, lang, build, ios]`,
  `doubles: [1, day]`.

- [ ] **Step 1: Write the failing tests** in `test/events.test.ts`:
  `accepts a valid batch and writes one point per event` (2 events → 2 `writeDataPoint` calls
  with the blob order above); `refuses an unknown name, value or field` (each → 400 `events`,
  0 writes); `refuses more than 100 events or a body over 64 KB`; `refuses a value that is not
  on its list even if it looks harmless` (`entries: "37"`, `lang: "russian"`, `cohort: "2026-48"`);
  `answers 204 and writes nothing with APP_EVENTS off`; `answers 429 when the rate limit says
  no`. In `test/index.test.ts`: `a turn with stats false writes no turn or draft point`.
- [ ] **Step 2: Run** `cd server/assistant && npm test` → the new tests fail.
- [ ] **Step 3: Implement** `events.ts` and the route: POST only (405 otherwise), body ≤ 64 KB,
  `parseEventsBatch`, `EVENTS_LIMIT.limit({ key: CF-Connecting-IP })` when the binding exists
  (30 per 60 s; the IP is only the key, never stored), 204 on success. `readConfig` gains
  `appEvents: env.APP_EVENTS === "on"`. `validate.ts` accepts an optional boolean `stats`;
  `index.ts` writes turn and draft points only when `config.turnStats && turn.stats !== false`.
  `wrangler.toml`: `[[analytics_engine_datasets]] binding = "EVENTS" dataset =
  "tenra_app_events"`, `[[ratelimits]] name = "EVENTS_LIMIT" namespace_id = "1101" simple = {
  limit = 30, period = 60 }`, `APP_EVENTS = "on"` with a comment pointing to plan-sales §4.
- [ ] **Step 4: Run** `npm test && npx tsc --noEmit` → all pass.
- [ ] **Step 5: Commit** `feat(assistant-server): /v1/events counts the app's milestones, no identifier`.

### Task 2: The report, `app-stats`

**Files:**
- Create: `server/assistant/scripts/app_stats.py`, `server/assistant/scripts/test_app_stats.py`
- Modify: `.github/workflows/assistant.yml` (`app-stats` in `action`'s options, a job like
  `turn-stats`, `days` default 28)

**Interfaces:**
- Consumes: the dataset `tenra_app_events` and the blob order of Task 1 (`blob1` kind … `blob13`
  ios, `double2` day).
- Produces: `python3 scripts/app_stats.py --days N` printing Markdown; pure functions
  `funnel(rows) -> list[dict]`, `drop_off(rows) -> list[dict]`, `retention(rows) -> list[dict]`
  over rows `{cohort, name, value, furthest0, reminder, capture, count}`.

- [ ] **Step 1: Write the failing tests** in `test_app_stats.py` (unittest, rows as fixtures):
  `test_funnel_counts_each_milestone_once_per_cohort` (installed 100, onboarding_done 60,
  entries:1 30 → 60% and 50% of the step before, 30% of installs); `test_drop_off_names_the_step_that_loses_most`;
  `test_retention_by_furthest0` (returned:1 with furthest0=entry 12 of 30 installs whose furthest0
  is entry → 40%; the denominator comes from the milestone counts: installs whose furthest day-0
  milestone is X = reached X minus reached the next one); `test_cohort_with_no_installs_is_skipped`.
- [ ] **Step 2: Run** `python3 -m unittest server/assistant/scripts/test_app_stats.py` → fail.
- [ ] **Step 3: Implement** the SQL (one `GROUP BY blob4, blob1, blob2, blob3, blob10, blob7,
  blob8` query with `SUM(_sample_interval)` as count, `timestamp > NOW() - INTERVAL 'N' DAY`) and
  the tables: funnel of day 0 by cohort; where they leave; returned 1/2/3/7/14/30/week2 by cohort
  and by furthest0, reminder, capture; first entry by day (entries:1 by `double2`); paywall by
  step, gate and plan; trial started, renewal off, converted; features per active day; opens.
  Same token and `query()` as `turn_stats.py` (Account Analytics: Read).
- [ ] **Step 4: Run** the tests → pass.
- [ ] **Step 5: Commit** `feat(assistant-server): app-stats, the funnel and retention from the app's counts`.

### Task 3: `UsageEvents` in the app

**Files:**
- Create: `Tenra/Services/Analytics/UsageEvents.swift` (the milestones, counters, buffer, caps,
  switch), `Tenra/Services/Analytics/UsageEventsTransport.swift` (protocol + the HTTP sender over
  `AgentConfig.serverURL`)
- Modify: `Tenra/Services/Premium/PremiumManager.swift` (`isAutomatedRun` internal instead of
  private)
- Test: `TenraTests/Services/Analytics/UsageEventsTests.swift`

**Interfaces:**
- Consumes: the lists and wire format of Task 1; `ActivationAttributes.OnboardingStepReached`,
  `.OnboardingOutcome`; `PaywallSource`; `ProStatus`.
- Produces:
  - `enum UsageScreen: String` (home, history, analytics, finances, assistant, add, import,
    settings, paywall, wardrobe), `enum UsageFeature: String` (the `feature` list),
    `enum UsageTenAction: String`, `enum UsagePaywallStep: String`.
  - `enum UsageMilestone: Hashable, Sendable` with cases `installed`,
    `onboardingStep(ActivationAttributes.OnboardingStepReached)`,
    `onboardingDone(ActivationAttributes.OnboardingOutcome)`, `firstScreen(UsageScreen)`,
    `entries(Int)`, `reminderOn`, `notifications(granted: Bool)`, `captureFirst`, `widgetOn`,
    `tenOpened`, `paywallFirst(PaywallSource)`, `trialStarted`, `renewalOff`, `converted`,
    `returned(day: Int)`, `returnedWeek2`; `var wire: (name: String, value: String)`.
  - `enum UsageCounter: Hashable, Sendable` with cases `open(cold: Bool)`, `entry`,
    `paywall(UsagePaywallStep, source: PaywallSource, plan: ProStatus.Plan?)`,
    `feature(UsageFeature)`, `ten(UsageTenAction)`, `moment(TenMomentEvent)`.
  - `struct UsageTraits: Equatable, Sendable { plan: String; entries: Int; reminder: Bool;
    capture: Bool; onboarding: String }`.
  - `struct UsageEvent: Codable, Equatable, Sendable` matching `UsageEventWire`.
  - `protocol UsageEventsTransport: Sendable { func send(_ events: [UsageEvent]) async throws }`
    and `struct HTTPUsageTransport: UsageEventsTransport` with `static func make() ->
    HTTPUsageTransport?` (nil without `AgentConfig.serverURL`).
  - "Once per install" means once per wire name for `onboarding_done`, `paywall_first` and
    `notifications` (the first answer, the first gate, the first outcome), and once per name and
    value for the rest (each step, screen, entry milestone and return day).
  - `@MainActor final class UsageEvents` with `static let shared`, `static let enabledKey =
    "usage.enabled"`, `init(defaults: UserDefaults = .standard, isSilent: Bool =
    PremiumManager.isAutomatedRun, transport: UsageEventsTransport? = HTTPUsageTransport.make(),
    traits: @escaping () -> UsageTraits)`, `var isEnabled: Bool` (get/set; set false clears the
    buffer), `func reach(_ milestone: UsageMilestone, now: Date = .now)` (once per install),
    `func count(_ counter: UsageCounter, now: Date = .now)`, `func noteOpen(cold: Bool, now: Date
    = .now)` (`installed` on the first one, `returned` days and `week2`, the `open` counter),
    `func flush() async`, `private(set) var pending: [UsageEvent]`, `var traits: () ->
    UsageTraits` (settable, AppCoordinator wires it), `static func cohort(installedAt: Date) ->
    String` (ISO-8601 week on a Gregorian calendar in the device's time zone),
    `static func entriesBucket(_ count: Int) -> String`,
    `static func proMilestones(from old: ProStatus?, to new: ProStatus?) -> [UsageMilestone]`.
  - UserDefaults keys: `usage.installedAt`, `usage.sent` (the milestones' wire names), `usage.furthest0`,
    `usage.dayCount` (day key + count for the 300 cap), `usage.buffer` (JSON, ≤ 500).

- [ ] **Step 1: Write the failing tests** (`@MainActor`, a suite `UserDefaults`, a recording
  transport): `aMilestoneGoesOnce` (reach `.tenOpened` twice → one pending, and none after a
  second `UsageEvents` on the same defaults); `theFirstOpenIsInstalledThenReturnsCount`
  (install 2026-12-01 23:59, open 2026-12-02 00:01 → `returned:1`; an open on day 7 →
  `returned:7` and `returned:week2`; day 8 → no new `returned`, `week2` not again);
  `theCohortIsAnISOWeek` (2026-12-28 → `2026-W53`, 2027-01-04 → `2027-W01`, a Buddhist-calendar
  phone the same); `furthest0FollowsDayZeroOnly` (onboarding steps then `entries(1)` on day 0 →
  furthest0 `entry`; `reminderOn` on day 2 leaves it); `eventsCarryTheDayTheyHappened`
  (queued on day 0, flushed on day 3 → `day == 0`); `theBufferKeeps500Newest`;
  `aDayStopsAt300`; `onceMeansTheFirstOutcome` (`onboardingDone(.finished)` then
  `onboardingDone(.restored)` after a backup restore → only `finished`; `firstScreen(.home)`
  and `firstScreen(.history)` → both); `offClearsAndSendsNothing` (switch off with 10 pending → 0 pending, flush
  sends nothing, reach after it adds nothing; on again → sends again, already-sent milestones
  still not resent); `silentInTests` (`isSilent: true` → nothing pending ever);
  `proTransitions` (nil → trial → `trialStarted`; trial willRenew → trial !willRenew →
  `renewalOff`; trial → paid annual → `converted`; paid → nil → nothing); `aFailedSendKeepsTheBatch`
  (transport throws once → pending unchanged; third failure in a row drops it);
  `noIdentifierInTheWire` (encode a batch: the JSON keys are exactly the fields of
  `UsageEventWire`).
- [ ] **Step 2: Run** `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/UsageEventsTests` (CI in the cloud) → fail to compile.
- [ ] **Step 3: Implement** `UsageEvents.swift` and the transport. The transport posts
  `{"events": [...]}` as JSON to `serverURL/v1/events` from a detached task with a 15 s timeout;
  any non-2xx is an error. `flush()` takes up to 100 from the buffer, sends, removes them on
  success; a periodic flush every 5 minutes while active and one on going to the background
  (wired in Task 4).
- [ ] **Step 4: Run** the tests → pass.
- [ ] **Step 5: Commit** `feat(analytics): UsageEvents, milestones once per install and counters, no identifier`.

### Task 4: Wiring, the switch and the turn flag

**Files:**
- Modify: `Tenra/ViewModels/AppCoordinator.swift` (traits closure: plan from `PremiumManager`,
  entries from `transactionStore.transactions.count`, reminder from `SpendingReminder`, capture
  from `WalletCaptureStore.shared.firstCaptureAt != nil`, onboarding from the stored
  `activation.onboarding`; `TransactionStore.onOwnRecords` → `count(.entry)` and
  `reach(.entries(n))` at 1/5/10/50; first capture → `reach(.captureFirst)`),
  `Tenra/Views/Home/MainTabView.swift` (`noteOpen` on `.active`, `flush()` on `.background`, the
  5-minute flush; `selectedTab` change → `reach(.firstScreen(...))`; `WidgetCenter` configurations
  non-empty → `reach(.widgetOn)`),
  `Tenra/ViewModels/OnboardingViewModel.swift` and `AppCoordinator` where
  `ActivationAttributes.noteOnboardingStep` / `noteOnboarding` are called (the same moments →
  `reach(.onboardingStep(...))`, `reach(.onboardingDone(...))`),
  `Tenra/Views/Assistant/AssistantView.swift` (next to `ActivationAttributes.noteTenOpened()` →
  `reach(.tenOpened)`; a question sent → `count(.ten(.asked))`),
  `Tenra/Views/Assistant/AssistantNoticeCard.swift` (`notice_opened`, `notice_hidden`),
  `Tenra/Services/Premium/PremiumManager.swift` (`notePaywallShown` → `reach(.paywallFirst)`
  and `count(.paywall(.shown, ...))`; `apply(_:)` → each of `proMilestones(from:to:)`),
  `Tenra/Views/Premium/PaywallSheet.swift` (completed, restored, cancelled, failed, closed),
  `SpendingReminder` (turned on → `reach(.reminderOn)`; the permission answer →
  `reach(.notifications(granted:))`), `TenMoments.celebrate` (`count(.moment)`), the screens of
  `UsageFeature` (their `.task` → `count(.feature(...))`, once per day per feature inside
  `UsageEvents`), `Tenra/Services/Agent/AgentServerClient.swift` (the turn body gets
  `"stats": false` while the switch is off), `Tenra/Views/Settings/SettingsPrivacySection.swift`
  (a second row, `UniversalRow(... accessory: .toggle(...))`, with a footer), 12 locales.
- Test: `TenraTests/Services/Analytics/UsageWiringTests.swift`

**Interfaces:**
- Consumes: everything Task 3 produces.
- Produces: strings `settings.usageStats` ("Anonymous usage statistics"),
  `settings.usageStats.footer` ("Counts which steps and screens are reached, never amounts,
  names or anything that identifies you. Helps us make Tenra better.") in 12 locales.

- [ ] **Step 1: Write the failing tests:** `ownRecordsReachEntryMilestones` (a `TransactionStore`
  with the hook, 5 own records → `entries:1` and `entries:5` pending, a series' payment adds
  nothing); `theTurnBodySaysStatsFalseWhenOff` (the request body `AgentServerClient` builds
  contains `"stats":false` only with the switch off); `onboardingStepsMirrorTheAttributes`
  (`OnboardingViewModel` advancing → the same steps as `ActivationAttributes` got).
- [ ] **Step 2: Run** the suite (CI) → fail.
- [ ] **Step 3: Implement** the wiring listed under Files; the strings with `python3` and
  `io.open(..., encoding="utf-8")`, then the parity check of CLAUDE.md red flag 13.
- [ ] **Step 4: Run** the suites of Task 3 and 4 plus `scripts/designkit_lint.sh` → pass.
- [ ] **Step 5: Commit** `feat(analytics): the app's milestones wired, the statistics switch, Ten's turns follow it`.

### Task 5: Privacy, docs, deploy

**Files:**
- Modify: `docs/public/privacy-policy.html` and its ru and kk pages (the section "What Tenra's
  server counts" gains the app's milestones and counters, their fields, 90 days, the switch;
  "no identifier of you or your device" stays true), `docs/release-notes.md` (1.10 item and phone
  checks), `docs/plan-sales.md` (§4 ticked, the status line), `docs/promotion-plan.md` §7
  (Saturday step 1 reads `app-stats`), `docs/backlog.md` (the "No behavioural analytics SDK"
  decision mentions the app's own counting), `CLAUDE.md` (a row in "When to Read Which Doc",
  a line under Monetization or Testing for the silence rule), `docs/README.md`
- Create: `docs/domains/analytics.md` (what is counted, the lists, the switch, the report, how to
  add an event: the Worker list and the app enum in one commit)

- [ ] **Step 1:** Write the docs above; `grep -n "—"` on the changed user-facing files → none.
- [ ] **Step 2:** Push; CI green (app, server `test` job, design lint).
- [ ] **Step 3:** After merge to main: Actions → Assistant server → `deploy`; `curl -s -X POST
  .../v1/events -d '{"events":[]}'` → 400 (`events`), proving the route is live.
- [ ] **Step 4:** The founder checks App Privacy in App Store Connect: Usage Data › Product
  Interaction, Analytics, not linked, not tracking (no change expected).
- [ ] **Step 5:** A week after 1.10 is out: the first `app-stats` run, its tables as new datasets
  of the founder's dashboard "Tenra с запуска" (promotion-plan §7 step 6), and the new columns in
  promotion-plan §6.
- [ ] **Step 6: Commit** `docs(analytics): what the app counts, the switch and the report`.
