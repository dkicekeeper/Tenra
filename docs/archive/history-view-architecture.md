# HistoryView Architecture

## 🏗️ Текущая Архитектура (До Оптимизации)

```
┌─────────────────────────────────────────────────────────────────┐
│                         HistoryView                             │
│                      (370 строк, 8 @State)                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Responsibilities:                                              │
│  • UI Layout & Coordination                                     │
│  • Filter Management (search, account, category, time)          │
│  • Cache Management (grouped transactions, sorted keys)         │
│  • Debouncing Logic (search 300ms, filters 150ms)              │
│  • Scroll Behavior (auto-scroll to today)                      │
│  • Day Expenses Calculation                                    │
│  • Empty State Logic                                           │
│  • Pagination Coordination                                     │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                         Dependencies                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  @ObservedObject transactionsViewModel: TransactionsViewModel   │
│  @ObservedObject accountsViewModel: AccountsViewModel           │
│  @ObservedObject categoriesViewModel: CategoriesViewModel       │
│  @EnvironmentObject timeFilterManager: TimeFilterManager        │
│  @StateObject paginationManager: TransactionPaginationManager   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
           │                    │                    │
           ▼                    ▼                    ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│HistoryFilterSec- │  │DateSectionHeader │  │  TransactionCard │
│     tion         │  │                  │  │                  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

### Проблемы:
- ❌ **Нарушение SRP:** View отвечает за слишком многое
- ❌ **Дублирование State:** Кеш в view + paginationManager
- ❌ **Сложность тестирования:** Логика смешана с UI
- ❌ **Высокая связанность:** Зависимость от 3 ViewModels

---

## 🎯 Целевая Архитектура (После Оптимизации)

```
┌─────────────────────────────────────────────────────────────────┐
│                         HistoryView                             │
│                    (150 строк, 3 @State)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Responsibilities:                                              │
│  • UI Layout & Coordination ONLY                                │
│  • Delegate to specialized components                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
           │
           ├──────────────┬──────────────┬──────────────┬─────────────
           ▼              ▼              ▼              ▼
┌─────────────────┐ ┌──────────────┐ ┌──────────────┐ ┌─────────────┐
│HistoryFilter    │ │HistoryScroll │ │DateSection   │ │History      │
│  Coordinator    │ │  Behavior    │ │ExpensesCache │ │Transactions │
│                 │ │              │ │              │ │   List      │
│ (ObservableObj) │ │   (Struct)   │ │(Observable)  │ │   (View)    │
└─────────────────┘ └──────────────┘ └──────────────┘ └─────────────┘
│                 │ │              │ │              │ │             │
│ • Search text   │ │ • Find scroll│ │ • Cache exp. │ │ • List UI   │
│ • Account filter│ │   target     │ │ • Invalidate │ │ • Sections  │
│ • Debouncing    │ │ • Today/     │ │ • Memoize    │ │ • Pagination│
│ • Reset filters │ │   Yesterday  │ │              │ │ • Scroll    │
└─────────────────┘ └──────────────┘ └──────────────┘ └─────────────┘
```

### Преимущества:
- ✅ **SRP Compliance:** Каждый компонент имеет одну ответственность
- ✅ **Легкость тестирования:** Изолированные unit-тесты
- ✅ **Переиспользуемость:** Компоненты можно использовать в других view
- ✅ **Читаемость:** Каждый компонент < 200 строк

---

## 📊 Диаграмма Потока Данных

### Фильтрация и Обновление

```
User Input
    │
    ├─→ Search Text ──────────────┐
    ├─→ Account Filter ───────────┤
    ├─→ Category Filter ──────────┤
    └─→ Time Filter ──────────────┤
                                  ▼
                      ┌────────────────────────┐
                      │HistoryFilterCoordinator│
                      │                        │
                      │ • Debounce search 300ms│
                      │ • Debounce filters 150 │
                      │ • Combine all filters  │
                      └────────────────────────┘
                                  │
                                  │ onChange(debouncedFilters)
                                  ▼
                      ┌────────────────────────┐
                      │   TransactionsViewModel│
                      │                        │
                      │ • filterTransactions() │
                      │ • groupByDate()        │
                      │ • sortKeys()           │
                      └────────────────────────┘
                                  │
                                  │ Filtered & Grouped
                                  ▼
                      ┌────────────────────────┐
                      │TransactionPagination   │
                      │       Manager          │
                      │                        │
                      │ • initialize(data)     │
                      │ • Load 10 sections     │
                      │ • hasMore?             │
                      └────────────────────────┘
                                  │
                                  │ visibleSections
                                  │ groupedTransactions
                                  ▼
                      ┌────────────────────────┐
                      │HistoryTransactionsList │
                      │                        │
                      │ • Render sections      │
                      │ • Show TransactionCard │
                      │ • Trigger loadMore     │
                      └────────────────────────┘
                                  │
                                  ▼
                              UI Update
