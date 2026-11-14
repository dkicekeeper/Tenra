# The next version: What's New and the checklist

1.8.3 is in the store since 2026-11-13/14 (build 90; its notes:
[archive/release-notes-1.8.3.md](archive/release-notes-1.8.3.md)). `main` already carries what is
under "In the next version" below (the server with prompt 2026-11-14.4 is deployed). **The next version has no number yet**: the project still says 1.8.3, and a build under a
released version is refused by App Store Connect, so the number is raised (the founder's call:
1.8.4 for a small update, 1.9 is kept for the update the featuring nomination promises in the last
week of December, [plan-growth.md](plan-growth.md) stage 4) before the next TestFlight build.

When the blocks are written: one `## <locale>` heading per storefront (en-US, ru, en-GB, de-DE,
es-ES, es-MX, fr-FR, fr-CA, tr, pt-BR, it, uk, ja, ko), which `prepare-version` (Actions → App
Store Connect, [asc.md](asc.md)) pastes into App Store Connect; en-GB (search in Kazakhstan)
carries ru's text. No em dashes (user rule). `prepare-version` refuses notes whose title names
another version.

## Phone checks

The checks 1.8.3 shipped with were done by the founder on 2026-11-14: all fine (the list is in
[archive/release-notes-1.8.3.md](archive/release-notes-1.8.3.md)). Those of the next version go
here.

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

## Submission checklist

1. **CI green**, then a TestFlight build under the new version number.
2. **The phone checks above**, for what the version adds.
3. **What's New** in this file, then `prepare-version --version <X> --build <N>`.
4. **App Review notes**, in English: `asc.py review-notes --version <X> --apply` (the block of
   1.8.3 is in its archived notes; add what the version brings).
5. **One submission**: `asc.py prepare-review --version <X>`; the founder sends it, or `--submit`
   on the founder's word.
