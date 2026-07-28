# Аудит производительности Tenra — июль 2026

**Дата**: 2026-07-28
**Кодовая база**: 460 `.swift`-файлов, 88 269 строк, ветка `main` @ `fc866ea`
**Профиль данных**: ~19 000 транзакций (рабочий набор пользователя)
**План внедрения**: [plans/PERFORMANCE_PLAN_2026_07.md](plans/PERFORMANCE_PLAN_2026_07.md)

> **Статус: реализовано (2026-07-28).** Все находки P0/P1/P2 внедрены, кроме явно отложенных в §«Что сознательно НЕ делаем». Проверено на устройстве: запуск заметно быстрее, приложение в целом отзывчивее. Численные замеры на устройстве (таблица Фазы 0 в плане) не снимались — подтверждение качественное.
>
> Итог по предупреждениям сборки: 181 → 20, из них про изоляцию акторов (блокеры Swift 6 language mode) 100 → 5. Тесты: 524 → 534, все зелёные.
>
> Осталось незакрытым (осознанно): `NSLock` в async-контексте в `CurrencyConverter` (5 предупреждений — лок **не** удерживается через `await`, это ограничение API, а не гонка), `InsightSignalSettings.shared` как дефолтный аргумент (2), потеря `MainActor` при конверсии замыканий (3). Логичнее чинить одним заходом при переходе на Swift 6 language mode.

---

## 0. Резюме

Кодовая база уже прошла несколько раундов оптимизации: двухфазный старт, `Task.detached`-снапшоты, O(1)-индексы в `TransactionStore`, FRC-пагинация, warm-start агрегаты. Явных «низко висящих плодов» уровня «пересканируем 19k транзакций на MainActor» почти не осталось — из 51 обращения `.filter {}` во `Views/` ни одно не сканирует полный набор в теле `body`, `AnyView` использован 11 раз, `.id(UUID())` — 0 раз.

Тем не менее аудит нашёл **один доминирующий источник CPU-затрат, который проходит через всё приложение**, и несколько структурных проблем.

### Главный вывод

**`DateFormatter.date(from:)` — самая дорогая операция в приложении, и она вызывается на каждой горячей траектории.**

Замер (Apple Silicon, `swiftc -O`, 19 000 итераций):

| Операция | Время | Относительно |
|---|---:|---:|
| `DateFormatter.date(from: "yyyy-MM-dd")` × 19k | **253.7 мс** | 1× |
| `DateFormatter.string(from:)` × 19k | 18.6 мс | 13.6× быстрее |
| `Calendar.dateComponents([.y,.m,.d])` × 19k | 4.5 мс | 56× быстрее |
| `Calendar.date(from: DateComponents)` × 19k | 3.9 мс | 65× быстрее |
| Ручной разбор UTF8 `yyyy-MM-dd` × 19k | **0.9 мс** | **282× быстрее** |

Ручной разбор + `Calendar.date(from:)` даёт полный эквивалент за **~4.8 мс против 253.7 мс — ускорение ~53×**. На устройстве (A17/A18 примерно в 1.5–2 раза медленнее по single-core, чем M-серия) исходная цифра — это **порядка 400–500 мс за один проход по набору**.

Приложение делает такой проход **минимум 4 раза за холодный старт и ещё 3 раза при каждом изменении фильтра или транзакции на главном экране.**

Одна утилита `FastDateParser` (~40 строк) устраняет весь этот класс затрат разом.

### Второй вывод

`initializeFastPath()` блокирует **первый кадр** синхронным обращением к контейнеру iCloud. `AppCoordinator.init` запускает `prepareICloud()` в `Task.detached(priority: .utility)`, но `initializeFastPath()` стартует практически одновременно и на MainActor вызывает `cloudSyncViewModel.loadBackups()` — это гонка, которую фоновая `.utility`-задача обычно проигрывает. Результат для пользователей с включёнными iCloud-бэкапами: сотни миллисекунд задержки до первого кадра ради данных, которые нужны только строке в Настройках.

### Приоритеты

| # | Находка | Влияние | Сложность |
|---|---|---|---|
| **P0-1** | `DateFormatter.date(from:)` в горячих циклах | Старт −0.3…0.5 с; сводка главного экрана −60…70 % | Низкая |
| **P0-2** | `loadBackups()` на критическом пути первого кадра | Первый кадр −100…400 мс (iCloud-пользователи) | Тривиальная |
| **P0-3** | Кэш дат ключуется по `tx.id`, а не по строке даты | 10× лишних разборов + 1.7 МБ | Низкая |
| **P1-1** | `SummaryCalculator` — 3 полных прохода, без мемоизации | −1.0…1.5 с задержки карточки сводки | Средняя |
| **P1-2** | Дублирование `Transaction` в индексах | ~15–20 МБ RSS | Средняя |
| **P1-3** | `TransactionCacheManager` без `en_US_POSIX` | **Баг корректности** в не-григорианских локалях | Тривиальная |
| **P1-4** | FRC `section.transactions` — вычисляемое свойство, 2× за проход | Плавность прокрутки Истории | Низкая |
| **P1-5** | `convertSync` берёт 2 NSLock на вызов | 38k блокировок за проход | Низкая |
| **P2-1** | `MiniProportionBar.body` — 3.56 с тайп-чека | Время сборки | Тривиальная |
| **P2-2** | 188 предупреждений, ~98 про actor-изоляцию | Блокирует Swift 6 | Средняя |
| **P2-3** | 4 байт-идентичных PNG иконки по 692 КБ | ~2 МБ размера бандла | Тривиальная |

