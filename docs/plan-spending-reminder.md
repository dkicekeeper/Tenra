# План: вечернее напоминание о тратах от Тэна

> Статус: дизайн утверждён основателем 2026-11-05 (вопросы проверки в §6). **В main с 2026-11-05:** задачи 1-5 §7, тесты зелёные (полный прогон 1619/1619 при 10 пропущенных), «Что нового» в [release-notes.md](release-notes.md). После итоговой проверки (с исправлениями: склейка перестановок, id по дням и снятие напоминания дня сразу, прослойка центра уведомлений, отложенное нажатие при живом процессе, метка по разрешению iOS, демо скриншотов) полный прогон зелёный: 1631 тест, 10 пропущены. Дальше: проверка на телефоне, App Privacy (основатель), выпуск, через две недели после выхода сравнение удержания по метке. Когда выйдет, план уходит в `archive/plans/`. Решения основателя помечены «(основатель)»,
> остальное решения ассистента «(решение ассистента)», их можно поменять при чтении.

## 1. Зачем

После запуска Apple Ads 80% новых пользователей открывают Tenra один раз и больше не возвращаются
(когорта KZ 30.10-01.11, [promotion-plan.md](promotion-plan.md) §6). Проход первого запуска 04.11
([backlog.md](backlog.md) «First run») показал главную причину: человека, который ведёт учёт
вручную, ничто не зовёт назад. Уведомления сейчас только тихие (provisional: недельная сводка и
сигналы лежат в Центре уведомлений без баннера), напоминания о тратах нет, автозапись Wallet
требует 8 шагов в «Командах». Без второго дня нет ни привычки, ни пробного периода (0 из 186).

Успех: заметно больше новых пользователей открывают Tenra на 2-й и 7-й день (RevenueCat
`last_seen_at`, App Analytics, удержание D1 и D7 в §6 плана продвижения), и через это пробные
периоды перестают быть нулём.

## 2. Что строим

**Вечернее напоминание от Тэна в те дни, когда в Tenra ничего не записано.** Короткая, лёгкая,
каждый раз новая фраза с картинкой Тэна. По нажатию открывается запись траты. Если человек не
реагирует, Тэн пишет реже, а через неделю тишины прощается и молчит до возвращения. Включается
только по согласию: Тэн спрашивает на Главной после первой записанной траты.

### Цели
- Вернуть человека на второй и следующие дни, пока привычка не сложилась.
- Тон Тэна: ровный, милый, с шутками, без фамильярности и без давления (основатель).
- Ноль раздражения: не беспокоить в дни, когда уже записано, и не долбить молчащих.

### Не цели
- Не маркетинговые пуши (скидки, Pro, «вернитесь»): только про сегодняшние траты.
- Не замена сигналов аналитики и недельной сводки: они остаются как есть.
- Не серверные пуши: всё локально на телефоне, как остальные уведомления Tenra.

### Анти-цели (провал, даже если работает)
- Чувство вины или упрёк («вы опять не записали!»), красные восклицания, стрелки.
- Пуш в день, когда человек уже записал трату (вручную или через автозапись).
- Пуш каждый день навсегда тому, кто давно не открывает приложение.
- Системный запрос разрешения без объяснения, при первом запуске или в онбординге.

## 3. Как ведёт себя

### 3.1 Когда приходит
- **Вечером, по умолчанию в 20:00** (основатель), время можно поменять в Настройках.
- **Только если сегодня ничего не записано** (основатель): ни одной операции, созданной сегодня
  (`Transaction.createdAt` в сегодняшнем дне), вручную, через Тэна, автозаписью Apple Pay,
  уведомлением банка или импортом. Операции регулярных платежей (`recurringSeriesId != nil`),
  которые Tenra создаёт сама, не считаются записью человека (решение ассистента). Дата операции
  не важна: записал вчерашнюю покупку сегодня, значит, сегодня записывал (решение ассистента).
- Если в момент записи траты на сегодня стоит напоминание, оно снимается сразу, в том числе когда
  запись приходит из автозаписи в фоне (`LogWalletPaymentIntent`, уведомления банка).

