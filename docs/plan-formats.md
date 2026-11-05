# Форматы дат и сумм: дизайн

Статус: дизайн утверждён основателем 2026-11-05. Сделаны задачи 1–3 (DesignKit 8.8.0, ветка
`claude/formats`, ждёт PR после 8.7.0) и 4, 7 (в main); задачи 5, 6 и 8 в main (DesignKit 8.8.0 закреплён); 9–11 ждут своей очереди. Макет экранов (утверждён 2026-11-05):
https://claude.ai/artifact/GXmE57X7WjPsSZ4HrQmcdq

Пометки: «(основатель)» решил владелец; «(моё решение)» решено при проектировании, его можно
оспорить; без пометки следует из кода или правил проекта.

## 1. Зачем

Даты и суммы должны выглядеть так, как человек привык. С 2026-11-05 суммы берут разделители из
региона iPhone («1 234,56» в Казахстане, «1,234.56» в США), а даты почти везде идут по жёсткому
шаблону «5 ноября»: в английском это «5 November», хотя в США пишут «November 5». Символ валюты
всегда стоит после числа, первый день недели берётся из системы.

Основатель (2026-11-05): по умолчанию порядок дат и вид сумм как принято в регионе, а в
Настройках можно выбрать свой формат. Пример, когда это нужно: телефон настроен на регион США,
а человек живёт в Казахстане и привык к «1 234,56 ₸».

## 2. Что строим

### Цели

- По умолчанию всё по региону iPhone: порядок дня и месяца, разделители в суммах, место
  символа валюты, первый день недели. Ничего настраивать не нужно.
- Раздел «Форматы» в Настройках, где каждый из пяти пунктов можно поменять.
- Выбор действует везде, где приложение показывает даты и суммы (§3.6).

### Не цели

- Язык месяцев и интерфейса: остаётся языком приложения.
- Время (12 или 24 часа): почти не показывается и следует настройке iPhone (основатель
  согласился 2026-11-05).
- Число знаков после запятой по валютам (у иены 0, у динара 3): сейчас у всех валют 2, так и
  остаётся.
- Код валюты вместо символа («1 234 KZT»).
- Экспорт и импорт CSV, хранение данных, разбор введённых сумм: форматы не меняются, чтобы файл
  всегда загружался обратно (основатель согласился).

### Анти-цели (провал, даже если работает)

- Где-то в приложении остался старый формат: человек выбрал «1,234.56», а на одном экране
  «1 234.56». Половинчатое применение хуже, чем никакого.
- После смены формата часть экранов показывает старое до перезапуска (правило 12 в CLAUDE.md:
  ключи кэшей и триггеры обновления включают каждое измерение, от которого зависит значение).
- Сумма читается как другое число: «1.234» по-немецки это тысяча двести тридцать четыре, а не
  одна целая. Пример под каждым вариантом показывает и тысячи, и копейки, чтобы это было видно.
- Экран настроек сложнее, чем задача: никаких своих шаблонов вроде «dd/MM/yy», только готовые
  варианты.

## 3. Как ведёт себя

### 3.1 По умолчанию и после выбора

- Пока человек пункт не трогал, этот пункт берётся из региона iPhone и меняется вместе с
  регионом (основатель: варианта «Как в регионе» в списках нет, просто отмечен формат региона).
- Выбранный вариант запоминается и от региона больше не зависит. Каждый пункт сам по себе: если
  поменяли только разделители, дата по-прежнему следует региону (моё решение).
- «Вернуть формат региона» внизу экрана сбрасывает все пять пунктов. Кнопка видна, только когда
  хотя бы один пункт отличается от формата региона.
- Настройки хранятся на устройстве (UserDefaults в общей App Group, чтобы их видел виджет). В
  резервную копию iCloud не входят (моё решение: это настройка телефона, как язык).

### 3.2 Экран (макет утверждён)

- Строка «Форматы» в «Общих настройках», между «Базовой валютой» и «Фоном», без значения
  справа, со стрелкой.
- Экран «Форматы» сверху вниз:
  1. «Так это будет выглядеть»: живой пример с датой, тремя операциями (две траты, доход) и
     полосой дней недели. Меняется сразу при выборе.
  2. Секция «Даты»: «Дата», «Первый день недели».
  3. Секция «Суммы»: «Разделители», «Символ валюты», «Копейки».
  4. Подпись: сначала выбран формат региона (с названием региона), экспорт CSV и данные не
     меняются.
  5. «Вернуть формат региона» (§3.1).
- В каждой строке справа текущий вариант («3 ноября 2026», «1 234,56», «После числа»).
- Строка открывает список вариантов (DesignKit `UniversalRow` с `.picker`): у каждого крупно
  образец, мелко пояснение; текущий отмечен галочкой. Выбор возвращает на «Форматы» (как в
  макете; если `.picker` DesignKit ведёт себя иначе, его поведение важнее).
- Компоненты только из DesignKit, никаких своих оболочек строк и карточек (правила проекта).

### 3.3 Дата

Варианты (образец на 3 ноября 2026, месяц на языке приложения):

| Вариант | В этом году | С годом | Пояснение |
|---|---|---|---|
| Словами | 3 ноября | 3 ноября 2026 | порядок по региону: в США «November 3», в России «3 ноября» |
| Точками | 03.11 | 03.11.2026 | день, месяц, год |
| Дробью | 11/03 | 11/03/2026 | месяц, день, год |
| ISO | 2026-11-03 | 2026-11-03 | год, месяц, день; всегда с годом (моё решение) |

- Формат региона: «Словами» (так приложение выглядит сейчас, моё решение).
- Меняются даты дня: заголовки дней в истории, даты операций, карточек, подписок, кредитов,
  депозитов, целей, уведомлений, выбранная дата в форме траты. «Сегодня», «Вчера», названия
  месяцев («Ноябрь 2026») и подписи осей графиков остаются как есть (моё решение).
