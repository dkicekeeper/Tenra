# Tenra — Локализация: Итальянский (it)

> Статус: черновик. Приоритет №6, фаза 4 (см. [README.md](README.md)).
> Витрина ASC: `it`. Валюта рынка: EUR.
> ⚠️ Все итальянские тексты в этом файле — AI-черновик и требуют вычитки нейтивом
> перед сабмитом (метаданные, скриншоты, голосовые ключевики).

---

## 1. Обзор рынка

- **Размер**: средний рынок App Store в Европе — меньше Германии и Франции, но стабильно
  в топ-10 европейских по загрузкам. ~50 млн потенциальных iOS-пользователей, доля iPhone
  в Италии ниже, чем в UK/DE (~25–30%), но абсолютные числа приличные.
- **ARPU**: приличный — ниже DE/FR/UK, но заметно выше Восточной Европы и Турции.
  Итальянцы платят за подписки (стриминг, фитнес), но чувствительнее к цене,
  чем немцы — см. §6 (цены).
- **Культура наличных и учёта расходов**: Италия — одна из самых «наличных» экономик
  Западной Европы (несмотря на пост-COVID рост карт). Ручной учёт трат — привычная
  практика: семейные бюджеты, тетради расходов («il libro dei conti»). Это идеальный
  фит для Tenra: приложение с ручным вводом + голосом, без привязки банка, покрывает
  наличные траты, которые банковские агрегаторы не видят.
- **Аргумент приватности работает**: чувствительность к передаче финансовых данных
  третьим лицам высокая (GDPR-культура, недоверие к «приложениям, которые просят
  доступ к банку»). «Nessun accesso alla banca, dati sul tuo dispositivo» — сильный
  дифференциатор против open-banking конкурентов.
- **Конкуренты на витрине it**: iSpazio-класс локальных трекеров, Money Manager,
  Spendee, 1Money, YNAB (слабо локализован — наша возможность), Fatture in Cloud
  (бизнес-сегмент, не конкурент).

**Вывод**: рынок фазы 4 — не первый приоритет по объёму, но дешёвый вход (один
диалект, одна витрина, EUR уже поддержан) и хороший продуктовый фит.

---

## 2. ASO-ключевики

⚠️ Черновик на основе экспертной оценки. Перед финализацией метаданных — валидация
реальных объёмов через ASA Search Popularity (витрина IT) или ASO-инструмент
(AppTweak/Astro/Sensor Tower). Порядок в таблице — ожидаемая ценность.

| # | Ключевик | Перевод | Ожидаемый объём | Конкуренция | Куда |
|---|---|---|---|---|---|
| 1 | gestione spese | учёт расходов | высокий | средняя | Title |
| 2 | budget | бюджет | высокий | высокая | Title |
| 3 | finanze personali | личные финансы | средний | средняя | Keywords (finanze) |
| 4 | spese personali | личные расходы | средний | средняя | Title (spese) |
| 5 | risparmio / risparmi | накопления | средний | средняя | Subtitle |
| 6 | abbonamenti | подписки | средний | низкая | Subtitle |
| 7 | soldi | деньги | высокий | высокая | Subtitle |
| 8 | portafoglio | кошелёк | средний | средняя | Keywords |
| 9 | contabilità | учёт/бухгалтерия | средний | средняя | Keywords |
| 10 | entrate e uscite | доходы и расходы | средний | низкая | Keywords |
| 11 | stipendio | зарплата | средний | низкая | Keywords |
| 12 | bollette | счета/коммуналка | средний | низкая | Keywords |
| 13 | mutuo | ипотека/кредит | средний | низкая | Keywords |
| 14 | conto / conti | счёт | средний | средняя | Keywords |

Дополнительные хвосты (проверить объёмы): `tracker spese`, `spese familiari`,
`budget familiare`, `gestione soldi`, `salvadanaio` (копилка), `deposito`.

---

## 3. Метаданные ASC (витрина it)

### Title (29/30)
```
Tenra: Budget, Gestione Spese
```

### Subtitle (29/30)
```
Soldi, abbonamenti e risparmi
```

### Keywords (100/100)
```
finanze,portafoglio,conto,contabilità,entrate,uscite,stipendio,bollette,mutuo,debiti,valuta,deposito
```
Без дублей со словами Title/Subtitle (budget, gestione, spese, soldi, abbonamenti,
risparmi уже индексируются оттуда). `contabilità` и `à` — ASC принимает диакритику;
если инструмент валидации покажет, что `contabilita` без акцента ищут чаще, — заменить.

### Promotional Text (164/170)
```
Tutte le tue finanze in un'unica app: budget per categoria, conti, abbonamenti e depositi. Privato e senza collegare la banca. Prova Tenra Pro gratis per 14 giorni.
```