### 3.2 Если человек не реагирует (основатель)
«Реакция» значит, что человек открыл Tenra (по пушу или сам) или записал операцию в самом
приложении. Запись в фоне (автозапись Apple Pay, уведомления банка) снимает напоминание этого дня,
но реакцией не считается и расписание не сбрасывает: иначе тот, кто давно не открывает Tenra, но
у кого работает автозапись, получал бы пуши в каждый день без покупок бесконечно (анти-цель)
(решение ассистента). От последней реакции, день 0 (решение ассистента по точным дням):
- дни 1, 2, 3: каждый вечер, если в этот день ничего не записано;
- дни 5 и 7: реже, через день;
- день 10: последнее мягкое сообщение «я тут, если понадоблюсь», с другой картинкой Тэна;
- дальше тишина, пока человек сам не откроет Tenra; тогда расписание начинается заново.
- В день 0 (человек открыл Tenra, но ничего не записал) вечернее напоминание тоже приходит, если
  время ещё не прошло.

Так как iOS не будит приложение в 20:00, напоминания на весь этот ряд ставятся заранее
(не больше 7 штук) и переставляются при каждом открытии Tenra, записи операции и смене
настройки, по образцу `StatementImportReminder` (решение ассистента).

### 3.3 Что пишет Тэн (основатель)
- Все пуши от имени Тэна: с его картинкой (`TenNotificationArt`), спокойное или весёлое
  настроение, на прощании другое (решение ассистента: `.happy` в обычные дни, `.idle` на
  прощании).
- Одна-две строки. Набор фраз чередуется, подряд одна и та же не приходит (решение ассистента:
  8-10 обычных фраз на язык и 2-3 прощальных; выбор без повтора последних 3).
- Примеры, одобренные основателем: «Тэн тут подумал: сегодня ни одной траты? Подозрительно 🙂»,
  «Минутка для денег: что сегодня купили?». Фразы для 12 языков пишутся как адаптация, а не
  дословный перевод: шутка должна работать на каждом языке. Без длинных тире (правило проекта).
- Иногда крючок из своих данных: вчерашняя категория трат, **без суммы** (основатель, 2026-11-05:
  текст виден на экране блокировки, как у «Проверить оплату»): «Вчера было кафе. А сегодня?».
  Поэтому от «скрытия сумм» текст не зависит. Пуши ставятся заранее, поэтому крючок возможен только в первом напоминании после дня с
  записями (день 1); дальше в ряду предыдущий день всегда пустой, там обычные фразы.
- Заголовок пуша пустой или «Тэн»: решает разработчик по тому, как это смотрится на экране
  блокировки (приложение и так подписано «Tenra»).

### 3.4 Нажатие на пуш
Открывает запись траты: тот же путь, что `tenra://add` (`AppCoordinator.handleDeepLink` →
`pendingQuickAdd` без категории): Тэн (поле ввода в фокусе, если это просто), а где Тэна нет,
Главная. Холодный запуск обрабатывается так же, как у пушей подписок
(`pendingDeepLinkSeriesIdOnLaunch`) (решение ассистента).

### 3.5 Согласие (основатель)
- **Новый пользователь:** сразу после первой сохранённой операции Тэн спрашивает «Напомнить
  вечером, если день пройдёт без записей?» с кнопкой «Напоминать» и ✕ **там, где операция
  сохранена** (основатель, 2026-11-05): записал в чате Тэна, значит, карточкой в чате, сразу под
  сохранённым черновиком (исключение из правила «сообщения Тэна только на Главной»); записал
  формой на Главной, значит, сообщением на Главной. Ответ в одном месте снимает вопрос в другом.
- «Напоминать» включает напоминание и показывает системный запрос iOS (полное разрешение, не
  provisional; из provisional iOS запрос показывает, см. `NotificationPermissionManager`). Если
  человек отказал в системном запросе, напоминание остаётся включённым в Настройках, а там
  строка «включите уведомления в настройках iOS», как у сигналов.