```

---

## 🔄 Lifecycle Events

### onAppear
```
HistoryView.onAppear
    │
    ├─→ Set initial filters (account, category)
    │
    ├─→ Initialize debouncedSearchText
    │
    └─→ updateCachedTransactions()
            │
            ├─→ Filter transactions (ViewModel)
            │
            ├─→ Group & Sort (ViewModel)
            │
            └─→ Initialize pagination (Manager)
                    │
                    └─→ Load first page (10 sections)
```

### onChange(filter)
```
User changes filter
    │
    ├─→ HapticManager.selection()
    │
    ├─→ Cancel previous debounce task
    │
    ├─→ Wait 150ms (debounce)
    │
    └─→ updateCachedTransactions()
            │
            └─→ Same flow as onAppear
```

### onScroll (near end)
```
User scrolls to section N-3
    │
    └─→ HistoryTransactionsList
            │
            └─→ onAppear(sectionKey)
                    │
                    └─→ paginationManager.shouldLoadMore(sectionKey)
                            │
                            ├─→ YES: loadNextPage()
                            │       │
                            │       └─→ Append 10 more sections
                            │
                            └─→ NO: Do nothing
```

---

## 🧩 Component Responsibilities

### HistoryView (Coordinator)
```swift
struct HistoryView: View {
    // MARK: - Coordination Only
    // • Setup dependencies
    // • Pass data to child components
    // • Handle navigation
    // • Manage lifecycle (onAppear, onDisappear)

    // NO business logic
    // NO complex state management
    // NO filtering logic
    // NO calculation logic
}
```

### HistoryFilterCoordinator (State Management)
```swift
@MainActor
class HistoryFilterCoordinator: ObservableObject {
    // MARK: - Filter State
    @Published var selectedAccountFilter: String?
    @Published var searchText: String
    @Published var debouncedSearchText: String

    // MARK: - Business Logic
    // • Debounce search input
    // • Debounce filter changes
    // • Combine multiple filters
    // • Reset all filters

    // NO UI code
    // NO data fetching
}
```

### HistoryScrollBehavior (Pure Logic)
```swift
struct HistoryScrollBehavior {
    // MARK: - Pure Functions
    // • Calculate scroll target
    // • Find today/yesterday section
    // • Fallback to first section

    // NO state
    // NO side effects
    // ONLY pure calculations
}
```

### DateSectionExpensesCache (Performance)
```swift
@MainActor
class DateSectionExpensesCache: ObservableObject {
    // MARK: - Caching
    private var cache: [String: Double]

    // • Memoize day expenses
    // • Invalidate on data change
    // • Reduce recalculations

    // NO UI code
    // NO filter logic
}
```

### HistoryTransactionsList (Presentation)
```swift
struct HistoryTransactionsList: View {
    // MARK: - UI Presentation
    // • Render list of transactions
    // • Show section headers
    // • Handle pagination triggers
    // • Display loading states

    // NO filter logic
    // NO complex calculations
    // ONLY presentation
}
```

---

## 🔀 State Flow Comparison

### Before (Messy)
```
HistoryView
    │
    ├─ @State searchText ──────────────┐
    ├─ @State debouncedSearchText ─────┤
    ├─ @State selectedAccountFilter ───┤
    ├─ @State searchTask ──────────────┤  ALL IN ONE PLACE
    ├─ @State filterTask ──────────────┤  = HARD TO MANAGE
    ├─ @State cachedGrouped ───────────┤
    ├─ @State cachedSorted ────────────┤
    └─ @StateObject paginationManager ─┘
```

### After (Clean)
```
HistoryView
    │
    ├─ @StateObject filterCoordinator
    │       ├─ searchText
    │       ├─ debouncedSearchText
    │       ├─ selectedAccountFilter
    │       └─ Internal debounce tasks
    │
    ├─ @StateObject expensesCache
    │       └─ Internal cache dictionary
    │
    └─ @StateObject paginationManager
            ├─ visibleSections
            ├─ groupedTransactions
            └─ Internal state
```

---

## 📈 Performance Optimizations

### 1. Memoization Flow
```
User scrolls
    │
    └─→ dateHeader(for: "2024-01-15") called
            │
            └─→ expensesCache.getExpenses(...)
                    │
                    ├─→ Cache HIT? ──→ Return cached (0.1ms)
                    │                      ✅ FAST
                    │
                    └─→ Cache MISS? ──→ Calculate + Cache (3ms)
                                           First time only