---

## 1. Методика

Что было сделано:

1. **Статический анализ** траектории запуска: `AppDelegate` → `TenraApp.task` → `AppCoordinator.init` → `initializeFastPath()` → `ContentView.task` → `initialize()` → `TransactionStore.loadData()` → `buildLoadSnapshot()`.
2. **Микробенчмарки** на Apple Silicon с `swiftc -O`, воспроизводящие точные конструкции из кода (`bench.swift`, `bench2.swift` в scratchpad). Все цифры в отчёте, помеченные «замер», получены так.
3. **Инструментированная сборка** с `-Xfrontend -warn-long-function-bodies=300 -Xfrontend -warn-long-expression-type-checking=300` — сборка прошла успешно (`** BUILD SUCCEEDED **`), выявлено 9 предупреждений о медленном тайп-чеке.
4. **Grep-обзор** антипаттернов SwiftUI, O(N)-сканов, дублирующихся кэшей, ad-hoc `DateFormatter`.
5. **Измерение layout** структуры `Transaction` через `MemoryLayout`.

Что **не** делалось (и должно быть сделано на устройстве при внедрении):

- Instruments Time Profiler / SwiftUI-трейс на реальном iPhone. Все «на устройстве» цифры в отчёте — экстраполяция с коэффициентом ×1.5–2 и **явно помечены как оценка**.
- Замер реального RSS через Instruments Allocations. Оценки памяти выведены из `MemoryLayout.stride` × количество копий.

---

## 2. Запуск (cold start)

### Текущая архитектура — что уже хорошо

Траектория продумана и большая часть тяжёлой работы уже уведена с MainActor:

- `AppDelegate.didFinishLaunching` → `CoreDataStack.preWarm()` грузит стор в фоне.
- `TenraApp.task` ждёт контейнер, затем строит координатор и **await'ит `initializeFastPath()` до публикации в `@State`** — первый рендер `MainTabView` уже имеет счета и категории, без вспышки пустого экрана.
- `loadData()` запускает 10 репозиторных чтений параллельно через `async let` + `Task.detached`; общее время ≈ max(отдельных), а не сумма.
- `buildLoadSnapshot()` строит все производные индексы одним проходом вне MainActor; на MainActor остаются только присваивания хеш-мапов.
- FRC `setup()` перекрывается с `loadData()`.
- Прогрев курсов валют идёт параллельно, с потолком ожидания 2.5 с.
- `Task.sleep(for: .milliseconds(16))` после `isFullyInitialized = true` отдаёт кадр рендеру.
- Бэкфилл `dateSectionKey` и очистка истории CoreData — фоновые, за флагом в UserDefaults.

Это грамотно. Оставшиеся проблемы — точечные.

---

### P0-2. `loadBackups()` блокирует первый кадр