- В диапазонах («3–10 ноября») формат применяется к каждой дате.

### 3.4 Первый день недели

- Варианты: понедельник, воскресенье. Если в регионе неделя начинается с другого дня
  (суббота), он тоже в списке (моё решение).
- Формат региона: `Locale.current` (`Calendar.current.firstWeekday`).
- Одна настройка для всего, что делит время на недели (основатель, 2026-11-05):
  - фильтр «Эта неделя» (сейчас всегда с понедельника, `TimeFilter.swift`) и «эта неделя» в
    Siri (`SpendingQueryService`);
  - недельные бюджеты категорий (`CategoryBudgetService.weeklyPeriod`) и сигналы о перерасходе;
  - недельные периоды аналитики и график трат по дням недели;
  - недельная сводка: приходит утром первого дня недели (сейчас всегда понедельник 9:00,
    `WeeklyDigestScheduler`), и сводка Тэна о неделе;
  - календарь подписок (DesignKit `MonthCalendar` и `CalendarRange`), `CalendarHeatmap`,
    `MiniBars`, `DateRangePickerSheet`, системные `DatePicker` (через
    `.environment(\.calendar, …)`).
- По умолчанию день берётся из региона и для тех, кто ничего не менял. В Казахстане это
  понедельник, как сейчас. У кого регион США, после обновления неделя начнётся с воскресенья:
  итоги «Этой недели» и окна недельных бюджетов сдвинутся на день (основатель принял это,
  2026-11-05).

### 3.5 Суммы

- **Разделители:** «1 234,56» (пробел и запятая), «1,234.56» (запятая и точка), «1.234,56»
  (точка и запятая), «1’234.56» (апостроф и точка), «1 234.56» (пробел и точка, прежний вид
  Tenra). Формат региона: его разделители (`DesignKitBridge.amountSeparators(for:)`, уже в main).
  Если у региона другая группировка цифр (Индия: «1,23,456.78»), формат региона тоже в списке
  отдельным вариантом (моё решение).
- **Символ валюты:** после числа («1 234 ₸») или перед ним («₸1 234»). Формат региона: как
  принято в регионе, то есть в валютном формате основного языка региона, а не языка
  приложения (моё решение). `NumberFormatter` для `en_KZ` ставит «₸1 234,50», хотя в
  Казахстане пишут «1 234 ₸»: английский интерфейс в Казахстане должен оставить символ после
  числа, как сейчас. Основной язык региона: вероятный язык по CLDR (`und-KZ` и подобные).
  Минус стоит перед символом: «−₸1 234» (моё решение).
- **Копейки:** «Если есть» (1 234 и 1 234,50, как сейчас), «Всегда» (1 234,00), «Никогда»
  (1 235, с округлением). Варианта по региону нет, по умолчанию «Если есть» (моё решение,
  регион этого не задаёт). Название пункта на других языках по смыслу: Cents, Cent, céntimos…
  «Копейки» касаются только показанных денежных сумм (моё решение): поля ввода всегда
  показывают точное значение, курсы валют, ставки и проценты сохраняют свою точность, а
  ненулевая сумма меньше 1 сохраняет копейки (остаток долга 0,40 ₸ не становится «0 ₸»).
- **Разделители** касаются каждого числа, которое показывает приложение, не только денег:
  проценты, ставки депозитов и кредитов, курсы, площадь и доли активов (моё решение, иначе
  «12.5%» рядом с «1.234,56» нарушает анти-цель о половинчатом применении). Сейчас такие числа
  форматируются двумя способами (`String(format: "%.1f%%")` и `.percent` по локали); обе
  ветки сводятся к одной точке входа.
- То же правило везде, где сумма собрана в текст: скрытые суммы («•••• ₸» становится «₸ ••••»
  при символе впереди), сокращённые суммы («1,2 млн ₸»), подписи осей графиков, поле ввода
  суммы (показывает выбранные разделители; при вводе по-прежнему принимаются и запятая, и
  точка).

### 3.6 Где действует

- Все экраны приложения и компоненты DesignKit.
- Виджеты: снимок для виджета передаёт выбранные форматы, виджет форматирует по ним.
- Уведомления, которые приложение собирает само (недельная сводка, сигналы аналитики,
  предложения Тэна во входящих). Уже запланированные уведомления пересобираются после смены
  формата (моё решение).
- Ответы Тэна: контекст запроса к серверу передаёт образец даты и суммы, а промпт на сервере
  (`server/assistant`) просит писать числа и даты в этом виде. Блоки ответа, которые рисует
  приложение, следуют настройкам сами.
- Озвучка VoiceOver читает сумму как число при любом варианте разделителей (проверить «1’234.56»
  и «1.234,56»).

### 3.7 Бесплатно

Это не функция Pro (основатель согласился 2026-11-05).

## 4. Ограничения

- Компоненты и токены живут в DesignKit: позиция символа, «Копейки никогда», разделители в
  поле ввода, формат дат и календарь с первым днём недели в компонентах DesignKit требуют
  выпуска DesignKit (PR в DesignKit, его CI собирает Tenra и Dalada). Он идёт после 8.7.0
  (PR из ветки `claude/first-run-fixes`, 2026-11-05). Новый API DesignKit не знает моделей Tenra:
  настройки передаются значениями (как `AmountDisplayConfiguration`) или хуками (как
  `DesignKitCurrencyConverter`). Dalada по умолчанию ничего не замечает.
- Правило 7 (суммы только через канонические форматтеры) и правило 15 (`FastDateParser` для
  хранимых дат, `en_US_POSIX` для разбора) остаются. Отображение дат идёт через одну точку входа
  в Tenra, разбор хранимых дат не трогаем.
- `InsightsService` работает вне MainActor: настройки читаются как `Sendable`-значение и входят
  в снимок, а не читаются из MainActor-состояния (docs/concurrency.md).
