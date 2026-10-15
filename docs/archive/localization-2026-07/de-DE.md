# Tenra — План локализации: Немецкий (de-DE)

> Статус: черновик. Создан 2026-07-03. Рынок: Германия, Австрия, немецкоязычная Швейцария.
> Фаза 1, приоритет №1 (см. [README.md](README.md)).
> ⚠️ Все немецкие тексты в этом файле — AI-черновик и **обязательно проходят вычитку нейтивом**
> до сабмита (метаданные, скриншоты, голосовые ключевики — всё).

---

## 1. Обзор рынка — почему приоритет №1

- **Privacy-first аудитория.** Германия — самый чувствительный к приватности рынок Европы
  (наследие Datenschutz-культуры, GDPR-родина, устойчивое недоверие к банковским агрегаторам).
  Позиционирование Tenra «данные локально + iCloud, никакого доступа к банку, без рекламы»
  попадает в ядро запроса, а не в nice-to-have. Конкуренты с обязательной привязкой банка
  (Finanzguru, Outbank) регулярно ловят негатив именно за доступ к счёту.
- **Культура Haushaltsbuch.** «Домовая книга расходов» — устоявшаяся бытовая практика с
  собственным поисковым запросом. Категория «Haushaltsbuch App» живая и с понятным интентом —
  Tenra по сути и есть цифровой Haushaltsbuch с бюджетами.
- **Высокий ARPU.** Германия — топ-5 App Store по выручке; готовность платить за качественный
  софт выше среднего по Европе, особенно за приватность и отсутствие рекламы. Швейцария —
  ещё выше (учесть CHF-прайсинг).
- **Три витрины одним переводом.** de-DE покрывает DE + AT + de-CH (у Австрии и Швейцарии
  отдельные storefront-цены, но общая локаль метаданных).
- **Мультивалютность как бонус для CH/AT.** EUR/CHF-сценарии (приграничные работники,
  Konten in zwei Währungen) — реальный кейс, который закрывает фича №5.

---

## 2. ASO-ключевики

⚠️ Объёмы — экспертная оценка; **до сабмита валидировать через ASA Search Popularity**
(или ASO-инструмент с DE-данными) и пересобрать поле keywords по фактическим объёмам.

| Немецкий запрос | EN-эквивалент | Комментарий |
|---|---|---|
| Haushaltsbuch | household expense book | Главный локальный запрос категории; нет прямого EN-аналога — обязателен в Title |
| Haushaltsbuch App | household book app | Длинный хвост главного запроса |
| Ausgaben Tracker | expense tracker | Англицизм «Tracker» устоялся в DE-поиске |
| Budget Planer | budget planner | Высокий интент; «Planer» покрывается словом Finanzplaner в Subtitle |
| Finanzplaner | finance planner | Широкий, конкурентный |
| Geld sparen | save money | Широкий интент-запрос, хорош для description/промо |
| Abo verwalten | manage subscriptions | Растущий запрос; фича №2 (подписки) — прямое попадание |
| Ausgaben und Einnahmen | expenses and income | Классика жанра, средний объём |
| Finanzen im Griff | finances under control | Идиома-запрос; скорее для description |
| Kontoauszug importieren | import bank statement | Низкий объём, но нулевая конкуренция; наша фича №7 |
| Haushaltsrechner | household calculator | Смежный запрос, дешёвый трафик |
| Sparplan | savings plan | Смежный (инвест-коннотация) — тестировать осторожно |
| Geld verwalten | manage money | Широкий, средняя конкуренция |
| Budget App | budget app | Англицизм, высокий объём — «Budget» уже в Title |

---

## 3. Метаданные ASC (de-DE)

Переведено от референсных US/RU метаданных из README. Счётчики — фактические.

### Title (29/30)

```
Tenra: Haushaltsbuch & Budget
```

Начинается с `Tenra:`, дальше самый сильный локальный кейворд (Haushaltsbuch) + Budget
(транснациональный запрос). Зеркалит логику US-Title (`Tenra: Budget, Expense Tracker`).

### Subtitle (29/30)

```
Ausgaben, Abos & Finanzplaner
```

Покрывает: Ausgaben (expense tracker), Abos (подписки — фича №2), Finanzplaner
(+ по словоформе цепляет «Planer»). Зеркалит US-Subtitle (`Money Manager & Subscriptions`).

### Keywords (98/100)

```
geld,sparen,konto,finanzen,einnahmen,schulden,kredit,zinsen,gehalt,kosten,währung,tracker,sparplan
```

