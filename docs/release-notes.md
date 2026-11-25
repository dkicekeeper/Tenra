# Tenra 1.10: What's New and the checklist

1.9 is in the store since 2026-11-25 (build 93; its notes:
[archive/release-notes-1.9.md](archive/release-notes-1.9.md)). **The next version is 1.10**, the
update the featuring nomination promises for the last week of December: build in TestFlight by
15.12, sent by 19.12 with a manual release on 26.12 (proposed, the founder's word pending,
[plan-release-1.9.md](plan-release-1.9.md) §6-7). What's New is written once the version is
assembled; no em dashes (user rule).

## In this version (in `main`)

- **The plan for January** ([plan-release-1.9.md](plan-release-1.9.md) §4): Ten's message on Home
  on 1-5 January and "Plan for January" on the year review's last page open Ten's chat; Ten
  drafts January's budgets from what is really spent, a rainy-day goal for the year when there is
  none, and the evening reminder when it is off. The rule is on the server since 2026-11-25, so a
  question in words gets the plan in 1.9 too.
- **"Не то" under Ten's answer** ([domains/assistant.md](domains/assistant.md) §7): the person
  sends the developer what was wrong, with the question and Ten's words (no figures from the
  cards). The server takes it since 2026-11-25.

- **The ✕ in onboarding leads to a ready app** (the founder's decision 2026-11-25, after the
  funnel of 11-24.11): the typed account or a card with no money in the chosen currency, and the
  picked categories (all when none is), so the first expense is one tap away; and the anonymous
  attribute `onboarding_step` (the furthest screen) to see where people leave onboarding.

Planned, not in `main` yet: Ten's moments (C, waits for DesignKit #105).

## Phone checks

- **"Plan for January"**: Settings → About → Diagnostics → the year review preview → its last
  page: the button closes the review and opens Ten's chat with "Составь мне план на январь";
  Ten's reply drafts budgets (and a goal when there is none, the reminder when it is off), each
  with its card; nothing is saved before Save. The message on Home cannot be seen before
  1 January (no date override): the button is its check.
- **"Не то"**: under the latest answer of Ten (not under a record drafted on the phone, not during
  the feedback talk); the sheet's four reasons, the preview with Ten's bold drawn, Send: the
  message arrives in Telegram with the reason, the question, Ten's words and the prompt version;
  the button then reads "Передано разработчику".

- **The ✕ in onboarding** (Settings → Diagnostics → reset onboarding, or a fresh install): the ✕
  on the currency, account and categories steps lands on Home with one account ("Карта", or the
  name typed) and the starting categories; a first expense saves at once. Run again with an
  account already there: no second account.

## Submission checklist

1. **CI green**, then a TestFlight build of 1.10.
2. **The phone checks above.**
3. **What's New** in 14 storefronts here, then `prepare-version --version 1.10 --build <N>`.
4. **App Review notes** (`review-notes --version 1.10 --apply`), then `prepare-review`; sending
   on the founder's word, with a manual release for 26.12.
5. **Ten's guide** (`server/assistant/src/prompt.ts`) once 1.10 is in the store: the plan button
   in the year review, the message of 1-5 January, "Не то".
