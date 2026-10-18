# Release audit 1.6 (2026-10-15)

Scope: everything since 1.5 (`29c56681..06922c8`, ~32k lines): Ten (the assistant, app side and
`server/assistant`), savings goals and personal debts (CoreData v13-v15), the insights redesign,
DesignKit 4.x. Eight read-only reviews ran in parallel: persistence and migration, goals and
debts, the assistant on the phone, the Worker, performance, design system and localization,
crashes and concurrency, release configuration and screenshots. No Xcode in the session: findings
come from reading call paths; the fixes were compiled and tested by CI on the branch.

Open items are in [backlog.md](../backlog.md) (section "Release audit 2026-10-15"); the manual
release steps are in [release-notes.md](../release-notes.md) (Submission checklist).

## Verdict

No crash or data loss for a 1.5 user who upgrades: v12 → v15 is purely additive (four new
entities, no change to existing ones, every non-optional attribute has a default), the
`+CoreDataProperties` match the model, the stack, backup and restore code are unchanged since 1.5,
and a v12 or TestFlight v13/v14 backup restores into 1.6. Design lint is clean (0 values), the 11
locales have identical keys, plural categories and format specifiers, and there are no em dashes
in user-facing text. The added Swift code has no force unwraps, `try!`, `as!` or `fatalError`.
Only `PremiumManager` imports RevenueCat. 1.6 schedules no new local notifications.

## Fixed on `claude/compassionate-curie-9bgxnb`

Server (`server/assistant`, 68 tests, deploy with Actions → Assistant → deploy):
- **Kept threads broke after every prompt deploy (P0).** Thinking blocks are bound to the system
  prompt, tools and earlier messages; the account was created after 2026-08-31, so a stale block
  is a 400 that no retry fixes. Now `thinking.block_binding.prefix_mismatch_behavior:
  "drop_block"` with the `thinking-binding-controls-2026-08-01` beta.
- **Unauthenticated requests cost money (P0).** RevenueCat lookup and KV writes ran before the App
  Attest check; the assertion is checked first now.
- **Someone else's Pro id (P1).** The `x-tenra-user` header was not signed. Pro is looked up only
  for `user` inside the signed body; the header alone counts as free.
