# Usage counts (analytics)

How far people get in the app and whether they come back, counted by Tenra's own server, with no
identifier and no third-party analytics (the founder's decisions of 2026-11-25,
[plan-sales.md](../plan-sales.md) §3-4). The plan that built it:
[plan-usage-events.md](../plan-usage-events.md).

## What is counted

`UsageEvents` (`Tenra/Services/Analytics/`) keeps two kinds of events:

- **Milestones**, sent **once per install** (the app remembers what it sent in UserDefaults
  `usage.sent`): `installed`, each onboarding step and its outcome, the first visit of each tab
  and of History, Settings, the paywall and Ten's wardrobe, own entries reaching 1, 5, 10 and 50,
  the evening reminder on, the notification answer, the first automatic capture, a Tenra widget on
  the phone, Ten opened, the first paywall's gate, a trial started, its renewal off, a trial paid,
  and the return days 1, 2, 3, 7, 14 and 30 plus "second week" (any day 7-13). Since each goes
  once, a milestone's count in an install week is the number of installs that reached it.
- **Counters**: opens (cold or warm), own records, the paywall's steps by gate and plan, Ten's
  questions and notices, Ten's moments, and features used (once a day each: budget, goal, debt,
  loan, deposit, asset, CSV export, year review, voice, statement).

Every event also carries the install week (`2026-W49`, ISO, from `usage.installedAt`), the day
since install, the plan (free, trial, pro, founder), a range of the record count, whether the
evening reminder and auto-capture are on, onboarding's outcome, the furthest step of the first
day (`furthest0`), the build, the iOS major version and the app language. Nothing else: no
amounts, names, texts, region, or identifier of the install, the person or the device.

A phone that used Tenra before 1.10 keeps its first day (`rating.installDate`) and sends no
`installed`; `app-stats` skips weeks without installs, so the first clean week is the one after
1.10 ships.

## Where it is called

The milestones sit next to the activation attributes sent to RevenueCat
(`ActivationAttributes`: onboarding, records, Ten opened), in `MainTabView` (open, return days,
tabs, widgets, the periodic send), `PremiumManager` (paywall shown, Pro transitions through
`UsageEvents.proMilestones`), `PaywallSheet` (the paywall's outcomes), `SpendingReminder`,
`NotificationPermissionManager`, `WalletCaptureStore`, `AssistantViewModel.send`, Ten's notices,
`TenMoments`, and `.usageFeature(_:)` / `.usageFirstScreen(_:)` (`Extensions/View+Usage.swift`)
on the feature screens. A new event is added to the server's list (`server/assistant/src/events.ts`)
and the app's enum (`UsageMilestone`, `UsageCounter`) in one commit: the server refuses a batch
with any value it does not know.

## Sending

A buffer of at most 500 (oldest dropped), at most 300 events a day, batches of 100 to
`POST /v1/events` 20 s after the app comes to the front, every 5 minutes while it stays and when it
leaves (`TenraApp`). A failed batch is kept; the third failure in a row drops it. Silent in unit
tests, UI tests and `-ScreenshotDemo` (`PremiumManager.isAutomatedRun`).

**The switch**: Settings › Privacy › "Anonymous usage statistics" (`usage.enabled`, on by
default). Off sends nothing and empties the buffer, and Ten's turns carry `stats: false`, so the
server does not count their labels either. The privacy policy ("How far people get in the app")
describes all of it; the App Privacy label's Usage Data › Product Interaction for Analytics, not
linked, covers it.

## Server and report

`POST /v1/events` (`server/assistant/src/events.ts`): no App Attest (it would give each install a
lasting key), every value checked against its list, a rate limit of 30 batches a minute keyed by
the address (never stored), one Analytics Engine point per event in `tenra_app_events`, on with
`APP_EVENTS = "on"`. Kept 90 days.

**Actions → Assistant server → `app-stats`** (`scripts/app_stats.py`, 28 days by default): the
funnel by install week, where people are lost on their first day (biggest loss first), who comes
back on each return day by the furthest step of day 0 and by the reminder and auto-capture, the
day of the first entry, the paywall by step, gate and plan, trials, features and opens. The
Saturday session reads it into the founder's dashboard "Tenra с запуска" and promotion-plan §6.
Its arithmetic is tested by `scripts/test_app_stats.py` in the server's test job.

## Tests

`UsageEventsTests` (once per install, return days, ISO weeks, `furthest0`, the day an event
happened, caps, the switch, silence, Pro transitions, failed sends, the wire's fields, safe
language and build, existing installs, own records, the turn's `stats`, tabs);
`server/assistant/test/events.test.ts` (the batch, unknown values, limits, off, rate limit, the
turn's flag).
