# История: нижняя навигация в стиле Apple Photos — дизайн

**Дата:** 2026-08-26
**Статус:** утверждён пользователем (сессия 2026-08-26)

## Контекст

Сага верхней панели фильтров + поиска в Истории (iOS 26/27): все системные варианты `.searchable` в навбаре либо ломали хит-тестинг чипов, либо рисовали неотключаемую непрозрачную подложку за верхним блоком, либо переставали закрываться; кастомная строка поиска отвергнута пользователем (правило: только системный поиск). Решение — перенос всей навигации экрана вниз, как в Apple Photos.

## Дизайн

### Верх
- Только системный навбар: назад + «History» (inline). Никаких фильтров/поиска сверху.
- Верхний блок (VStack: спейсер, HistoryFilterSection, кастомный searchRow, кастомная лупа) удаляется полностью; List — единственный контент, скроллится под навбар со штатным системным эффектом.

### Низ (История)
- Таббар приложения скрыт на этом экране: `.toolbar(.hidden, for: .tabBar)` (прецедент CloudBackupsView; НЕ трогать стабильного владельца `TabBarVisibility`).
- Системный нижний тулбар:
  - `ToolbarItemGroup(placement: .bottomBar)`: три иконки-кнопки — `calendar` (период → showingTimeFilter), `wallet.bifold` (счёт → showingAccountFilter), `tag` (категория → showingCategoryFilter). Активный фильтр: заполненный вариант символа + tint `AppColors.accent`. Accessibility-лейблы из существующих ключей (`filter.allAccounts`, `filter.allCategories`, displayName периода) — новых ключей локализации НЕ добавлять.
  - `ToolbarSpacer(.flexible, placement: .bottomBar)`.
  - `DefaultToolbarItem(kind: .search, placement: .bottomBar)` + существующий `.searchable(text:isPresented:prompt:)` — весь поиск системный.
- Все шторки фильтров и логика (`HistoryFilterCoordinator`, дебаунс) не меняются.

### Глобально
- `MainTabView`: `.tabBarMinimizeBehavior(.onScrollDown)` на TabView — таббар сжимается при скролле вниз на всех табах.

### Чистка
- `Tenra/Views/Components/Input/HistoryFilterSection.swift` удалить (единственный потребитель — HistoryView; проверить grep'ом перед удалением).
- `@FocusState isSearchFieldFocused`, `searchRow`, `closeSearch()` удалить из HistoryView.

## Проверка (обязательна на устройстве)
- `HistoryFilterUITests` обновить: фильтры = нижние тулбар-кнопки (по accessibility-лейблам), поиск = системная кнопка внизу → `app.searchFields`; сценарии: открытие шторки счёта наверху и после скролла; поиск: раскрыть → набрать → стереть → закрыть.
- Прогон: iPhone iOS 27 (`TEST_RUNNER_NO_DEMO=1`) + Simulator iOS 26.2 (демо-режим).
- Визуально по скриншотам: нет плашки за навбаром (обе темы), нижние капсулы, поведение search-кнопки; конфликт с «+»-табом (role: .search) исключён скрытием таббара.

## Риски
- `DefaultToolbarItem(kind:.search)` на запушенном экране внутри TabView — поведение на iOS 27 проверяется тестом; при сбое системного нижнего поиска остаётся вариант search-кнопка → `isSearchActive` + `.searchable` без DefaultToolbarItem.
- Скрытие таббара уводит «+» с экрана Истории — принято дизайном (как в Photos, добавление доступно с других экранов).
