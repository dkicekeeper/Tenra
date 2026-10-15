# Tenra — Локализация: Французский (fr-FR + fr-CA)

> Статус: план/черновик. Приоритет №3, фаза 2 (см. [README.md](README.md)).
> Витрины ASC: **fr-FR** (Франция) и **fr-CA** (Канада). Базовый перевод — fr-FR;
> для fr-CA — секция минимальных отличий в конце файла.
> ⚠️ **Все французские тексты в этом файле — AI-черновик. Обязательна вычитка нейтивом
> (носителем из Франции; для fr-CA-отличий — из Квебека) до сабмита.**
> Подсчёт символов выполнен программно (len по Unicode-символам), но пересчитать в ASC перед сабмитом.

---

## 1. Обзор рынка

**Франция (fr-FR):**
- Один из топ-10 App Store рынков по выручке; **высокий ARPU**, платёжеспособная аудитория,
  доля iOS ~33–37% (выше в крупных городах и среди целевой аудитории 25–45).
- **Конкуренция умеренная.** Сильные локальные игроки завязаны на open banking / привязку счёта:
  Bankin', Linxo, Sumeria (ex-Lydia), приложения самих банков. В нише *ручного* трекинга без
  привязки банка — в основном глобальные приложения со слабой французской локализацией
  (Money Manager, Spendee, 1Money). Ниша «приватный трекер без банка» относительно свободна.
- **Приватность — главный рычаг позиционирования.** Во Франции сильная CNIL/RGPD-культура:
  пользователи настороженно относятся к передаче банковских доступов третьим лицам, а именно
  этого требуют Bankin'/Linxo. Сообщение «*aucune connexion bancaire, vos données restent sur
  votre appareil*» — прямой контраст с основными конкурентами, выносим его в promo-текст,
  описание и скриншот №2. Не заявлять формально «conforme RGPD» как маркетинговый бейдж —
  говорить фактами (локальные данные, нет рекламы, нет продажи данных).
- Высокая усталость от подписок → аргументы «essai gratuit 14 jours», «résiliable en un geste»
  и наличие **lifetime**-цены работают на конверсию (см. §7).

**Канада (fr-CA):**
- Квебек ~8,7 млн человек, высокая доля iOS, высокий ARPU. Отдельная витрина ASC почти
  бесплатна при готовом fr-FR: те же тексты с минимальными лексическими правками (§9).
- Юридический бонус: франкоязычная витрина снимает вопросы к продукту со стороны
  квебекских норм о французском языке (Loi 96 / OQLF) при маркетинге в провинции.

---

## 2. ASO-ключевики

⚠️ **Объёмы не валидированы.** Оценка экспертная; перед сабмитом прогнать через
ASA Search Popularity (витрина FR) или ASO-инструмент (AppTweak/Astro/Sensor Tower)
и пересобрать поле Keywords по реальным объёмам.

