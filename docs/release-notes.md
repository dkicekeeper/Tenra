# Tenra 1.8.3: What's New and the checklist

Version 1.8.3 in the project since 2026-11-11 (the founder's call: a small update now; 1.9 is
kept for the update the featuring nomination promises in the last week of December,
[plan-growth.md](plan-growth.md) stage 4). 1.8.2 is in the store since 2026-11-10/11 (build 76;
its notes and checklist: [archive/release-notes-1.8.2.md](archive/release-notes-1.8.2.md)).
**Status 2026-11-12:** the changes below are in `main` (Tenra#160, Tenra#161, then Ten's forms,
state line, help with complaints, the entries and editing and deleting records, at f3900c7),
TestFlight build
86 is processed (from the cloud, `main` at 9708fca; 85 failed at signing and was never uploaded), the server with `POST /v1/feedback` and
prompt 2026-11-12.12 is deployed and the owner's Telegram chat is linked (`telegram-link`, a test line arrived 12.11), the What's New blocks for the 13 storefronts and en-GB are not
written, the phone checks are not done.

When the blocks are written: one `## <locale>` heading per storefront (en-US, ru, en-GB, de-DE,
es-ES, es-MX, fr-FR, fr-CA, tr, pt-BR, it, uk, ja, ko), which `prepare-version` (Actions → App
Store Connect, [asc.md](asc.md)) pastes into App Store Connect; en-GB (search in Kazakhstan)
carries ru's text. No em dashes (user rule). `prepare-version` refuses notes whose title names
another version.

## In this version (main since 2026-11-10)

- Ten opens the app's own forms: asked to add an account, a deposit, a loan or a category (or
  how to), it answers with a button that opens the form with what was said already filled in
  (the bank, the amount, the rate, the term), and with buttons to the lists of Finances, a
  goal, a debt, Settings, the backups and the Wallet guide. After build 77; needs the server
  with prompt 2026-11-12.3 or later (2026-11-12.4 is deployed).
- Ten knows how the app is set up for the person (the plan, the free accounts used, automatic
  capture, backups, the spending reminder, budgets), so its help is about them: "the weekly
  backup is on, but the copies stay on this phone". After build 78; same server.
- Ten helps with a complaint: after "Not really" in the feedback talk, once the words are with
  the developer, Ten tries to settle the problem itself (opens the form, checks the data, names
  the nearest thing Tenra has), then asks whether it helped. With cloud answers off it offers to
  help first. Needs the server with prompt 2026-11-12.4 (deployed 2026-11-12).
- Ten changes what is saved: "the freelance income on the 24th was 170 000, fix it" or "delete
  the Steam purchase" gets a card with the record as it is and as it becomes (or the records
  that go), saved or deleted with one tap and undone with another. Transfers and loan or deposit
  records stay in History. Needs the server with prompt 2026-11-12.5 (deployed 2026-11-12). In build 80.
- "Put everything from Glovo under Groceries": Ten moves all records of a merchant (up to 50)
  to another category with one card. In build 81.
- Ten changes a goal (name, target, deadline) and a debt (due date, note, settled) with a card
  that shows what it is and what it becomes. In build 82.
- "Put Spotify on hold": Ten pauses or resumes a subscription with a card. In build 83.
- "I paid the loan today": Ten's button opens the loan with its payment form already open.
  In build 84.
- Ten knows the terms of loans and deposits: the rate, the monthly payment and its day, the
  payments left, the interest accrued on a deposit. Needs the server with prompt 2026-11-12.7
  (deployed 2026-11-12). In build 81.
- "Find my subscriptions in the history": Ten looks through the last year for payments that
  repeat like a subscription and offers to add them. Needs the server with prompt 2026-11-13.1.
  Not in a build yet.
- Ten's home is one thing at a time: Ten, large, with the message it wrote first (or its
  greeting) under it; three chips over the field, "Record", "Ask" and "How to"; the chats behind
  a button at the top. In build 86 (build 84 had an earlier, busier arrangement).