### Description (1709 символов — в целевом окне 1500–2500)
```
Tenra è il gestore di finanze personali privato per iPhone e iPad: budget, spese, conti, abbonamenti e depositi — tutto in un'unica app, senza collegare la banca.

BUDGET PER CATEGORIA
Imposta un limite mensile per ogni categoria e vedi subito, nella schermata principale, quanto hai speso e quanto ti resta. Niente sorprese a fine mese.

TUTTE LE TUE FINANZE IN UN POSTO
Conti correnti, contanti, carte, depositi con interessi, abbonamenti e prestiti con piano di rimborso. Il quadro completo, sempre a portata di mano.

SCOPRI DOVE VANNO I TUOI SOLDI
Statistiche chiare su saldo, spese e flusso netto del mese. Le categorie principali con ripartizione mensile, per capire davvero le tue abitudini.

PUNTEGGIO FINANZIARIO
Un unico voto che riassume la tua salute finanziaria: risparmi, rispetto dei budget e fondo di emergenza.

PIÙ VALUTE, UN TOTALE ONESTO
Conti in EUR, USD, CHF e altre valute con tassi di cambio reali: un unico totale nella tua valuta di base.

AGGIUNGI LE SPESE CON LA VOCE
Di' l'importo e la categoria — «15 euro di benzina» — e la spesa è registrata. Anche più operazioni in una sola frase.

IMPORTA GLI ESTRATTI CONTO
Importa PDF o CSV dalla tua banca: Tenra riconosce le operazioni e le assegna alle categorie giuste.

PRIVATO PER DAVVERO
I tuoi dati restano sul tuo dispositivo e nel tuo iCloud. Nessun accesso alla banca, nessuna pubblicità, nessuna vendita di dati.

TENRA PRO
La registrazione quotidiana delle spese e 3 conti sono gratis per sempre. Tenra Pro sblocca conti illimitati, inserimento vocale, importazione PDF/CSV, depositi e prestiti. Prova gratuita di 14 giorni sull'abbonamento annuale.

Scarica Tenra e prendi il controllo dei tuoi soldi — un budget alla volta.
```

### What's New (первый релиз локали, 162 символа)
```
Tenra ora parla italiano! Interfaccia completamente tradotta, inserimento vocale in italiano e importazione degli estratti conto delle principali banche italiane.
```

---

## 4. Подписи скриншотов (8 фреймов, порядок залочен)

UI на скриншотах — на итальянском, суммы в **EUR** (формат it: `1.234,56 €`).
Примеры сумм: бюджет 400 €, аренда 850 €, продукты 320 €.

| # | Экран | Заголовок | Подзаголовок |
|---|---|---|---|
| 1 | Главная | Un budget per ogni categoria | Limiti, spese e quanto ti resta nel mese — subito in home |
| 2 | Финансы | Tutte le tue finanze in un posto | Conti, depositi, abbonamenti e prestiti — senza collegare la banca |
| 3 | Аналитика | Scopri dove vanno i tuoi soldi | Saldo, spese e flusso netto del mese — a colpo d'occhio |
| 4 | Финансовый скор | La tua salute finanziaria, in un voto | Risparmi, budget e fondo di emergenza in un punteggio chiaro |
| 5 | Топ категория | Conosci le tue spese principali | Categorie di spesa con ripartizione mensile chiara |
| 6 | История | Ogni movimento sotto controllo | Spese, entrate e interessi sui depositi — in un'unica cronologia |
| 7 | Голос | Aggiungi le spese con la voce | Di' importo e categoria — la spesa è registrata |
| 8 | Мультивалютность | EUR, USD, CHF — un unico totale | Conti in valute diverse, un totale onesto in euro |

---

## 5. Адаптация фич

### 5.1 Голосовой ввод (VoiceInputParser + Segmenter)

`SFSpeechRecognizer` locale: `it-IT`. Contextual strings — локализованные названия
категорий и счетов пользователя.

**Глаголы трат (expenseKeywords, ~20):**

```
speso, spesi, spesa*, comprato, comprata, comprati, acquistato, pagato,
pagata, pagati, preso, presa, ordinato, costato, costata, sborsato,
prelevato, ricaricato, rinnovato, prenotato
```

⚠️ **Омонимия `spesa`**: «una spesa» = трата (маркер расхода), но «la spesa» /
«fare la spesa» = поход за продуктами (маркер категории Продукты). Правило парсера:
если `spesa` идёт в связке `fatto/fatta la spesa`, `spesa al supermercato`,
`spesa da <бренд ритейла>` — это категория Groceries; иначе — общий маркер расхода
без категории. Покрыть тестами обе ветки.

**Глаголы/маркеры дохода (incomeKeywords, ~10):**

```
ricevuto, incassato, guadagnato, accreditato, rimborsato, rimborso,
stipendio, pensione, bonus, venduto, vinto, entrata
```

**Даты (parseDate):**