- ✕ значит «не сейчас»: Тэн больше не спрашивает, включить можно в Настройках.
- **Те, у кого Tenra уже стоит:** один раз то же сообщение на Главной (если у них есть хотя бы
  одна операция).
- Сообщение не появляется, если напоминание уже включено (например, в Настройках).
- Как выглядит: одна карточка Тэна для обоих мест, DesignKit `NoticeCard` с живым Тэном слева,
  как у сообщений Тэна (`AssistantNoticeCard`). На Главной она стоит среди карточек настройки
  (`ContentView.setupCards`, первой), а не в очереди сообщений Тэна: там показывается одно
  непрочитанное сообщение и только где Тэн доступен, предложение могло бы потеряться (решение
  ассистента, 2026-11-05, вместо нового вида `AssistantNotice`).

### 3.6 Настройки
В Настройках, раздел уведомлений (`SettingsView.notificationsSection`), рядом с «Сигналы
аналитики»: строка «Напоминание о тратах» с переключателем и временем (решение ассистента:
отдельная страница с переключателем, выбором времени и пояснением «только в дни без записей»).
Включение переключателя в Настройках просит полное разрешение, как у сигналов.
По умолчанию выключено, пока человек не согласится (основатель: опт-ин).

### 3.7 Замер (основатель, 2026-11-05)
Анонимная метка в RevenueCat, атрибут `spending_reminder`: `on`, `off` (выключил в Настройках),
`declined` (✕ на предложении), `denied` (согласился, но отказал в системном запросе iOS);
нет атрибута, значит, ещё не спрашивали. Пишется при каждом изменении через `PremiumManager`
(только он импортирует RevenueCat), по образцу `paywall_source` (решение ассистента по значениям).
Через две недели удержание D1 и D7 сравнивается по этой метке в RevenueCat (§6 плана
продвижения). Основатель обновляет ответы App Privacy в App Store Connect: данные о
взаимодействии с продуктом, не связаны с личностью, не для отслеживания (через API ASC это не
меняется).

### 3.8 Бесплатно
Для всех, включая бесплатных (решение ассистента: это удержание, а не функция Pro; Pro
продаётся тем, кто остался).

## 4. Ограничения
- Локальные уведомления, `UNCalendarNotificationTrigger` без повтора; общий лимит iOS 64
  ожидающих на приложение делят все отправители Tenra.
- Идентификаторы с префиксом `spendingReminder_`; тап маршрутизирует `AppDelegate`.
- Строки во всех 12 локалях (`Tenra/*.lproj/Localizable.strings`, правило 13 CLAUDE.md), без
  длинных тире; суммы, если будут, через канонический форматтер.
- Тесты чистой логики (расписание по дням реакции, пропуск дня с записью, исключение регулярных,
  выбор фразы без повтора) по образцу `StatementImportReminder.reminderDates`; ожидания в тестах
  считают опросы, не время (правило Testing).
- Документы в том же коммите: [domains/insights.md](domains/insights.md) §Signal notifications
  (новый отправитель), `docs/release-notes.md` следующей версии (видимое изменение), этот план и
  [promotion-plan.md](promotion-plan.md) §7.

## 5. Что оставлено разработчику
Имена типов и файлов (по дереву решений CLAUDE.md: сервис в `Services/Notifications/`), где именно
снимать сегодняшнее напоминание при записи (одна точка у `TransactionStore` или у каждого пути
записи), вид страницы настроек на компонентах DesignKit, точная вёрстка сообщения на Главной.

## 6. Решено основателем после проверки дизайна (2026-11-05)
1. Предложение напоминания появляется там, где сохранена первая операция, в том числе карточкой
   в чате Тэна (§3.5).
2. Во «вчерашнем» крючке категория без суммы (§3.3).
3. Замер: анонимная метка `spending_reminder` в RevenueCat и обновление App Privacy (§3.7).

---

## 7. План реализации

> **Для исполнителя:** superpowers:executing-plans (или subagent-driven-development), задачи по
> порядку, шаги с чекбоксами.

**Цель:** вечернее напоминание Тэна в дни без записей, с затуханием, предложением после первой
операции, настройкой и меткой в RevenueCat.

