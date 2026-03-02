# Requirements: AIFinanceManager — Tech Debt & Safety Milestone

**Defined:** 2026-03-02
**Core Value:** Точный учёт финансов с мгновенным откликом — приложение не должно терять данные, зависать или давать неверные цифры.

## v1 Requirements

### Safety (Активные риски — дедлок и гонки)

- [x] **SAFE-01**: Удалить `RecurringTransactionService.swift` (558 LOC) — мигрировать все активные call sites в `TransactionStore+Recurring.swift`
- [x] **SAFE-02**: Удалить `RecurringTransactionServiceProtocol.swift` (59 LOC) после завершения SAFE-01
- [x] **SAFE-03**: Исправить `DateFormatter` race в `TransactionQueryService` — объявить `@MainActor private static let`, форматировать на MainActor, передавать `String` в `Task.detached`

### Security (Безопасность данных)

- [x] **SEC-01**: Включить `NSFileProtectionComplete` для CoreData SQLite store в `CoreDataStack.swift`
- [x] **SEC-02**: Добавить upper-bound валидацию (≤ 999_999_999.99) в `AmountInputView` и вызывать `AmountFormatter.validate()` перед принятием суммы

### Cleanup (Мёртвый код)

- [x] **CLN-01**: Удалить `Services/CSV/TransactionConverterService.swift` (5 LOC, deprecated Phase 37)
- [x] **CLN-02**: Удалить `Protocols/TransactionConverterServiceProtocol.swift` (6 LOC, no implementations)
- [x] **CLN-03**: Удалить deprecated секцию Account Balance Cache из `TransactionCacheManager.swift` (~77 LOC)
- [x] **CLN-04**: Закрыть TODO в `UnifiedTransactionCache.swift` — заменить незаконченный prefix invalidation на full invalidation per event

### Performance (Производительность)

- [ ] **PERF-01**: Добавить `categoryTotals: [String: Decimal]` в `PreAggregatedData.build()` — устранить O(N) группировку по категориям при каждой гранулярности Insights (`.allTime` 307ms → <50ms)
- [ ] **PERF-02**: Вынести Recurring методы из `TransactionStore` в отдельный `RecurringStore` (~200 LOC извлечь) — первый шаг разбивки 1213-LOC монолита

### Testing (Критичное покрытие)

- [ ] **TEST-01**: Unit-тесты для `DepositInterestService` — расчёт процентов, граничные даты
- [ ] **TEST-02**: Unit-тесты для `CategoryBudgetService` — граничные периоды, budget rollover
- [ ] **TEST-03**: Unit-тесты для `RecurringTransactionGenerator` — leap year (Feb 29), month-end (Jan 31 → Feb 28/29), DST
- [ ] **TEST-04**: CoreData round-trip тест — save transaction → reload app → verify fields intact

### CoreData (Миграция схемы)

- [x] **DATA-01**: Создать explicit CoreData migration mapping model для deprecated aggregate entities (`MonthlyAggregateEntity`, `CategoryAggregateEntity`) — предотвратить crash при обновлении у пользователей со старой схемой

## v2 Requirements

### Testing (дополнительное покрытие)

- **TEST-05**: UI-тесты для Add/Edit/Delete Transaction flow
- **TEST-06**: Тест `InsightsViewModel` staleness flow и cache invalidation
- **TEST-07**: CSV import edge cases (emoji, дубликаты, неверная кодировка)
- **TEST-08**: CoreData concurrent writes (background save + viewContext read)

### Performance

- **PERF-03**: Полная разбивка `TransactionStore` — `AccountStore`, `RecurringStore`, `CachedMetadata`
- **PERF-04**: Увеличить `SWIFT_STRICT_CONCURRENCY` до `full` и исправить выявленные нарушения

### Security

- **SEC-03**: CSV import whitelist для column names (CSVColumnMapping.allCases enforcement)

## Out of Scope

| Feature | Reason |
|---------|--------|
| iCloud / CloudKit sync | Масштабный рефакторинг, отдельный milestone |
| Новые UI-фичи | Этот milestone — только надёжность |
| Полное переписывание TransactionStore | Слишком рискованно без тестов; PERF-02 — первый шаг |
| Swift 6 strict mode (full) | v2; сначала нужны тесты для безопасного перехода |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SAFE-01 | Phase 1 | Complete |
| SAFE-02 | Phase 1 | Complete |
| SAFE-03 | Phase 1 | Complete |
| CLN-01 | Phase 1 | Complete |
| CLN-02 | Phase 1 | Complete |
| CLN-03 | Phase 1 | Complete |
| CLN-04 | Phase 1 | Complete |
| SEC-01 | Phase 2 | Complete |
| SEC-02 | Phase 2 | Complete |
| DATA-01 | Phase 2 | Complete |
| PERF-01 | Phase 3 | Pending |
| PERF-02 | Phase 3 | Pending |
| TEST-01 | Phase 4 | Pending |
| TEST-02 | Phase 4 | Pending |
| TEST-03 | Phase 4 | Pending |
| TEST-04 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 16 total
- Mapped to phases: 16
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-02*
*Last updated: 2026-03-02 — traceability filled by roadmapper*
