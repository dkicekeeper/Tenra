# Tenra 1.8.3: What's New and the checklist

Version 1.8.3 in the project since 2026-11-11 (the founder's call: a small update now; 1.9 is
kept for the update the featuring nomination promises in the last week of December,
[plan-growth.md](plan-growth.md) stage 4). 1.8.2 is in the store since 2026-11-10/11 (build 76;
its notes and checklist: [archive/release-notes-1.8.2.md](archive/release-notes-1.8.2.md)).
**Status 2026-11-11:** the changes below are in `main` (Tenra#160), TestFlight build 77 is
processed (from the cloud, `main` at a1e3b00), the server with `POST /v1/feedback` and the
Telegram secrets is deployed, the What's New blocks for the 13 storefronts and en-GB are not
written, the phone checks are not done.

When the blocks are written: one `## <locale>` heading per storefront (en-US, ru, en-GB, de-DE,
es-ES, es-MX, fr-FR, fr-CA, tr, pt-BR, it, uk, ja, ko), which `prepare-version` (Actions → App
Store Connect, [asc.md](asc.md)) pastes into App Store Connect; en-GB (search in Kazakhstan)
carries ru's text. No em dashes (user rule). `prepare-version` refuses notes whose title names
another version.

## In this version (main since 2026-11-10)

- A gate's paywall can come from its own RevenueCat placement (the identifier is the gate's
  `paywall_source`, [promotion-plan.md](promotion-plan.md) §2): no visible change until
  placements are set up in the dashboard.
- Settings › Assistant: turning cloud answers on shows the same consent screen as the chat's
  first question (App Review 5.1.2(i)); before, the switch turned the cloud on without it.
- Ten in Russia and Belarus (no cloud there): the first question gets Ten's message once,
  questions not answered here, expenses recorded as usual with an example; after that Ten offers
  no questions, the field asks for an expense, "Ask Ten" is gone from the screens, and a question
  typed anyway does not go to the server. Checked again a week later.
- Ten's privacy: a fact Ten forgot leaves the chats that mention it (they can still be read; a
  question from one starts a new chat, "Ten forgot something from this chat"); expenses typed
  before cloud answers were allowed are never described to the AI later.
- The evening reminder: a transfer between your own banks merged when Tenra opens no longer
  counts as recording that day (it keeps the expense's creation time); the next day's line about
  yesterday's category survives a time-zone change.
- The evening reminder: no banner while Tenra is open at its time; "Remind me" with
  notifications already off for Tenra opens Tenra's page in iOS Settings (before, the tap did
  nothing visible).
- Fixes nobody should notice (release audit 1.6 races): a chat deleted while its reply is
  written stays deleted, and two saves of a chat or a fact keep one copy; a goal, a debt or an
  asset added right after launch no longer vanishes until the next one; "New chat" while Ten
  drafts a typed expense keeps the expense in its chat, and a message sent then stays in the
  field. Voice input lost an audio silence detector it never used (auto-stop is the 5-second
  pause, as before).

- Feedback through Ten (in `main` since 2026-11-11): Ten asks on Home "How do you like
  Tenra?" from the third day with five entries, then every 45 days while the person records.
  "Write" opens Ten's chat, where Ten asks and two chips answer ("I like it", "Not really"); Ten
  then asks what else to add, or what went wrong and how to fix it, and the person's words go to
  the developer, not to the AI. The rating survey's "not really" opens the same talk (it opened an
  e-mail). "I like it" asks Apple for the rating prompt after sending. Needs the server with
  `POST /v1/feedback` deployed first (Actions → Assistant server → deploy), and the privacy
  policy's line (on the site once merged).

Not for the user's notes, already live on Ten's server (no release needed): free users' share
of the day (900 of 1 200 calls) with 300 kept for Pro and trials, a call the model never
started is given back, a 5-second RevenueCat timeout, and the model stops when the app leaves
mid-answer.

**On the phone before this version goes out** (from the PRs' test plans, Tenra#150, #151, #153):
1. The paywall opens from every gate as before (no placements set up yet).
2. Settings › Assistant: switching cloud answers on shows the consent screen; off is immediate.
3. "Remind me" on Ten's offer with notifications off for Tenra opens iOS Settings; at the
   reminder's time with Tenra open, no banner.
4. With a VPN to Russia: the first question gets Ten's one message, then no ready-made
   questions, the field reads "Запишите трату, например «кофе 1500»", "Спросить Ten" is gone from
   the screens' menus, and "кофе 1500" is recorded.
5. Forget a fact Ten used in a chat (What Ten knows about me): that chat shows "Тэн забыл
   кое-что из этого чата", and a question from it opens a new chat; "Forget all" marks every
   chat in the history.
6. Two own banks' pushes merged into a transfer the next morning: that day's evening reminder
   still comes if nothing else was recorded.
7. Feedback through Ten: Ten's message "Как вам Tenra?" on Home (a phone with five entries,
   installed three days ago or more), "Написать" opens Ten's chat with Ten's question and the
   chips "Нравится" and "Не очень" over the field; a chip becomes your message, Ten asks the next
   question after a moment; your answer shows "Спасибо! Передал разработчику…", the Home message
   leaves, and the message arrives in Telegram; after "Нравится" Apple's rating prompt may follow;
   with no network Ten says "Не получилось отправить" and the next message is tried again. The
   rating survey's "not really" opens the chat with "Что именно не понравилось…" at once.
   **App Privacy** in App Store Connect: updated by the founder on 2026-11-11 for a message to
   the developer (user content for app functionality, not linked to the person, no tracking).

**On the phone, left from the versions already in the store** (not marked done before 1.8.2 went
out; the store build is the one to check):

1. **1.8.2** (in the store, build 76): a fresh install as a free person reaches the paywall
   after the last onboarding step, ✕ lands on Home with the account and categories saved; after a
   purchase or restore too. Analytics' paywall appears after the 3rd entry, not on the day of the
   onboarding offer. With real bank pushes: a subscription's charge lands on its planned charge
   (one transaction, the bank's amount and date) or asks "Looks like X" in To review; a transfer
   from one of your banks to another becomes one transfer (asked in To review when only the
   amount and time match), "Not a transfer" puts both back; Transfer and top-up list no loans.
2. **Carried over from 1.8.1** (the Simulator covered the rest,
   [archive/release-notes-1.8.1.md](archive/release-notes-1.8.1.md) item 2): the evening push at the
   set time on a day with nothing recorded and none after an entry (manual, Ten's draft, Apple Pay
   capture); a tap opens Ten; VoiceOver reads amounts in "1’234.56" and "1.234,56"; the widget
   shows a chosen format.
3. **Actions** (1.8.2): long press a deposit, a loan and a
   subscription on their lists and open their menus: "Изменить" first, "Удалить" last; delete an
   account from its own screen (both choices), a loan (both choices) and a transaction (alert, not
   a sheet); the transaction menu of a recurring payment shows "Прекратить повторение".
   "Спросить Ten" on an account, a deposit, a loan and a subscription opens a new empty chat with
   two questions over the field; the previous chat is in the home's list; a question tapped goes
   (the consent sheet first on a fresh install).

## Submission checklist

1. **CI green**, then a TestFlight build (done: build 77 from a1e3b00, 2026-11-11; CI green on
   cf089ea, the branch's head before the merge).
2. **The phone checks above.**
3. **What's New** in this file, then `prepare-version --version 1.8.3 --build <N>`.
4. **One submission**: `asc.py prepare-review --version 1.8.3`; the founder sends it, or
   `--submit` on the founder's word.