Без пробелов, без дублей слов из Title/Subtitle (haushaltsbuch, budget, ausgaben, abos,
finanzplaner — уже проиндексированы). Комбинации собираются автоматически:
«geld sparen», «geld verwalten» (verwalten вырезан по лимиту — вернуть, если research
покажет объём выше, чем у sparplan/zinsen).

### Promotional Text (153/170)

```
Ihre Finanzen, Ihre Daten: Tenra speichert alles lokal auf Ihrem iPhone – ohne Bankzugang, ohne Werbung. Budgets, Konten, Abos und Analysen in einer App.
```

### Description (1934 симв., лимит-цель 1500–2500)

Формальное «Sie» во всём тексте. Хук — приватность (главный дифференциатор рынка),
далее блоки фич в порядке позиционирования из README, затем Pro, футер.

```
Ihre Finanzen gehören Ihnen – und nur Ihnen. Tenra ist das private Haushaltsbuch für iPhone und iPad: Alle Daten bleiben lokal auf Ihrem Gerät, optional mit iCloud-Backup. Kein Bankzugang, keine Konto-Verknüpfung, keine Werbung, kein Verkauf Ihrer Daten.

BUDGETS DIREKT AUF DEM STARTBILDSCHIRM
• Monatliche Limits pro Kategorie
• Ausgaben und Restbudget auf einen Blick
• Sofort sehen, wo Sie über dem Plan liegen

ALLE FINANZEN AN EINEM ORT – OHNE BANKZUGANG
• Girokonten, Bargeld, Sparkonten
• Festgeld und Tagesgeld mit Zinsberechnung
• Kredite mit Tilgungsplan
• Abos im Überblick: Netflix, Spotify & Co.

ANALYSEN, DIE WEITERHELFEN
• Wohin fließt Ihr Geld? Kategorien, Trends, Monatsvergleich
• Saldo, Ausgaben und Netto-Cashflow pro Monat
• Top-Kategorien mit übersichtlicher Aufschlüsselung

FINANZ-SCORE
• Ihre finanzielle Gesundheit in einer Zahl
• Sparquote, Budgets und Notgroschen fließen in die Bewertung ein

MULTIWÄHRUNG MIT ECHTEN WECHSELKURSEN
• Konten in EUR, USD, CHF und über 150 weiteren Währungen
• Ein ehrlicher Gesamtwert in Ihrer Basiswährung

SPRACHEINGABE
• „12 Euro für Mittagessen ausgegeben“ – fertig
• Betrag, Kategorie und Datum werden automatisch erkannt

KONTOAUSZÜGE IMPORTIEREN
• PDF- und CSV-Import Ihrer Bankauszüge
• Automatische Erkennung und Zuordnung der Umsätze

TENRA PRO
Kostenlos enthalten: tägliche Ausgabenerfassung mit bis zu 3 Konten und allen Budgets. Tenra Pro erweitert die App um unbegrenzte Konten, Spracheingabe, PDF/CSV-Import, Festgeld und Kredite. Wählen Sie das Jahres-Abo mit 14 Tagen kostenloser Testphase – oder den einmaligen Lifetime-Kauf, ganz ohne Abo.

Datenschutz: Tenra benötigt kein Konto, keine Registrierung und keinen Zugriff auf Ihre Bank. Ihre Daten verlassen Ihr Gerät nur, wenn Sie das iCloud-Backup aktivieren.

Fragen oder Feedback? Wir freuen uns auf Ihre Nachricht: support@tenra.app
Datenschutzerklärung und Nutzungsbedingungen finden Sie in der App.
```

### What's New — шаблон

```
Danke, dass Sie Tenra nutzen!

Dieses Update enthält:
• [Neue Funktion in einem Satz]
• [Verbesserung in einem Satz]
• Fehlerbehebungen und Leistungsverbesserungen

Fehlt Ihnen etwas? Schreiben Sie uns: support@tenra.app
```

---

## 4. Скриншоты (8 фреймов, порядок залочен)

UI на немецком, суммы в **EUR** (формат: `1.234,56 €`). Для de-CH витрины скриншоты те же
(отдельный CHF-сет — только если метрики оправдают).