- Кэши, где лежит уже отформатированный текст (подписи инсайтов `formattedValue`, заголовки
  секций истории и подобные), получают версию форматов в ключ и обновляются при её смене без
  перезапуска (правило 12).
- 12 языков (правило 13): все новые строки во всех `Localizable.strings`, без длинных тире.
- Шаги на 19 тысячах операций не должны стать медленнее: форматтеры кэшируются, как
  `AmountDisplayConfiguration.formatter` и `DateFormatters` сейчас (docs/gotchas.md).

## 5. Что оставлено разработчику

- Как именно хранить настройки и как называется тип (например, `FormatPreferences` в
  `Services/Settings/`), как резолвить формат региона из `Locale`.
- Форма API DesignKit (поля конфигурации, хуки, `Environment`), если выполняются §3 и §4.
- Порядок миграции мест, где форматируются даты (около 80 мест в Tenra: `DateFormatters`,
  шаблоны, `.formatted(date:)`), и какие из них оставить (отладка, имена файлов, разбор).
- Как пересобирать запланированные уведомления.
- Тексты пояснений в списках и подписей на 12 языках (смысл в §3).

## 6. Решено основателем после проверки дизайна (2026-11-05)

- Первый день недели двигает всё недельное, включая фильтр «Эта неделя», недельные бюджеты и
  день недельной сводки; по умолчанию он из региона (§3.4).

## 7. План реализации

> Для исполнителя: superpowers:executing-plans (или subagent-driven-development), задача за
> задачей; шаги отмечаются `- [ ]`.

**Цель:** форматы дат и сумм по региону с выбором в Настройках, применённые везде (§3).

**Архитектура:** чистое ядро `FormatPreferences` превращает сохранённый выбор и `Locale` в
`ResolvedFormats`. `FormatSettings` (`@Observable`, MainActor) хранит выбор в App Group, держит
потокобезопасный снимок для фоновых читателей (`FormatSettings.snapshot`, `AppCalendar.current`)
и сообщает об изменении; `AppCoordinator` применяет его к DesignKit, кэшам, виджету и
уведомлениям, а корни вкладок перестраиваются по `FormatSettings.version`. DesignKit 8.8.0
добавляет позицию символа, режимы копеек, вторичную группировку, разделители в поле ввода и хук
формата дат.

**Технологии:** SwiftUI (iOS 26), Swift Testing, DesignKit (SPM), WidgetKit, Cloudflare Worker
(TypeScript, vitest).

**Спецификация:** §1–6 этого файла и макет (ссылка в начале).

**Порядок:** задачи 1–3 в DesignKit (ветка `claude/formats` от `claude/first-run-fixes`, после
слияния 8.7.0 перебазировать на `main`), PR открывает владелец по ссылке; задачи 4 и 7 в Tenra
не зависят от DesignKit и идут, пока PR ждёт; задачи 5, 6, 8–11 после выпуска 8.8.0 и подъёма
версии в Tenra (шаг 1 задачи 5).

### Глобальные ограничения

- iOS 26.0; API iOS 27 только внутри `#if compiler(>=6.4)` и `#available(iOS 27, *)`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: всё, что читают `InsightsService`,
  `TimeFilter.dateRange()` и виджет, `nonisolated` и `Sendable`.
- Суммы только через канонические форматтеры (правило 7). Хранимые даты разбирает
  `FastDateParser`, форматтеры разбора с `en_US_POSIX` (правило 15). `AmountFormatter`, CSV,
  контекст для ИИ с числами и разбор ввода не меняются.
- Каждая новая строка во всех 12 `Localizable.strings` (правило 13), без длинных тире;
  позиционные спецификаторы, если перевод переставляет аргументы (правило 14).
- Интерфейс только из компонентов DesignKit; `scripts/design_lint.py` и
  `scripts/section_rows_lint.py` зелёные.
- Кэш, где лежит отформатированный текст или граница недели, включает `FormatSettings.version`
  или перестраивается в `onChange` (правило 12).
- Сьюты, которые пишут `FormatSettings.snapshot` или `AmountDisplayConfiguration.shared`, несут
  `@MainActor` и `.sharedProcessState`; ожидания считают опросы, а не время.