**Архитектура:** чистое ядро `SpendingReminderPlan` (какие напоминания и когда, какой текст)
без UIKit и UserDefaults, под тестами; сервис `SpendingReminder` по образцу
`StatementImportReminder` хранит состояние в UserDefaults и переставляет ожидающие уведомления;
`TransactionStore` сообщает о каждой добавленной операции через замыкание, которое ставит
`AppCoordinator`, поэтому фоновые записи интентов (у них свой `AppCoordinator` через
`IntentEnvironment`) снимают напоминание дня так же, как записи в приложении.

**Стек:** Swift, SwiftUI, UserNotifications, swift-testing, DesignKit (`NoticeCard`,
`ParticleCreature`, `FormSection`, `UniversalRow`), RevenueCat только в `PremiumManager`.

**Дизайн:** §1-6 этого файла.

### Глобальные ограничения
- Строки во всех 12 локалях (en, ru, de, es, fr, tr, pt-BR, it, uk, ja, ko, kk), паритет ключей
  проверяется `diff` из CLAUDE.md; правка через `python3` с `encoding="utf-8"`, не `perl -CSD`;
  без длинных тире; специфаторы `%@` без перестановки (один аргумент).
- Имя Тэна: Ten (en, de, es, fr, tr, pt-BR, it), Тэн (ru, kk), Тен (uk), テン (ja), 텐 (ko).
- Ни одной суммы в тексте пуша.
- Идентификаторы уведомлений `spendingReminder_<n>`, `threadIdentifier` `spendingReminder`.
- Время по умолчанию 20:00, выключено по умолчанию.
- Ряд дней от последней реакции: обычные `[0, 1, 2, 3, 5, 7]`, прощание `10`.
- Фраз: 8 обычных, 2 прощальных, 1 с крючком (`%@` = название категории в кавычках «»).
- Тесты: suite `@MainActor` там, где строятся MainActor-типы; ожидания по счёту опросов;
  `-only-testing` на уровне suite (имя типа).
- В тот же коммит документы: §8 ниже.

### Внимание при проверке (что тесты задач не покрывают сами по себе)
1. Черновик, сохранённый в чате Тэна (FastPath или ответ модели), снимает напоминание дня: он
   идёт через `TransactionStore.add`; проверить на телефоне, тест задачи 3 пинит замыкание.
2. Импорт старой выписки сегодня считается записью сегодня (`createdAt` сегодня): тест задачи 1.
3. Отказ в системном запросе после «Напоминать»: ничего не планируется, метка `denied`, в
   Настройках строка про настройки iOS: тест задачи 2 на `reschedule` без разрешения.
4. Фоновая автозапись не сдвигает `lastReaction`: тест задачи 2.
5. Отказ (✕) переживает перезапуск, предложение больше не показывается: тест задачи 2.

---

### Задача 1: чистое ядро `SpendingReminderPlan`

**Файлы:**
- Создать: `Tenra/Services/Notifications/SpendingReminderPlan.swift`
- Тест: `TenraTests/Services/Notifications/SpendingReminderPlanTests.swift`