- **Heavy users could not ask anything (P1).** `<app_context>` (categories with ids, 30 facts)
  passed the 4 000-character text-block limit: now 16 KB; a tool result 64 KB (a year's forecast).
- Mid-stream overload maps to a retryable error; country from `request.cf`; KV counter writes are
  best effort (one write per second per key).

App:
- **Backups lost Ten's long threads, and a restore then crashed the assistant (P0).**
  `AgentThreadEntity.payload` allows external storage; a value over ~100 KB goes to
  `.Tenra_SUPPORT/_EXTERNAL_DATA`, which backups (a copy of `Tenra.sqlite`) do not carry.
  Payloads are LZFSE-compressed now (plain JSON still reads), and the history is trimmed by size
  (128 KB) as well as count.
- **"Delete all data" kept Ten's chat (P1, privacy).** The open thread, drafts and attachments
  stayed in memory and were written back into the new store; Home kept notices naming debtors
  and goals. `AssistantViewModel.storeDidReset` and `AssistantInbox.clear` on
  `storeDidResetNotification`.
- **Debts that never settle (P1).** Double sums (1 142.49 + 12 294.80 = 13 437.289999999999)
  left "0 left" debts open and goals unreached; within half a cent now. A debt its repayments
  settled reopens when they no longer cover it; a goal's or debt's entries move to a new currency.
- **CSV import through Ten bypassed Pro (P1).** The paperclip → File and "Open in Tenra" CSV
  path now goes through the paywall.
- **Retry ignored a revoked cloud consent (P2).** It asks for consent again.
- **Consent text (P2).** "Tenra's server keeps nothing" was untrue (App Attest key, counts);
  goals and debts were not named among what leaves the phone. 11 locales.
- **Privacy manifest (P2):** collected data types for Ten and the disk-space API (`E174.1`).
- "20%%" shown literally in two recommendations (since 1.5); VoiceOver read `status.active` and an
  English character count (DesignKit keys missing); `simulate_loan` could overflow `Int`.
- Privacy policy and App Privacy draft: the App Attest key is kept until 400 days after last use.

## Not fixed: worth doing before or soon after 1.6

P1, decide before submission:
- **Ten animates on Home** whenever an unread notice exists (`AssistantNoticeCard`,
  `ParticleCreature` `.compact`, no `AmbientMotionGate`); also the chat mascot `.lively` never
  dozes. Check with Instruments (Energy) on the device; use the still `CreatureGlyph` on Home if
  it keeps the display at 120 Hz.
- **Founding Users are free on the server**: the app treats them as Pro, the server gives 150
  calls a month per install, then "You've used this month's questions". Grant them `pro` in
  RevenueCat, or accept the limit.
- **The binary for review was never tested**: TestFlight builds come from Xcode 26 in CI; the App
  Store build from the Mac with Xcode 27 compiles the iOS 27 paths (the `.prominent` action tab,
  `swipeActionsContainer`).

P2:
- Privacy: forgetting a fact leaves it in kept threads (the old `<app_context>` is resent);
  FastPath messages typed before consent go out with the next cloud question (`<draft_status>`);
  the Settings toggle turns the cloud on without the consent sheet.
- RU/BY storefronts show the cloud mode; every question there answers 451.
- Attestation failures look permanent (`try?` in `AgentServerClient`), no Retry, a new Secure
  Enclave key per question; RevenueCat outage (502) has no Retry either.
- `invalid` 400s (size) show Retry, which resends the same request.
- Notices ignore "hide amounts" (amount baked into the body); notices outlive a deleted debt,
  goal or subscription.
- Performance: a library photo is decoded and redrawn at full resolution on the main thread
  (100-200 MB); each streamed piece re-parses the whole reply and re-renders the chat and the
  assistant home; free-tier allowance does Keychain IPC on the main thread; FastPath runs the
  voice parser (a 19k-transaction pass) on questions too; `forecast_balance` builds its series in
  O(days × occurrences) on the main thread; notices can pop in during the Home reveal.
- Correctness: chat cards do not refresh after the transaction they show is edited (red flag
  12); goal screens ignore `currencyRatesVersion` and a day change; `reachedAt` is set only while
  the goal's screen is open; the debt Pro gate is checked at draft time only; two repayment drafts
  can over-repay; the UI accepts a repayment above what is left and a due date before the loan.
- Concurrency: fetch-or-insert saves without a uniqueness constraint can duplicate a row
  (threads, goals, debts, facts); a load can overwrite an `add` in flight; a FastPath draft in
  flight races `reset()`; typed text is lost when a FastPath draft is still running; a chat
  deleted during its save comes back.
- Voice sheet: closing it within the first 100 ms can leave the microphone on; "say it again"
  keeps the old silence timer.
- "Open in Tenra" where the assistant is unavailable does nothing and leaves the file in
  `Documents/Inbox`.
- German: ~22 of Ten's strings say "du", the rest of the app (and Ten's own notices) "Sie";
  Japanese empty-state lines are casual while Ten is polite elsewhere.
- VoiceOver is not told when Ten's reply arrives.
- Terms of Use still say Tenra has no access to financial data; mic and speech permission texts
  don't mention Ten.

Server, before traffic grows: counters in Durable Objects (KV read-then-write is not atomic,
reads up to 60 s stale); a Rate Limiting binding per IP on `/v1/attest*` and `/v1/turn`;
separate global caps for free and Pro (≈34 fresh keys can trip the shared 5 000-call breaker);
a RevenueCat timeout and last-known tier; refund the count when the upstream call fails before
output; abort the stream when the client disconnects; accept a range of `protocol` versions and
send an app build header from the next app version; reject development attestations after the
beta; a protected environment for deploy.

P3: unbounded `results` in a kept thread; a contribution/repayment JSON that fails to decode is
wiped on the next save; CSV export leaves out goals, debts and facts; previews without
`AppCoordinator` (HistoryView, InsightDetailView, AssistantWardrobe); fixed speech frames at
accessibility text sizes; `PayoffProgressCard` at large Dynamic Type (DesignKit); a "Settle"
single tap without confirmation.

## Screenshots

Every 1.5 frame shows the "+" tab; Ten, goals and debts appear nowhere. Ten never appears in the
Simulator (`AssistantAvailability` needs App Attest), and the demo seed has no goals, debts,
notices or conversation, so the pipeline needs code before it can shoot 1.6. Plan in
[release-notes.md](../release-notes.md) (Screenshots).
