# Tenra 1.8.2: What's New (ASC, 13 storefront locales and en-GB)

Version 1.8.2 in the project since 2026-11-06, TestFlight build 74 (from the cloud, 2026-11-07) for
the device check. 1.8.1 is in the store since 2026-11-06/07 (its notes and checklist:
[archive/release-notes-1.8.1.md](archive/release-notes-1.8.1.md)), so 1.8.2 can go to review once the
device check below passes. `prepare-version` (Actions → App Store Connect, [asc.md](asc.md)) pastes
each block into App Store Connect; en-GB (search in Kazakhstan) carries ru's text. No em dashes
(user rule).

**What's New: not written yet.** The changes are the funnel (below) and a reminder fix, nothing a
person asks for by name; App Store Connect still needs a text in every locale. A short
"Improvements and fixes" style note in 14 localizations is enough, written before `prepare-version`.

## In 1.8.2 (main since 2026-11-06)

- The trial offer at the end of onboarding: after "Start" on the auto-capture step, a free person
  sees Tenra Pro's paywall when the App Store has plans (source `onboarding`); ✕, a swipe or a
  purchase ends onboarding on Home with the account and categories saved. A founder or Pro, or no
  plans loaded, goes straight to Home.
- Analytics' soft paywall from 3 entries (was 10), not within a day of the onboarding offer.
- Activation attributes in RevenueCat (`onboarding`, `entries`, `ten_opened`): covered by the
  App Privacy answers of 2026-11-06, nothing to change.
- The evening reminder: deposit interest posted at launch no longer counts as recording the day; a
  new recurring payment does. tr offer text reads "%@ saatinde".
- Transfer and top-up offer accounts and deposits, no longer loans (a loan is paid on its own
  screen). From build 74.
- A subscription's real charge (a bank's notification, Apple Pay, an expense entered by hand)
  merges into its planned charge instead of standing beside it: "This is a subscription…" in an
  expense's repeat menu, Link payments, and "Looks like X" in To review; the merchant is
  remembered. From build 74.
- A transfer between two of the person's banks that neither bank marks as one ("Перевод" in one
  app, "Пополнение" in the other) becomes one transfer instead of an expense and an income; when
  only the amount and the time say so, To review asks ("Not a transfer" puts them back). From
  build 74.

## Submission checklist

1. **CI green**, then a TestFlight build from `main` (done: build 74, CI green on a5b2d92f).
2. **Device check of 1.8.2** (build 74): a fresh install as a free person reaches the paywall
   after the last onboarding step, ✕ lands on Home with the account and categories saved; after a
   purchase or restore too. Analytics' paywall appears after the 3rd entry, not on the day of the
   onboarding offer. With real bank pushes: a subscription's charge lands on its planned charge
   (one transaction, the bank's amount and date) or asks "Looks like X" in To review; a transfer
   from one of your banks to another becomes one transfer (asked in To review when only the
   amount and time match), "Not a transfer" puts both back; Transfer and top-up list no loans.
3. **Phone checks carried over from 1.8.1** (the Simulator covered the rest,
   [archive/release-notes-1.8.1.md](archive/release-notes-1.8.1.md) item 2): the evening push at the
   set time on a day with nothing recorded and none after an entry (manual, Ten's draft, Apple Pay
   capture); a tap opens Ten; VoiceOver reads amounts in "1’234.56" and "1.234,56"; the widget
   shows a chosen format.
4. **What's New** in this file (14 localizations), then `prepare-version --version 1.8.2 --build 74`.
5. **One submission**: `asc.py prepare-review --version 1.8.2`; the founder sends it.