- Никаких значений из банковских выписок в тестах и коммитах.
- Tenra: коммиты в `main`, без push (пушит владелец). DesignKit: своя ветка и PR.
- Тесты Tenra: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/<Suite>`
  (фильтр только по имени типа сьюта); итог читать из `xcrun xcresulttool get test-results summary`.
- Тесты DesignKit: `xcodebuild test -scheme DesignKit -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:DesignSupportTests/<Suite>`.

### Внимание при проверке

1. Формат меняют на открытом экране «Форматы»: экран остаётся (стек не сбрасывается в корень),
   а после возврата Главная, История и Аналитика показывают новый формат без перезапуска.
   Тест: `FormatsUITests` в задаче 8.
2. Выбраны «1,234.56», а на клавиатуре региона запятая: введённое «1,5» сохраняется как 1.5,
   а не 15. Тест: `typedCommaStaysDecimal` в задаче 2.
3. «Копейки: никогда» и сумма меньше 1: 0,40 ₸ и −0,40 ₸ остаются с копейками. Тест:
   `fractionsNeverKeepsCentsUnderOne` в задаче 1.
4. Регион сменился, один пункт выбран вручную: выбранный остаётся, остальные идут за новым
   регионом. Тест: `choiceStaysOthersFollowRegion` в задаче 4.
5. Неделя с воскресенья: в воскресенье утром «Эта неделя» и недельный бюджет начинаются в это
   воскресенье, сводка приходит в воскресенье в 9:00. Тесты в задаче 7.

### Задача 1 (DesignKit): символ валюты, копейки, вторичная группировка

**Файлы:** `Sources/DesignSupport/AmountDisplayConfiguration.swift`,
`Sources/DesignSupport/Formatting.swift`,
`Sources/DesignComponents/Amounts/FormattedAmountText.swift`; тест
`Tests/DesignSupportTests/AmountDisplayOptionsTests.swift` (новый).

**Даёт:**
- `public enum CurrencySymbolPosition: Sendable, Hashable { case after, before }`
- `public enum AmountFractions: Sendable, Hashable { case whenPresent, always, never }`
- в `AmountDisplayConfiguration`: `symbolPosition = .after`, `fractions = .whenPresent`,
  `secondaryGroupingSize: Int? = nil`; `showDecimalsWhenZero` становится вычисляемым (чтение
  `fractions == .always`, запись `true` → `.always`, `false` → `.whenPresent`), чтобы Dalada
  собиралась без правок. `makeNumberFormatter()` ставит `secondaryGroupingSize`.
- параметр `configuration: AmountDisplayConfiguration = .shared` у
  `Formatting.formatCurrencySmart` и `Formatting.formatCurrencyCompact` (тесты не трогают
  `shared`).
- `public static func attachSymbol(_ number: String, symbol: String, isNegative: Bool, position: CurrencySymbolPosition) -> String`
  в `Formatting`: после числа «1 234 ₸» (через пробел), перед числом «₸1 234» без пробела, знак
  минуса впереди символа «-₸1 234».

- [x] **Шаг 1. Тесты** (`AmountDisplayOptionsTests`, каждая с конфигурацией из
  `AmountDisplayConfiguration()` и правкой одного поля):
  ```swift
  @Test func symbolAfterIsTheDefault()      // formatCurrencySmart(1234, "KZT") == "1 234 ₸"
  @Test func symbolBeforeKeepsTheSignFirst() // .before: 1234 → "₸1 234", -1234 → "-₸1 234"
  @Test func fractionsAlways()               // .always: 1234 → "1 234.00 ₸"
  @Test func fractionsNeverRounds()          // .never: 1234.5 → "1 235 ₸" (округление .halfUp)
  @Test func fractionsNeverKeepsCentsUnderOne() // .never: 0.4 → "0.40 ₸", -0.4 → "-0.40 ₸"
  @Test func secondaryGrouping()             // "," + secondary 2: 1234567.8 → "12,34,567.80 ₸"
  @Test func compactFollowsSeparatorAndSymbol() // decimal ",", .before, locale en_US:
                                             // formatCurrencyCompact(1_200_000, "USD") == "$1,2M"
  @Test func showDecimalsWhenZeroMapsToFractions() // set true → fractions == .always
  ```
- [x] **Шаг 2.** Запустить сьют: падает (нет `symbolPosition`, `fractions`, `configuration:`).
- [x] **Шаг 3.** Реализовать в трёх файлах. `FormattedAmountText`: единица перед числом при
  `.before` (знак, символ, число), скрытая сумма «₸ ••••», запасной сокращённый вид через
  `formatCurrencyCompact`, дробная часть не рисуется при `.never`, кроме 0 < |x| < 1.
  Подписи осей (`ChartValueFormat.compactString`) идут через тот же `formatCompactNumber`;
  если он форматирует сам, перевести. Умолчания прежние, поэтому снимки Gallery не меняются.
- [x] **Шаг 4.** Сьют зелёный, затем весь `xcodebuild test -scheme DesignKit`.
- [x] **Шаг 5.** Коммит «feat(amounts): symbol position, fractions, secondary grouping».

### Задача 2 (DesignKit): разделители в поле ввода суммы

**Файлы:** `Sources/DesignSupport/AmountInputFormatting.swift`; тест
`Tests/DesignSupportTests/AmountInputSeparatorsTests.swift` (новый).

**Даёт:** `displayAmount(for:configuration: = .shared)` группирует и ставит десятичный знак из
конфигурации, в том числе у незаконченного ввода («1234,» показывается с выбранным знаком).
`cleanAmountString(_:)` для набранного текста не меняется: запятая и точка значат дробь.
Вставка из буфера (`AnimatedInputComponents`, `clipboardText`) сначала убирает выбранный знак
группировки, если в тексте есть и выбранный десятичный: `cleanPastedAmount(_:configuration:)`.

- [x] **Шаг 1. Тесты:**
  ```swift
  @Test func displayUsesConfiguredSeparators() // commaDot: "1234.5" → "1,234.5"; dotComma → "1.234,5"
  @Test func displayDefaultUnchanged()          // "1234.5" → "1 234.5"
  @Test func typedCommaStaysDecimal()           // cleanAmountString("1,5") == "1.5"
  @Test func pastedGroupedAmount()              // commaDot: cleanPastedAmount("1,234.56") == "1234.56";
                                                // spaceComma: cleanPastedAmount("1 234,56") == "1234.56"
  ```
- [x] **Шаг 2.** Падают. **Шаг 3.** Реализовать. **Шаг 4.** Зелёные + весь пакет.
- [x] **Шаг 5.** Коммит «feat(input): amount field shows the configured separators».

### Задача 3 (DesignKit): формат дат, первый день недели, выпуск 8.8.0

**Файлы:** `Sources/DesignSupport/DesignKitDateFormat.swift` (новый),
`Sources/DesignComponents/Content/MonthCalendar.swift`,
`Sources/DesignComponents/Sheets/DateRangePickerSheet.swift`, `VERSION`, `CHANGELOG.md`,
`docs/design-system.md`; тест `Tests/DesignComponentsTests/CalendarWeekStartTests.swift`.

**Даёт:** `public enum DesignKitDateFormat { public nonisolated(unsafe) static var day: (@Sendable (_ date: Date, _ includeYear: Bool) -> String)? }`
(как `DesignKitCurrencyConverter`); `MonthCalendar` (подпись недели «3 нояб. – 9 нояб.») и
`DateRangePickerSheet` (подписи границ) берут дату из хука, без хука как сейчас. Заголовок дней
недели и строки `MonthCalendar` следуют `range.calendar.firstWeekday` (проверить; если уже так,
только тест).

- [x] **Шаг 1. Тесты:** `weekStartsOnSunday` — `CalendarRange(today: 2026-11-05, calendar:` григорианский с
  `firstWeekday = 1)` даёт первую неделю с воскресенья 2026-11-01; `weekdayHeaderFollowsCalendar` —
  порядок символов дней в заголовке начинается с воскресенья (через внутреннюю функцию заголовка,
  открытую для тестов `internal`); `dayHookIsUsed` — с хуком подпись недели равна строке хука.
- [x] **Шаг 2–4.** Красный, реализация, зелёный весь пакет.
- [x] **Шаг 5.** `VERSION` 8.8.0, раздел CHANGELOG «8.8.0» (Added: позиция символа, копейки,
  вторичная группировка, разделители в поле ввода, `DesignKitDateFormat`; умолчания не меняются),
  `docs/design-system.md` DesignKit (§6 суммы, раздел про хуки). Коммит, push ветки, ссылка на PR
  владельцу: `https://github.com/dkicekeeper/DesignKit/compare/main...claude/formats?expand=1`.

