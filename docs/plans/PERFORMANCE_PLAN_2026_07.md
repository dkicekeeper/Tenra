# План оптимизации производительности — июль 2026

**Источник**: [../PERFORMANCE_AUDIT_2026_07.md](../PERFORMANCE_AUDIT_2026_07.md)
**Дата составления**: 2026-07-28
**Оценка объёма**: 5 фаз, ~4–6 рабочих дней

> **Статус: выполнено (2026-07-28).** Фазы 1–5 внедрены целиком, включая 2.5 и 4. Фаза 0 (замер базовой линии через Instruments) **не выполнялась** — эффект подтверждён качественно на физическом устройстве, таблица ниже осталась незаполненной. Единственная неизмеренная величина — экономия памяти Фазы 4 (~10 МБ по расчёту из `MemoryLayout.stride`, не из Allocations).
>
> Два отклонения от плана по ходу работы, оба задокументированы в коде:
> 1. **Гейт 2.2 сработал** — `DateFormatter` оказался не равномерно строгим (месяц 13 → nil, но 30 февраля → 2 марта). Парсер приведён к измеренному поведению, тест заменён на исчерпывающий перебор пространства месяц/день.
> 2. **Фаза 4 вскрыла скрытую зависимость** — индексы резолвят через `transactionById`, и пересборка от массива `transactions` могла дать пустые бакеты. Закрыто `ensureTransactionByIdInSync()`, а не правкой упавших тестов.

---

## Принципы

