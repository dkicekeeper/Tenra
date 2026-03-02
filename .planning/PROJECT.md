# AIFinanceManager

## What This Is

Нативное iOS-приложение для личных финансов на SwiftUI + CoreData. Позволяет отслеживать счета, транзакции, бюджеты, депозиты и повторяющиеся платежи с ML-инсайтами и голосовым вводом. Целевая аудитория — один пользователь, без облачной синхронизации.

## Core Value

Точный учёт финансов с мгновенным откликом — приложение не должно терять данные, зависать или давать неверные цифры.

## Requirements

### Validated

Существующий функционал (Phase 1–42):

- ✓ Управление счетами (текущие, депозиты, с процентами) — Phase 1–4
- ✓ Добавление/редактирование/удаление транзакций — Phase 7
- ✓ Категории, подкатегории, бюджеты по категориям — Phase 10
- ✓ Повторяющиеся платежи и подписки — Phase 9
- ✓ Импорт CSV (19k строк, NSBatchInsertRequest) — Phase 28, 35
- ✓ Голосовой ввод транзакций — Phase 10+
- ✓ Парсинг PDF-выписок — Phase 10+
- ✓ InsightsService — 10 типов инсайтов, 5 гранулярностей, HealthScore — Phase 24, 38, 42
- ✓ TransactionStore как SSOT — Phase 7, 16, 40
- ✓ Прогрессивная инициализация (<50ms fast-path) — Phase 28
- ✓ Skeleton loading — Phase 30
- ✓ Design system (AppColors, AppSpacing, AppTypography и др.) — Phase 32–34
- ✓ PreAggregatedData — O(N) single pass для Insights — Phase 42
- ✓ ContentView полностью реактивен через `.task(id:)` — Phase 39

### Active

Milestone: **Tech Debt & Safety** (текущий):

- [ ] Удалить `RecurringTransactionService` (558 LOC, DispatchSemaphore дедлок-риск)
- [ ] Исправить DateFormatter race в `TransactionQueryService`
- [ ] Включить CoreData `.NSFileProtectionComplete`
- [ ] Добавить upper-bound валидацию сумм в `AmountInputView`
- [ ] Удалить 4 deprecated файла (`TransactionConverterService`, 2 протокола, deprecated секция кэша)
- [ ] Закрыть TODO в `UnifiedTransactionCache` (prefix invalidation → full invalidation)
- [ ] Оптимизировать `.allTime` Insights (307ms → добавить `categoryTotals` в `PreAggregatedData`)
- [ ] Начать разбивку `TransactionStore` (1213 LOC) — вынести Recurring в `RecurringStore`
- [ ] Написать критичные тесты: `DepositInterestService`, `CategoryBudgetService`, `RecurringTransactionGenerator` edge cases, CoreData round-trip
- [ ] CoreData explicit migration для deprecated aggregate entities

### Out of Scope

- iCloud / CloudKit sync — масштабный рефакторинг, отдельный milestone
- Многопользовательский режим — personal finance app, single user by design
- Новые UI-фичи — этот milestone только о надёжности и чистоте кода
- Полное переписывание `TransactionStore` — только первый шаг (Recurring extract)

## Context

- 42 фазы разработки, ~19k транзакций в памяти (7.6 MB)
- `SWIFT_STRICT_CONCURRENCY = targeted` — не `full`; часть нарушений скрыта
- CoreData schema содержит deprecated entities (MonthlyAggregateEntity, CategoryAggregateEntity) без migration model
- 0 UITests на 132 SwiftUI views; частичное покрытие ViewModels и Services
- `RecurringTransactionService.swift` — единственный файл с активным дедлок-риском (8x `DispatchSemaphore.wait()` на `@MainActor`)
- Codebase map: `.planning/codebase/`

## Constraints

- **Tech Stack**: Swift/SwiftUI/CoreData — no new external dependencies
- **iOS Target**: 26.0+ (Xcode 26 beta)
- **Breaking changes**: Нельзя менять публичный API `TransactionStore` — Views зависят от него напрямую
- **Concurrency**: Все изменения должны компилироваться с `SWIFT_STRICT_CONCURRENCY = targeted`
- **Data safety**: Любые изменения в Repository слое требуют проверки с `resetAllData()` → import cycle

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| DispatchSemaphore → удалить весь файл | Частичное исправление опаснее полного удаления | — Pending |
| UnifiedTransactionCache: full invalidation вместо prefix | Проще, менее рискованно, достаточно для текущей нагрузки | — Pending |
| TransactionStore: только Recurring extract | Минимальный риск регрессий; полный split — следующий milestone | — Pending |
| CoreData file protection: `.complete` | Финансовые данные; iOS применяет при locked screen | — Pending |

---
*Last updated: 2026-03-02 after initialization*