### Задача 4 (Tenra): ядро `FormatPreferences` и хранилище `FormatSettings`

**Файлы:** `Tenra/Services/Settings/FormatPreferences.swift`,
`Tenra/Services/Settings/FormatSettings.swift`, `Tenra/Utils/AppCalendar.swift` (новые); тесты
`TenraTests/Services/Settings/FormatPreferencesTests.swift`, `FormatSettingsTests.swift`.
Удалить `DesignKitBridge.amountSeparators(for:)` и `TenraTests/Utils/AmountSeparatorsTests.swift`
(их случаи переходят в `FormatPreferencesTests`), `configure()` пока берёт разделители из
`FormatSettings.snapshot`.

**Даёт:**
```swift
nonisolated enum DateStyle: String, Codable, Sendable, CaseIterable { case words, dots, slash, iso }
nonisolated enum AmountSeparators: String, Codable, Sendable, CaseIterable {
    case spaceComma, commaDot, dotComma, apostropheDot, spaceDot, region }
nonisolated enum AmountSymbolPosition: String, Codable, Sendable { case after, before }
nonisolated enum CentsDisplay: String, Codable, Sendable, CaseIterable { case whenPresent, always, never }
nonisolated struct FormatChoices: Codable, Sendable, Equatable {   // nil = как в регионе
    var date: DateStyle?; var firstWeekday: Int?; var separators: AmountSeparators?
    var symbol: AmountSymbolPosition?; var cents: CentsDisplay? }
nonisolated struct ResolvedFormats: Sendable, Equatable {
    var dateStyle: DateStyle; var firstWeekday: Int
    var decimalSeparator: String; var groupingSeparator: String; var secondaryGroupingSize: Int?
    var symbol: AmountSymbolPosition; var cents: CentsDisplay }
nonisolated enum FormatPreferences {
    static func resolve(_ choices: FormatChoices, locale: Locale) -> ResolvedFormats
    static func region(for locale: Locale) -> ResolvedFormats          // resolve(FormatChoices(), …)
    static func weekStartOptions(regionFirstWeekday: Int) -> [Int]       // [2, 1] + день региона
    static func separatorOptions(region: ResolvedFormats) -> [AmountSeparators] // 5 + .region
    static func symbolPosition(regionCode: String?) -> AmountSymbolPosition }
@MainActor @Observable final class FormatSettings {
    init(defaults: UserDefaults, locale: @escaping () -> Locale = { .current })
    private(set) var choices: FormatChoices; private(set) var resolved: ResolvedFormats
    private(set) var version: Int; var isCustomized: Bool       // resolved != region(for: locale())
    var onChange: ((ResolvedFormats) -> Void)?
    func set(_ edit: (inout FormatChoices) -> Void); func resetToRegion(); func regionDidChange()
    nonisolated static var snapshot: ResolvedFormats            // под замком, обновляется при каждом изменении;
                                                                // до первого экземпляра читает выбор из App Group сам
                                                                // (DesignKitBridge.configure() идёт раньше AppCoordinator)
    static let storageKey = "settings.formats"                  // JSON FormatChoices в group.dakacom.Tenra
}
nonisolated enum AppCalendar { static var current: Calendar }  // Calendar.current, firstWeekday из snapshot
```
Значения разделителей: `spaceComma` = (U+00A0, ","), `commaDot` = (",", "."), `dotComma` =
(".", ","), `apostropheDot` = (U+2019, "."), `spaceDot` = (U+00A0, "."). Пробел, U+00A0 и U+202F
при сравнении с регионом считаются одним «пробелом»; `.region` значит точные знаки и группировку
региона и предлагается, только когда регион не совпал ни с одним из пяти. Позиция символа
региона: вероятный язык региона (`Locale.Language(identifier: "und-<регион>").maximalIdentifier`),
валютный `NumberFormatter` для `<язык>_<регион>`, символ впереди, если `positiveFormat`
начинается с «¤». `regionDidChange()` подписан на `NSLocale.currentLocaleDidChangeNotification`;
`version` растёт только когда меняется `resolved`.