| Итальянский | Значение |
|---|---|
| oggi | сегодня |
| ieri | вчера |
| l'altro ieri / ieri l'altro / avantieri | позавчера |
| lunedì … domenica (scorso/scorsa) | день недели (прошлый) |
| il 3 luglio / 3 luglio | явная дата |
| 03/07 / 03/07/2026 | числовой формат DD/MM |

**Союзы-разделители мультиоперационных фраз (VoiceInputSegmenter, ~8):**

```
e, ed, poi, e poi, inoltre, anche, più, dopo, oltre a, insieme a
```

Тест-фраза: «Ho speso 20 euro di benzina, poi 15 al ristorante e anche 5 di caffè»
→ 3 операции.

**Ключевики категорий (~30, маппинг):**

| Итальянский | Категория |
|---|---|
| taxi, tassì, uber | Такси |
| benzina, gasolio, carburante, distributore | Топливо |
| spesa*, supermercato, alimentari | Продукты |
| affitto | Аренда |
| bolletta, bollette | Коммунальные |
| luce, gas, acqua | Коммунальные |
| internet, telefono, cellulare | Связь |
| ristorante, pizzeria, pizza, trattoria | Кафе и рестораны |
| bar, caffè, colazione, aperitivo | Кафе |
| pranzo, cena | Еда вне дома |
| farmacia, medicine | Аптека |
| medico, dottore, visita | Здоровье |
| palestra, piscina | Спорт |
| cinema, concerto, teatro | Развлечения |
| vestiti, abbigliamento, scarpe | Одежда |
| regalo, regali | Подарки |
| parcheggio | Парковка |
| autostrada, pedaggio | Дорожные сборы |
| treno, autobus, metro, biglietto | Транспорт |
| volo, aereo | Путешествия |
| hotel, albergo | Путешествия |
| parrucchiere, barbiere, estetista | Красота |
| sigarette, tabacchi | Табак |
| libro, libri | Книги/образование |

**Фонетические алиасы брендов (ServiceLogo, ~10):**

| Распознаётся как | Бренд |
|---|---|
| da zon, dazone, dazn | DAZN |
| nètflix, netflix | Netflix |
| spotifai, spotify | Spotify |
| amazon, àmazon | Amazon |
| esselunga | Esselunga |
| conad | Conad |
| coop | Coop |
| enel, enel energia | Enel |
| tim | TIM |
| vodafone, vodafon | Vodafone |
| trenitalia | Trenitalia |
| eni, agip | Eni |

### 5.2 Импорт выписок (StatementTextParser)

**Топ-банки для образцов PDF (собрать 3–5 реальных выписок каждого):**

| Банк | Примечание |
|---|---|
| Intesa Sanpaolo | №1 по клиентам; estratto conto с колонками Data contabile / Data valuta |
| UniCredit | №2; форматы близки к Intesa |
| Poste Italiane / BancoPosta | огромная база «наличной» аудитории — наш сегмент |
| BPER Banca | топ-5, региональная база |
| FinecoBank | онлайн-банк, самые «чистые» CSV/PDF — хорош для первого парсера |
| Revolut | общий европейский формат, вероятно уже частично покрыт |

**Типичные заголовки колонок:**

```
Data, Data contabile, Data valuta, Descrizione, Descrizione operazioni,
Causale, Importo, Addebiti, Accrediti, Dare, Avere, Entrate, Uscite, Saldo
```

Ключевые слова секций: `ESTRATTO CONTO`, `LISTA MOVIMENTI`, `MOVIMENTI`,
`SALDO INIZIALE`, `SALDO FINALE`.

**Форматы:**
- Даты: `DD/MM/YYYY` (03/07/2026), встречается `DD.MM.YYYY` и `DD/MM/YY`.
- Числа: `1.234,56` — точка как разделитель тысяч, запятая как десятичный.
  Отрицательные суммы: `-1.234,56` или раздельные колонки Addebiti/Accrediti
  (Dare/Avere) — обе схемы покрыть тестами.
- Валюта: `€`, `EUR`; символ обычно после суммы (`1.234,56 €`).

**CSVColumnMapping — локальные значения типов:**

| Итальянский | Тип |
|---|---|
| spesa, uscita, addebito, pagamento | expense |
| entrata, accredito, reddito, incasso | income |
| bonifico, trasferimento, giroconto | transfer |

⚠️ `bonifico` в выписках — это и внешние платежи (аренда!), не только переводы между
своими счетами. Маппить в transfer только в CSV-колонке «тип операции»; в описаниях
операций (`Descrizione`) слово `bonifico` типом не считать.

### 5.3 Логотипы

`ServiceLogoRegistry`: добавить итальянские бренды — Esselunga, Conad, Coop, Carrefour IT,
Enel, Eni Plenitude, TIM, Vodafone IT, Iliad, WindTre, Trenitalia, Italo, DAZN, Sky Italia,
Poste Italiane, Intesa Sanpaolo, UniCredit, Fineco, Satispay.

