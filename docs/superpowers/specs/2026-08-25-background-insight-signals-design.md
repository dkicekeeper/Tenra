# Органичные фоновые пуши инсайт-сигналов — дизайн

**Дата:** 2026-08-25
**Статус:** утверждён (брейншторм в сессии от 2026-08-25)
**Контекст:** закрывает отложенный follow-up №1 из `docs/archive/INSIGHTS_PRODUCT_AUDIT_2026_07_13.md` (BGAppRefreshTask) и запрос пользователя: пуши должны приходить фоном, в разное время, «органично», а не пачкой сразу после пересчёта в приложении.

## Проблема

Сигнальные пуши (`InsightSignalService`) вычисляются только при пересчёте инсайтов внутри приложения (вкладка «Аналитика»). Пока приложение закрыто, новых сигналов нет; после долгого отсутствия первый пересчёт отправляет несколько пушей почти одновременно (сейчас смягчено лимитом 2/пересчёт + разнос 3 минуты, коммит `faaeed6`). Хочется: доставку в «естественные» времена дня и реальное фоновое обновление.

## Решение: два уровня

### Уровень 1 — фоновый пересчёт (`BackgroundInsightsRefresher`)

Новый файл `Tenra/Services/Insights/BackgroundInsightsRefresher.swift`.

- **Идентификатор задачи:** `dakacom.Tenra.insightsRefresh` (BGAppRefreshTask).
- **Регистрация:** в `AppDelegate.application(_:didFinishLaunchingWithOptions:)` (регистрация обязана произойти до конца launch).
- **Планирование submit:** при уходе в фон (`scenePhase → .background` в `TenraApp` — onChange уже существует) и в конце каждого фонового прогона. `earliestBeginDate = now + 4 часа`. iOS исполняет best-effort — фактически несколько раз в день, время выбирает система.
- **Прогон (handler):**
  1. Ранние выходы: мастер-тумблер сигналов И дайджест выключены (`InsightSignalSettings`); нотификации не авторизованы; загрузка данных пуста.
  2. Данные напрямую из `CoreDataRepository` (без `AppCoordinator`/`TransactionStore`/ViewModels — ноль UI-побочных эффектов): транзакции, счета, категории, рекуррентные серии, базовая валюта из настроек.
  3. `balanceFor` — персистентный `account.balance` (поддерживается `BalanceCoordinator.persistBalance` при работе приложения).
  4. `InsightsService.PreAggregatedData.build(...)` + `computeGranularities([.month, .week], ...)` со свежесозданными `TransactionCacheManager` и `TransactionCurrencyService`.
  5. `InsightSignalService.processInsights(monthInsights)` → пуши через оконный планировщик (уровень 2).
  6. `WeeklyDigestScheduler.reschedule(weekPoints:baseCurrency:)` — дайджест обновляется свежими данными.
  7. `task.setTaskCompleted(success:)` вызывается ВСЕГДА; expiration handler отменяет вычислительный `Task`.

**Ограничение (осознанное):** фоновый прогон не генерирует догон рекуррентных транзакций и депозитных процентов (это машинерия MainActor-стора). Пересчёт видит данные на момент последнего открытия плюс уже записанное. Для сигналов-переходов приемлемо.

### Уровень 2 — оконный планировщик доставки (в `InsightSignalService`)

Заменяет текущий разнос «первый сразу, второй +3 минуты».

- **Чистая функция** `nonisolated static func deliveryDates(count:now:calendar:rng:) -> [Date]`:
  - окно доставки **09:00–21:00** локального времени;
  - первая дата = `now`, если внутри окна; иначе следующее утро в случайное время 09:00–10:30;
  - каждая следующая = предыдущая + случайные 2–4 часа; вылет за 21:00 переносится на следующее утро (09:00–10:30) с продолжением цепочки;
  - `rng: inout some RandomNumberGenerator` — параметр для детерминированных тестов (в проде `SystemRandomNumberGenerator`).
- `processInsights` планирует пуши: дата ≈ now → `trigger: nil` (как сейчас), будущая дата → `UNCalendarNotificationTrigger` (компоненты y/m/d/h/m, `repeats: false`).
- Лимиты не меняются: 7-дневный дедуп по id, 5/неделя, 2/пересчёт. С фоновыми прогонами несколько раз в день сигналы растекаются по дню естественно.

### Отмена неактуального (stale-guard)

При каждом `processInsights`:
- получить pending-запросы с префиксом `insightSignal_`;
- вычислить eligible-набор из свежих инсайтов: critical/warning + включённый тип (`InsightSignalKind.from` + `enabledKinds`) — БЕЗ фильтра по истории дедупа (запланированный сигнал уже в истории);
- pending id ∉ eligible → `removePendingNotificationRequests`;
- записи истории НЕ удаляются при отмене — «мигающий» сигнал не должен пушиться повторно;
- контент валидных pending не обновляется (устаревание на часы приемлемо для алерта-перехода; YAGNI).

Логика «что отменить» выносится в чистую функцию `(pendingIds:eligibleIds:) -> Set<String>` для юнит-теста.

## Изменения в проекте

- `Tenra/Info.plist`: `UIBackgroundModes = [fetch]`, `BGTaskSchedulerPermittedIdentifiers = [dakacom.Tenra.insightsRefresh]`. Entitlements не нужны.
- Новый файл подхватывается сборкой автоматически (file-system-synchronized groups).

## Обработка ошибок

- Handler обёрнут целиком: любая ошибка → `setTaskCompleted(success: false)` + submit следующего прогона.
- Expiration handler: `computeTask.cancel()`; проверки `Task.isCancelled` между фазами (загрузка → пересчёт → доставка).
- Двойная регистрация/двойной submit BGTaskScheduler переживает штатно (submit заменяет pending request).

## Тестирование

Юнит-тесты (`TenraTests`):
- `deliveryDates`: now внутри окна → первая = now; ночь (23:00) → утро 09:00–10:30; переполнение окна цепочкой → перенос на следующий день; сидированный rng → детерминированный результат; count 0/1.
- Функция отмены: pending ⊂ eligible → пусто; pending ∖ eligible → отменяются; пустые входы.
- Существующие `InsightSignalServiceTests` (selectSignals) не меняются.

Ручная проверка BGAppRefresh — только на устройстве (симулятор BGTaskScheduler не поддерживает), после паузы в дебаггере:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"dakacom.Tenra.insightsRefresh"]
```

## Обновление доков

- `docs/domains/insights.md` §Signal notifications: снять «Known limitation» про пересчёт только на вкладке Аналитики, описать BGAppRefresh + окно доставки.
- `docs/archive/INSIGHTS_PRODUCT_AUDIT_2026_07_13.md` не трогаем (архив).