**Файл**: [Tenra/ViewModels/AppCoordinator.swift:289](../Tenra/ViewModels/AppCoordinator.swift#L289)

```swift
func initializeFastPath() async {
    ...
    // Populate backup count/storage so the Settings row doesn't read 0 until the user
    // navigates into CloudBackupsView. listBackups() is a synchronous directory scan.
    cloudSyncViewModel.loadBackups()     // ← на MainActor, до isFastPathDone = true

    reconcileOnboardingAfterFastPath()
    isFastPathDone = true
}
```

Так как `TenraApp.task` делает `await c.initializeFastPath()` **перед** `coordinator = c`, всё внутри этого метода находится на критическом пути до первого кадра.

Что делает `loadBackups()` синхронно ([CloudSyncViewModel.swift:59](../Tenra/ViewModels/CloudSyncViewModel.swift#L59)):

1. `backupService.listBackups()` → `backupsDirectoryURL()` → если `isICloudEnabled`, то `iCloudBackupsDirectoryURL()` → `resolveICloudDocumentsURL()`.

   Комментарий в самом сервисе ([CloudBackupService.swift:57-59](../Tenra/Services/Utilities/CloudBackupService.swift#L57)):
   > *«The first `url(forUbiquityContainerIdentifier:)` call can block for hundreds of ms, so prefer calling this once off the main thread at launch.»*

2. `contentsOfDirectory` по папке бэкапов.
3. Для каждого бэкапа: `startDownloadingUbiquitousItem` + `Data(contentsOf:)` + `JSONDecoder().decode`.
4. `estimateStorageUsed()` — рекурсивный обход размера директории.
5. `backupService.isICloudEnabled` — чтение UserDefaults.

**Про «prewarm уже есть»**: `AppCoordinator.init` действительно запускает `Task.detached(priority: .utility) { cloudBackupService.prepareICloud() }` ([строка 219](../Tenra/ViewModels/AppCoordinator.swift#L219)). Но это **гонка, а не гарантия**: задача с приоритетом `.utility` стартует в тот же момент, что и `initializeFastPath()`, и почти наверняка не успевает. Кэш `cachedICloudDocuments` к моменту вызова `loadBackups()` пуст → MainActor платит полную стоимость.

**Оценка**: 100–400 мс на первом кадре для пользователей с включённым iCloud-бэкапом. Для остальных — десятки миллисекунд на обход директории и декод JSON.

**Ценность на первом кадре**: нулевая. Данные нужны только строке в `SettingsView`.

**Исправление**: перенести вызов из `initializeFastPath()` в фоновую задачу после `isFastPathDone = true`, либо целиком в `.task` экрана Настроек. Одна строка.

---

### P0-1a. Разбор дат в `buildLoadSnapshot()` — на критическом пути к `isFullyInitialized`

**Файл**: [TransactionStore+LoadSnapshot.swift:112-136](../Tenra/ViewModels/TransactionStore+LoadSnapshot.swift#L112)

```swift
let dateFormatter = DateFormatters.dateFormatter

for tx in transactions {
    ...
    if let parsed = dateFormatter.date(from: tx.date) {   // ← 19 000 × 13.4 мкс
        parsedDates[tx.id] = parsed
    }
    ...
}
```

**Замер**: 253.7 мс на Mac. **Оценка на устройстве: 380–500 мс.**

Работа идёт в `Task.detached`, то есть MainActor не блокируется — но `loadData()` **await'ит** этот снапшот, а `initialize()` await'ит `loadData()`. Флаг `isFullyInitialized` (а с ним и появление ссылки на Историю с карточкой сводки) отложен ровно на это время.

При первом запуске / после миграции схемы, когда warm-start агрегаты в CoreData пусты, тот же снапшот дополнительно строит `coldStartCategoryAggregates` и `coldStartAccountAggregates` — оба уже используют готовый `parsedDates`, так что повторного разбора нет. Это правильно.

---

### P0-1b. Прочие обращения к парсеру на старте

Полный подсчёт по кодовой базе:

- **155** обращений `.date(from:` (разбор — дорогая сторона)
- **67** обращений `dateFormatter.string(from:` (форматирование — в 13 раз дешевле)

Топ файлов по количеству разборов:

| Файл | Кол-во |
|---|---:|
| `Services/Deposits/DepositInterestService.swift` | 13 |
| `Models/InsightGranularity.swift` | 11 |
| `Services/Insights/InsightsService.swift` | 10 |
| `Services/Transactions/TransactionFilterService.swift` | 7 |
| `Services/Recurring/RecurringTransactionGenerator.swift` | 7 |
| `ViewModels/TransactionStore+Recurring.swift` | 6 |
| `Services/Insights/InsightsService+Spending.swift` | 6 |
| `Models/TimeFilter.swift` | 5 |

Не все из них — циклы по 19k. Но `TransactionFilterService`, `SummaryCalculator`, `TransactionStore+Recurring` и `InsightsService` — именно они.

---

### P0-1c. Корень проблемы: `Transaction.date` — это `String`

**Файл**: [Tenra/Models/Transaction.swift:94](../Tenra/Models/Transaction.swift#L94)

```swift
struct Transaction: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let date: String // YYYY-MM-DD
```

Это порождает круговой цикл преобразований на каждый холодный старт:

```
CoreData Date  ──DateFormatter.string──▶  Transaction.date: String  ──DateFormatter.date──▶  parsedDateById: [String: Date]
     (быстро, 18.6 мс)                                                    (медленно, 253.7 мс)
```

То есть на старте приложение конвертирует `Date` → `String` (в `TransactionEntity.toTransaction()`, [строка 33](../Tenra/CoreData/Entities/TransactionEntity+CoreDataClass.swift#L33)) и тут же конвертирует обратно `String` → `Date` (в `buildLoadSnapshot`), заплатив за обратный путь в 13 раз больше.

**Полное решение** — заменить тип поля на `Date` — это широкая правка (155 мест разбора, весь CSV round-trip, вся сортировка по строке, `Codable`-совместимость с бэкапами). **Не рекомендуется в этом раунде.**

**Практичное решение**: `FastDateParser`. Формат `yyyy-MM-dd` фиксирован и локале-независим — `DateFormatter` для него избыточен на два порядка.

```swift
enum FastDateParser {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    /// Разбирает строго "yyyy-MM-dd". nil для любого другого формата.
    /// Эквивалент DateFormatters.dateFormatter.date(from:) при
    /// locale = en_US_POSIX, calendar = gregorian, timeZone = .current.
    static func date(from s: String) -> Date? {
        var y = 0, m = 0, d = 0, i = 0
        for b in s.utf8 {
            switch i {
            case 0...3: guard b >= 48, b <= 57 else { return nil }; y = y * 10 + Int(b - 48)
            case 4, 7:  guard b == 45 else { return nil }
            case 5, 6:  guard b >= 48, b <= 57 else { return nil }; m = m * 10 + Int(b - 48)
            case 8, 9:  guard b >= 48, b <= 57 else { return nil }; d = d * 10 + Int(b - 48)
            default:    return nil          // строка длиннее 10 байт
            }
            i += 1
        }
        guard i == 10 else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}
```

**Замер эквивалентной реализации: 0.9 мс (разбор) + 3.9 мс (`Calendar.date(from:)`) = 4.8 мс против 253.7 мс.**

> ⚠️ Перед заменой обязателен тест-пин: `FastDateParser.date(from:)` должен возвращать **побайтово тот же** `Date`, что и `DateFormatters.dateFormatter.date(from:)`, для набора граничных случаев (високосный год, 29 февраля, переход на летнее время, первый/последний день месяца, невалидные строки, пустая строка, строка с временем). Это дешёвый property-based тест и он полностью снимает риск.

---

## 3. Горячие пути данных

### P1-1. `SummaryCalculator` — три полных прохода на каждое обновление главного экрана

**Файл**: [Tenra/Services/Transactions/SummaryCalculator.swift](../Tenra/Services/Transactions/SummaryCalculator.swift)

`ContentView.task(id: summaryTrigger)` вызывает в одной detached-задаче `compute()` и `computeTopExpenseWeights()`. Внутри:

```swift
// compute(), строка 52 — проход №1
let filtered = transactions.filter { tx in
    guard let txDate = dateFormatter.date(from: tx.date) else { return false }   // 19k разборов
    return txDate >= filterStart && txDate < filterEnd
}

for tx in filtered {
    ...
    guard let txDate = dateFormatter.date(from: tx.date) else { continue }       // ← проход №2:
    ...                                                                          //   ТА ЖЕ строка
}                                                                                //   разбирается ПОВТОРНО

// computeTopExpenseWeights(), строка 135 — проход №3
for tx in transactions {
    guard let txDate = dateFormatter.date(from: tx.date) else { continue }       // ещё 19k разборов
```

**Итого: ~2.5–3 полных прохода разбора за одно обновление сводки.**

Замер: **~635 мс на Mac** (2.5 × 253.7). **Оценка на устройстве: 1.0–1.3 с.**

Работа идёт вне MainActor, так что интерфейс не замирает — но карточка сводки на главном экране обновляется с задержкой больше секунды, и при этом греется процессор и садится батарея.

**Как часто это происходит?** `SummaryTrigger` имеет 6 измерений ([ContentView.swift:39-56](../Tenra/Views/Home/ContentView.swift#L39)):

| Измерение | Что его двигает |
|---|---|
| `txVersion` | любое добавление / правка / удаление транзакции |
| `filterStart` / `filterEnd` | переключение периода, наступление нового месяца |
| `isImporting` | старт/конец импорта CSV или PDF |
| `isFullyInitialized` | завершение холодного старта |
| `ratesVersion` | приземление свежих курсов после prewarm |
| `baseCurrency` | смена базовой валюты |

То есть: **при каждом старте + при каждой добавленной транзакции + при каждом переключении фильтра**.

**Три уровня исправления** (в порядке отношения выгоды к риску):

1. **Убрать повторный разбор внутри `compute()`.** Одна строка: слить фильтр и цикл в один проход, сохранив `txDate` из первой проверки. −33 % бесплатно.
2. **Перевести на `FastDateParser`.** Оставшиеся ~1.7 прохода: 430 мс → 8 мс. **−98 %.**
3. **(Опционально)** Использовать существующие `categoryAggregatesByKey` вместо полного скана. Индекс уже хранит 4 гранулярности (день/месяц/год/всё время) на категорию и уже поддерживается инкрементально. Для пресетов `.thisMonth` / `.thisYear` сводка получается за O(количество категорий) вместо O(19k). Более крупная работа — оставить на потом, п.1+2 закрывают проблему.

---

### P0-3. Кэш дат ключуется по `tx.id` вместо строки даты

**Файл**: [TransactionStore.swift:227](../Tenra/ViewModels/TransactionStore.swift#L227)

```swift
@ObservationIgnored internal(set) var parsedDateById: [String: Date] = [:]
```

19 000 транзакций за 5 лет содержат примерно **1 800 уникальных строк дат**. Ключевание по `tx.id` означает:

- **~10× лишних разборов** при построении (19 000 вместо ~1 800)
- **~1.7 МБ** словаря вместо ~0.2 МБ (ключ — 36-символьный UUID в куче + `Date`)
- инвалидация на транзакцию вместо инвалидации на дату

Примечательно, что **`InsightsService` уже нашёл правильный подход** и задокументировал его ([InsightsService.swift:862-865](../Tenra/Services/Insights/InsightsService.swift#L862)):

```swift
/// Pre-parsed date strings -> Date. Keyed by date STRING (not tx.id)
/// since many transactions share the same date.
/// Eliminates O(DateFormatter) re-parsing across all generators.
let txDateMap: [String: Date]
```

Тот же приём есть и в `TransactionCacheManager.getParsedDate(for:)`. То есть в кодовой базе живут **три параллельных кэша разобранных дат** с разными схемами ключей:

| Кэш | Ключ | Размер | Кто пользуется |
|---|---|---:|---|
| `TransactionStore.parsedDateById` | `tx.id` | ~19 000 | агрегаты счетов, индексы серий |
| `InsightsService.PreAggregatedData.txDateMap` | строка даты | ~1 800 | генераторы инсайтов |
| `TransactionCacheManager.parsedDateCache` | строка даты | ~1 800 | группировка Истории |

Правильная цель — **один кэш, ключуемый по строке даты**, поверх `FastDateParser`. С `FastDateParser` разбор становится настолько дешёвым (0.25 мкс), что мемоизация превращается в оптимизацию памяти, а не скорости — и это даёт свободу упростить архитектуру.

---

### P1-3. `TransactionCacheManager` теряет `en_US_POSIX` — баг корректности

**Файл**: [Tenra/Services/Cache/TransactionCacheManager.swift:41-45](../Tenra/Services/Cache/TransactionCacheManager.swift#L41)

```swift
private let dateFormatter = DateFormatter()

init() {
    dateFormatter.dateFormat = "yyyy-MM-dd"
    // ← НЕТ: dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    // ← НЕТ: dateFormatter.calendar = Calendar(identifier: .gregorian)
}
```

Сравните с каноническим `DateFormatters.dateFormatter` ([DateFormatters.swift:17-23](../Tenra/Utils/DateFormatters.swift#L17)), который корректно ставит `locale = en_US_POSIX`.

**Последствие**: `DateFormatter` без явной локали наследует календарь региона устройства. Пользователь с регионом Таиланд (буддийский календарь, год 2569) или Саудовская Аравия (календарь Умм аль-Кура) получит из строки `"2026-07-28"` **другую дату или `nil`**.

Что ломается: `TransactionGroupingService.parseDate()` ходит через этот кэш ([TransactionGroupingService.swift:42-48](../Tenra/Services/Transactions/TransactionGroupingService.swift#L42)) — то есть у таких пользователей разъезжается группировка по датам в Истории.

Приложение локализовано на **11 языков**, включая ja/ko, и распространяется глобально — регион устройства не совпадает с языком. Это реальный, а не теоретический риск.

**Это баг корректности, а не только производительности.** Исправляется одной строкой; при переходе на `FastDateParser` (жёстко григорианский) исчезает как класс.

---

### P1-5. `convertSync` берёт две блокировки на вызов

**Файл**: [Tenra/Services/Currency/CurrencyConverter.swift:124-133](../Tenra/Services/Currency/CurrencyConverter.swift#L124)

```swift
static func convertSync(amount: Double, from: String, to: String) -> Double? {
    if from == to { return amount }
    let store = CurrencyRateStore.shared
    guard let fromRate = store.currentRate(for: from),    // NSLock lock/unlock
          let toRate   = store.currentRate(for: to),      // NSLock lock/unlock
          toRate > 0 else { return nil }
    return amount * fromRate / toRate
}
```

`CurrencyRateStore.currentRate(for:)` берёт `NSLock` на каждое обращение ([CurrencyRateStore.swift:98-101](../Tenra/Services/Currency/CurrencyRateStore.swift#L98)).

Вызывается по одной транзакции в каждом агрегирующем цикле: `SummaryCalculator.compute`, `computeTopExpenseWeights`, `computeCategoryAggregates`, `computeAccountAggregates`, генераторы инсайтов. **38 000 захватов блокировки за проход.**

Незанятый `NSLock` стоит ~20 нс, то есть ~1 мс за проход — само по себе немного, но это ещё и барьер памяти, который мешает компилятору оптимизировать цикл, и точка потенциальной конкуренции, когда несколько detached-задач считают одновременно (что на старте как раз и происходит).

**Исправление**: снимать снапшот курсов один раз перед массовой операцией.

```swift
struct RateSnapshot: Sendable {
    private let rates: [String: Double]
    init() { rates = CurrencyRateStore.shared.cachedRates }
    func convert(_ amount: Double, from: String, to: String) -> Double? { ... }
}
```

Дополнительный плюс: снапшот **фиксирует курсы на всё время расчёта**. Сейчас, если prewarm приземлится в середине агрегирующего цикла, первая половина транзакций будет пересчитана по старым курсам, а вторая — по новым, и итог окажется внутренне несогласованным. Флаг `aggregatesAreFXStale` ловит холодный кэш, но не этот сценарий.

---

## 4. Память

### P1-2. Дублирование значений `Transaction` в индексах

**Замер**: `MemoryLayout<Transaction>.stride = 256 байт`. 19 000 × 256 = **4.75 МБ на одну копию** (только тело структуры; строковые буферы в куче разделяются через COW, так что копии индексов их не дублируют).

`TransactionStore` держит одновременно:

| Структура | Копий набора | Оценка |
|---|---:|---:|
| `transactions: [Transaction]` | 1.0 | 4.75 МБ |
| `transactionById: [String: Transaction]` | 1.0 + оверхед словаря | ~7 МБ |
| `transactionsByAccount: [String: [Transaction]]` | ~1.3 (переводы дают 2 ноги) | ~6 МБ |
| `transactionsByCategoryName: [String: [Transaction]]` | ~0.95 (без переводов) | ~4.5 МБ |
| `transactionsBySeriesId: [String: [Transaction]]` | мало (только повторяющиеся) | ~0.5 МБ |
| `transactionIdSet: Set<String>` | — | ~1 МБ |
| `parsedDateById: [String: Date]` | — | ~1.7 МБ |
| **Итого** | | **~25 МБ** |

Комментарий в коде оценивает набор в «~7.6 МБ для 19k tx» ([TransactionStore.swift:380](../Tenra/ViewModels/TransactionStore.swift#L380)) — это верно для базового массива со строками, но **не учитывает четырёхкратное дублирование в индексах**.

Плюс транзиентные пики: при перестроении индексов старая и новая копия существуют одновременно.

**Исправление**: группирующие словари должны хранить `[String]` (идентификаторы), а не `[Transaction]`. Разрешение идёт через уже существующий `transactionById` за O(1).

```swift
// Было: [String: [Transaction]]   ~11 МБ на три словаря
// Стало: [String: [String]]       ~1.5 МБ
var transactionIdsByAccount: [String: [String]]
```

Экономия ~10 МБ. Для приложения, которое iOS может выгрузить из памяти в фоне, это ощутимая разница в живучести состояния между переключениями приложений.

Дополнительно `parsedDateById` → ключевание по строке даты: −1.5 МБ (см. P0-3).

**Итог: ~25 МБ → ~13 МБ.**

Правка затрагивает контракт чтения индексов в нескольких файлах (`TransactionStore+AccountAggregates`, `+SeriesIndex`, `+CategoryIndex`, представления деталей) — умеренная по объёму, но механическая. Стоит делать после P0.

---

## 5. UI и рендеринг

### Что уже сделано хорошо

- 11 обращений `AnyView` на 223 файла представлений — минимально.
- 0 обращений `.id(UUID())` (классический источник паразитных анимаций).
- 1 обращение `.shadow(` — Liquid Glass вместо ручных теней.
- `List` с 500+ секциями решён нарезкой `prefix(visibleSectionLimit)` + бесконечная прокрутка.
- `TransactionCard` помечен `.equatable()`.
- `TransactionPaginationController` — грамотный FRC: `fetchBatchSize = 50`, `sectionNameKeyPath` по **хранимой** колонке `dateSectionKey` (комментарий фиксирует, что transient-вариант заставлял FRC поднимать все 19k объектов, ~10 с).
- `GroupedTransactionList` кэширует секции в `@State private var cachedSections: [DaySection]` со **сохранённым** массивом `transactions` — `.count` внутри `ForEach` даёт O(1). Проверено: здесь проблемы нет.

### P1-4. FRC `section.transactions` — вычисляемое свойство, вызывается дважды за проход

**Файл**: [TransactionPaginationController.swift:41-51](../Tenra/ViewModels/TransactionPaginationController.swift#L41)

```swift
var transactions: [Transaction] {
    (sectionInfo.objects as? [TransactionEntity] ?? [])
        .compactMap { entity -> Transaction? in
            guard !entity.isDeleted else { return nil }
            return entity.toTransaction()        // ← + DateFormatter.string на каждую сущность
        }
}
```

Потребитель — [HistoryTransactionsList.swift:134 и 137](../Tenra/Views/Components/Cards/HistoryTransactionsList.swift#L134):

```swift
Section(
    header: dateHeader(
        isoDate: section.date,
        displayLabel: displayLabel,
        transactions: section.transactions        // ← материализация №1
    )
) {
    ForEach(section.transactions) { transaction in // ← материализация №2
```

`List` строит заголовки всех видимых секций сразу. При `visibleSectionLimit = 100` и ~5 транзакциях на день это **~1 000 вызовов `toTransaction()` за один проход `body`**, каждый с `DateFormatter.string` и 12 retain'ами строк. Порядка 2–5 мс на проход — на самой чувствительной к джанку траектории (прокрутка).

**Исправление**: материализовать один раз в локальную константу.

```swift
ForEach(displaySections) { section in
    let rows = section.transactions      // одна материализация
    Section(header: dateHeader(isoDate: section.date, displayLabel: displayLabel, transactions: rows)) {
        ForEach(rows) { transaction in ... }
    }
}
```

Либо — надёжнее — превратить `transactions` из вычисляемого свойства в лениво-мемоизированное хранимое (секция уже держит `sectionInfo` по ссылке).

### P1-4b. Линейный поиск счёта на каждую строку

Тот же файл, [строки 145-146](../Tenra/Views/Components/Cards/HistoryTransactionsList.swift#L145):

```swift
let sourceAccount = accountsViewModel.accounts.first { $0.id == transaction.accountId }
let targetAccount = accountsViewModel.accounts.first { $0.id == transaction.targetAccountId }
```

Две проблемы:

1. Линейный скан вместо `transactionStore.accountById` — индекс существует специально для этого и задокументирован в [architecture.md](architecture.md#o1-lookup-indexes). N счетов мало, так что стоимость невелика.
2. **Важнее**: чтение `accountsViewModel.accounts` внутри тела строки подписывает **каждую строку** на весь массив счетов. Любое изменение баланса любого счёта помечает грязными все видимые строки Истории. Это ровно тот антипаттерн, от которого предостерегает [gotchas.md](gotchas.md) («Pre-resolve per-row data at ForEach call site»), — причём комментарий прямо над этими строками утверждает, что данные пре-резолвятся.

**Исправление**: поднять `let accountById = transactionStore.accountById` из тела `ForEach` в тело функции.

### P2-1. Время тайп-чека

Инструментированная сборка (`-warn-long-function-bodies=300`) дала 9 предупреждений, из них два значимых:

| Файл | Символ | Время |
|---|---|---:|
| `Views/Components/Charts/MiniProportionBar.swift:26` | `body` | **3 559 мс** |
| `Views/Components/Charts/MiniProportionBar.swift:32` | выражение | 553–613 мс (×6) |
| `Views/History/HistoryView.swift:105` | `historyEventContent` | 440 мс |
| `Views/History/HistoryView.swift:106` | выражение | 403 мс |

Причина в `MiniProportionBar` — смешение `CGFloat`, `Double` и литералов в одном выражении ([строки 32-38](../Tenra/Views/Components/Charts/MiniProportionBar.swift#L32)):

```swift
.frame(width: max(
    barHeight / 2,
    (geo.size.width - segmentGap * CGFloat(segments.count - 1))
        * CGFloat(segment.amount / total)
))
```

Solver перебирает комбинации перегрузок `/`, `*`, `-`, `max`. Разбивка на промежуточные `let` с явными аннотациями типа убирает 3.5 с из каждой сборки, где этот файл перекомпилируется:

```swift
let gapTotal: CGFloat = segmentGap * CGFloat(segments.count - 1)
let available: CGFloat = geo.size.width - gapTotal
let share: CGFloat = CGFloat(segment.amount / total)
let minWidth: CGFloat = barHeight / 2
.frame(width: max(minWidth, available * share))
```

Дополнительный контекст: **387 блоков `#Preview`** на 223 файла представлений. Каждый тайп-чекается при каждой сборке. Это не ошибка (превью полезны), но объясняет базовую длительность сборки и стоит помнить при оценке.

---

## 6. Сборка и бинарник

### Настройки сборки — в порядке

- Release: `SWIFT_COMPILATION_MODE = wholemodule`, `VALIDATE_PRODUCT = YES`, `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`. `SWIFT_OPTIMIZATION_LEVEL` не задан явно → дефолт `-O`. Корректно.
- Debug: `-Onone`, `ONLY_ACTIVE_ARCH = YES`, `dwarf`, `ENABLE_TESTABILITY = YES`. Корректно.
- Внешних зависимостей ровно одна: `purchases-ios-spm` (RevenueCat). Отличная дисциплина — влияние на время старта минимально.
- `PerformanceProfiler` целиком под `#if DEBUG` — в релиз не попадает.
- 2 обращения `print(` на всю кодовую базу; логирование идёт через `os.Logger`, который под `-O` компилируется в проверку уровня перед сериализацией аргументов.

### P2-3. Иконка приложения: 4 байт-идентичных PNG

```
Assets.xcassets/AppIcon.appiconset/App Icon3.png      692 КБ  md5 b31cb8bb…
Assets.xcassets/AppIcon.appiconset/App Icon3 1.png    692 КБ  md5 b31cb8bb…   (вариант "dark")
Assets.xcassets/AppIcon.appiconset/App Icon3 2.png    692 КБ  md5 b31cb8bb…   (вариант "tinted")
Assets.xcassets/LaunchIcon.imageset/App Icon3.png     692 КБ  md5 b31cb8bb…
```

Все четыре — **один и тот же файл** (совпадающий MD5). `Contents.json` объявляет варианты `luminosity: dark` и `luminosity: tinted`, но содержимое идентично светлому — то есть iOS 18+ отрисует ровно то же самое, что и по умолчанию.

Действие: удалить записи `appearances` из `Contents.json` и два дубликата (система корректно откатится на универсальную иконку), а `LaunchIcon` завести ссылкой на тот же ресурс. **Экономия ~2 МБ** в `Assets.car`, если компилятор ассетов не дедуплицирует по содержимому (на что полагаться не стоит).

При желании иметь настоящие dark/tinted варианты — это отдельная дизайнерская задача, а не текущее состояние.

### P2-2. 188 предупреждений сборки

Разбивка:

| Категория | Кол-во |
|---|---:|
| `call to main actor…` / `main actor…` (изоляция акторов) | **98** |
| `initialization of immutable value…` (неиспользуемые `let`) | 24 |
| `expression took…` / `getter for property…` (тайп-чек) | 9 |
| прочее (неиспользуемые переменные, конверсии) | 57 |

Предупреждения об акторах сконцентрированы в `Services/Insights/*`:

| Файл | Кол-во |
|---|---:|
| `InsightsService+Savings.swift` | 16 |
| `InsightsService+Recurring.swift` | 14 |
| `InsightsService+Spending.swift` | 13 |
| `InsightsService+Forecasting.swift` | 12 |
| `InsightsService+CashFlow.swift` | 6 |

Это `nonisolated`-сервисы, которые обращаются к неявно-MainActor статикам (следствие `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, см. [concurrency.md](concurrency.md#default-isolation-gotcha)). **Под Swift 6 language mode каждое из них станет ошибкой компиляции.** Сейчас это не влияет на производительность в рантайме, но это долг, который заблокирует переход. Лечится добавлением `nonisolated` к чистым хелперам — механически.

В `TransactionStore+LoadSnapshot.swift` таких предупреждений 2 — то есть даже в свежем, специально проектировавшемся под `nonisolated` коде они просачиваются. Разумно включить `-warnings-as-errors` для этой категории после разбора.

---

## 7. Сводная таблица находок

| ID | Находка | Файл | Замерено / оценка | Приоритет |
|---|---|---|---|---|
| P0-1 | `DateFormatter.date(from:)` в горячих циклах | 155 мест, гл. обр. `LoadSnapshot`, `SummaryCalculator`, `FilterService` | 253.7 мс/проход (замер) → 4.8 мс | **P0** |
| P0-2 | `loadBackups()` на критическом пути первого кадра | `AppCoordinator.swift:289` | 100–400 мс (оценка) | **P0** |
| P0-3 | Кэш дат по `tx.id` вместо строки даты | `TransactionStore.swift:227` | 10× разборов + 1.7 МБ | **P0** |
| P1-1 | Тройной проход в `SummaryCalculator` | `SummaryCalculator.swift:52,76,135` | ~635 мс/обновление (замер) | **P1** |
| P1-2 | Дублирование `Transaction` в индексах | `TransactionStore.swift` | ~25 МБ → ~13 МБ | **P1** |
| P1-3 | Нет `en_US_POSIX` — **баг корректности** | `TransactionCacheManager.swift:41` | ломает не-григорианские регионы | **P1** |
| P1-4 | FRC `section.transactions` × 2 за проход | `HistoryTransactionsList.swift:134,137` | ~1 000 материализаций/проход | **P1** |
| P1-4b | Линейный скан счетов + подписка на массив | `HistoryTransactionsList.swift:145` | лишние инвалидации строк | **P1** |
| P1-5 | `convertSync` — 2 NSLock на вызов | `CurrencyConverter.swift:124` | 38k блокировок/проход | **P1** |
| P2-1 | Тайп-чек `MiniProportionBar.body` | `MiniProportionBar.swift:26` | 3 559 мс (замер) | **P2** |
| P2-2 | 98 предупреждений про акторы | `Services/Insights/*` | блокирует Swift 6 | **P2** |
| P2-3 | 4 идентичных PNG иконки | `Assets.xcassets` | ~2 МБ бандла | **P2** |

---

## 8. Что было проверено и оказалось в порядке

Чтобы аудит был честным, вот гипотезы, которые **не подтвердились**:

- **`Array(transactionStore.transactions)`** в `ContentView.task` и `InsightsViewModel` — выглядит как копия 4.75 МБ, но `Array.init` из нативного массива возвращает тот же буфер без копирования. Затрат нет.
- **`GroupedTransactionList` — `section.transactions.count` внутри `ForEach`** — выглядит как O(N²), но `DaySection` хранит массив, а не вычисляет его. O(1).
- **`InsightsViewModel.invalidateAndRecompute()`** вызывается из четырёх наблюдателей (курсы, категории, счета, транзакции) — но он корректно закрыт `guard isVisible else { return }` плюс дебаунс 800 мс. Пересчёт не идёт, пока вкладка Аналитики не открыта.
- **Ленивый рендер вкладок iOS 26** — подтверждено в [gotchas.md](gotchas.md), что `AnalyticsTab.body` и `SettingsTab.body` не выполняются на старте. Инициализация неактивных вкладок вне критического пути.
- **`os.Logger.debug`** — 118 обращений, но под `-O` компилятор вставляет проверку уровня перед сериализацией аргументов. В релизе почти бесплатно.
- **Ожидание prewarm курсов 2.5 с** в `initialize()` — идёт **после** `isFullyInitialized = true`, интерфейс не блокирует.
- **`purgeHistory` и бэкфилл `dateSectionKey`** — оба на фоновом контексте CoreData, оба за флагом в UserDefaults, оба вне критического пути.

---

## 9. Ожидаемый совокупный эффект

При выполнении P0 + P1 (оценка; требует подтверждения на устройстве через Instruments):

| Метрика | Сейчас (оценка на устройстве) | После | Дельта |
|---|---:|---:|---:|
| Время до первого кадра | базовое + 100–400 мс | базовое | **−100…400 мс** |
| Время до `isFullyInitialized` | базовое + 400–500 мс | базовое + ~10 мс | **−390…490 мс** |
| Обновление карточки сводки | 1.0–1.3 с | 30–60 мс | **−95 %** |
| Пиковая память (индексы) | ~25 МБ | ~13 МБ | **−48 %** |
| Инкрементальная сборка (файлы графиков) | базовая + 3.6 с | базовая | **−3.6 с** |
| Размер бандла | базовый | базовый − 2 МБ | **−2 МБ** |

Порядок работ, критерии приёмки и разбивка по фазам — в [plans/PERFORMANCE_PLAN_2026_07.md](plans/PERFORMANCE_PLAN_2026_07.md).

---

**Автор аудита**: Claude Opus 5
**Артефакты замеров**: микробенчмарки и лог сборки в scratchpad сессии
**Статус**: находки подтверждены статически и микробенчмарками; профилирование на устройстве — обязательный шаг Фазы 0
