# Tenra — Локализация: Испанский (es-ES + es-MX)

> Статус: план / черновик. Приоритет №2, фаза 2 (см. [README.md](README.md)).
> Витрины ASC: **es-ES** (Испания) и **es-MX** (Мексика + вся LATAM без отдельных витрин).
> ⚠️ Все испанские тексты в этом файле — AI-черновик. Перед сабмитом обязательна вычитка
> нейтивом (в идеале двумя: один из Испании, один из Мексики) — см. воркстрим L5 в README.

---

## 1. Обзор рынка

Испанский — максимальный охват за один перевод среди всех фаз плана:

- **Испания (es-ES)** — зрелый iOS-рынок ЕС, платёжеспособность ниже Германии, но выше LATAM.
  Высокое проникновение подписочной модели, привычка к freemium.
- **LATAM (es-MX)** — витрина es-MX обслуживает Мексику и де-факто весь испаноязычный
  Латам-регион (Колумбия, Аргентина, Чили, Перу и др. видят es-MX как ближайшую локаль).
  Мексика — крупнейший iOS-рынок региона и №1 по скачиваниям среди испаноязычных стран.
- **Испаноязычные США** — ~40 млн носителей; App Store US показывает испанские метаданные
  пользователям с испанской локалью устройства, и испанские ключевики **индексируются на
  US-витрине** через es-MX. Это бесплатный бонус к самому большому рынку мира.

**Экономика:** ARPU обеих витрин ниже DE (особенно LATAM), но суммарный объём аудитории
компенсирует: один перевод UI (1347 ключей) + один базовый пакет метаданных закрывает
20+ стран. Ожидание: высокая воронка установок, конверсия trial→paid ниже немецкой —
компенсируем ценой (см. §6).

**Стратегия перевода:** один нейтральный базовый перевод UI (без региональных
идиом), две витрины ASC с точечными отличиями (лексика, валюта, цены, банки). Отличия
собраны в §3.3 и по ходу разделов.

---

## 2. ASO-ключевики (черновик)

⚠️ Объёмы ниже — экспертная оценка. Перед фиксацией метаданных прогнать через
ASA Search Popularity (доступна для витрин ES и MX) или ASO-инструмент
(AppTweak/Astro/Sensor Tower) — как для de-DE (воркстрим L4).

| Запрос | EN-эквивалент | Комментарий |
|---|---|---|
| control de gastos | expense tracker | Главная фраза ниши в обеих локалях; «контроль расходов», а не «трекер» |
| finanzas personales | personal finance | Высокочастотник, конкурентный; обязателен в title/subtitle-связке |
| presupuesto | budget | Ядро позиционирования Tenra; одинаково ES/MX |
| gastos e ingresos | expenses and income | Естественная связка; покрывается словами gastos + ingresos |
| ahorro / ahorrar dinero | saving / save money | Мотивационный запрос, широкий |
| administrar dinero | manage money | В MX частотнее, чем в ES (в ES чаще «gestionar dinero») |
| suscripciones | subscriptions | Растущая ниша «трекер подписок»; у Tenra нативная фича |
| gestor de gastos | expense manager | ES-вариант; в MX реже |
| apuntar gastos | log/track expenses | Разговорный запрос «записывать траты», низкая конкуренция |
| deudas / préstamos | debts / loans | Долги — сильный мотиватор в LATAM |
| gastos hormiga | (нет прямого) | 🇲🇽 Чисто мексиканский термин «муравьиные траты» (мелкие незаметные расходы) — культурный феномен и готовый маркетинговый хук для es-MX (промотекст, скриншот 5) |
| quincena | (нет прямого) | 🇲🇽 Двухнедельная зарплата — центральное понятие финансового цикла в MX; кандидат в keywords es-MX |

Примечания:
- В поле keywords класть слова **без диакритики** (`prestamo`, `deposito`) — поиск ASC
  нечувствителен к акцентам, а символы экономятся.