- [x] **Шаг 1. Тесты** `FormatPreferencesTests`:
  ```swift
  @Test func kazakhstanInRussian()   // region(ru_KZ) == ResolvedFormats(.words, 2, ",", "\u{00A0}", nil, .after, .whenPresent)
  @Test func englishInKazakhstanKeepsSymbolAfter() // region(en_KZ).symbol == .after
  @Test func unitedStates()          // region(en_US): firstWeekday 1, ".", ",", .before
  @Test func germany()               // region(de_DE): ",", ".", .after
  @Test func india()                 // region(en_IN).secondaryGroupingSize == 2; separatorOptions содержит .region
  @Test func franceNarrowSpaceIsSpace() // separatorOptions(region(fr_FR)) не содержит .region
  @Test func choiceStaysOthersFollowRegion() // choices.separators = .commaDot:
      // resolve(ru_KZ): ".", ",", firstWeekday 2; resolve(en_US): ".", ",", firstWeekday 1
  @Test func weekStartOptions()      // 2 → [2, 1]; 1 → [2, 1]; 7 → [2, 1, 7]
  ```
  `FormatSettingsTests` (`@MainActor`, `.sharedProcessState`, свой `UserDefaults(suiteName:)` на
  тест): `persistsChoices` (новый экземпляр читает выбор), `versionBumpsOnlyOnChange` (set того же
  значения не растит `version`), `customizedAndReset` (ru_KZ: сначала `false`; `.commaDot` →
  `true`; `resetToRegion()` → `false` и `choices == FormatChoices()`), `snapshotFollows`
  (`FormatSettings.snapshot == resolved` после `set`), `appCalendarUsesWeekStart`
  (`firstWeekday = 1` → `AppCalendar.current.firstWeekday == 1`).
- [x] **Шаг 2.** Красные. **Шаг 3.** Реализовать. **Шаг 4.** Оба сьюта зелёные, затем полный
  прогон (удалённые `AmountSeparatorsTests` не должны оставить ссылок).
- [x] **Шаг 5.** Коммит «feat(formats): region-resolved format preferences and their store».

### Задача 5 (Tenra): суммы и числа по выбранному формату

**Файлы:** `Tenra.xcodeproj/project.pbxproj` и `Package.resolved` (версия DesignKit),
`Tenra/Utils/DesignKitBridge.swift`, `Tenra/Utils/NumberDisplay.swift` (новый), места показа
процентов, ставок, курсов и площади; тесты `TenraTests/Utils/DesignKitBridgeFormatsTests.swift`,
`NumberDisplayTests.swift`.

**Даёт:** `DesignKitBridge.apply(_ formats: ResolvedFormats)` (разделители, вторичная
группировка, `symbolPosition`, `fractions`; хук дат добавит задача 6); `configure()` зовёт
`apply(FormatSettings.snapshot)`.
`nonisolated enum NumberDisplay { static func percent(_ percentValue: Double, fractionDigits: Int = 0, formats: ResolvedFormats = FormatSettings.snapshot) -> String; static func decimal(_ value: Double, fractionDigits: Int, formats: ResolvedFormats = FormatSettings.snapshot) -> String }`:
число с выбранными разделителями, процент без пробела, как сейчас «34%» (`percentValue` 34.2
значит 34,2%).

- [x] **Шаг 1.** Поднять DesignKit до 8.8.0: в `XCRemoteSwiftPackageReference "DesignKit"`
  `version = 8.8.0;`, затем `xcodebuild -resolvePackageDependencies -scheme Tenra` (или дождаться
  коммита workflow «DesignKit update»). Сборка зелёная.
- [x] **Шаг 2. Тесты:** `DesignKitBridgeFormatsTests` (`@MainActor`, `.sharedProcessState`,
  восстанавливает `AmountDisplayConfiguration()` после себя): `apply` с `ResolvedFormats`
  (разделители `commaDot`, символ `.before`, копейки `.never`) →
  `Formatting.formatCurrencySmart(1234.5, currency: "USD") == "$1,235"`.
  `NumberDisplayTests`: `percent(34.2, fractionDigits: 1, dotComma) == "34,2%"`,
  `percent(34.2) == "34%"` (spaceComma), `decimal(1234.5, fractionDigits: 2, commaDot) == "1,234.50"`.
- [x] **Шаг 3.** Красные; реализовать; зелёные.
- [x] **Шаг 4.** Перевести показ чисел на `NumberDisplay`: места из
  `grep -rnE 'String\(format: "%\.[0-9]f%%?"|\.formatted\(\.percent' Tenra --include='*.swift'`,
  кроме логов, CSV, контекста ИИ и ключей. В `InsightsService+Spending.shareOfSpendingSubtitle`
  процент тоже через `NumberDisplay.percent`. Полный прогон.
- [x] **Шаг 5.** Коммит «feat(formats): amounts and numbers in the chosen format».

### Задача 6 (Tenra): даты по выбранному стилю

**Файлы:** `Tenra/Utils/DateFormatters.swift`, места показа дат дня, `DesignKitBridge.apply`;
тест `TenraTests/Utils/DateDisplayStyleTests.swift`.

**Даёт:** `nonisolated static func day(_ date: Date, includeYear: Bool, style: DateStyle = FormatSettings.snapshot.dateStyle, locale: Locale = .current) -> String`
в `DateFormatters`: `words` берёт у шаблона `dMMMM` (`setLocalizedDateFormatFromTemplate`)
только порядок: день впереди → `d MMMM` / `d MMMM yyyy`, месяц впереди → `MMMM d` /
`MMMM d, yyyy` (так русский остаётся «3 ноября 2026» без «г.», как сейчас), `dots` `dd.MM` / `dd.MM.yyyy`, `slash`
`MM/dd` / `MM/dd/yyyy`, `iso` всегда `yyyy-MM-dd`; форматтеры в кэше по (стиль, год, локаль).
`displayDateOmittingCurrentYear` и `displayString(from:)` идут через `day`;
`displayDateFormatter` и `displayDateWithYearFormatter` удаляются после переноса вызовов.
`apply` ставит `DesignKitDateFormat.day = { DateFormatters.day($0, includeYear: $1) }`.

