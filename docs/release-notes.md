# Tenra, next version: What's New (ASC, 13 storefront locales and en-GB)

Version number not set yet (the owner's call). `prepare-version` (Actions → App Store Connect,
[asc.md](asc.md)) pastes each block into App Store Connect → the version → the locale → "What's
New in This Version"; en-GB (search in Kazakhstan) carries ru's text. No em dashes (user rule).
Names of screens as the app shows them (`settings.title`, `settings.spendingReminder.title`).

New since 1.8 (in the store since 2026-11-04):
- Ten's evening spending reminder ([plan-spending-reminder.md](plan-spending-reminder.md)):
  on days with nothing recorded, rarer after silence, a goodbye on day 10, no amounts; offered
  after the first entry on Home or in Ten's chat; Settings › Spending reminder; free.

## en-US

```
What's new in Tenra:
• Ten now reminds you in the evening on days with nothing logged: a short, light note that never shows an amount. If you don’t drop by, Ten writes less often and then lets you be. Turn it on when Ten asks after your first expense, or in Settings › Spending reminder.
```

## ru

```
Что нового в Tenra:
• Тэн напоминает вечером в дни, когда ничего не записано: коротко, легко и без сумм. Если вы не заглядываете, он пишет реже, а потом не беспокоит. Включите, когда Тэн спросит после первой траты, или в Настройках › Напоминание о тратах.
```

## en-GB

```
Что нового в Tenra:
• Тэн напоминает вечером в дни, когда ничего не записано: коротко, легко и без сумм. Если вы не заглядываете, он пишет реже, а потом не беспокоит. Включите, когда Тэн спросит после первой траты, или в Настройках › Напоминание о тратах.
```

## de-DE

```
Neu in Tenra:
• Ten erinnert Sie abends an Tagen ohne Einträge: kurz, locker und ohne Beträge. Schauen Sie nicht vorbei, meldet sich Ten seltener und lässt Sie dann in Ruhe. Einschalten, wenn Ten nach Ihrer ersten Ausgabe fragt, oder in Einstellungen › Ausgaben-Erinnerung.
```

## es-ES

```
Novedades de Tenra:
• Ten te recuerda por la noche los días sin registros: breve, ligero y sin importes. Si no pasas por aquí, Ten escribe menos y luego te deja tranquilo. Actívalo cuando Ten te lo pregunte tras tu primer gasto, o en Ajustes › Recordatorio de gastos.
```

## es-MX

```
Novedades de Tenra:
• Ten te recuerda por la noche los días sin registros: breve, ligero y sin importes. Si no pasas por aquí, Ten escribe menos y luego te deja tranquilo. Actívalo cuando Ten te lo pregunte tras tu primer gasto, o en Ajustes › Recordatorio de gastos.
```

## fr-FR

```
Nouveautés de Tenra :
• Ten vous le rappelle le soir les jours sans saisie : bref, léger et sans montants. Si vous ne passez pas, Ten écrit moins souvent, puis vous laisse tranquille. Activez-le quand Ten vous le propose après votre première dépense, ou dans Réglages › Rappel des dépenses.
```

## fr-CA

```
Nouveautés de Tenra :
• Ten vous le rappelle le soir les jours sans saisie : bref, léger et sans montants. Si vous ne passez pas, Ten écrit moins souvent, puis vous laisse tranquille. Activez-le quand Ten vous le propose après votre première dépense, ou dans Réglages › Rappel des dépenses.
```

## tr

```
Tenra'da yenilikler:
• Ten, hiçbir şey yazılmayan günlerde akşam kısa ve hafif bir hatırlatma gönderir, tutar göstermeden. Uğramazsan daha seyrek yazar, sonra rahat bırakır. İlk harcamandan sonra Ten sorduğunda ya da Ayarlar › Harcama hatırlatıcısı bölümünden aç.
```

## pt-BR

```
Novidades do Tenra:
• Ten lembra você à noite nos dias sem registros: curto, leve e sem valores. Se você não aparecer, Ten escreve menos e depois deixa você em paz. Ative quando Ten perguntar depois do seu primeiro gasto, ou em Ajustes › Lembrete de gastos.
```

## it

```
Novità di Tenra:
• Ten ti ricorda la sera nei giorni senza voci: breve, leggero e senza importi. Se non passi, Ten scrive meno spesso e poi ti lascia in pace. Attivalo quando Ten te lo chiede dopo la prima spesa, o in Impostazioni › Promemoria delle spese.
```

## uk

```
Що нового в Tenra:
• Тен нагадує ввечері в дні, коли нічого не записано: коротко, легко й без сум. Якщо ви не заглядаєте, він пише рідше, а потім не турбує. Увімкніть, коли Тен запитає після першої витрати, або в Налаштуваннях › Нагадування про витрати.
```

## ja

```
Tenra の新機能：
• 記録のない日の夜に、テンが短くお知らせします。金額は表示しません。しばらく開かないと、お知らせは少なくなり、やがて止まります。最初の支出のあとにテンが尋ねたとき、または 設定 › 支出のリマインダー でオンにできます。
```

## ko

```
Tenra의 새로운 기능:
• 기록이 없는 날 저녁에 텐이 짧게 알려 드려요. 금액은 보여 주지 않아요. 앱을 열지 않으시면 알림이 줄다가 멈춰요. 첫 지출 뒤에 텐이 물어볼 때, 또는 설정 › 지출 알림에서 켤 수 있어요.
```

## Submission checklist

1. **CI green**, then a TestFlight build from `main` (Actions → TestFlight, [asc.md](asc.md)).
2. **Device check**: Ten's offer after the first expense on Home and after a draft saved in
   Ten's chat; "Remind me" shows the system prompt; the push at the set time on a day with
   nothing recorded, none after an entry (a manual one, Ten's draft, an Apple Pay capture); a
   tap opens Ten; Settings › Spending reminder switches it and moves the time.
   Refuse the system prompt from quiet (provisional) notifications and check iOS Settings: if
   Tenra stays provisional, reminders arrive quietly while the attribute says `denied`.
3. **The store build**: `prepare-version --version X --build N`.
4. **What's New**: this file (`prepare-version`), en-GB included.
5. **App Privacy** (founder, in App Store Connect; not in the API): the RevenueCat attribute
   `spending_reminder` (on, off, declined, denied) is Product Interaction, used for analytics,
   not linked to the user's identity, not for tracking. Update the answers before sending.
6. **One submission**: `asc.py prepare-review --version X`; the founder sends it.