- Единственное/множественное число Apple частично матчит, но `gastos` (мн.) — каноничная
  форма запросов, `gasto` почти не ищут.

---

## 3. Метаданные ASC

### 3.1 es-ES (Испания)

| Поле | Значение | Счётчик |
|---|---|---|
| Title | `Tenra: Presupuesto y Gastos` | 27/30 |
| Subtitle | `Finanzas y Suscripciones` | 24/30 |
| Keywords | `dinero,ahorro,cuenta,ingresos,deuda,prestamo,deposito,divisas,cartera,efectivo,sueldo,control,diario` | 100/100 |

Альтернативы (решить после валидации объёмов, §2):
- Title-alt: `Tenra: Control de Gastos` (24/30) — точное вхождение главной фразы ниши,
  но теряем `presupuesto` из title (сильнейшего поля).
- Subtitle-alt: `Control de Finanzas y Ahorro` (28/30) — забирает `control` и `ahorro`
  в более сильное поле; тогда из keywords убрать дубли `control`,`ahorro` и добавить
  `moneda,nomina` (99/100), но теряем `suscripciones` — а это живая ниша. Базовый вариант
  предпочтительнее до появления данных.

**Promotional Text** (170 max, можно менять без ревью):

```
Tus gastos, presupuestos y suscripciones bajo control — sin conectar tu banco. Datos privados en tu iPhone y 14 días de prueba gratis.
```
Счётчик: 134/170.

**Description** (1657 символов, цель 1500–2500 ✓). Хук: контроль расходов + приватность
без привязки банка.

```
¿A dónde se va tu dinero cada mes? Tenra te lo muestra sin que tengas que conectar tu banco: tú registras tus gastos y la app hace el resto. Tus datos se quedan en tu iPhone y en tu iCloud — sin publicidad, sin venta de datos y sin acceso a tus cuentas bancarias.

PRESUPUESTOS QUE SE VEN
Define un límite mensual por categoría y mira en la pantalla principal cuánto llevas gastado y cuánto te queda. Sin hojas de cálculo.

TODAS TUS FINANZAS EN UN SOLO LUGAR
• Cuentas y efectivo
• Depósitos con intereses calculados automáticamente
• Suscripciones con recordatorio de cada cobro
• Préstamos con calendario de pagos

ANALÍTICA CLARA
Saldo, gastos e ingresos, flujo neto del mes y tus categorías principales. Descubre patrones y recorta lo que sobra.

PUNTUACIÓN FINANCIERA
Ahorros, presupuestos y colchón de emergencia resumidos en un solo número que mejora contigo.

MULTIMONEDA DE VERDAD
Cuentas en EUR, USD o cualquier otra divisa, con tipos de cambio reales y un total honesto en tu moneda base.

AÑADE GASTOS CON TU VOZ
Di «gasté 12 euros en el súper» y la operación queda registrada con importe, categoría y fecha.

IMPORTA TUS EXTRACTOS
¿Años de historial en tu banco? Importa PDF o CSV y Tenra reconoce y clasifica los movimientos automáticamente.

PRIVACIDAD ANTE TODO
Sin registro obligatorio, sin conexión bancaria, sin anuncios. Tus finanzas son solo tuyas.

TENRA PRO
El registro diario y hasta 3 cuentas son gratis para siempre. Tenra Pro desbloquea cuentas ilimitadas, entrada por voz, importación de PDF/CSV, depósitos y préstamos. 14 días de prueba gratis con la suscripción anual.

Descarga Tenra y toma el control de tu dinero hoy mismo.
```

**What's New — шаблон:**

```
Novedades:
• [фича 1 на испанском]
• [фича 2]
• Mejoras de rendimiento y corrección de errores.

¿Te gusta Tenra? Déjanos una reseña — nos ayuda muchísimo.
```

### 3.2 es-MX (Мексика + LATAM)