---

## 6. Цены (EUR, витрина it)

Ориентир: чуть ниже прайс-поинтов DE/FR. Аргументы:
- ARPU и медианный доход в Италии ниже немецкого/французского (~15–20% по располагаемому
  доходу), чувствительность к цене подписок выше — итальянский рынок исторически
  «trial-heavy, конверсия ниже».
- Конкуренты на витрине it (Money Manager, 1Money, Spendee) сидят в диапазоне
  1,99–3,49 €/мес — вставать выше без узнаваемости бренда рискованно.
- Скидка относительно DE/FR — один шаг price point, не демпинг: сохраняем восприятие
  «премиального, но честного» продукта и пространство для промо.

| План | DE/FR (ориентир) | **Италия (рекомендация)** |
|---|---|---|
| Месяц | 2,99 € | **2,49 €** |
| Год (14-дней триал) | 12,99 € | **9,99 €** |
| Lifetime | 29,99 € | **24,99 €** |

Годовой = ~4 месячных → сильный якорь на годовую подписку (наша целевая SKU).
Настраивать отдельными price points на витрину IT в ASC, не автоконвертацией.
Paywall-тексты в RevenueCat dashboard перевести на итальянский (включая
обязательные ссылки Termini/Privacy — App Review 3.1.2(c)).

---

## 7. Культурные заметки

- **Обращение на «tu»**: в итальянских consumer-приложениях норма — «tu» (неформальное
  «ты»), включая банковские апы (Intesa, Satispay пишут «i tuoi soldi», «le tue spese»).
  «Lei» (формальное) в мобильном UI выглядит архаично. Все тексты выше — на «tu».
- **Плюрализация**: итальянский = категории `one/other` (как en). В `Localizable.stringsdict`
  два plural-ключа — прямой перенос без особых случаев (в отличие от ru/uk).
  Пример: `1 transazione` / `5 transazioni`.
- **Форматы**: десятичная запятая, точка для тысяч (`1.234,56 €`), символ € после суммы
  с пробелом, даты DD/MM/YYYY, неделя с понедельника — всё покрывается системной
  локалью `it_IT`, но проверить кастомные форматтеры (`Formatting.formatCurrencySmart`).
- **Лексика финансов**: «estratto conto» (выписка), «movimenti» (операции), «saldo»
  (баланс), «canone» (регулярный платёж/абонплата — встречается в выписках),
  «rata» (взнос по кредиту). Использовать в UI слова из банковского обихода,
  а не кальки с английского.
- Англицизмы `budget`, `app`, `smartphone` — полностью ассимилированы, переводить
  не нужно (никакого «bilancio preventivo»).

---

## 8. Чек-лист запуска (витрина it)

Порядок — по инженерным воркстримам README (L1–L5):

- [ ] **L1 UI**: перевод `Localizable.strings` (1347 ключей) + `Localizable.stringsdict`
      (one/other) → нейтив-вычитка → `plutil -lint` + diff-паритет ключей
- [ ] **L2 Голос**: expenseKeywords/incomeKeywords (§5.1) + parseDate (oggi/ieri/l'altro ieri)
      + союзы Segmenter + ключевики категорий с тестами на омонимию `spesa`
- [ ] **L2 Голос**: фонетические алиасы брендов в `ServiceLogo`
- [ ] **L3 Выписки**: образцы PDF Intesa Sanpaolo, UniCredit, BancoPosta, BPER, Fineco
      (+ Revolut) → заголовки/даты/числа в `StatementTextParser` → тесты
- [ ] **L3 CSV**: `CSVColumnMapping` — spesa/entrata/bonifico (§5.2), тест round-trip
- [ ] **Логотипы**: итальянские бренды в `ServiceLogoRegistry` (§5.3)
- [ ] **L4 ASO**: валидация ключевиков §2 реальными объёмами (ASA IT) → финализация
      Title/Subtitle/Keywords
- [ ] **L4 ASC**: метаданные §3 (после нейтив-ревью), 8 скриншотов с итальянским UI
      и суммами в EUR (§4)
- [ ] **L4 Цены**: price points §6 в ASC + перевод paywall в RevenueCat dashboard
- [ ] **L5 Верификация**: прогон приложения в `it` (Scheme → App Language), ключевые экраны
- [ ] **L5 Голос**: 10–15 тестовых фраз на итальянском (суммы, категории, даты, мультиоперации)
- [ ] **L5 Импорт**: прогон реальных выписок топ-банков
- [ ] **Native review**: финальный чек-лист нейтивом перед сабмитом
- [ ] Обновить статус в [README.md](README.md) после запуска

---

**Создан**: 2026-07-03. Черновик до нейтив-ревью.
