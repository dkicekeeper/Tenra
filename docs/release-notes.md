# The next version: What's New and the checklist

1.8.3 is in the store since 2026-11-13/14 (build 90; its notes:
[archive/release-notes-1.8.3.md](archive/release-notes-1.8.3.md)). `main` already carries what is
under "In the next version" below (the server with prompt 2026-11-14.4 is deployed). **The next
version is 1.8.4** (the project says 1.8.4 since 2026-11-23; the founder's call: 1.8.4 for a small
update, 1.9 is kept for the update the featuring nomination promises in the last week of December,
[plan-growth.md](plan-growth.md) stage 4). What's New blocks are not written yet.

When the blocks are written: one `## <locale>` heading per storefront (en-US, ru, en-GB, de-DE,
es-ES, es-MX, fr-FR, fr-CA, tr, pt-BR, it, uk, ja, ko), which `prepare-version` (Actions → App
Store Connect, [asc.md](asc.md)) pastes into App Store Connect; en-GB (search in Kazakhstan)
carries ru's text. No em dashes (user rule). `prepare-version` refuses notes whose title names
another version.

## Phone checks

The checks 1.8.3 shipped with were done by the founder on 2026-11-14: all fine (the list is in
[archive/release-notes-1.8.3.md](archive/release-notes-1.8.3.md)).

- **Trial reminder** (sandbox account, annual with the 14-day trial): after the purchase on the
  paywall iOS asks for notifications (when Tenra had only quiet ones or none); Settings → Tenra
  Pro shows the trial. The reminder is pending for 10:00 two calendar days before the trial's
  last day (sandbox trials last minutes, so check the pending request in Xcode's console or
  with a debugger, not by waiting). Turning renewal off in the sandbox subscriptions and
  reopening Tenra replaces its words with "Продление выключено, списаний не будет…".
- **Ten's question after renewal is off**: with the same sandbox trial turned off, Home shows
  Ten's "Продление Pro выключено"; "Написать" opens the talk with three chips ("Дорого", "Хватает
  бесплатного", "Не хочу подписку"). A chip arrives in Telegram at once with the source `trial`
  (server deployed with `trial` among the sources), Ten asks its follow-up, and the words typed
  next arrive too; the message leaves Home after the first send. "Не хочу подписку" mentions the
  lifetime purchase on the same screen.

## In the next version

- Ten sends words to the developer from its chat (the owner's report 2026-11-14: asked to pass
  on that the budgets are good, Ten promised to, then said it cannot). "Передай разработчику…"
  gives a card with the words and "Отправить"; after it the card says "Отправлено
  разработчику" and the words arrive in Telegram with the source `chat`. "Хочу оставить отзыв"
  after praise also gives a button to the App Store's review page. Needs the server with prompt
  2026-11-14.3; on 1.8.3 the same server only stops Ten from promising to pass anything on.
- Ten does what is asked of it directly: "Напомни завтра утром заплатить за интернет" gives a
  card with the words and the time, "Сохранить" asks for notifications once and the reminder
  comes at 09:00 ("Отмена" removes it); "Включи вечернее напоминание на 21:00" switches the
  Settings reminder; "Переименуй счёт Kaspi Gold в Основная карта" and "Не учитывай Freedom в
  общем балансе" change the account (Home shows it, "Отмена" puts it back). "Как отменить Tenra
  Pro" gives a button to the Apple Account's subscriptions. "Поменяй валюту на доллары",
  "Отправь маме 20 000" and "Удали счёт" get the way to do it, never a claim that it is done.

- A subscription billed by Apple (the owner's report 2026-11-15: Roblox 6 060 on the 13th, charged
  as APPLE.COM/BILL, stayed a separate expense next to the planned charge): with APPLE.COM/BILL
  already linked to another subscription, To review now asks "Похоже на Roblox" with "Объединить";
  after one merge by hand each next charge of that amount merges on its own, and the other Apple
  subscriptions keep merging too.

- Tenra Pro's free trial (docs/promotion-plan.md §6, 2026-11-23: all five trials of November
  were turned off, four on the second day): a notification two days before the trial ends says
  what happens next (the yearly subscription and its price, or that nothing is charged with
  renewal off) and how to cancel; after a trial starts on the paywall Tenra asks for
  notifications so it comes as a banner. With renewal off, Ten asks on Home what did not suit
  (three chips and the words after them, to the developer with the source `trial`). The paywall
  and Apple's retention message promise this reminder: publish them with 1.8.4.

## Submission checklist

1. **CI green**, then a TestFlight build under the new version number.
2. **The phone checks above**, for what the version adds.
3. **What's New** in this file, then `prepare-version --version <X> --build <N>`.
4. **App Review notes**, in English: `asc.py review-notes --version <X> --apply` (the block of
   1.8.3 is in its archived notes; add what the version brings).
5. **One submission**: `asc.py prepare-review --version <X>`; the founder sends it, or `--submit`
   on the founder's word.