Title и Subtitle — **идентичны es-ES** (совпадение указано явно):

| Поле | Значение | Счётчик |
|---|---|---|
| Title | `Tenra: Presupuesto y Gastos` | 27/30 |
| Subtitle | `Finanzas y Suscripciones` | 24/30 |
| Keywords | `dinero,ahorro,cuenta,ingresos,deuda,prestamo,deposito,divisas,cartera,quincena,sueldo,control,diario` | 100/100 |

Keywords отличаются одной заменой: `efectivo` → `quincena` (оба 8 симв., счётчик не
меняется). `quincena` — высокорелевантный чисто мексиканский запрос (§2); `efectivo`
частично покрывается `dinero`. Если валидация объёмов покажет обратное — откатить,
строка es-ES остаётся валидной для обеих витрин.

**Promotional Text — идентичен es-ES** (134/170): текст нейтральный, регионализмов нет.

**Description** (1666 символов, цель 1500–2500 ✓) — тот же текст с **тремя** отличиями:

1. `MULTIMONEDA DE VERDAD`: `Cuentas en EUR, USD…` → `Cuentas en MXN, USD…`
2. Пример голоса: `«gasté 12 euros en el súper»` → `«gasté 200 pesos en el súper»`
3. Заголовок секции импорта: `IMPORTA TUS EXTRACTOS` → `IMPORTA TUS ESTADOS DE CUENTA`
   (в Мексике банковская выписка — «estado de cuenta», «extracto» звучит по-испански).