**Интерфейсы (производит):**
```swift
nonisolated enum SpendingReminderPlan {
    static let regularDayOffsets = [0, 1, 2, 3, 5, 7]
    static let farewellDayOffset = 10
    static let regularPhraseCount = 8
    static let farewellPhraseCount = 2

    struct Hook: Equatable, Sendable { let category: String; let day: Date }
    enum Phrase: Equatable, Sendable { case regular(Int), hook(String), farewell(Int) }  // индексы с 1
    struct Reminder: Equatable, Sendable { let date: Date; let phrase: Phrase }

    /// Напоминания после последней реакции, только будущие, без дня с записью.
    static func reminders(lastReaction: Date, lastRecorded: Date?, hook: Hook?, now: Date,
                          hour: Int, minute: Int, calendar: Calendar = .current) -> [Reminder]
    /// Номер фразы дня: соседние дни разные, повтор не раньше чем через `count` дней.
    static func phraseIndex(for day: Date, count: Int, calendar: Calendar = .current) -> Int  // 1...count
    /// Операция, записанная человеком сегодня: createdAt в сегодняшнем дне, не регулярная и не
    /// проценты по вкладу (их пишет сверка при запуске). Новая регулярная серия тоже запись дня:
    /// `SpendingReminder.noteSeriesCreated` через `TransactionStore.onSeriesCreated`.
    static func isUserRecord(_ tx: Transaction, now: Date, calendar: Calendar = .current) -> Bool
    /// Крючок из записанных сейчас операций: категория последнего по createdAt расхода (.expense).
    static func hook(from transactions: [Transaction], now: Date, calendar: Calendar = .current) -> Hook?
}
```
`phraseIndex`: номер дня от `calendar.startOfDay` эпохи (`Date(timeIntervalSinceReferenceDate: 0)`)
по модулю `count`, плюс 1. Крючок только у напоминания, чей день на 1 позже `hook.day`; иначе
`.regular(phraseIndex)`. У прощания `.farewell(phraseIndex(count: farewellPhraseCount))`.

- [x] **Шаг 1: тесты (падают).** `SpendingReminderPlanTests` (`@Suite`, календарь
  `Calendar(identifier: .gregorian)` с `TimeZone(identifier: "Asia/Almaty")`):
  - `freshReactionGivesFullSeries`: реакция и `now` 5.11 10:00, записей нет → 7 напоминаний на
    5, 6, 7, 8, 10, 12, 15.11 в 20:00; последнее `.farewell`, остальные не `.farewell`.
  - `recordedTodaySkipsTonight`: `lastRecorded` 5.11 12:00 → первое напоминание 6.11, всего 6.
  - `pastTimeSkipsTonight`: `now` 5.11 20:30 → первое 6.11.
  - `oldReactionKeepsOnlyTheTail`: реакция 1.11, `now` 5.11 10:00 → 6.11 (день 5), 8.11 (день 7),
    11.11 (день 10, прощание).
  - `silentAfterFarewell`: реакция 1.11, `now` 12.11 → `[]`.
  - `hookOnlyTheNextDay`: `hook` (Кафе, 5.11), реакция 5.11, `lastRecorded` 5.11 → напоминание
    6.11 `.hook("Кафе")`, у 7.11 и дальше не `.hook`.
  - `customTimeRespected`: 21:30 → все `date` в 21:30.
  - `phrasesDifferOnNeighbourDays`: 8 дней подряд дают 8 разных `phraseIndex(count: 8)` в 1...8.
  - `userRecordExcludesRecurringAndOldCreation`: `createdAt` сегодня → true; с
    `recurringSeriesId` → false; `createdAt` вчера, дата сегодня → false; `createdAt` сегодня,
    дата прошлого месяца → true.
  - `hookTakesLatestExpense`: доход и два расхода сегодня → категория последнего расхода; только
    доходы → nil.
- [x] **Шаг 2:** прогон suite, ожидается FAIL (тип не найден):
  `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/SpendingReminderPlanTests`
- [x] **Шаг 3:** реализовать `SpendingReminderPlan` по интерфейсу.
- [x] **Шаг 4:** прогон, PASS; счёт тестов из `xcresulttool get test-results summary` (10).
- [x] **Шаг 5:** коммит `feat(reminder): spending reminder plan core`.

### Задача 2: сервис `SpendingReminder` и метка RevenueCat

**Файлы:**
- Создать: `Tenra/Services/Notifications/SpendingReminder.swift`
- Изменить: `Tenra/Services/Premium/PremiumManager.swift` (рядом с `notePaywallShown`)
- Тест: `TenraTests/Services/Notifications/SpendingReminderTests.swift`

**Интерфейсы:**
- Потребляет: `SpendingReminderPlan` (задача 1), `TenNotificationArt.attachment(mood:)`,
  `NotificationPermissionManager.shared.requestAuthorization() async -> Bool`.