| # | Экран | Заголовок (DE) | Подзаголовок (DE) |
|---|---|---|---|
| 1 | Главная | Budget für jede Kategorie | Limits, Ausgaben und Restbudget – direkt auf dem Startbildschirm |
| 2 | Финансы | Alle Ihre Finanzen an einem Ort | Konten, Festgeld, Abos und Kredite – ohne Bankzugang |
| 3 | Аналитика | Sehen Sie, wohin Ihr Geld fließt | Saldo, Ausgaben und Netto-Cashflow pro Monat – auf einen Blick |
| 4 | Финансовый скор | Ihre finanzielle Gesundheit im Blick | Sparquote, Budgets und Notgroschen in einer verständlichen Zahl |
| 5 | Топ категория | Entdecken Sie Ihre größten Ausgaben | Ausgabenkategorien mit anschaulicher Monatsübersicht |
| 6 | История | Jede Buchung unter Kontrolle | Ausgaben, Einnahmen und Zinsen – in einem übersichtlichen Verlauf |
| 7 | Голос | Ausgaben einfach per Sprache erfassen | „12 Euro für Mittagessen“ – gesagt, gebucht |
| 8 | Мультивалютность | EUR, USD, CHF – ein ehrlicher Gesamtwert | Konten in mehreren Währungen, ein Gesamtsaldo in Ihrer Währung |

Примечание к №8: порядок валют изменён под рынок (EUR первым, CHF вместо KZT).

---

## 5. Адаптация фич

### 5.1 Голосовой ввод (L2: VoiceInputParser + Segmenter)

`SFSpeechRecognizer` locale: `de-DE` (покрывает и AT/CH-акценты; при жалобах — тест `de-AT`/`de-CH`).
Учесть: в немецком глагол-перфект уходит в конец фразы («Ich habe 12 Euro für Taxi **ausgegeben**») —
парсер должен искать ключевые глаголы по всей фразе, не только в начале.

**Глаголы/маркеры трат (`expenseKeywords`), ~20:**

`ausgegeben, gekauft, bezahlt, gezahlt, gekostet, abgebucht, bestellt, getankt, gebucht, geholt, ausgelegt, hingelegt, beglichen, überwiesen, gegönnt, erworben, verlängert, abonniert, draufgegangen, investiert`

**Глаголы/маркеры дохода (`incomeKeywords`), ~12:**

`bekommen, erhalten, verdient, eingenommen, gutgeschrieben, eingegangen, erstattet, zurückbekommen, Gehalt, Lohn, Bonus, Trinkgeld`

⚠️ `überwiesen` двусмысленно (перевёл кому-то = расход; «überwiesen bekommen» = доход) —
сегментировать по контексту «bekommen/erhalten» рядом, иначе трактовать как расход/перевод.

**Слова дат (`parseDate`):**

`heute, gestern, vorgestern, letzte Woche, letzten Monat, am Montag/Dienstag/Mittwoch/Donnerstag/Freitag/Samstag/Sonntag, vor drei Tagen, Anfang des Monats` + числовые форматы `am 12.06.`, `12. Juni`.

**Союзы-разделители (`VoiceInputSegmenter`), ~8:**

`und, dann, danach, außerdem, sowie, und noch, anschließend, plus, dazu`

**Ключевики категорий (~30), маппинг на категории (сверить имена с `CategoryIcon.swift`):**

| Немецкое слово | Категория |
|---|---|
| Taxi, Uber | Транспорт |
| Benzin, Sprit, getankt, Tankstelle | Транспорт/Авто |
| Bahn, Zug, Ticket, ÖPNV, Bus | Транспорт |
| Parken, Parkhaus | Транспорт/Авто |
| Lebensmittel, Einkauf, Supermarkt | Продукты |
| Rewe, Edeka, Aldi, Lidl, Penny, Netto | Продукты |
| Bäcker, Bäckerei | Продукты/Еда вне дома |
| Restaurant, Essen gehen, Mittagessen, Abendessen | Еда вне дома |
| Döner, Pizza, Imbiss | Еда вне дома |
| Café, Kaffee | Еда вне дома |
| Miete | Жильё |
| Strom, Gas, Nebenkosten, Heizung | Коммунальные |
| Handy, Handyvertrag, Internet | Связь |
| Apotheke, Arzt, Medikamente | Здоровье |
| Fitnessstudio, Gym | Спорт/Здоровье |
| Kino, Konzert | Развлечения |
| Kleidung, Schuhe | Одежда |
| Friseur | Красота |
| Drogerie, dm, Rossmann | Быт/Красота |
| Versicherung | Страхование/Финансы |
| Geschenk | Подарки |
| Urlaub, Reise, Hotel, Flug | Путешествия |
| Bücher | Образование/Досуг |
| Haustier, Tierarzt | Питомцы |
| Kita, Schule | Дети/Образование |

**Фонетические алиасы брендов для `ServiceLogo` (~10, популярные в DE):**