- Settings › Assistant has "Ask Ten about the app", and Ten's home puts first the "how to"
  questions for what the person has not set up yet (automatic capture, a first budget, a backup
  in iCloud). After build 79.
- Ten's chat: the three typing dots are gone; while Ten works, the step it is on shimmers.
- Converting an account to a deposit from the account's own screen asks for Tenra Pro, as the
  accounts list already did.
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
   rating survey ("Нравится ли вам Tenra?") must not come up over the talk (build 77 showed it
   while the answer was being typed), and Apple's prompt comes only after Ten's thanks. The
   rating survey's "not really" opens the chat with "Что именно не понравилось…" at once.
   **App Privacy** in App Store Connect: updated by the founder on 2026-11-11 for a message to
   the developer (user content for app functionality, not linked to the person, no tracking).
8. Ten as a helper (build 79, cloud answers on): "Как открыть депозит в Halyk на 2 млн под
   14,5%?" answers with "Создать депозит"; the button opens the deposits list and the form
   opens over it by itself with the bank, the amount and the rate filled in (a free person gets
   the paywall first, then the form). The same for "добавь счёт Freedom в долларах", a loan and
   a category. "У меня включена резервная копия?" answers about this phone (automatic or not,
   iCloud or not, the last copy) with a button to the backups. While Ten works there are no
   three dots, only the shimmering step.
9. A complaint in the feedback talk (build 79): "Не очень", then "не понял, как завести
   депозит": Ten thanks, says it will look, and answers with the form's button; then the chips
   "Помогло" and "Не помогло"; either arrives in Telegram as the same words with "Ten helped"
   or "Ten did not help". The help spends no free answer. With cloud answers off: the thanks,
   then the chip "Помоги разобраться", which opens the consent screen and goes on after "Turn
   on". After "Нравится" nothing changes.
10. "Convert to deposit" in an account's "…" menu as a free person opens the paywall; after a
    purchase the conversion form opens.
11. Ten changes what is saved (build 80): "Вчерашний кофе был на 1 800, исправь" finds the
    record and shows a card with "Было" and "Станет"; "Сохранить" changes it in History, "Отмена"
    puts it back. "Удали вчерашний кофе" shows the record and "Удалить"; "Отмена" returns it
    with its subcategory. A transfer or a loan payment is refused with a button to History.
    Balances of the account move with the change and back with the undo.
12. Settings › Assistant, "Спросить Тэна о приложении" opens Ten with three how-to questions;
    Ten's home starts with the questions for what is not set up (automatic capture, a first
    budget, a backup in iCloud).
13. Build 81: "Перенеси всё из Glovo в Продукты" shows one card with the number of records and
    the records as they will be; "Сохранить" moves them, "Отмена" puts them back. "Какая ставка
    по кредиту и сколько платежей осталось?" and "Сколько процентов набежало по депозиту?" are
    answered with the app's own figures.

14. Ten's home (build 86): Ten is large; under it the card "Тэн пишет" when a message
    waits ("Разобрать" starts its chat), else one line of greeting; over the field the chips
    "Записать" (the keyboard comes up), "Спросить" and "Как сделать" (their questions replace the
    chips, "Назад" brings the three back, a question starts a chat); the bubble at the top right
    opens the chats, a long press deletes one; nothing is cut off on a small phone and in the
    largest text size. "Поставь Spotify на паузу" (build 83)
    shows the subscription and "Встанет на паузу"; "Отмена" resumes it. "Сегодня заплатил по
    кредиту" gives a button that opens the loan with its payment form already open.

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

1. **CI green**, then a TestFlight build (done: build 86 from 9708fca, 2026-11-13; CI green on
   225edd2, the last commit that touched the app).
2. **The phone checks above.**
3. **What's New** in this file, then `prepare-version --version 1.8.3 --build <N>`.
4. **One submission**: `asc.py prepare-review --version 1.8.3`; the founder sends it, or
   `--submit` on the founder's word.