- Производит:
```swift
@MainActor enum SpendingReminder {
    static let identifierPrefix = "spendingReminder_"
    nonisolated static let enabledKey = "settings.spendingReminder.enabled"   // Bool, false
    nonisolated static let minutesKey = "settings.spendingReminder.minutes"   // Int, 1200 = 20:00
    nonisolated static let offerKey = "spendingReminder.offer"                // OfferState.rawValue
    enum OfferState: String { case notAsked, accepted, declined }
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool
    static func minutes(defaults: UserDefaults = .standard) -> Int
    static func offerState(defaults: UserDefaults = .standard) -> OfferState
    static func shouldOffer(hasRecords: Bool, defaults: UserDefaults = .standard) -> Bool
    static func noteAppOpened(now: Date = Date(), defaults: UserDefaults = .standard)
    static func noteRecorded(_ transactions: [Transaction], now: Date = Date(), defaults: UserDefaults = .standard)
    static func acceptOffer() async          // accepted, enabled, полный запрос; denied → метка
    static func declineOffer(defaults: UserDefaults = .standard)
    static func setEnabled(_ on: Bool, defaults: UserDefaults = .standard) async  // из Настроек; on при notAsked ставит accepted
    static func reschedule(now: Date = Date(), defaults: UserDefaults = .standard) async
}
// PremiumManager
func noteSpendingReminder(_ value: String)   // "on" | "off" | "declined" | "denied", атрибут "spending_reminder"
```
Внутренние ключи: `spendingReminder.lastReaction`, `.lastRecorded`, `.hookCategory`,
`.hookDay`. `noteAppOpened` пишет `lastReaction` и вызывает `reschedule`; `noteRecorded` фильтрует
`isUserRecord`, при наличии пишет `lastRecorded` и крючок, `lastReaction` не трогает,
`reschedule`. `reschedule` снимает все ожидающие с префиксом; выключено или нет разрешения
(`authorized`/`provisional`) → выходит; иначе ставит `reminders(...)`: заголовок
`spendingReminder.notification.title`, тело по `Phrase` (`spendingReminder.phrase.<n>`,
`spendingReminder.hook` c `%@`, `spendingReminder.farewell.<n>`), вложение Тэна `.happy`
(обычные) и `.idle` (прощание), `UNCalendarNotificationTrigger(repeats: false)`.
`shouldOffer` = `hasRecords && offerState == .notAsked && !isEnabled`.

- [x] **Шаг 1: тесты (падают).** `SpendingReminderTests` (`@MainActor`, свой `UserDefaults(suiteName:)`
  на тест, без центра уведомлений: проверяются ключи):
  - `offeredOnceAfterFirstRecord`: `shouldOffer(hasRecords: false)` false; true при записях;
    после `declineOffer` false и после пересоздания `UserDefaults` с тем же suite тоже false.
  - `enabledHidesOffer`: `enabledKey` true → `shouldOffer` false.
  - `backgroundRecordKeepsReaction`: `noteAppOpened(now: 1.11)`, затем `noteRecorded([tx сегодня], now: 5.11)`
    → `lastReaction` остаётся 1.11, `lastRecorded` 5.11.
  - `recurringRecordIgnored`: `noteRecorded([tx с recurringSeriesId])` не пишет `lastRecorded`.
  - `defaultsAreOffAt20`: пустые defaults → `isEnabled` false, `minutes` 1200, `offerState` `.notAsked`.
- [x] **Шаг 2:** прогон suite, FAIL.
- [x] **Шаг 3:** реализовать `SpendingReminder` и `PremiumManager.noteSpendingReminder`
  (`guard isConfigured`, как `notePaywallShown`); `acceptOffer`, `declineOffer`, `setEnabled`
  зовут `noteSpendingReminder`.
- [x] **Шаг 4:** прогон, PASS (5 тестов).
- [x] **Шаг 5:** коммит `feat(reminder): spending reminder service and RevenueCat attribute`.

### Задача 3: подключение (запись, открытие, нажатие)