- [x] **Шаг 1. Тесты** (дата 2026-11-03, григорианский календарь, `Asia/Almaty`):
  ```swift
  @Test func wordsRussian()   // ru_KZ: "3 ноября", с годом "3 ноября 2026" 
  @Test func wordsUnitedStates() // en_US: "November 3", "November 3, 2026"
  @Test func dots()           // "03.11", "03.11.2026"
  @Test func slash()          // "11/03", "11/03/2026"
  @Test func isoAlwaysWithYear() // "2026-11-03" в обоих случаях
  ```
- [x] **Шаг 2–3.** Красные; реализовать.
- [x] **Шаг 4.** Перенести показ дат дня на `day(_:includeYear:)`: вызовы `displayDateFormatter`,
  `displayDateWithYearFormatter`, шаблоны `dMMM` и `dMMMyyyy` (`HistoryTransactionsList`),
  `"d MMM"` (`TimeFilter`), `.formatted(date: .long/.abbreviated, …)` и `dateStyle` в показе
  (список: `grep -rnE 'setLocalizedDateFormatFromTemplate|dateStyle =|formatted\(date:|\.dateTime' Tenra`).
  Не трогать: «месяц год», дни недели, подписи осей `MMM`, время, POSIX и разбор, имена файлов,
  `Debug/`. Полный прогон.
- [x] **Шаг 5.** Коммит «feat(formats): day dates in the chosen style».

### Задача 7 (Tenra): первый день недели везде

**Файлы:** `Tenra/Models/TimeFilter.swift`, `Tenra/Services/Categories/CategoryBudgetService.swift`,
`Tenra/Services/Notifications/WeeklyDigestScheduler.swift`, `Tenra/Models/InsightGranularity.swift`,
`Tenra/Services/Insights/InsightsService.swift`, `InsightsService+Spending.swift`,
`Tenra/Views/Insights/SpendingByDaySection.swift`, `InsightDetailView.swift`,
`Tenra/Views/Components/Cards/InsightsCardView.swift`,
`Tenra/Views/Components/Charts/PeriodChartAdapters.swift`,
`Tenra/Services/Intents/SpendingQueryService.swift`, `Tenra/Services/Agent/FinanceToolkit.swift`,
`FinanceToolkitCompute.swift`, `AgentContextBuilder.swift`,
`Tenra/Views/Components/Input/SubscriptionCalendarView.swift`, `Tenra/Views/Home/MainTabView.swift`;
тест `TenraTests/Models/WeekStartTests.swift`.

**Даёт:** `TimeFilter.dateRange(now: Date = Date(), calendar: Calendar = AppCalendar.current)`
(«Эта неделя» через `calendar.dateInterval(of: .weekOfYear, for: now)`, без жёсткого
понедельника); `CategoryBudgetService.weeklyPeriod(now:calendar:)` (internal static);
`WeeklyDigestScheduler.nextFireDate(after: Date, calendar: Calendar) -> Date?` (первый день недели
календаря, 9:00). В остальных файлах недельная арифметика берёт `AppCalendar.current` вместо
`Calendar.current`; `CalendarRange(calendar: AppCalendar.current)` в календаре подписок;
`.environment(\.calendar, AppCalendar.current)` на `MainTabView` (с `formatSettings.version` в
зависимостях, задача 8).

- [x] **Шаг 1. Тесты** (`Asia/Almaty`; «воскресный» календарь `firstWeekday = 1`, «понедельничный» `2`):
  ```swift
  @Test func thisWeekFromSunday()   // now вс 2026-11-08 10:00: start 2026-11-08 00:00, end 2026-11-15
  @Test func thisWeekFromMonday()   // то же now: start 2026-11-02 00:00
  @Test func weeklyBudgetFromSunday() // weeklyPeriod: start 2026-11-08
  @Test func digestOnSunday()       // after чт 2026-11-05 12:00: 2026-11-08 09:00
  @Test func digestOnMonday()       // after тот же момент: 2026-11-09 09:00
  ```
- [x] **Шаг 2–3.** Красные; реализовать, потом заменить недельный `Calendar.current` в списке
  файлов (`grep -nE 'weekOfYear|yearForWeekOfYear|firstWeekday|\.weekday' …`).
- [x] **Шаг 4.** Полный прогон (в том числе `InsightGranularity` и бюджеты).
- [x] **Шаг 5.** Коммит «feat(formats): one first day of the week for everything weekly».

### Задача 8 (Tenra): экран «Форматы», подключение и обновление без перезапуска

**Файлы:** `Tenra/Views/Settings/FormatsSettingsView.swift` (новый),
`Tenra/Views/Settings/SettingsGeneralSection.swift`, `Tenra/ViewModels/AppCoordinator.swift`,
`Tenra/TenraApp.swift` или `MainTabView.swift` (окружение), `Tenra/Views/Home/TabViews.swift`
(корни вкладок), 12 `Localizable.strings`; тест `TenraUITests/FormatsUITests.swift`.

**Даёт:** `AppCoordinator.formatSettings: FormatSettings` (App Group defaults), в окружении.
`onChange` в координаторе: `DesignKitBridge.apply`, `insightsViewModel.invalidateAndRecompute()`,
запись снимка виджета и `WidgetCenter.shared.reloadAllTimelines()`, пересборка уведомлений
(недельная сводка, подписки `rescheduleAllActiveSubscriptions`, сигналы аналитики).
Корень каждой вкладки внутри её `NavigationStack` получает `.id(formatSettings.version)`, сам
стек нет, чтобы открытые экраны остались.

- [x] **Шаг 1.** Строки (ключи, en): `settings.formats` «Formats»; `formats.preview` «How it will
  look»; `formats.section.dates` «Dates»; `formats.section.amounts` «Amounts»; `formats.date`
  «Date»; `formats.weekStart` «First day of the week»; `formats.separators` «Separators»;
  `formats.symbol` «Currency symbol»; `formats.symbol.after` «After the number»;
  `formats.symbol.before` «Before the number»; `formats.cents` «Cents»; `formats.cents.whenPresent`
  «If any»; `formats.cents.always` «Always»; `formats.cents.never` «Never»; `formats.footer`
  «Your region's format is picked first (now %@). CSV export and your saved data don't change.»;
  `formats.reset` «Use the region's format». Русский по макету («Копейки», «Если есть»,
  «Вернуть формат региона»), остальные 10 языков по смыслу; паритет ключей проверить `diff`.