| # | Запрос (fr) | EN-эквивалент | Комментарий |
|---|---|---|---|
| 1 | gestion budget | budget management | Топ-запрос ниши; «budget» обязателен в Title |
| 2 | suivi des dépenses | expense tracking | Второй якорный запрос; в Title в виде «Suivi Dépenses» |
| 3 | dépenses | expenses | Высокочастотный корень; покрывается Title |
| 4 | budget familial | family budget | Стабильный запрос, семейная аудитория |
| 5 | économiser | to save money | Глагольный запрос; покрываем «économie» в Keywords |
| 6 | finances personnelles | personal finance | Категорийный запрос, средний объём |
| 7 | abonnements | subscriptions | Трекинг подписок — растущая ниша; в Subtitle |
| 8 | gestion argent | money management | Покрывается Subtitle («Gestion d'argent») |
| 9 | épargne | savings | Ключ в Keywords; связка со скором и депозитами |
| 10 | compte / comptes | account(s) | «Мультисчётность» — наш дифференциатор |
| 11 | portefeuille | wallet | Частотный, но размытый (крипто-кошельки) — мониторить релевантность |
| 12 | dépensier / tracker dépenses | spending tracker | Хвостовые вариации; закрываются комбинаторикой Title+Keywords |

Примечания:
- ASC индексирует комбинации слов из Title + Subtitle + Keywords — не дублировать корни между полями.
- Аксаны сохраняем (`épargne`, а не `epargne`): поиск ASC во французской витрине матчит
  диакритику, а пользователи вводят с аксанами (автокоррекция iOS их ставит). При валидации
  объёмов проверить пары с/без аксанов — если «epargne» показывает отдельный объём, решить по данным.

---

## 3. Метаданные ASC (fr-FR)

### Title (лимит 30)

```
Tenra : Budget, Suivi Dépenses
```
**30/30.** Покрывает запросы №1–3. Пробел перед «:» — французская типографика (§7);
ASC считает его как символ, учтено.

Запасной вариант, если нейтив сочтёт «Suivi Dépenses» (без «des») слишком телеграфным:
`Tenra : Budget et Dépenses` — **26/30**.

### Subtitle (лимит 30)

```
Gestion d'argent & abonnements
```
**30/30.** Покрывает «gestion argent» (№8) и «abonnements» (№7).

Запасной вариант: `Argent, abonnements, épargne` — **28/30** (тогда «épargne» убрать из Keywords).

### Keywords (лимит 100, без пробелов, без дублей с Title/Subtitle)

```
finances,compte,épargne,facture,dette,prêt,crédit,portefeuille,devise,salaire,livret,économie,cash
```
**98/100.** Проверено: нет пересечений с Title/Subtitle (budget, suivi, dépenses, gestion,
argent, abonnements — не повторяются). «livret» — специфично французский запрос
(Livret A — самый массовый сберегательный продукт), хорошо ложится на фичу депозитов.

### Promotional Text (лимит 170)

```
Budgets par catégorie, comptes, abonnements et crédits — sans connexion bancaire. Vos données restent sur votre appareil. Essai gratuit de 14 jours avec Tenra Pro.
```
**163/170.** Приватность — во втором предложении, сразу после фич: главный дифференциатор для рынка (§1).

### Description (цель 1500–2500; vouvoiement)

**2078 символов.**

```
Tenra est un gestionnaire de finances personnelles pensé pour une chose : vous redonner le contrôle de votre argent, sans jamais toucher à vos identifiants bancaires.

VOS BUDGETS, DÈS L'ÉCRAN D'ACCUEIL
Fixez une limite mensuelle pour chaque catégorie — courses, restaurants, transport — et voyez immédiatement ce qui a été dépensé et ce qu'il vous reste. Pas de menus cachés : l'essentiel est visible dès l'ouverture de l'app.

TOUTES VOS FINANCES AU MÊME ENDROIT
Comptes courants, livrets et dépôts (avec calcul des intérêts), abonnements, crédits avec échéancier de remboursement : tout est réuni dans une seule vue claire. Et tout cela sans connexion bancaire — vous saisissez ce que vous voulez, quand vous le voulez.

VOYEZ OÙ PART VOTRE ARGENT
Des analyses lisibles vous montrent votre solde, vos dépenses et votre flux net du mois. Le score financier résume votre santé financière en une seule note : épargne, respect des budgets, coussin de sécurité.

MULTIDEVISE, SANS TRICHER
Comptes en euros, en dollars ou en francs suisses ? Tenra convertit avec de vrais taux de change et affiche un total unique et fiable dans votre devise de référence.

AJOUTEZ UNE DÉPENSE EN PARLANT
Dites simplement « 12 euros de courses hier » — l'opération est enregistrée, catégorisée et datée. (Tenra Pro)

IMPORTEZ VOS RELEVÉS BANCAIRES
Importez un relevé PDF ou CSV : Tenra reconnaît les opérations, les montants et les dates, et vous propose un mappage par catégorie. (Tenra Pro)

VOTRE VIE PRIVÉE D'ABORD
Vos données restent sur votre appareil et dans votre iCloud. Aucun accès à votre banque, aucune publicité, aucune revente de données. Vos finances ne regardent que vous.

TENRA PRO
La version gratuite couvre le suivi quotidien avec 3 comptes. Tenra Pro débloque les comptes illimités, la saisie vocale, l'import PDF/CSV, les dépôts et les crédits. Essai gratuit de 14 jours, résiliable à tout moment en un geste. Une licence à vie est également disponible si vous préférez payer une seule fois.

Reprenez la main sur votre budget — téléchargez Tenra et commencez dès aujourd'hui.
```

### What's New (шаблон)

**221 символ.**

```
Merci d'utiliser Tenra ! Cette version apporte :
• des corrections de bugs et des améliorations de performance ;
• une interface plus fluide sur iOS 26.

Une question, une idée ? Écrivez-nous — nous lisons chaque message.
```

⚠️ Французский в среднем на 15–25% длиннее английского: при любой правке метаданных
пересчитывать лимиты, не переносить EN-структуру фраз «в лоб».

---

## 4. Подписи скриншотов (8 фреймов, порядок залочен)

UI на скриншотах — на французском, **суммы в EUR** (формат `1 234,56 €` — символ после суммы,
см. §5.2). Примеры сумм: бюджет `450 €`, баланс `12 480,50 €`.

| # | Экран | Заголовок | Подзаголовок |
|---|---|---|---|
| 1 | Главная | Un budget pour chaque catégorie | Limites, dépenses et solde du mois — dès l'écran d'accueil |
| 2 | Финансы | Toutes vos finances au même endroit | Comptes, dépôts, abonnements et crédits — sans connexion bancaire |
| 3 | Аналитика | Voyez où part votre argent | Solde, dépenses et flux net du mois — en un coup d'œil |
| 4 | Финансовый скор | Votre santé financière en une note | Épargne, budgets et coussin de sécurité — un score clair |
| 5 | Топ категория | Découvrez vos plus grosses dépenses | Catégories de dépenses avec répartition claire par mois |
| 6 | История | Chaque opération sous contrôle | Dépenses, revenus et intérêts des dépôts — dans un seul fil |
| 7 | Голос | Ajoutez vos dépenses à la voix | Dites le montant et la catégorie — c'est enregistré |
| 8 | Мультивалютность | EUR, USD, CHF — un seul vrai total | De vrais taux de change, un total fiable dans votre devise |

Примечание к №8: тройку валют для FR-витрины меняем на EUR/USD/CHF (франк релевантен —
приграничные работники Швейцарии, ~230 тыс. человек); для fr-CA — CAD/USD/EUR (§9).

---

## 5. Адаптация фич

### 5.1 Голосовой ввод (VoiceInputParser + Segmenter) — воркстрим L2

`SFSpeechRecognizer` locale: `fr-FR` (для канадских пользователей — `fr-CA`, брать из локали
устройства). Contextual strings — из локализованных названий категорий и счетов пользователя.

**Глаголы трат (`expenseKeywords`), ~20** — матчить по причастию и инфинитиву;
разговорные формы обязательны, диктовка бытовая:

```
dépensé, acheté, payé, réglé, déboursé, commandé, pris, coûté, sorti,
retiré, mis, donné, offert, remboursé (долг — расход), claqué (разг.),
cramé (разг.), filé (разг.), lâché (разг.), abonné (подписка), facturé
```
⚠️ «versé» двусмысленный: «j'ai versé 100 € au propriétaire» — расход,
«on m'a versé mon salaire» — доход. Правило: пассив/«on m'a versé» → доход, активный «j'ai versé» → расход.

**Глаголы/маркеры дохода (`incomeKeywords`), ~15:**

```
reçu, touché, gagné, encaissé, perçu, vendu, salaire, paie, paye,
prime, virement reçu, remboursé (мне вернули — контекст!), versement,
dividendes, intérêts, revenu
```
⚠️ «remboursé» в обоих списках — дизамбигуация по подлежащему: «j'ai remboursé» → расход,
«on m'a remboursé / j'ai été remboursé» → доход.

**Даты (`parseDate`):**

```
aujourd'hui, hier, avant-hier, ce matin, ce soir, la semaine dernière,
lundi…dimanche (последний прошедший день недели),
«le 12», «le 12 juin», «12/06» — формат DD/MM
```

**Союзы-разделители (`VoiceInputSegmenter`), ~8** для мультиоперационных фраз
(«20 euros de taxi et puis 15 euros au resto»):

```
et, puis, ensuite, aussi, après, également, et puis, ainsi que
```
⚠️ «et» внутри числительных («vingt et un euros», «cent et un») — не разделитель:
не сегментировать, если «et» стоит между числовыми словами.

**Ключевики категорий (~30) → маппинг на категории приложения** (идентификаторы — см.
`CategoryIcon.swift` и словарь парсера; ниже — целевая категория по смыслу):

| Ключевики (fr) | Категория |
|---|---|
| taxi, uber, vtc, métro, bus, tram, train, sncf, navigo | Транспорт |
| essence, carburant, gasoil, péage, parking, stationnement | Авто |
| courses, supermarché, hypermarché, épicerie, marché | Продукты |
| restaurant, resto, café, boulangerie, brasserie, kebab, livraison | Еда вне дома |
| loyer, charges, électricité, gaz, eau, assurance habitation | Жильё/ЖКХ |
| internet, forfait, mobile, téléphone, box | Связь |
| pharmacie, médecin, mutuelle, dentiste, kiné | Здоровье |
| cinéma, concert, sortie, bar, jeux | Развлечения |
| vêtements, fringues (разг.), chaussures, coiffeur | Одежда/уход |
| sport, salle, fitness, piscine | Спорт |
| cadeau, anniversaire | Подарки |
| voyage, hôtel, billets, vacances | Путешествия |
| école, crèche, cantine, études | Образование/дети |
| impôts, taxe | Налоги |
| tabac, clope (разг.) | Прочее/вредные привычки |

**Фонетические алиасы брендов (`ServiceLogo`), ~10** (как «ютуб» → YouTube — здесь
проблема не в кириллице, а в распознавании речи и локальных брендах):

```
carrefour → Carrefour          leclerc → E.Leclerc
auchan → Auchan                intermarché → Intermarché
décathlon → Decathlon          fnac → Fnac
sncf → SNCF                    edf → EDF
canal plus / canal + → Canal+  free → Free (оператор; конфликт со словом «free» — матчить только fr-локаль)
uber eats / ubereats → Uber Eats   leboncoin → Leboncoin
```

Тест-фразы для верификации (L5): «j'ai dépensé 12 euros de courses hier»,
«20 euros de taxi et puis 15 au resto», «on m'a versé mon salaire, 2 400 euros»,
«abonnement Canal Plus 25 euros», «avant-hier j'ai claqué 60 balles au resto»
(⚠️ «balles» = разговорное «евро» — добавить в парсер сумм).

### 5.2 Импорт выписок (StatementTextParser + CSV) — воркстрим L3

**Топ-5 банков Франции** (собрать образцы PDF-выписок, покрыть тестами):

| Банк | Типичные заголовки выписки |
|---|---|
| BNP Paribas | RELEVÉ DE COMPTE; Date, Nature des opérations, Valeur, Débit, Crédit |
| Crédit Agricole | Extrait de compte; Date, Libellé, Débit euros, Crédit euros |
| Société Générale | RELEVÉ DE COMPTE; Date, Valeur, Nature de l'opération, Débit, Crédit |
| La Banque Postale | Relevé de vos comptes; Date, Opérations, Montant (+/−) |
| Boursorama / BoursoBank | Date opération, Date valeur, Libellé, Montant (одна колонка со знаком) |

Ключевые слова для детекции секций/колонок (аналог «ТРАНЗАКЦИИ ПО СЧЕТУ»):
`RELEVÉ DE COMPTE`, `Extrait de compte`, `Date`, `Date valeur`, `Libellé`,
`Nature de l'opération(s)`, `Opérations`, `Débit`, `Crédit`, `Montant`, `Solde`,
`ANCIEN SOLDE`, `NOUVEAU SOLDE`, `TOTAL DES OPÉRATIONS`.
Маркеры типов операций в libellé: `CB` / `CARTE` (карта), `PRLV` / `PRÉLÈVEMENT` (директ-дебит),
`VIR` / `VIREMENT` (перевод), `RETRAIT DAB` (снятие наличных), `CHÈQUE`.

**Форматы:**
- Даты: **DD/MM/YYYY** (`12/06/2026`), встречается `DD/MM/YY` и `12 juin 2026` — месяцы
  словами добавить в словарь дат (janvier…décembre, сокращения janv., févr., …, déc.).
- Числа: **`1 234,56`** — запятая как десятичный разделитель, **пробел как разделитель тысяч**.
  ⚠️ **Отдельный нюанс для парсера:** в PDF это почти всегда не обычный пробел, а
  **неразрывный (U+00A0) или узкий неразрывный (U+202F)**, иногда U+2009. Перед парсингом
  числа нормализовать все варианты пробелов (`\u{00A0}`, `\u{202F}`, `\u{2009}`, `\u{0020}`)
  внутри числового токена. Написать unit-тест именно на `1\u{202F}234,56` — обычный
  `Formatter` без нормализации это молча не парсит.
- Знак суммы: двухколоночные Débit/Crédit (знак по колонке) ИЛИ одна колонка Montant
  со знаком `−`/`+` (⚠️ минус бывает типографским U+2212, не только hyphen-minus).
- Валюта: `EUR`, `€` — символ обычно **после** суммы с пробелом (`1 234,56 €`).

**CSV (`CSVColumnMapping`)** — локальные значения типов операций:

```
dépense / débit / sortie      → expense
revenu / recette / crédit / entrée → income
virement / transfert          → transfer
```
Заголовки колонок CSV: `Date`, `Libellé` / `Description`, `Montant`, `Catégorie`, `Compte`, `Type`.
Экспорт из французского Excel — разделитель `;` (потому что `,` занята десятичными) —
убедиться, что детектор разделителя это покрывает.

---

## 6. Цены (EUR, витрина fr-FR)

Якорь (README): ≈ $3 / $10 / $24 (мес / год / lifetime). Рекомендация для Франции —
**на уровне немецкой витрины или на один price point ниже**:

| Продукт | Рекомендация FR | Логика |
|---|---|---|
| Месяц | **2,99 €** | Психологический порог «до 3 €»; выше — усиливаем и без того высокую французскую настороженность к подпискам. На уровне DE (там 2,99–3,99 € — если DE зафиксирует 3,99 €, для FR оставить 2,99 €: чувствительность к цене подписки во Франции выше при сопоставимом ARPU) |
| Год | **12,99 €** (триал 14 дней) | ≈ 36% от 12 месяцев — заметно «выгоднее» месячной, главный продукт витрины |
| Lifetime | **29,99 €** | ≈ 2,3 годовых; lifetime особенно хорошо резонирует именно во Франции (усталость от подписок) — выносить на пейволл явно |

- Отдельные price points в ASC, **не автоконвертация** (иначе получатся кривые суммы вида 3,49 €).
- Цены включают TVA 20% — Apple вычитает её из выручки; при сравнении с KZ-якорем помнить про нетто.
- После 6–8 недель — сверка trial→paid с DE-когортой (ворота фазы из README).

---

## 7. Культурные заметки

1. **Vouvoiement обязателен.** Всё общение с пользователем — UI, метаданные, пейволл,
   пуши, What's New — строго на «vous». Tutoiement во Франции допустим только у
   подчёркнуто молодёжных брендов; для финансового приложения «tu» подрывает доверие.
2. **Типографика:** перед `:` `;` `?` `!` — **espace insécable** (в идеале узкий U+202F,
   допустим U+00A0). Кавычки — французские « guillemets » с неразрывными пробелами внутри.
   Символ € — после суммы через неразрывный пробел. Это касается и Localizable.strings,
   и скриншотов, и метаданных (в Title уже учтено: «Tenra : …»).
3. **Плюрализация (stringsdict):** категории `one/other`. ⚠️ Во французском **`one`
   покрывает 0 и 1** (и 1,5): «0 transaction», «1 transaction», «2 transactions».
   Проверить все формулировки счётчиков: строка для `one` должна корректно читаться
   и при нуле (не писать «une seule transaction» в one-форме). Прогнать оба plural-ключа
   с n = 0, 1, 2.
4. **Настороженность к подпискам.** Французский рынок известен subscription fatigue и
   регуляторной культурой лёгкой отмены (loi Chatel, résiliation en 3 clics). Явно писать:
   срок триала, «résiliable à tout moment», и показывать lifetime как альтернативу.
   Тёмные паттерны на пейволле (скрытая цена после триала) — репутационный риск выше среднего.
5. **Приватность как ценность, а не мелкий шрифт.** CNIL — самый известный в Европе
   регулятор приватности, аудитория тренирована годами. «Sans connexion bancaire» /
   «vos données restent sur votre appareil» — использовать в первых строках описания,
   promo и скриншоте №2 (уже сделано в §3–4).
6. **Лексика домена:** «courses» (продукты, а не «shopping»), «livret» (сберегательный
   счёт — понятнее, чем «dépôt», из-за Livret A), «prélèvement» (автосписание),
   «virement» (перевод). Использовать эти слова в UI-переводе — по ним же пользователи ищут.

---

## 8. Чек-лист запуска (fr-FR)

- [ ] **L1** Перевод `Localizable.strings` (1347 ключей) + `Localizable.stringsdict` (2 ключа, one/other; one покрывает 0/1 — см. §7.3)
- [ ] **L1** Нейтив-вычитка (носитель fr-FR), `plutil -lint`, diff-паритет ключей (скрипт аудита 2026-07-03)
- [ ] **L1** Типографика: espaces insécables перед `: ; ? !`, guillemets, `€` после суммы
- [ ] **L2** `expenseKeywords` / `incomeKeywords` (~20/~15, §5.1) + дизамбигуация versé/remboursé
- [ ] **L2** `parseDate`: aujourd'hui/hier/avant-hier, дни недели, DD/MM, месяцы словами
- [ ] **L2** `VoiceInputSegmenter`: 8 союзов + исключение «et» в числительных («vingt et un»)
- [ ] **L2** ~30 ключевиков категорий + маппинг; «balles» как разговорное «евро»
- [ ] **L2** ~10 алиасов брендов в `ServiceLogo`; локаль `fr-FR`/`fr-CA` в `SFSpeechRecognizer`
- [ ] **L3** Образцы PDF-выписок 5 банков (§5.2) + тесты заголовков/секций
- [ ] **L3** Парсер чисел: нормализация U+00A0/U+202F/U+2009, U+2212-минус, тест `1 234,56`
- [ ] **L3** `CSVColumnMapping`: dépense/revenu/virement (+débit/crédit/transfert), CSV с `;`
- [ ] **L4** Keyword research с реальными объёмами (ASA/инструмент) → финализация Keywords
- [ ] **L4** Метаданные в ASC (fr-FR): Title/Subtitle/Keywords/Promo/Description из §3, пересчёт лимитов
- [ ] **L4** 8 скриншотов: французский UI, суммы в EUR, подписи из §4
- [ ] **L4** Цены: отдельные price points 2,99/12,99/29,99 € (§6); пейволл RevenueCat на французском (vouvoiement, футер Terms/Privacy)
- [ ] **L5** Прогон приложения в локали fr (Scheme → App Language), ключевые экраны
- [ ] **L5** Голос: 10–15 тест-фраз (§5.1), включая мультиоперации и разговорные формы
- [ ] **L5** Импорт: выписки 5 банков end-to-end
- [ ] **L5** Native review чек-лист перед сабмитом
- [ ] **fr-CA** Витрина fr-CA: правки из §9, цены в CAD, скриншоты с CAD

---

## 9. fr-CA — минимальные отличия (Канада / Квебек)

Принцип: **один перевод приложения (fr)**, отдельная — только витрина ASC fr-CA.
Отдельный `fr-CA.lproj` не заводим, пока метрики не оправдают (квебекский французский
полностью понимает fr-FR-тексты; обратное направление чувствительнее — поэтому базу
пишем нейтрально, без франко-французского сленга в UI).

**Лексика (courriel-стиль — официальная терминология OQLF):**

| fr-FR | fr-CA | Где встречается |
|---|---|---|
| e-mail / mail | **courriel** | Поддержка, настройки, описание («Écrivez-nous») |
| shopping | **magasinage** | Название/ключевики категории |
| week-end | **fin de semaine** | Даты, аналитика по неделям |
| téléphone mobile / forfait mobile | **cellulaire / forfait cellulaire** | Категория «Связь» |
| supermarché (контекст) | + **dépanneur** (мини-маркет) | Добавить в ключевики категорий голоса для fr-CA |
| SMS | **texto** | Если появится в строках |

Метаданные fr-CA: взять тексты §3 и заменить только лексику из таблицы (в текущем
описании — одно место: «Écrivez-nous» в What's New нейтрально, правок почти нет).
Пример суммы в описании оставить в долларах: « 12 dollars de courses hier ».

**Валюта и форматы:** суммы на скриншотах — **CAD**, формат fr-CA: `1 234,56 $`
(символ `$` после суммы, как с €; при необходимости уточнения — `$ CA`).
Скриншот №8: «CAD, USD, EUR — un seul vrai total».

**Цены (CAD, отдельные price points):** месяц **4,49 $ CA**, год **17,99 $ CA**
(триал 14 дней), lifetime **44,99 $ CA** — эквивалент FR-уровня по курсу с округлением
до канадских price points; провалидировать по фактической сетке ASC.

**Банки (если дойдёт до отдельной поддержки выписок fr-CA; в фазу 2 не входит — бэклог):**
Desjardins, Banque Nationale, RBC/Banque Royale, BMO, TD Canada Trust. Выписки часто
двуязычные (заголовки вида `Date / Date`, `Retrait / Withdrawal`, `Dépôt / Deposit`,
`Solde / Balance`) — EN-парсер частично покрывает; отдельные образцы собрать до включения
маркетинга импорта на витрине fr-CA.

**Ключевики ASO fr-CA:** база та же; при валидации объёмов проверить «magasinage»,
«cellulaire», «REER» (пенсионные счета — возможный хвост для «épargne»).

---

*Создано: 2026-07-03. Черновик — до сабмита обязательны нейтив-ревью и валидация объёмов ключевиков.*