| Как распознаёт SFSpeechRecognizer | Канонический бренд |
|---|---|
| pay pal / peipal | PayPal |
| amazon prime / prime | Amazon Prime |
| netflix / netfliks | Netflix |
| spotify / spottify | Spotify |
| di azett en / dazn | DAZN |
| deutsche bahn / de be / DB | Deutsche Bahn |
| lieferando | Lieferando |
| zalando | Zalando |
| ikea / ikeja | IKEA |
| sky / skai | Sky |
| you tube / juhtjub | YouTube |
| whats app / wazapp | WhatsApp |

(Финальный список алиасов уточнить живыми тестами диктовки — L5.)

### 5.2 Импорт выписок (L3: StatementTextParser)

**Форматы рынка:** даты `DD.MM.YYYY` (также `DD.MM.YY`), числа `1.234,56`
(точка — разряды, запятая — десятичные), отрицательные суммы `-12,34` либо маркеры
`S`/`H` (Soll/Haben) в старых форматах Sparkasse. Кодировка старых CSV Sparkasse/ING
бывает ISO-8859-1, не UTF-8 — детектить.

**Топ-банки и типичные заголовки колонок:**

| Банк | Формат | Типичные заголовки |
|---|---|---|
| Sparkasse (CAMT-CSV) | CSV `;` | `Auftragskonto, Buchungstag, Valutadatum, Buchungstext, Verwendungszweck, Beguenstigter/Zahlungspflichtiger, IBAN, BIC, Betrag, Waehrung, Info` |
| DKB | CSV `;` | `Buchungsdatum, Wertstellung, Status, Zahlungspflichtige*r, Zahlungsempfänger*in, Verwendungszweck, Umsatztyp, Betrag (€)` |
| N26 | CSV `,` | `Datum, Empfänger, Kontonummer, Transaktionstyp, Verwendungszweck, Betrag (EUR)` (встречаются и EN-заголовки: `Date, Payee, Amount (EUR)`) |
| ING | CSV `;` | `Buchung, Valuta, Auftraggeber/Empfänger, Buchungstext, Verwendungszweck, Saldo, Währung, Betrag` |
| Deutsche Bank / Commerzbank | PDF/CSV | `Buchungstag, Wert, Umsatzart, Verwendungszweck, Soll, Haben, Umsatz in EUR` |
| Trade Republic | PDF | Секции `Kontoauszug`, колонки `Datum, Typ, Beschreibung, Zahlungseingang, Zahlungsausgang, Saldo` |

**Ключевые слова заголовков для `StatementTextParser`** (аналог «ТРАНЗАКЦИИ ПО СЧЕТУ»):
`Kontoauszug, Umsatzübersicht, Umsätze, Buchungstag, Buchungsdatum, Wertstellung, Valuta, Verwendungszweck, Buchungstext, Auftraggeber, Empfänger, Begünstigter, Zahlungspflichtiger, Betrag, Umsatz, Saldo, Soll, Haben, Währung, IBAN, BIC`.

Задача L3: собрать 3–5 реальных образцов PDF/CSV (Sparkasse, DKB, N26, ING + один из
Deutsche Bank/Commerzbank; Trade Republic — стретч) и покрыть тестами парсинга.

### 5.3 CSV-маппинг типов (`CSVColumnMapping`)

| Немецкое значение | Тип |
|---|---|
| Ausgabe, Lastschrift, Kartenzahlung, Soll, Abbuchung | expense |
| Einnahme, Gutschrift, Eingang, Haben, Lohn/Gehalt | income |
| Überweisung, Umbuchung, Dauerauftrag (между своими счетами) | transfer |

⚠️ `Überweisung` в банковских CSV чаще значит «исходящий платёж» (expense), а не перевод
между своими счетами — маппить в transfer только при распознанных обоих счетах, иначе expense.

---

## 6. Цены (DE / AT / CH)

Якорь из README: ≈ $3/мес, $10/год, $24 lifetime. Для немецкого рынка рекомендую **выше якоря**:

| Тир | Рекомендация DE/AT | Рекомендация CH | Обоснование |
|---|---|---|---|
| Месяц | **2,99 €** | 3.00 CHF | Психологический порог «до 3 €»; ровно на уровне якоря — месяц оставляем дешёвым входом |
| Год (14-дн триал) | **17,99–19,99 €** (старт: 19,99 €) | 20.00 CHF | +80–100% к якорю: DE-аудитория платит за privacy и отсутствие рекламы; конкуренты с банк-привязкой стоят 30–75 €/год — мы всё ещё «дёшево» |
| Lifetime | **39,99 €** | 45.00 CHF | +65% к якорю; главный тир для рынка — немецкий скептицизм к подпискам делает lifetime самым конверсионным оффером (см. §7) |