- [x] **Шаг 2. UI-тест** `FormatsUITests` (`-ScreenshotDemo -NoRevenueCat`, только Simulator):
  Главная → шестерёнка → «Formats» → «Separators» → «1,234.56»; на экране остаётся заголовок
  «Formats» (стек не сброшен); назад дважды; на Главной есть текст по `\d,\d{3}`. Красный.
- [x] **Шаг 3.** `FormatsSettingsView` по макету: превью (`FormSection` с датой
  `DateFormatters.day`, тремя строками операций на компонентах DesignKit с
  `FormattedAmountText`, полосой дней недели из `AppCalendar.current.shortWeekdaySymbols` от
  первого дня), секции «Даты» и «Суммы» из `UniversalRow(…, accessory: .picker(binding, options:))`
  (метка варианта: образец, у копеек «Если есть (1 234 и 1 234,50)»), подпись с названием
  региона, кнопка сброса при `isCustomized` (кнопка DesignKit, как на других страницах
  Настроек). Привязка: чтение из `resolved`, запись `set { $0.<поле> = value }`. Строка
  «Форматы» в `SettingsGeneralSection` между базовой валютой и фоном, `.navigation`. Подключение в
  `AppCoordinator` и `.id` на корнях вкладок.
- [x] **Шаг 4.** UI-тест зелёный (`-parallel-testing-enabled NO`), полный прогон юнит-тестов,
  `design_lint.py`, `section_rows_lint.py`. `#Preview` в новом файле получают все
  `@Environment`, которые читает вид. В чек-лист проверки на телефоне (`release-notes.md`):
  VoiceOver читает «1’234.56» и «1.234,56» как числа, виджет в новом формате.
- [x] **Шаг 5.** Коммит «feat(formats): Formats page in Settings».

### Задача 9 (Tenra): виджет

**Файлы:** `Tenra/Services/Widgets/WidgetSnapshot.swift`, `TenraWidgets/WidgetData.swift`; тест
в `TenraTests` рядом с `WidgetSnapshotTests`.

**Даёт:** `WidgetSnapshot.Formats: Codable, Equatable { var decimal: String; var grouping: String; var symbolBefore: Bool; var cents: String; var dateStyle: String }`,
поле `formats: Formats?` (старый снимок без него читается, виджет тогда форматирует как
система). `WidgetData.money` строит сумму из этих полей (те же правила, что задача 1), а
`horizonLine` дату: `words` как сейчас, остальные числом без года.

- [ ] **Шаг 1. Тест:** ключи JSON `formats`, `decimal`, `grouping`, `symbolBefore`, `cents`,
  `dateStyle` (как `WidgetSnapshotTests` закрепляет остальные); снимок без `formats`
  декодируется. **Шаг 2–4.** Красный, реализация, зелёный.
- [ ] **Шаг 5.** Коммит «feat(widget): the chosen formats». Вид виджета владелец проверяет на
  телефоне (у тестов нет доступа к цели виджета).

### Задача 10 (Tenra и сервер): даты в ответах Тэна

**Файлы:** `Tenra/Services/Agent/AgentContextBuilder.swift`, `server/assistant/src/prompt.ts`,
тесты `TenraTests/Services/Agent/AgentProtocolTests.swift` (или соседний сьют контекста) и
`server/assistant/test/` (vitest).

**Даёт:** строка `date_format: <DateFormatters.day(2026-11-03, includeYear: true)>` в
`<app_context>`; в промпте правило: дату в тексте писать так, как показывает `date_format`.
Образец суммы не нужен: промпт уже запрещает цифры денег в тексте, суммы показывают карточки,
а они следуют настройкам.

- [ ] **Шаг 1. Тесты:** контекст со стилем `dots` содержит `date_format: 03.11.2026`; vitest:
  промпт содержит `date_format`. **Шаг 2–4.** Красные, реализация, зелёные (`npm test` в
  `server/assistant`).
- [ ] **Шаг 5.** Коммит «feat(assistant): Ten writes dates in the chosen format». Выкатка
  Worker по [domains/assistant.md](domains/assistant.md) §12.

### Задача 11 (Tenra): кэши отформатированного текста и документы

**Файлы:** находки из
`grep -rln 'formatCurrencySmart\|DateFormatters\.\|NumberDisplay\.' Tenra/ViewModels Tenra/Services`
(13 файлов на 2026-11-05), `docs/`.

- [ ] **Шаг 1.** Для каждого места, где отформатированная строка хранится дольше одного вызова
  (`Insight.metric.formattedValue`, подписи, тексты входящих Тэна, заголовки секций истории),
  убедиться, что `onChange` её пересобирает, или добавить `FormatSettings.version` в ключ.
  Тест на одно хранимое место: после смены разделителей `formattedValue` у инсайта
  «Топ категория» с новым знаком.
- [ ] **Шаг 2.** Документы: `docs/design-system.md` §5 (раздел «Separators» становится
  «Formats»: `FormatSettings`, `DateFormatters.day`, `NumberDisplay`, `AppCalendar`),
  `docs/domains/insights.md` (недели по `AppCalendar`), `docs/domains/intents.md` («эта неделя»),
  `docs/domains/assistant.md` (`date_format`), `docs/release-notes.md` (What's New во всех 14
  блоках), статус этого файла, строка в `docs/README.md`; план целиком в `docs/archive/plans/`.
- [ ] **Шаг 3.** Полный прогон, линты; коммит «feat(formats): refresh cached text, docs».