1. **Сначала измерить на устройстве, потом чинить.** Все цифры аудита получены микробенчмарками на Mac и статическим анализом. Фаза 0 обязательна — она даёт базовую линию, без которой невозможно доказать эффект.
2. **Одна фаза = один коммит = один замер.** Не смешивать фазы: если регрессия, нужно понимать, откуда.
3. **Не менять поведение.** Все правки — чисто производительностные, кроме P1-3 (баг корректности с локалью), который чинится явно и отдельно.
4. **Пин тестами до замены.** `FastDateParser` не заменяет `DateFormatter` до того, как тест докажет побитовую эквивалентность.
5. **Профилировать на реальном устройстве** (`Dkicekeeper 17`), не в Симуляторе, и **без подключённого отладчика** — см. [../gotchas.md](../gotchas.md#build--profiling): флуд `os.Logger.debug` под отладчиком раздувал реальный <1 с старт в измеренные 4–6 с.

---

## Фаза 0 — Базовая линия (обязательно, ~2 часа)

Без этого шага остальные фазы недоказуемы.

### 0.1 Трейс холодного старта на устройстве

```bash
xcrun xctrace record --template 'App Launch' \
  --output ~/Desktop/tenra-baseline-launch.trace \
  --device 'Dkicekeeper 17' \
  --launch -- <bundle-id>
```

Снять 5 запусков, взять медиану. Отключить автоблокировку экрана на время записи.

### 0.2 Трейс главного экрана

```bash
xcrun xctrace record --template 'Time Profiler' \
  --output ~/Desktop/tenra-baseline-home.trace \
  --device 'Dkicekeeper 17' --attach Tenra
```

Сценарий во время записи: переключить период три раза, добавить одну транзакцию, вернуться на главный экран.

### 0.3 Базовая линия памяти

Instruments → Allocations, снять persistent-байты после `isFullyInitialized`.

### 0.4 Зафиксировать цифры

Записать в таблицу ниже. Все последующие фазы сверяются с ней.

| Метрика | База | Ф1 | Ф2 | Ф3 | Ф4 |
|---|---|---|---|---|---|
| Время до первого кадра | | | | | |
| Время до `isFullyInitialized` | | | | | |
| `loadData()` (из лога `📦 [INIT]`) | | | | | |
| Обновление сводки (детач-задача) | | | | | |
| Persistent-память после старта | | | | | |
| Чистая сборка | | | | | |

> Приложение уже логирует тайминги старта: `🚀 [INIT]`, `📦 [INIT]`, `🔄 [INIT]`, `💰 [INIT]`, `📋 [INIT]`, `✅ [INIT]`, `💱 [INIT]` — снять их с устройства через Console.app как дешёвую дополнительную линию.

**Критерий выхода**: таблица заполнена, трейсы сохранены.

---

## Фаза 1 — Быстрые победы (полдня, максимальное отношение выгоды к риску)

Четыре независимые правки, каждая — несколько строк. Можно делать одним коммитом.

### 1.1 Убрать `loadBackups()` с критического пути первого кадра *(P0-2)*

**Файл**: [`Tenra/ViewModels/AppCoordinator.swift:289`](../../Tenra/ViewModels/AppCoordinator.swift#L289)

```swift
// Было — синхронно на MainActor до isFastPathDone:
cloudSyncViewModel.loadBackups()
reconcileOnboardingAfterFastPath()
isFastPathDone = true

// Стало:
reconcileOnboardingAfterFastPath()
isFastPathDone = true

// Счётчик бэкапов нужен только строке в Настройках — снять его после
// первого кадра. resolveICloudDocumentsURL() блокирует на сотни мс
// (см. комментарий в CloudBackupService), поэтому не на MainActor-старте.
Task(priority: .utility) { [weak self] in
    self?.cloudSyncViewModel.loadBackups()
}
```

**Проверка**: открыть Настройки, убедиться, что число бэкапов и объём хранилища отображаются. Открыть `CloudBackupsView` — список полон.

**Риск**: минимальный. Худший случай — строка в Настройках показывает 0 первые ~200 мс после старта, если пользователь успеет туда дойти.

---

### 1.2 Починить локаль в `TransactionCacheManager` *(P1-3, баг корректности)*

**Файл**: [`Tenra/Services/Cache/TransactionCacheManager.swift:43-45`](../../Tenra/Services/Cache/TransactionCacheManager.swift#L43)

```swift
init() {
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.calendar = Calendar(identifier: .gregorian)
    dateFormatter.timeZone = .current
}
```

**Проверка**: в Симуляторе выставить регион Таиланд (Settings → General → Language & Region → Region → Thailand), запустить, открыть Историю. До правки — группировка по датам разъезжается или секции пустые; после — корректна.

**Риск**: нулевой. Правка приводит форматтер к тому же контракту, что и канонический `DateFormatters.dateFormatter`.

> Заметка: эта правка станет избыточной в Фазе 2 (`FastDateParser` жёстко григорианский), но делается сейчас, потому что это баг у живых пользователей, и она не должна ждать более крупного рефакторинга.

---

### 1.3 Материализовать секции Истории один раз *(P1-4, P1-4b)*

**Файл**: [`Tenra/Views/Components/Cards/HistoryTransactionsList.swift:128-146`](../../Tenra/Views/Components/Cards/HistoryTransactionsList.swift#L128)

```swift
private func transactionsListView(sections: [TransactionSection]) -> some View {
    let displaySections = Array(sections.prefix(visibleSectionLimit))
    let hasMore = displaySections.count < sections.count
    // Поднять индекс из тела строки: иначе каждая строка подписывается
    // на весь массив accounts и любое изменение баланса метит грязными
    // все видимые строки (см. gotchas.md, "Pre-resolve per-row data").
    let accountById = transactionsViewModel.transactionStore?.accountById ?? [:]

    return ScrollViewReader { proxy in
        List {
            ForEach(displaySections) { section in
                // section.transactions — ВЫЧИСЛЯЕМОЕ свойство: каждое обращение
                // заново делает compactMap { entity.toTransaction() } со своим
                // DateFormatter.string на сущность. Материализуем один раз.
                let rows = section.transactions
                let displayLabel = displayLabelCache[section.date] ?? displayDateKey(from: section.date)
                Section(
                    header: dateHeader(isoDate: section.date, displayLabel: displayLabel, transactions: rows)
                ) {
                    ForEach(rows) { transaction in
                        let styleData = CategoryStyleHelper.cached(...)
                        let sourceAccount = transaction.accountId.flatMap { accountById[$0] }
                        let targetAccount = transaction.targetAccountId.flatMap { accountById[$0] }
                        ...
                    }
                }
                .id(section.id)
            }
            ...
        }
    }
}
```

**Проверка**: прокрутить Историю на весь набор — плавность не хуже базовой. Отредактировать транзакцию — строка обновляется. Изменить баланс счёта — строки Истории **не** перерисовываются целиком.

**Риск**: низкий. Семантика идентична, `accountById` — задокументированный публичный индекс ([../architecture.md](../architecture.md#o1-lookup-indexes)).

---

### 1.4 Разбить выражение в `MiniProportionBar` *(P2-1)*

**Файл**: [`Tenra/Views/Components/Charts/MiniProportionBar.swift:32-38`](../../Tenra/Views/Components/Charts/MiniProportionBar.swift#L32)

```swift
ForEach(segments) { segment in
    let gapTotal: CGFloat = segmentGap * CGFloat(segments.count - 1)
    let available: CGFloat = geo.size.width - gapTotal
    let share: CGFloat = CGFloat(segment.amount / total)
    let minWidth: CGFloat = barHeight / 2
    Rectangle()
        .fill(segment.color)
        .frame(width: max(minWidth, available * share))
}
```

**Проверка**: пересобрать с `-Xfrontend -warn-long-function-bodies=300` — предупреждение по `MiniProportionBar` исчезает. Открыть превью — вид не изменился.

**Риск**: нулевой, чистая аннотация типов.

**Критерий выхода Фазы 1**: сборка зелёная, замеры сняты, время до первого кадра снизилось у iCloud-пользователей.

---

## Фаза 2 — `FastDateParser` (1.5 дня, наибольший эффект)

Это центральная фаза. Делать строго по шагам.

### 2.1 Реализовать утилиту

**Новый файл**: `Tenra/Utils/FastDateParser.swift`

```swift
//  FastDateParser.swift
//  Быстрый разбор канонического формата "yyyy-MM-dd" (Transaction.date).
//
//  Зачем: DateFormatter.date(from:) стоит ~13.4 мкс за вызов — на 19k
//  транзакций это 254 мс за проход (замер, Apple Silicon -O). Формат
//  фиксирован и локале-независим, поэтому весь механизм ICU избыточен.
//  Ручной разбор UTF8 + Calendar.date(from:) даёт тот же Date за ~4.8 мс
//  на тот же объём — ускорение ~53×.
//
//  Контракт: побитово эквивалентен DateFormatters.dateFormatter.date(from:)
//  (locale = en_US_POSIX, calendar = gregorian, timeZone = .current).
//  Закреплён FastDateParserTests.

import Foundation

enum FastDateParser {

    nonisolated static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    /// Разбирает строго "yyyy-MM-dd". Возвращает nil для любого другого формата.
    nonisolated static func date(from s: String) -> Date? {
        var y = 0, m = 0, d = 0, i = 0
        for b in s.utf8 {
            switch i {
            case 0, 1, 2, 3:
                guard b >= 48, b <= 57 else { return nil }
                y = y * 10 + Int(b - 48)
            case 4, 7:
                guard b == 45 else { return nil }          // '-'
            case 5, 6:
                guard b >= 48, b <= 57 else { return nil }
                m = m * 10 + Int(b - 48)
            case 8, 9:
                guard b >= 48, b <= 57 else { return nil }
                d = d * 10 + Int(b - 48)
            default:
                return nil                                  // длиннее 10 байт
            }
            i += 1
        }
        guard i == 10 else { return nil }
        // Calendar валидирует диапазоны (месяц 13, день 32 → nil),
        // как это делает и DateFormatter при lenient = false.
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }

    /// Форматирует Date обратно в "yyyy-MM-dd" без DateFormatter.
    /// Замер: 5.4 мс на 19k против 18.6 мс у DateFormatter.string.
    nonisolated static func string(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0, m = c.month ?? 0, d = c.day ?? 0
        return "\(y)-\(m < 10 ? "0" : "")\(m)-\(d < 10 ? "0" : "")\(d)"
    }
}
```

> ⚠️ `nonisolated` обязателен: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` делает `enum`-статики неявно MainActor-изолированными, и вызов из `Task.detached` не скомпилируется. См. [../concurrency.md](../concurrency.md#default-isolation-gotcha).

### 2.2 Пин-тесты **до** замены (не пропускать)

**Новый файл**: `TenraTests/Utils/FastDateParserTests.swift`

```swift
@Suite struct FastDateParserTests {

    private static let reference: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    @Test func matchesDateFormatterAcrossDecade() {
        // Каждый день с 2015-01-01 по 2035-12-31 — включает високосные,
        // переходы на летнее время, границы месяцев.
        var d = Self.reference.date(from: "2015-01-01")!
        let end = Self.reference.date(from: "2035-12-31")!
        while d <= end {
            let s = Self.reference.string(from: d)
            #expect(FastDateParser.date(from: s) == Self.reference.date(from: s),
                    "разошлись на \(s)")
            #expect(FastDateParser.string(from: d) == s, "форматирование разошлось на \(s)")
            d = Calendar.current.date(byAdding: .day, value: 1, to: d)!
        }
    }

    @Test func rejectsMalformedInput() {
        for bad in ["", "2026-7-28", "2026/07/28", "2026-07-28T10:00:00",
                    "26-07-28", "2026-07-2", "abcd-ef-gh", "2026-13-01",
                    "2026-02-30", "2026-00-10", "2026-07-00", " 2026-07-28"] {
            #expect(FastDateParser.date(from: bad) == nil, "должно быть nil: '\(bad)'")
        }
    }

    @Test func handlesLeapDay() {
        #expect(FastDateParser.date(from: "2024-02-29") == Self.reference.date(from: "2024-02-29"))
        #expect(FastDateParser.date(from: "2025-02-29") == nil)   // не високосный
    }
}
```

**Запуск** (фильтр только на уровне сюиты — метод-левел молча выполняет 0 тестов, см. CLAUDE.md):

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/FastDateParserTests
```

**Гейт**: пока эти тесты не зелёные — к шагу 2.3 не переходить.

---

### 2.3 Заменить в горячих путях (только в них)

Порядок по убыванию эффекта. **Не** переписывать все 155 мест — только те, что в циклах по всему набору.

| # | Файл | Строки | Проходов на 19k |
|---|---|---|---|
| 1 | `ViewModels/TransactionStore+LoadSnapshot.swift` | 112, 129 | 1 (холодный старт) |
| 2 | `Services/Transactions/SummaryCalculator.swift` | 48, 53, 76, 126, 135 | 3 (каждое обновление сводки) |
| 3 | `Services/Transactions/TransactionFilterService.swift` | 38, 58, 75, 93, 109, 133, 309 | 1 на фильтр |
| 4 | `ViewModels/TransactionStore+SeriesIndex.swift` | 22, 48 | инкрементально |
| 5 | `ViewModels/TransactionStore+AccountAggregates.swift` | 107 | инкрементально |
| 6 | `Services/Insights/InsightsService*.swift` | `PreAggregatedData.build` | 1 на пересчёт |

Замена дословная:

```swift
// Было:
DateFormatters.dateFormatter.date(from: tx.date)
// Стало:
FastDateParser.date(from: tx.date)
```

Остальные ~100 мест (единичные вызовы в формах, представлениях деталей, парсерах CSV) **оставить как есть** — там разница неизмерима, а лишние правки — лишний риск.

---

### 2.4 Схлопнуть двойной разбор в `SummaryCalculator` *(P1-1)*

**Файл**: [`Tenra/Services/Transactions/SummaryCalculator.swift:52-87`](../../Tenra/Services/Transactions/SummaryCalculator.swift#L52)

Даже с быстрым парсером не нужно разбирать одну и ту же строку дважды. Слить фильтр и цикл:

```swift
nonisolated static func compute(
    transactions: [Transaction],
    filterStart: Date, filterEnd: Date, baseCurrency: String
) -> Summary {
    let today = Calendar.current.startOfDay(for: Date())
    let rates = RateSnapshot()              // см. Фазу 3

    var totalIncome = 0.0, totalExpenses = 0.0
    var totalInternal = 0.0, plannedExpenses = 0.0
    var minDate: String?, maxDate: String?

    // Один проход: разбор → окно → конверсия → классификация.
    // Раньше было два разбора одной строки (фильтр + цикл) плюс
    // отдельный map/sorted по всему отфильтрованному массиву ради
    // границ периода.
    for tx in transactions {
        guard let txDate = FastDateParser.date(from: tx.date) else { continue }
        guard txDate >= filterStart, txDate < filterEnd else { continue }

        let amountInBase: Double
        if tx.currency == baseCurrency {
            amountInBase = tx.amount
        } else if let fx = rates.convert(tx.amount, from: tx.currency, to: baseCurrency) {
            amountInBase = fx
        } else {
            amountInBase = tx.convertedAmount ?? tx.amount
        }

        switch tx.type.summaryContribution(isFuture: txDate > today) {
        case .income:            totalIncome += amountInBase
        case .expense:           totalExpenses += amountInBase
        case .internalTransfer:  totalInternal += amountInBase
        case .plannedExpense:    plannedExpenses += amountInBase
        case .ignored:           break
        }

        // Границы периода — min/max за тот же проход вместо
        // filtered.map { $0.date }.sorted() (аллокация + O(n log n)).
        if minDate == nil || tx.date < minDate! { minDate = tx.date }
        if maxDate == nil || tx.date > maxDate! { maxDate = tx.date }
    }

    return Summary(
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        totalInternalTransfers: totalInternal,
        netFlow: totalIncome - totalExpenses,
        currency: baseCurrency,
        startDate: minDate ?? "",
        endDate: maxDate ?? "",
        plannedAmount: plannedExpenses
    )
}
```

Заодно убирается `filtered.map { $0.date }.sorted()` — лишняя аллокация массива строк плюс сортировка O(n log n) ради двух значений. Лексикографическое сравнение строк `yyyy-MM-dd` эквивалентно хронологическому, так что `min`/`max` по строке корректны.

**Проверка**: `SummaryContributionTests` должны остаться зелёными — они пинят правило классификации. Сверить итоги сводки на главном экране до и после для всех пресетов периода.

---

### 2.5 Перевести кэш дат на ключ-строку *(P0-3)*

**Файл**: [`Tenra/ViewModels/TransactionStore.swift:227`](../../Tenra/ViewModels/TransactionStore.swift#L227)

```swift
// Было: 19 000 записей, ключ — 36-символьный UUID
@ObservationIgnored internal(set) var parsedDateById: [String: Date] = [:]

// Стало: ~1 800 записей, ключ — 10-символьная строка даты.
// Много транзакций делят одну дату; InsightsService.PreAggregatedData.txDateMap
// уже использует эту схему — приводим store к ней же.
@ObservationIgnored internal(set) var parsedDateByDateString: [String: Date] = [:]
```

Затрагиваемые места чтения:
- `TransactionStore+AccountAggregates.swift:107` — `parsedDateById[tx.id]` → `parsedDateByDateString[tx.date]`
- `TransactionStore+SeriesIndex.swift:22, 30, 48, 50, 83, 100` — сопровождение индекса
- `TransactionStore+LoadSnapshot.swift:37, 106-107, 129-130, 227` — построение снапшота

Инкрементальное сопровождение сильно упрощается: при удалении транзакции **нельзя** удалять запись по дате (её могут делить другие транзакции). Проще всего — не удалять вовсе: словарь ограничен количеством уникальных дат и растёт логарифмически, максимум несколько тысяч записей за годы использования. Полная перестройка происходит на каждом холодном старте.

**Проверка**: `TenraTests` целиком. Особое внимание — тестам агрегатов счетов и индексов серий.

**Критерий выхода Фазы 2**: `xcodebuild test -only-testing:TenraTests` зелёный; трейс показывает падение времени до `isFullyInitialized` и времени пересчёта сводки согласно таблице.

---

## Фаза 3 — Снапшот курсов валют (полдня) *(P1-5)*

**Новый файл**: `Tenra/Services/Currency/RateSnapshot.swift`

```swift
//  Неизменяемый снимок курсов для массовых расчётов.
//
//  Зачем: CurrencyConverter.convertSync берёт NSLock дважды за вызов
//  (по разу на каждую валюту). В цикле по 19k транзакциям — 38 000
//  захватов блокировки за проход, плюс барьеры памяти мешают
//  векторизации цикла.
//
//  Второй, более важный эффект: снапшот ФИКСИРУЕТ курсы на всё время
//  расчёта. Если prewarm приземлится в середине цикла, convertSync
//  пересчитает первую половину по старым курсам, а вторую — по новым,
//  и итог окажется внутренне несогласованным. Флаг aggregatesAreFXStale
//  ловит холодный кэш, но не этот сценарий.

import Foundation

struct RateSnapshot: Sendable {
    private let rates: [String: Double]

    /// Снять на MainActor или в фоне — один раз перед массовой операцией.
    nonisolated init() {
        self.rates = CurrencyRateStore.shared.cachedRates
    }

    /// Та же семантика KZT-пивота, что и у CurrencyConverter.convertSync.
    nonisolated func convert(_ amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }
        guard let fromRate = rate(for: from),
              let toRate = rate(for: to), toRate > 0 else { return nil }
        return amount * fromRate / toRate
    }

    private func rate(for currency: String) -> Double? {
        currency == "KZT" ? 1.0 : rates[currency]
    }
}
```

Подключить в циклах:

| Файл | Функция |
|---|---|
| `Services/Transactions/SummaryCalculator.swift` | `compute`, `computeTopExpenseWeights` |
| `ViewModels/TransactionStore+LoadSnapshot.swift` | `computeCategoryAggregates`, `computeAccountAggregates`, `coldConvertSource`, `coldConvertTarget` |
| `Services/Insights/InsightsService.swift` | `PreAggregatedData.build` |

`CurrencyConverter.convertSync` **оставить** для единичных вызовов — их сотни и переписывать их нет смысла.

> ⚠️ Логика `usedStaleFallback` / `aggregatesAreFXStale` должна сохраниться: пустой снапшот (`rates.isEmpty`) означает холодный кэш, `convert` возвращает `nil`, вызывающая сторона ставит флаг ровно как сейчас. Не потерять — иначе мультивалютные агрегаты перестанут самолечиться при приземлении курсов (см. CLAUDE.md ⚠️ #12).

**Проверка**: тесты конверсии валют. Помнить про требования из CLAUDE.md — сюита, мутирующая `CurrencyRateStore.shared`, должна быть `@MainActor` и вызывать `clearAll()` в `init()`.

---

## Фаза 4 — Память: индексы по идентификаторам (1–1.5 дня) *(P1-2)*

Более объёмная механическая правка. Делать **после** Фаз 1–3 и только при подтверждённом Instruments давлении на память.

### 4.1 Заменить группирующие словари

**Файл**: `Tenra/ViewModels/TransactionStore.swift`

```swift
// Было — три словаря с полными значениями Transaction (256 байт каждое):
@ObservationIgnored internal(set) var transactionsByAccount: [String: [Transaction]]
@ObservationIgnored internal(set) var transactionsByCategoryName: [String: [Transaction]]
@ObservationIgnored internal(set) var transactionsBySeriesId: [String: [Transaction]]

// Стало — идентификаторы; разрешение через transactionById за O(1):
@ObservationIgnored internal(set) var transactionIdsByAccount: [String: [String]]
@ObservationIgnored internal(set) var transactionIdsByCategoryName: [String: [String]]
@ObservationIgnored internal(set) var transactionIdsBySeriesId: [String: [String]]
```

Добавить хелперы, чтобы места чтения менялись минимально:

```swift
func transactions(forAccount id: String) -> [Transaction] {
    transactionIdsByAccount[id]?.compactMap { transactionById[$0] } ?? []
}
func transactions(forSeries id: String) -> [Transaction] {
    transactionIdsBySeriesId[id]?.compactMap { transactionById[$0] } ?? []
}
func transactions(forCategoryName name: String) -> [Transaction] {
    transactionIdsByCategoryName[name]?.compactMap { transactionById[$0] } ?? []
}
```

### 4.2 Обновить места чтения

Полный список получить так:

```bash
grep -rn "transactionsByAccount\|transactionsByCategoryName\|transactionsBySeriesId" Tenra --include='*.swift'
```

Ожидаемо затронуты: `TransactionStore+AccountAggregates`, `+CategoryIndex`, `+SeriesIndex`, `+LoadSnapshot`, `AccountDetailView`, `CategoryDetailView`, `SubscriptionDetailView`, `SubscriptionEditView`, `LinkPaymentsView`.

### 4.3 Обновить построение снапшота

`TransactionStore+LoadSnapshot.buildLoadSnapshot` — накапливать `tx.id` вместо `tx`. Поля структуры `LoadedIndexSnapshot` меняются на `[String: [String]]`.

**Ожидаемая экономия**: ~10 МБ (~25 МБ → ~13 МБ индексов после учёта Фазы 2.5).

**Проверка**: полный прогон `TenraTests`. Ручная проверка экранов деталей — счёт, категория, подписка, вклад, кредит — списки транзакций и суммы совпадают.

> ⚠️ Помнить про порядок: `compactMap` по идентификаторам сохраняет порядок вставки, как и раньше. Но там, где код полагался на порядок внутри `transactionsBySeriesId` (генерация повторяющихся операций), проверить явно.

---

## Фаза 5 — Гигиена (полдня, можно параллельно)

### 5.1 Дедуплицировать иконку приложения *(P2-3)*

Все четыре PNG байт-идентичны (`md5 b31cb8bbecdf9c315989ca929c234f24`).

```bash
rm "Tenra/Assets.xcassets/AppIcon.appiconset/App Icon3 1.png"
rm "Tenra/Assets.xcassets/AppIcon.appiconset/App Icon3 2.png"
```

Из `Tenra/Assets.xcassets/AppIcon.appiconset/Contents.json` убрать обе записи с `appearances` — останется одна универсальная. iOS 18+ корректно откатится на неё для тёмного и тонированного режимов.

Для `LaunchIcon.imageset` — либо оставить (одна копия, 692 КБ), либо, если он показывает ту же иконку, использовать `AppIcon` напрямую.

**Проверка**: собрать, установить, посмотреть иконку в светлой и тёмной теме, а также в тонированном режиме (Настройки → Экран «Домой» → Тонировать).

**Экономия**: ~1.4 МБ гарантированно, до ~2 МБ если компилятор ассетов не дедуплицировал.

### 5.2 Разобрать предупреждения об изоляции акторов *(P2-2)*

98 предупреждений, сконцентрированы в `Services/Insights/*`. Под Swift 6 language mode каждое станет ошибкой.

Приоритет по файлам:

```
InsightsService+Savings.swift       16
InsightsService+Recurring.swift     14
InsightsService+Spending.swift      13
InsightsService+Forecasting.swift   12
InsightsService+CashFlow.swift       6
```

Схема лечения одна: добавить `nonisolated` к чистым статическим хелперам, которые `nonisolated`-сервис вызывает из фонового контекста. Прецедент — `LedgerPolicyRule.isRealized` ([../concurrency.md](../concurrency.md#default-isolation-gotcha)).

Порядок модификаторов — уровень доступа **всегда** первым: `private nonisolated func`, никогда не `nonisolated private`.

### 5.3 Убрать 24 предупреждения `initialization of immutable value`

Механическая чистка неиспользуемых `let`. Заодно посмотреть на `TransactionStore+LoadSnapshot.swift:206-207`:

```swift
var (cat, fxStale) = computeCategoryAggregates(...)
coldStartCategoryAggregates = cat
coldStartCategoryAggregatesAreFXStale = fxStale
_ = cat        // ← мёртвый код
_ = fxStale    // ← мёртвый код
```

`var` здесь тоже должен быть `let`.

---

## Что сознательно НЕ делаем

Зафиксировано, чтобы не всплывало снова:

| Идея | Почему нет |
|---|---|
| Сменить `Transaction.date` на `Date` | 155 мест разбора, весь CSV round-trip, сортировка по строке, `Codable`-совместимость с бэкапами. `FastDateParser` даёт 95 % выигрыша за 5 % риска. Пересмотреть, если появится схема v13 по другим причинам. |
| Считать сводку главного экрана из `categoryAggregatesByKey` | Настоящая архитектурная победа (O(категорий) вместо O(19k)), но Фаза 2 и так снимает задержку до ~30 мс. Отложить до момента, когда набор данных вырастет кратно. |
| Оконная загрузка транзакций (не все 19k в памяти) | Ломает контракт единственного источника истины у `TransactionStore`, от которого зависят все O(1)-индексы. 4.75 МБ базового массива — приемлемо; проблема в дублировании индексов, а её решает Фаза 4. |
| Убрать блоки `#Preview` ради времени сборки | 387 превью — реальная стоимость тайп-чека, но превью ценны для разработки, и Xcode не рендерит их в CI. Не трогать. |
| Заменить `os.Logger.debug` на условную компиляцию | Под `-O` компилятор уже вставляет проверку уровня перед сериализацией аргументов. Затраты близки к нулю. |

---

## Порядок выполнения и контрольные точки

```
Фаза 0  Базовая линия ──────────────────┐  ОБЯЗАТЕЛЬНО ПЕРВОЙ
                                        │
Фаза 1  Быстрые победы ─────────────────┤  независимы, один коммит
  1.1 loadBackups с крит. пути          │
  1.2 локаль (баг корректности)         │
  1.3 материализация секций Истории     │
  1.4 тайп-чек MiniProportionBar        │
                                        │  ← замер, сверка с базой
Фаза 2  FastDateParser ─────────────────┤  наибольший эффект
  2.1 утилита                           │
  2.2 пин-тесты          ← ГЕЙТ         │
  2.3 замена в горячих путях            │
  2.4 один проход в SummaryCalculator   │
  2.5 кэш дат по строке                 │
                                        │  ← замер
Фаза 3  RateSnapshot ───────────────────┤  зависит от 2.4
                                        │  ← замер
Фаза 4  Индексы по id ──────────────────┤  только при подтверждённом
                                        │    давлении на память
                                        │  ← замер
Фаза 5  Гигиена ────────────────────────┘  можно параллельно с 3/4
```

### Критерии приёмки

| Метрика | Цель |
|---|---|
| Время до первого кадра | −100 мс и лучше (iCloud-пользователи) |
| Время до `isFullyInitialized` | −350 мс и лучше |
| Обновление карточки сводки | < 100 мс (сейчас ~1.0–1.3 с, оценка) |
| Persistent-память после старта | −8 МБ и лучше (после Фазы 4) |
| `xcodebuild test -only-testing:TenraTests` | зелёный на каждой фазе |
| Предупреждения сборки | 188 → < 90 (после Фазы 5) |
| Регрессии поведения | ноль |

### Заметки по прогону тестов

Из CLAUDE.md, чтобы не потерять время:

- Фильтровать **на уровне сюиты**, по **имени типа**: `-only-testing:TenraTests/FastDateParserTests`. Фильтр по методу молча выполняет 0 тестов и печатает `TEST SUCCEEDED`. Отображаемое имя из `@Suite("...")` — тоже 0 тестов.
- Разбирать результат так: `grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"`. Не грепать `expect` — попадают предупреждения компилятора про `#expect`.
- Полный прогон может напечатать `** TEST FAILED **` при нуле упавших `Test case` — флак параллельных клонов. Перезапустить ту же команду один раз перед расследованием.
- Сюита, конструирующая MainActor-изолированные типы, должна быть помечена `@MainActor`.

### Заметки по замерам

- Профилировать на **физическом устройстве** `Dkicekeeper 17`, не в Симуляторе.
- **Отсоединить отладчик** перед измерением — флуд `os.Logger.debug` под отладчиком раздувал реальный <1 с старт в измеренные 4–6 с ([../gotchas.md](../gotchas.md#build--profiling)).
- Отключить автоблокировку экрана на время записи трейса.
- Перед профилированием открыть Xcode → Window → Devices and Simulators, чтобы «прогреть» соединение.
- Если `xctrace` падает 2–3 раза подряд — бросить трейс и опираться на логи `[INIT]` из Console.app.

---

## Обновление документации по завершении

Выполнено 2026-07-28.

- [x] [`docs/gotchas.md`](../gotchas.md) — три новых раздела: «Date parsing» (стоимость `DateFormatter.date(from:)`, неравномерная строгость, требование `en_US_POSIX`, ключевание кэша по строке даты), «Grouping indexes store ids, not values», «Currency conversion in bulk loops».
- [x] [`docs/architecture.md`](../architecture.md) — раздел «Grouping indexes (id-based)» с таблицей соответствия хранилище ↔ view, правилом «привязывай бакет к `let`» и требованием `ensureTransactionByIdInSync()`; в список O(1)-индексов добавлен `parsedDateByDateString`.
- [x] [`docs/domains/currency.md`](../domains/currency.md) — раздел «`RateSnapshot` — for bulk loops»: оба обоснования (трафик локов и консистентность курсов внутри одного прохода), список текущих мест применения, граница «единичные конверсии остаются на `convertSync`».
- [x] [`CLAUDE.md`](../../CLAUDE.md) — красный флаг #15 про `FastDateParser`; заодно поправлена строка про индексы `TransactionStore` (`internal(set)` → `var`, ссылка на `TransactionIndex`).
- [x] `docs/CACHE_AUDIT.md` (с тех пор заархивирован в [`archive/CACHE_AUDIT_2026_06_03.md`](../archive/CACHE_AUDIT_2026_06_03.md)) — консолидация трёх кэшей дат, новое правило инвалидации (не выселять по дате при удалении транзакции), баг с локалью описан как тот же класс «забытого измерения», плюс FX-консистентность как ранее не названное измерение.

Также помечены как реализованные шапки [аудита](../PERFORMANCE_AUDIT_2026_07.md) и этого плана.