- Соотношение год/lifetime ≈ 1:2 — lifetime окупается за 2 года, выглядит честно.
- Задавать **отдельные price points на витрину** (DE/AT в EUR, CH в CHF), не автоконвертацию.
- Founding-grandfathering из PremiumConfig действует как есть — DE-запуск его не касается.
- Через 6–8 недель после запуска — сверка trial→paid по ASC/RevenueCat; если конверсия
  просядет, тестировать 17,99 € за год раньше, чем трогать lifetime.

---

## 7. Культурные заметки

- **Sie, не du.** Для финансового приложения — строго формальное «Sie» в UI, метаданных,
  paywall и поддержке. «Du» в финтехе позволяют себе необанки для молодёжи (N26), но для
  приложения про приватность и контроль денег «Sie» сигнализирует серьёзность. Единообразно везде.
- **Числа и валюта.** Десятичный разделитель — запятая, разряды — точка: `1.234,56 €`.
  Символ € — после суммы с пробелом (де-факто стандарт DE; система через `Locale` сделает
  правильно — не хардкодить). Даты: `DD.MM.YYYY`.
- **Плюрализация.** de = категории `one/other` в `Localizable.stringsdict` (2 plural-ключа).
  Проще, чем ru (one/few/many/other) — но проверить формулировки для 0: «0 Buchungen» (other).
- **Скептицизм к подпискам.** Abo-Falle («подписочная ловушка») — устойчивый негативный мем;
  немецкое законодательство даже требует «кнопку отмены» у подписок. Выводы: (1) на paywall
  в RevenueCat **показывать lifetime заметно**, не прятать за подпиской; (2) явно писать
  «jederzeit kündbar» у подписки и «einmaliger Kauf, kein Abo» у lifetime; (3) 14-дневный
  триал подписи «kostenlos testen, erst danach wird abgebucht».
- **Приватность — доказывать, не декларировать.** Явно писать «kein Bankzugang», «Daten
  bleiben auf dem Gerät». App Privacy labels в ASC должны соответствовать (никаких
  data-linked-to-you сюрпризов) — DE-пользователи их реально читают.
- **Anglizismen — умеренно.** Tracker, App, Backup — ок (устоялись); остальное — по-немецки.
  «Cashflow» в финконтексте допустим.

---

## 8. Чек-лист запуска de-DE

- [ ] **L1. UI-перевод**: `Localizable.strings` (1347 ключей) + `Localizable.stringsdict`
      (2 plural-ключа, категории one/other). AI-черновик → `plutil -lint` → diff-паритет ключей.
- [ ] **L1. Нейтив-вычитка** всего UI + метаданных этого файла (единый глоссарий: Sie-форма,
      Buchung vs Transaktion, Konto vs Account — зафиксировать термины до вычитки).
- [ ] **L2. Голос**: expenseKeywords/incomeKeywords/parseDate/сегментер/категорийные ключевики
      из §5.1 → `VoiceInputParser`; locale `de-DE` в `SFSpeechRecognizer`; алиасы брендов в
      `ServiceLogo`; 10–15 тестовых фраз (суммы с запятой! «zwölf Euro fünfzig»).
- [ ] **L3. Выписки**: образцы Sparkasse/DKB/N26/ING (+DB или Commerzbank), заголовки из §5.2
      в `StatementTextParser`, `CSVColumnMapping` из §5.3, числа `1.234,56`, даты `DD.MM.YYYY`,
      кодировка ISO-8859-1 — всё под тестами.
- [ ] **L4. Скриншоты**: 8 фреймов из §4, UI на немецком, суммы в EUR.
- [ ] **L4. Метаданные ASC**: Title/Subtitle/Keywords/Promo/Description из §3 — **после**
      валидации ключевиков через ASA Search Popularity.
- [ ] **L4. Цены**: price points из §6 на витринах DE/AT/CH (не автоконвертация).
- [ ] **L4. RevenueCat paywall**: немецкие тексты оффера, lifetime заметно, «jederzeit kündbar»,
      футер Terms/Privacy (App Review 3.1.2(c)).
- [ ] **L5. Тест в локали**: Scheme → App Language = German, прогон ключевых экранов
      (длинные немецкие слова ломают лейауты — проверить Zeilenumbruch на карточках и кнопках).
- [ ] **L5. Финальный native review** чек-лист перед сабмитом.

---

**Последнее обновление**: 2026-07-03