**Файлы:**
- Изменить: `Tenra/ViewModels/TransactionStore.swift` (`apply`, шаг после `updateState`)
- Изменить: `Tenra/ViewModels/AppCoordinator.swift` (init: замыкание; стэш холодного запуска)
- Изменить: `Tenra/Views/Home/MainTabView.swift` (scenePhase `.active`; приём тапа)
- Изменить: `Tenra/AppDelegate.swift` (`didReceive`)
- Изменить: `Tenra/Extensions/Notification+Extensions.swift` (`.spendingReminderTapped`)
- Тест: `TenraTests/Services/Notifications/SpendingReminderWiringTests.swift`

**Интерфейсы:**
- Производит: `TransactionStore.onRecorded: (([Transaction]) -> Void)?` (`@ObservationIgnored`),
  вызывается в `apply` для `.added(tx)` → `[tx]` и `.bulkAdded(txs)` → `txs` (после фильтра
  дублей); `AppCoordinator.pendingQuickAddOnLaunch: QuickAdd?` (static, как
  `pendingDeepLinkSeriesIdOnLaunch`).
- Потребляет: `SpendingReminder.noteRecorded`, `.noteAppOpened` (задача 2),
  `AppCoordinator.handleDeepLink(URL(string: "tenra://add")!)`.

- [x] **Шаг 1: тест (падает).** `SpendingReminderWiringTests` (`@MainActor`, `.sharedProcessState`,
  store на in-memory репозитории, как в соседних тестах `TransactionStore`; store удерживается):
  `addCallsOnRecorded` (один `add` → замыкание получило эту операцию),
  `bulkAddPassesOnlyFresh` (повторный `addBatch` тех же id → замыкание не вызвано).
- [x] **Шаг 2:** прогон, FAIL.
- [x] **Шаг 3:** `onRecorded` в `apply`; в `AppCoordinator.init` `transactionStore.onRecorded = { SpendingReminder.noteRecorded($0) }`;
  в `MainTabView` при `.active` рядом с `StatementImportReminder.reschedule()` вызвать
  `SpendingReminder.noteAppOpened()`; в `AppDelegate` префикс `spendingReminder_` → стэш
  `pendingQuickAddOnLaunch = QuickAdd(category: nil)` и post `.spendingReminderTapped`;
  `MainTabView.onReceive(.spendingReminderTapped)` → `coordinator.handleDeepLink(tenra://add)`;
  init координатора забирает стэш в `pendingQuickAdd`.
- [x] **Шаг 4:** прогон, PASS; сборка `generic/platform=iOS Simulator` без ошибок.
- [x] **Шаг 5:** коммит `feat(reminder): wire records, app opens and taps`.

### Задача 4: предложение Тэна (Главная и чат) и строки

**Файлы:**
- Создать: `Tenra/Views/Components/Cards/SpendingReminderOfferCard.swift`
- Изменить: `Tenra/Views/Home/ContentView.swift` (`setupCards`, первой)
- Изменить: `Tenra/Views/Assistant/AssistantChatView.swift` (после `turnFooter`)
- Изменить: 12 × `Tenra/<locale>.lproj/Localizable.strings`

**Интерфейсы:**
- Производит: `struct SpendingReminderOfferCard: View { let onAccept: () -> Void; let onDecline: () -> Void }`
  (адаптер над `NoticeCard`, слева `ParticleCreature(mood: .happy, style: .compact)` в
  `NoticeCardMetrics.leadingSize`, кнопка с `bell`, ✕ с `assistant.notice.hide`).
- Потребляет: `SpendingReminder.shouldOffer`, `.acceptOffer()`, `.declineOffer()`.

Показ: на Главной при `coordinator.isFullyInitialized && SpendingReminder.shouldOffer(hasRecords: store.transactionsCount > 0)`;
в чате при том же условии и если `transactionsCount` вырос с момента открытия чата (запомнить в
`.onAppear`). Наблюдение за ответом через `@AppStorage(SpendingReminder.offerKey)` и
`@AppStorage(SpendingReminder.enabledKey)`, чтобы ответ в одном месте снимал карточку в другом.
Время в тексте: `minutes` в формате `Date.FormatStyle(time: .shortened)`.