```

### 2. Debouncing Strategy
```
User types "food"
    │
    ├─ "f" ──→ Start 300ms timer ──→ Cancelled by "o"
    ├─ "o" ──→ Start 300ms timer ──→ Cancelled by "o"
    ├─ "o" ──→ Start 300ms timer ──→ Cancelled by "d"
    └─ "d" ──→ Start 300ms timer ──→ Completed!
                                      │
                                      └─→ Update filter (once)
```

### 3. Pagination Loading
```
Initial Load: 10 sections (fast, ~50ms)
    │
User scrolls
    │
    ├─→ Reach section 8 (trigger at N-3)
    │       │
    │       └─→ Load next 10 sections (background)
    │
    └─→ Smooth scroll, no janks
```

---

## 🧪 Testing Strategy

### Unit Tests

#### HistoryFilterCoordinator
```swift
class HistoryFilterCoordinatorTests: XCTestCase {
    func testSearchDebouncing() { ... }
    func testFilterDebouncing() { ... }
    func testResetFilters() { ... }
    func testCombinedFilters() { ... }
}
```

#### HistoryScrollBehavior
```swift
class HistoryScrollBehaviorTests: XCTestCase {
    func testScrollToToday() { ... }
    func testScrollToYesterday() { ... }
    func testScrollToFirstPastSection() { ... }
    func testScrollFallback() { ... }
}
```

#### DateSectionExpensesCache
```swift
class DateSectionExpensesCacheTests: XCTestCase {
    func testCacheHit() { ... }
    func testCacheMiss() { ... }
    func testCacheInvalidation() { ... }
    func testCorrectCalculation() { ... }
}
```

### Integration Tests
```swift
class HistoryViewIntegrationTests: XCTestCase {
    func testFilterApplication() { ... }
    func testPaginationFlow() { ... }
    func testSearchWithFilters() { ... }
}
```

---

## 📦 File Structure (After Refactoring)

```
Views/
├── HistoryView.swift (150 lines) ✨ Simplified
├── History/
│   ├── HistoryTransactionsList.swift (NEW)
│   ├── HistoryScrollBehavior.swift (NEW)
│   └── DateSectionExpensesCache.swift (NEW)
└── Components/
    ├── HistoryFilterSection.swift (existing)
    ├── DateSectionHeader.swift (existing)
    └── TransactionCard.swift (existing)

ViewModels/
├── TransactionsViewModel.swift (existing)
├── AccountsViewModel.swift (existing)
├── CategoriesViewModel.swift (existing)
└── HistoryFilterCoordinator.swift (NEW) ✨

Managers/
└── TransactionPaginationManager.swift (existing)
```

---

## 🎯 Migration Path

### Step 1: Extract Cache Logic
```
HistoryView.swift (370 lines)
    │
    └─→ Extract ─→ DateSectionExpensesCache.swift (50 lines)
            │
            └─→ HistoryView.swift (340 lines)
```

### Step 2: Extract Filter Logic
```
HistoryView.swift (340 lines)
    │
    └─→ Extract ─→ HistoryFilterCoordinator.swift (100 lines)
            │
            └─→ HistoryView.swift (270 lines)
```

### Step 3: Extract Scroll Logic
```
HistoryView.swift (270 lines)
    │
    └─→ Extract ─→ HistoryScrollBehavior.swift (60 lines)
            │
            └─→ HistoryView.swift (240 lines)
```

### Step 4: Extract List View
```
HistoryView.swift (240 lines)
    │
    └─→ Extract ─→ HistoryTransactionsList.swift (120 lines)
            │
            └─→ HistoryView.swift (150 lines) ✅ TARGET
```

---

## 📊 Metrics Comparison

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Lines in HistoryView | 370 | 150 | -59% |
| @State variables | 8 | 3 | -62% |
| Responsibilities | 8 | 2 | -75% |
| Unit testable components | 1 | 5 | +400% |
| Cyclomatic complexity | High | Low | ⬇️⬇️ |
| Coupling | High | Low | ⬇️⬇️ |
| Cohesion | Low | High | ⬆️⬆️ |

---

## ✅ Conclusion

Новая архитектура обеспечивает:
- 🎯 **Single Responsibility:** Каждый компонент имеет одну четкую роль
- 🧪 **Testability:** Легко писать unit-тесты для изолированной логики
- 🔄 **Maintainability:** Изменения в одном компоненте не влияют на другие
- ⚡ **Performance:** Мемоизация и оптимизации применяются точечно
- 📚 **Readability:** Код легко читать и понимать

**Следующий шаг:** Начать реализацию с Phase 1 (Critical Optimizations)