Остальной текст (включая What's New шаблон) — идентичен es-ES.

### 3.3 Отличия es-ES vs es-MX — сводка

Общая лексика (нейтральный «tú»-испанский) покрывает ~95% текста. **Финансовая лексика
почти полностью совпадает**: cuenta, gasto, ingreso, presupuesto, ahorro, préstamo,
depósito, transferencia, deuda, saldo, comisión, tarjeta — одинаковы. Реальные отличия:

| Понятие | es-ES 🇪🇸 | es-MX 🇲🇽 | Где всплывает |
|---|---|---|---|
| Банковская выписка | extracto (bancario) | estado de cuenta | Description, экран импорта |
| Автомобиль | coche | carro / auto | Категории трат, голос |
| Телефон / связь | móvil | celular | Категории, голос |
| Аренда жилья | alquiler | renta | Категории, голос |
| Компьютер | ordenador | computadora | Категории (редко) |
| Парковка | parking / aparcamiento | estacionamiento | Категории, голос |
| Зарплата (периодика) | nómina | quincena / nómina | Голос-доходы, keywords |
| Позавчера | anteayer | antier / anteayer | Парсер дат в голосе |
| Мгновенный платёж | Bizum | SPEI / transferencia | Алиасы брендов, выписки |
| Формат чисел | 1.234,56 € | $1,234.56 | Парсер выписок — критично, §5.2 |

В UI-переводе (Localizable.strings) использовать **нейтральные формы**, понятные обоим
рынкам (auto/vehículo вместо coche/carro, teléfono вместо móvil/celular, где возможно).
Региональные формы уходят в **словари распознавания** (голос, выписки) — там нужны ВСЕ
варианты сразу, конфликтов нет.

---

## 4. Подписи скриншотов (8, порядок залочен по README)

Валюта в UI на скриншотах: **EUR для es-ES / MXN для es-MX**. Тексты подписей общие,
кроме №7 (глагол) и №8 (порядок валют).

| # | Экран | Заголовок | Подзаголовок |
|---|---|---|---|
| 1 | Главная | Presupuesto para cada categoría | Límites, gastos y saldo restante del mes — directo en la pantalla principal |
| 2 | Финансы | Todas tus finanzas en un solo lugar | Cuentas, depósitos, suscripciones y préstamos — sin conectar tu banco |
| 3 | Аналитика | Mira a dónde se va tu dinero | Saldo, gastos y flujo neto del mes — de un solo vistazo |
| 4 | Финансовый скор | Tu salud financiera en un número | Ahorros, presupuestos y colchón en una puntuación clara |
| 5 | Топ категория | Descubre tus mayores gastos | Categorías de gasto con un desglose claro mes a mes |
| 6 | История | Cada movimiento bajo control | Gastos, ingresos e intereses de depósitos — en una sola lista |
| 7 | Голос | 🇪🇸 Añade gastos con tu voz / 🇲🇽 Agrega gastos con tu voz | — |
| 8 | Мультивалютность | 🇪🇸 EUR, USD, GBP — un total real / 🇲🇽 MXN, USD, EUR — un total real | — |

Примечание к №7: «añadir» в Мексике понятно, но «agregar» — узус; разница в одном слове,
дешёвая и заметная нейтиву. К №5 для es-MX опционально A/B: подзаголовок
«Detecta tus gastos hormiga con un desglose claro mes a mes» — термин узнаваем мгновенно.

---

## 5. Адаптация фич

### 5.1 Голосовой ввод (воркстрим L2: VoiceInputParser + Segmenter)

Прецедент — `plans/006-voice-english-date-and-type-keywords.md`. Все списки ниже —
объединённые ES+MX (парсеру нужны оба варианта одновременно).

**`expenseKeywords` — глаголы/маркеры трат (~13):**

| Испанский | Примечание |
|---|---|
| gasté / me gasté | «потратил»; возвратная форма частотна в ES |
| compré | купил |
| pagué | заплатил |
| aboné | внёс/оплатил (формальнее) |
| saqué | снял (наличные) |
| di / dejé | дал / оставил (чаевые) |
| me costó / costó | «мне обошлось в…» |
| pedí | заказал (доставка) |
| eché gasolina | 🇲🇽/🇪🇸 «заправился» — устойчивое выражение |
| recargué | пополнил (телефон/карту) — частотно в MX |
| doné | пожертвовал |
| perdí | потерял |
| invertí | вложил |

**`incomeKeywords` — глаголы/маркеры дохода (~9):**

| Испанский | Примечание |
|---|---|
| recibí | получил |
| cobré | получил оплату — главный глагол дохода |
| gané | заработал |
| ingresé / me ingresaron | ES: «мне перечислили» |
| me pagaron | мне заплатили |
| me depositaron | 🇲🇽 «мне закинули на счёт» |
| sueldo / salario | зарплата (оба слова — оба рынка) |
| nómina | 🇪🇸 зарплата на счёт (в MX тоже используется) |
| quincena / aguinaldo | 🇲🇽 двухнедельная зарплата / 13-я зарплата (декабрь) |

**`parseDate` — слова и форматы:**
- hoy (сегодня), ayer (вчера), **anteayer** 🇪🇸 / **antier** 🇲🇽 (позавчера — включить оба),
  antes de ayer (разговорный синоним).
- Относительные: el lunes, la semana pasada, hace dos días.
- Числовые форматы: `DD/MM/YYYY` и `DD/MM` — оба рынка (в отличие от US MM/DD).

**`VoiceInputSegmenter` — союзы-разделители (~8):**
`y`, `e` (перед i-: «e ingresé»), `luego`, `después`, `también`, `además`, `aparte`,
`y luego` / `y también` (составные — проверять до одиночных).

**Ключевики категорий (~30, маппинг слово → категория Tenra, см. `CategoryIcon.swift`):**

| Слова | Категория |
|---|---|
| taxi, uber, cabify 🇪🇸, didi 🇲🇽 | Такси |
| gasolina, gasolinera, diésel | Топливо |
| comida, restaurante, tacos 🇲🇽, menú del día 🇪🇸 | Еда вне дома |
| súper, supermercado, mercado, despensa 🇲🇽 | Продукты |
| café, cafetería, desayuno | Кафе |
| farmacia, medicinas, doctor, médico | Здоровье |
| gimnasio, gym, deporte | Спорт |
| ropa, zapatos, tenis 🇲🇽 / zapatillas 🇪🇸 | Одежда |
| luz, agua, gas, recibo | Коммуналка |
| internet, wifi, móvil 🇪🇸, celular 🇲🇽, recarga | Связь |
| alquiler 🇪🇸, renta 🇲🇽, casa, piso 🇪🇸, departamento 🇲🇽 | Жильё |
| metro, autobús, camión 🇲🇽, colectivo, tren, cercanías 🇪🇸 | Транспорт |
| coche 🇪🇸, carro 🇲🇽, auto, taller, estacionamiento 🇲🇽, parking 🇪🇸 | Авто |
| cine, concierto, juego, boleto 🇲🇽 / entrada 🇪🇸 | Развлечения |
| peluquería, corte, estética 🇲🇽 | Красота |
| mascota, veterinario, perro, gato | Питомцы |
| regalo, cumpleaños | Подарки |
| viaje, hotel, vuelo, avión | Путешествия |
| colegio 🇪🇸, escuela, universidad, colegiatura 🇲🇽 | Образование |
| seguro, impuestos, comisión | Финансы/сборы |

**`ServiceLogo` — фонетические алиасы брендов (~12):**

| Как распознаёт речь | Бренд |
|---|---|
| «ютьюб» → yutub / yutú | YouTube |
| guasap / wasap | WhatsApp |
| espotifai / spotifai | Spotify |
| netflis / néflix | Netflix |
| amazón / ámazon | Amazon |
| mercadona | Mercadona 🇪🇸 |
| el corte inglés | El Corte Inglés 🇪🇸 |
| bisum / bizum | Bizum 🇪🇸 |
| oxxo / oso 🇲🇽 (частая ошибка STT) | OXXO 🇲🇽 |
| didí / didi | DiDi 🇲🇽 |
| rapi / rappi | Rappi 🇲🇽 |
| mercado libre / meli | Mercado Libre 🇲🇽 |

`SFSpeechRecognizer`: передавать `es-ES` или `es-MX` по локали пользователя (обе
поддерживаются iOS); contextual strings — из локальных названий категорий и счетов.

### 5.2 Импорт выписок (воркстрим L3: StatementTextParser + CSV)

**Топ-банки и типичные заголовки выписок** (собрать образцы PDF 3–5 банков на рынок,
покрыть тестами):

🇪🇸 Испания:

| Банк | Типичные заголовки колонок |
|---|---|
| CaixaBank | Fecha, Fecha valor, Concepto, Importe, Saldo |
| BBVA | F. Operación, F. Valor, Concepto, Importe, Disponible |
| Santander | Fecha operación, Fecha valor, Concepto, Importe, Saldo |
| ING (Cuenta Naranja) | Fecha, Descripción, Importe (€), Saldo |

🇲🇽 Мексика:

| Банк | Типичные заголовки колонок |
|---|---|
| BBVA México | Fecha, Fecha de operación, Descripción/Concepto, Cargo, Abono, Saldo |
| Banorte | Fecha, Descripción, Depósitos, Retiros, Saldo |
| Nu México | Fecha, Descripción, Monto (единая колонка со знаком) |
| Santander México | Fecha, Concepto, Retiro, Depósito, Saldo |

Ключевое структурное отличие: испанские выписки чаще дают **одну колонку Importe со
знаком**, мексиканские — **парные колонки Cargo/Abono (или Retiro/Depósito)**, где обе
суммы положительные и тип операции определяется колонкой. Парсер должен уметь обе схемы.
Словарь заголовков: Fecha, Fecha valor, Fecha de operación, Concepto, Descripción,
Importe, Monto, Cargo, Abono, Retiro, Depósito, Saldo, Movimientos.

**Форматы дат:** `DD/MM/YYYY` (оба рынка); в выписках встречаются `DD-MM-YYYY` и
текстовые `12 ENE 2026` / `12/ene/2026` — нужен словарь сокращений месяцев
(ENE, FEB, MAR, ABR, MAY, JUN, JUL, AGO, SEP/SEPT, OCT, NOV, DIC).

⚠️ **Форматы чисел — главный региональный нюанс:**

| | 🇪🇸 es-ES | 🇲🇽 es-MX |
|---|---|---|
| Числа | `1.234,56` (точка — тысячи, запятая — десятичные) | `1,234.56` (US-схема: запятая — тысячи, точка — десятичные) |
| Валюта | `1.234,56 €` (символ после) | `$1,234.56` (символ до; peso использует `$`!) |

Один «испанский» парсер чисел молча даст **ошибку в 100 раз** на чужом формате
(`1,234` = 1.234 в ES и 1234 в MX). Парсер выписок обязан определять схему по локали
документа/банка или эвристикой по структуре числа, а не по языку. Знак `$` в
мексиканских выписках — это MXN, не USD (USD помечают `USD`/`US$`). Покрыть оба
формата юнит-тестами (aналогично Красному флагу №6 — не доверять «одному формату»).

**`CSVColumnMapping` — локальные значения типов:**

| Испанский | → тип |
|---|---|
| gasto, cargo, retiro, egreso (LATAM), pago, compra | expense |
| ingreso, abono, depósito, cobro | income |
| transferencia, traspaso | transfer |

### 5.3 Логотипы
Пополнить `ServiceLogoRegistry` брендами из §5.1 (Mercadona, El Corte Inglés, Bizum,
OXXO, Banorte, Nu, Rappi, DiDi, Mercado Libre, CaixaBank, ING, Liverpool 🇲🇽, Soriana 🇲🇽).

---

## 6. Цены (воркстрим L4; отдельные price points, не автоконвертация)

Якорь (KZ): 1490₸ / 4990₸ / 11900₸ ≈ **$3 / $10 / $24**.

**es-ES (EUR)** — чуть ниже уровня DE (немецкие цены — верхняя планка ЕС):

| Продукт | Цена | ≈ USD | vs якорь |
|---|---|---|---|
| Месяц | 2,99 € | ~$3.2 | ≈ якорь |
| Год (14 дней триал) | 9,99 € | ~$10.8 | ≈ якорь |
| Lifetime | 22,99 € | ~$24.8 | ≈ якорь, на тир ниже «круглых» 24,99 € |

Испания терпит околоевропейские цены; занижать сильнее смысла нет — теряем маржу без
роста конверсии. Если de-DE зафиксирует 3,99/12,99/29,99 € — испанские тиры выше не
поднимать.

**es-MX (MXN)** — агрессивно вниз: LATAM максимально чувствителен к цене, а витрина
es-MX закрывает и более бедные рынки региона:

| Продукт | Цена | ≈ USD | vs якорь |
|---|---|---|---|
| Месяц | 49 MXN | ~$2.6 | −15% |
| Год (14 дней триал) | 179 MXN | ~$9.6 | −5%, месячный эквивалент ~15 MXN продаёт годовую |
| Lifetime | 399 MXN | ~$21 | −12%, психологический порог <400 |

При слабой конверсии через 6–8 недель (ворота фазы, README) — тестировать 39/149/349 MXN
(≈ $2.1/$8/$18.7), прежде чем трогать EUR-цены. RevenueCat: цены задавать per-storefront
в ASC (все price points существуют в сетке Apple), paywall-тексты оффера перевести в
дашборде RC (один испанский перевод на обе витрины).

---

## 7. Культурные заметки

- **Tú vs usted.** Рекомендация: **нейтральный tú** для всего UI, метаданных и paywall —
  в обеих локалях. Это стандарт мобильных приложений (Apple, Google, N26, Fintonic,
  BBVA-app используют tú); usted звучит канцелярски и дистанцирует. В Мексике usted жив
  в вежливой речи, но в интерфейсах tú давно норма. Избегать **vosotros** (только
  Испания) в пользу конструкций без обращения ко множественному числу; **vos**
  (Аргентина/Ц. Америка) не использовать — tú понятен всем.
- **Плюрализация:** испанский = категории `one/other` (README, воркстрим L1):
  `1 día / 2 días`, `1 operación / 5 operaciones`. Проверить оба plural-ключа
  `Localizable.stringsdict`. Ловушка: 0 — это `other` («0 días»), в отличие от fr/pt-BR.
- **Тон:** испанский маркетинговый текст терпит чуть больше эмоции, чем немецкий, но
  Tenra продаёт приватность и контроль — держать спокойный, конкретный тон; без
  восклицательных цепочек и «¡¡Increíble!!».
- **Приватность как хук** работает на обоих рынках, но по-разному: в ES — GDPR-культура
  («sin venta de datos»), в MX — недоверие к банкам и телефонным мошенничествам
  («sin acceso a tus cuentas bancarias», «sin conectar tu banco»).
- **Формат валюты в UI:** отдаётся системному форматтеру по локали (см. Красный флаг №7 —
  только канонические форматтеры), вручную ничего не собирать: `1.234,56 €` vs `$1,234.56`
  разъедутся сами правильно.

---

## 8. Чек-лист запуска (обе витрины)

Порядок — по воркстримам README (L1–L5); релиз только когда готово всё.

- [ ] **L1** `Localizable.strings` es (1347 ключей) + `Localizable.stringsdict` (2 plural-ключа, one/other)
- [ ] **L1** Нейтральная лексика UI проверена на «мексиканское ухо» и «испанское ухо» (два нейтив-ревьюера)
- [ ] **L1** `plutil -lint` + diff-паритет ключей (скрипт аудита 2026-07-03)
- [ ] **L2** `expenseKeywords`/`incomeKeywords` из §5.1 внесены в парсер
- [ ] **L2** `parseDate`: hoy/ayer/anteayer/**antier** + DD/MM форматы
- [ ] **L2** Ключевики категорий (~30) + союзы сегментера (~8)
- [ ] **L2** Алиасы брендов в `ServiceLogo` (~12) + логотипы в `ServiceLogoRegistry`
- [ ] **L2** `SFSpeechRecognizer` получает es-ES/es-MX; 10–15 тестовых фраз на КАЖДЫЙ вариант (суммы с запятой И точкой, категории, даты, мультиоперации)
- [ ] **L3** Образцы PDF-выписок: CaixaBank, BBVA, Santander, ING + BBVA México, Banorte, Nu, Santander MX
- [ ] **L3** Парсер чисел: тесты на `1.234,56` И `1,234.56`; `$` в MX = MXN
- [ ] **L3** Схемы Importe-со-знаком И Cargo/Abono покрыты тестами
- [ ] **L3** `CSVColumnMapping`: gasto/ingreso/transferencia/egreso/traspaso
- [ ] **L4** Валидация объёмов ключевиков (ASA Search Popularity ES + MX) → финализация title/subtitle/keywords §3
- [ ] **L4** Метаданные залиты в ASC: es-ES и es-MX отдельно (отличия — §3.2)
- [ ] **L4** Скриншоты ×8: UI на испанском, EUR для es-ES / MXN для es-MX, подписи §4
- [ ] **L4** Цены per-storefront (§6): 2,99/9,99/22,99 € и 49/179/399 MXN; триал 14 дней на годовой
- [ ] **L4** Paywall в RevenueCat переведён (один es-перевод), футер Terms/Privacy на месте
- [ ] **L5** Прогон приложения в локали es (Scheme → App Language), ключевые экраны
- [ ] **L5** Native review обеих витрин перед сабмитом
- [ ] Ворота фазы: конверсия установок и trial→paid через 6–8 недель (ASC + RevenueCat)