Ключи (12 локалей): `spendingReminder.notification.title` (имя Тэна), `spendingReminder.phrase.1`…`.8`,
`spendingReminder.hook`, `spendingReminder.farewell.1`, `.2`, `spendingReminder.offer.title`,
`spendingReminder.offer.message` (`%@` = время), `spendingReminder.offer.action`.
ru, опорные (остальные адаптируются, не дословно):
- phrase.1 «Тэн тут подумал: сегодня ни одной траты? Подозрительно 🙂»
- phrase.2 «Минутка для денег: что сегодня купили?»
- phrase.3 «День почти закончился. Запишем, куда ушли деньги?»
- phrase.4 «Тэн скучает по цифрам. Покажете, что было сегодня?»
- phrase.5 «Одна запись в день, и месяц станет понятнее. Что сегодня?»
- phrase.6 «Кофе, такси, продукты? Тэн готов записать»
- phrase.7 «Вечерний вопрос от Тэна: на что сегодня тратили?»
- phrase.8 «Пара секунд, и день в порядке. Запишем траты?»
- hook «Вчера в Tenra: «%@». А сегодня что было?»
- farewell.1 «Тэн на месте, если понадобится. Пока не буду отвлекать 🙂»
- farewell.2 «Я тут, если захотите записать траты. Хорошего вечера!»
- offer.title «Напомнить вечером?»
- offer.message «Если день пройдёт без записей, Тэн напомнит в %@. Без спама.»
- offer.action «Напоминать»

- [x] **Шаг 1:** карточка и показ на Главной и в чате; превью карточки.
- [x] **Шаг 2:** строки в 12 локалях (python, utf-8), паритет: `diff` ключей en с каждой
  локалью пуст; `grep -c '—'` по новым строкам 0; проверка ru и ja на кракозябры.
- [x] **Шаг 3:** сборка без ошибок; `design-lint` (`python3 scripts/design_lint.py`) и
  `scripts/section_rows_lint.py` чисты.
- [x] **Шаг 4:** коммит `feat(reminder): Ten's offer on Home and in the chat, strings`.

### Задача 5: Настройки

**Файлы:**
- Создать: `Tenra/Views/Settings/SpendingReminderSettingsView.swift`
- Изменить: `Tenra/Views/Settings/SettingsView.swift` (`notificationsSection`)
- Изменить: 12 × `Localizable.strings`

Страница: `FormSection(footer: settings.spendingReminder.footer)` с `UniversalRow` переключателем
(`settings.spendingReminder.toggle`, иконка `bell`) → `SpendingReminder.setEnabled`;
при включении строка времени (`settings.spendingReminder.time`, `DatePicker` `.hourAndMinute`,
пишет `minutesKey` и `reschedule`); при `authorizationStatus == .denied` строка
`settings.insightSignals.permissionDenied` с `openAppSettings()`, как у сигналов. Строка в
`notificationsSection` под «Сигналами аналитики»: `settings.spendingReminder.title`, иконка
`bell`, `.navigation`. ru: title «Напоминание о тратах», toggle «Напоминать вечером», time «Время»,
footer «Тэн напомнит только в дни, когда в Tenra ничего не записано, и будет писать реже, если
вы не заглядываете».

- [x] **Шаг 1:** страница, строка, превью; строки в 12 локалях с проверкой паритета.
- [x] **Шаг 2:** сборка без ошибок, линтеры чисты, полный прогон `TenraTests` (счёт из
  `xcresulttool`).
- [x] **Шаг 3:** коммит `feat(reminder): settings page`.

## 8. Документы (в коммите последней задачи)
- [domains/insights.md](domains/insights.md) §Signal notifications: строка про `SpendingReminder`
  (ряд, крючок, префикс, тап → `tenra://add`, метка).
- `docs/release-notes.md` следующей версии (видимое изменение, 13 витрин, без длинных тире).
- [backlog.md](backlog.md) «First run» п. 1: убрать после выхода.
- [promotion-plan.md](promotion-plan.md) §7: «Воронка первого запуска», замер по метке через две
  недели после выхода; основатель обновляет App Privacy.
- Этот план: статус, потом в `docs/archive/plans/`, когда выйдет; строка в [README.md](README.md).
