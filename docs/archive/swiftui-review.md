# SwiftUI Expert Review - State Management & Modern APIs

**Date:** 2026-02-11
**Codebase:** Tenra
**Review Focus:** State management patterns, modern API adoption, and SwiftUI best practices

---

## Executive Summary

The codebase shows **strong architectural patterns** with a clear Single Source of Truth architecture using `TransactionStore`. However, there are several opportunities to modernize state management by migrating from `ObservableObject` to the `@Observable` macro (iOS 17+) and updating deprecated APIs.

**Key Findings:**
- ✅ Excellent: Single Source of Truth pattern with `TransactionStore`
- ✅ Good: Proper `@MainActor` usage on ViewModels
- ⚠️ **Critical**: Still using legacy `ObservableObject` instead of `@Observable` macro
- ⚠️ **High Priority**: Widespread use of deprecated APIs (`foregroundColor`, `cornerRadius`, `NavigationView`)
- ⚠️ Medium: Inconsistent property wrapper usage (mixing `@StateObject` and `@ObservedObject`)
- ✅ Good: Views generally follow SRP and proper decomposition

---

## 1. State Management Analysis

### 1.1 Current Architecture ✅

**Strengths:**
- **Single Source of Truth**: `TransactionStore` serves as the centralized state manager
- **Proper Actor Isolation**: ViewModels correctly marked with `@MainActor`
- **Combine Publishers**: Good use of publishers for data flow
- **Dependency Injection**: Clean separation between views and state

**Architecture Pattern:**
```swift
TransactionStore (Single Source of Truth)
    ↓
ViewModels observe TransactionStore via Combine
    ↓
Views observe ViewModels
    ↓
AppCoordinator orchestrates dependencies
```

### 1.2 Critical Issue: Legacy `ObservableObject` Usage ⚠️

**Problem:** All ViewModels still use `ObservableObject` protocol instead of the modern `@Observable` macro (iOS 17+).

**Found in:**
- `TransactionsViewModel.swift:14` - `class TransactionsViewModel: ObservableObject`
- `CategoriesViewModel.swift:15` - `class CategoriesViewModel: ObservableObject`
- `AccountsViewModel.swift:15` - `class AccountsViewModel: ObservableObject`
- `TransactionStore.swift:68` - `final class TransactionStore: ObservableObject`

**Impact:**
- Less efficient view updates (entire view body recomputes)
- More verbose state declarations
- Missing modern SwiftUI optimization opportunities

**Recommendation:** Migrate to `@Observable` macro

#### Before (Current):
```swift
@MainActor
class TransactionsViewModel: ObservableObject {
    @Published var allTransactions: [Transaction] = []
    @Published var displayTransactions: [Transaction] = []
    @Published var categoryRules: [CategoryRule] = []
    // ... more @Published properties
}
```

#### After (Recommended):
```swift
@Observable
@MainActor
class TransactionsViewModel {
    var allTransactions: [Transaction] = []
    var displayTransactions: [Transaction] = []
    var categoryRules: [CategoryRule] = []
    // No @Published needed - automatic tracking!
}
```

**Benefits:**
1. **Better Performance**: Only recomputes views that depend on changed properties
2. **Less Boilerplate**: No need for `@Published` wrapper
3. **Type Safety**: Better compile-time guarantees
4. **Modern Swift**: Leverages Swift observation framework

### 1.3 Property Wrapper Inconsistencies

**Issue:** Mixing `@StateObject` and `@ObservedObject` without clear pattern

**Examples:**

ContentView.swift:
```swift
@EnvironmentObject var coordinator: AppCoordinator  // ✅ Good - injected
@State private var isInitializing = true  // ✅ Good - local state
```

SettingsView.swift:
```swift
@ObservedObject var settingsViewModel: SettingsViewModel  // ⚠️ Should be let
@ObservedObject var transactionsViewModel: TransactionsViewModel  // ⚠️ Should be let
```

AddTransactionModal.swift:
```swift
@StateObject private var coordinator: AddTransactionCoordinator  // ✅ Good - owned
```

**Recommendations:**

1. **For owned ViewModels** (created in view):
   - Current: `@StateObject`
   - After `@Observable` migration: `@State`

2. **For injected ViewModels** (passed from parent):
   - Current: Remove `@ObservedObject`, use `let`
   - After `@Observable` migration: Still use `let` (automatic observation)

3. **For local view state**:
   - Keep using `@State private` (this is correct)

#### Migration Example:

**Before:**
```swift
struct SettingsView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
}
```

**After `@Observable` migration:**
```swift
struct SettingsView: View {
    let settingsViewModel: SettingsViewModel  // No wrapper needed!
    let transactionsViewModel: TransactionsViewModel
}
```

---

## 2. Deprecated API Usage Analysis

### 2.1 Critical Deprecated APIs Found

#### `foregroundColor()` → `foregroundStyle()`
**Status:** ⚠️ Used extensively (30+ files)

**Example Locations:**
- `AccountCard.swift`
- `CategoryRow.swift`
- `FormattedAmountText.swift`
- `SubscriptionCard.swift`

**Migration:**
```swift
// ❌ Deprecated
Text("Amount")
    .foregroundColor(.primary)

// ✅ Modern
Text("Amount")
    .foregroundStyle(.primary)
```

#### `cornerRadius()` → `clipShape(.rect(cornerRadius:))`
**Status:** ⚠️ Used moderately (15+ files)

**Migration:**
```swift
// ❌ Deprecated
RoundedRectangle(cornerRadius: 12)
    .fill(Color.blue)

// ✅ Modern
Rectangle()
    .fill(Color.blue)
    .clipShape(.rect(cornerRadius: 12))
```

#### `NavigationView` → `NavigationStack`
**Status:** ⚠️ Critical - used in multiple root views

**Found in:**
- `ContentView.swift:47`
- `SettingsView.swift` (via sheets)
- `AddTransactionModal.swift:62`

**Migration:**
```swift
// ❌ Deprecated
NavigationView {
    List { /* ... */ }
}

// ✅ Modern
NavigationStack {
    List { /* ... */ }
}
```

**Note:** This requires more careful migration as it changes navigation patterns. Consider using `navigationDestination(for:)` for type-safe navigation.

#### `onTapGesture()` → `Button`
**Status:** ⚠️ Should audit usage

When `onTapGesture()` doesn't need location or count information, prefer `Button` for better accessibility.

---

## 3. State Management Patterns - Detailed Review

### 3.1 TransactionStore Architecture ✅

**Excellent implementation** of event sourcing pattern:

```swift
@MainActor
final class TransactionStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var categories: [CustomCategory] = []

    // ✅ Proper encapsulation - only TransactionStore can modify
    func add(_ transaction: Transaction) async throws
    func update(_ transaction: Transaction) async throws
    func delete(_ transaction: Transaction) async throws
}
```

**Strengths:**
1. ✅ Single mutation point for all transactions
2. ✅ Event-driven architecture with clear state transitions
3. ✅ Proper async/await usage for operations
4. ✅ Comprehensive error handling with custom errors
5. ✅ LRU cache for computed properties

**After `@Observable` migration:**
```swift
@Observable
@MainActor
final class TransactionStore {
    private(set) var transactions: [Transaction] = []
    private(set) var accounts: [Account] = []
    private(set) var categories: [CustomCategory] = []

    // Same methods - @Observable handles observation automatically
}
```

### 3.2 ViewModel-View Relationships

**Current Pattern (works but verbose):**

```swift
// ViewModel
@MainActor
class TransactionsViewModel: ObservableObject {
    @Published var allTransactions: [Transaction] = []
}

// View
struct HistoryView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel

    var body: some View {
        List(transactionsViewModel.allTransactions) { /* ... */ }
    }
}
```

**Recommended Pattern with `@Observable`:**

```swift
// ViewModel
@Observable
@MainActor
class TransactionsViewModel {
    var allTransactions: [Transaction] = []  // No @Published!
}

// View
struct HistoryView: View {
    let transactionsViewModel: TransactionsViewModel  // No wrapper!

    var body: some View {
        List(transactionsViewModel.allTransactions) { /* ... */ }
        // SwiftUI automatically tracks dependency on allTransactions
    }
}
```

**Benefits:**
- 🚀 **Performance**: Only this view re-renders when `allTransactions` changes
- ✨ **Simplicity**: No property wrappers to manage
- 🎯 **Precision**: Fine-grained observation of individual properties

---

## 4. View Structure & Composition

### 4.1 Good Patterns Found ✅

**ContentView.swift** - Excellent decomposition:
```swift
struct ContentView: View {
    // ✅ Good: Local state is private
    @State private var isInitializing = true
    @State private var selectedAccount: Account?

    var body: some View {
        NavigationView {
            ZStack {
                mainContent  // ✅ Good: Extracted computed property
                loadingOverlay
            }
        }
    }

    // ✅ Good: Separate computed properties for sections
    private var mainContent: some View { /* ... */ }
    private var loadingOverlay: some View { /* ... */ }
    private var accountsSection: some View { /* ... */ }
}
```

**Strengths:**
1. ✅ Proper use of `private` for local state
2. ✅ Extracted complex views into computed properties
3. ✅ Clear separation of concerns

### 4.2 Areas for Improvement

**Issue**: Using `.onChange(of:)` with old signature

**Found in:**
```swift
// ContentView.swift:60
.onChange(of: viewModel.appSettings.wallpaperImageName) { _, _ in
    loadWallpaperOnce()
}

// AddTransactionModal.swift:86
.onChange(of: coordinator.formData.accountId) { _, _ in
    coordinator.updateCurrencyForSelectedAccount()
}
```

**Recommendation:** This is fine if targeting iOS 17+, but consider using the no-parameter variant for cleaner code:

```swift
.onChange(of: viewModel.appSettings.wallpaperImageName) {
    loadWallpaperOnce()
}
```

---

## 5. Performance Observations

### 5.1 Good Patterns ✅

1. **Debounced Updates:**
```swift
// ContentView.swift:385
private var summaryUpdatePublisher: AnyPublisher<Void, Never> {
    Publishers.Merge3(
        timeFilterManager.$currentFilter.map { _ in () },
        viewModel.$allTransactions.map { _ in () },
        viewModel.$dataRefreshTrigger.map { _ in () }
    )
    .debounce(for: 0.1, scheduler: RunLoop.main)  // ✅ Prevents excessive updates
    .eraseToAnyPublisher()
}
```

2. **LRU Cache in TransactionStore:**
```swift
private let cache: UnifiedTransactionCache
```

3. **Async Loading:**
```swift
.task { await initializeIfNeeded() }
```

### 5.2 Potential Issues

**Heavy ViewModels:** Several ViewModels are passed to views even when only a subset of data is needed.

**Example:**
```swift
// QuickAddTransactionView receives 4 ViewModels
QuickAddTransactionView(
    transactionsViewModel: viewModel,
    categoriesViewModel: categoriesViewModel,
    accountsViewModel: accountsViewModel,
    transactionStore: coordinator.transactionStore
)
```

**Recommendation:** Consider creating focused view models or passing only needed data:
```swift
// Instead of passing entire ViewModel
struct QuickAddProps {
    let accounts: [Account]
    let categories: [CustomCategory]
    let addTransaction: (Transaction) async throws -> Void
}
```

---

## 6. Threading & Concurrency

### 6.1 Good Patterns ✅

1. **Proper `@MainActor` marking:**
```swift
@MainActor
class TransactionsViewModel: ObservableObject { /* ... */ }
```

2. **Async operations properly structured:**
```swift
func addAccount(...) async {
    let account = Account(...)
    transactionStore?.addAccount(account)

    if let coordinator = balanceCoordinator {
        await coordinator.registerAccounts([account])
        await coordinator.setInitialBalance(initialBal, for: account.id)
    }
}
```

3. **Task usage in views:**
```swift
.task {
    await coordinator.initialize()
}
```

---

## 7. Recommended Migration Priority

### Phase 1: High Priority (Do First) 🔴

1. **Migrate to `@Observable` macro**
   - Start with `TransactionStore`
   - Then migrate all ViewModels
   - Update views to use `let` instead of `@ObservedObject`
   - Estimated effort: 2-3 days
   - Impact: Performance improvement + modernization

2. **Replace deprecated APIs**
   - `foregroundColor()` → `foregroundStyle()`
   - `cornerRadius()` → `clipShape(.rect(cornerRadius:))`
   - Estimated effort: 1-2 days
   - Impact: Future-proofing

### Phase 2: Medium Priority 🟡

3. **NavigationView → NavigationStack**
   - More complex migration
   - Consider type-safe navigation with `navigationDestination(for:)`
   - Estimated effort: 2-3 days
   - Impact: Modern navigation patterns

4. **Optimize ViewModel dependencies**
   - Create focused props instead of passing entire ViewModels
   - Estimated effort: 1-2 days
   - Impact: Better performance, clearer dependencies

### Phase 3: Low Priority 🟢

5. **Audit and fix `onTapGesture()` usage**
   - Replace with `Button` where appropriate
   - Estimated effort: 0.5 days
   - Impact: Better accessibility

---

## 8. Migration Guide: `ObservableObject` to `@Observable`

### Step 1: Update TransactionStore

**Before:**
```swift
@MainActor
final class TransactionStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var categories: [CustomCategory] = []

    let repository: DataRepositoryProtocol
    private let cache: UnifiedTransactionCache
    private let balanceCoordinator: BalanceCoordinator
}
```

**After:**
```swift
@Observable
@MainActor
final class TransactionStore {
    private(set) var transactions: [Transaction] = []
    private(set) var accounts: [Account] = []
    private(set) var categories: [CustomCategory] = []

    // Keep these as-is
    let repository: DataRepositoryProtocol
    private let cache: UnifiedTransactionCache
    private let balanceCoordinator: BalanceCoordinator
}
```

### Step 2: Update ViewModels

**Before:**
```swift
@MainActor
class CategoriesViewModel: ObservableObject {
    @Published private(set) var customCategories: [CustomCategory] = []
    @Published var categoryRules: [CategoryRule] = []
    @Published var subcategories: [Subcategory] = []

    weak var transactionStore: TransactionStore?
    private var categoriesSubscription: AnyCancellable?
}
```

**After:**
```swift
@Observable
@MainActor
class CategoriesViewModel {
    private(set) var customCategories: [CustomCategory] = []
    var categoryRules: [CategoryRule] = []
    var subcategories: [Subcategory] = []

    // Keep weak reference
    weak var transactionStore: TransactionStore?
    // Keep Combine subscription - @Observable doesn't replace Combine!
    private var categoriesSubscription: AnyCancellable?
}
```

**Important Note:** Keep Combine subscriptions! `@Observable` handles SwiftUI observation, but you still need Combine for cross-object reactive updates.

### Step 3: Update Views

**Before:**
```swift
struct SettingsView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel

    var body: some View {
        List {
            Text(transactionsViewModel.allTransactions.count)
        }
    }
}
```

**After:**
```swift
struct SettingsView: View {
    let settingsViewModel: SettingsViewModel
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel

    var body: some View {
        List {
            // SwiftUI automatically observes the count property
            Text(transactionsViewModel.allTransactions.count)
        }
    }
}
```

### Step 4: Update AppCoordinator

**Before:**
```swift
@MainActor
class AppCoordinator: ObservableObject {
    @Published var transactionStore: TransactionStore
    @Published var transactionsViewModel: TransactionsViewModel
    // ... other ViewModels
}
```

**After:**
```swift
@Observable
@MainActor
class AppCoordinator {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    // ... other ViewModels

    // These don't need to be @Published anymore
}
```

### Step 5: Update @StateObject Usage

**Before:**
```swift
struct AddTransactionModal: View {
    @StateObject private var coordinator: AddTransactionCoordinator

    init(...) {
        _coordinator = StateObject(wrappedValue: AddTransactionCoordinator(...))
    }
}
```

**After:**
```swift
struct AddTransactionModal: View {
    @State private var coordinator: AddTransactionCoordinator

    init(...) {
        _coordinator = State(initialValue: AddTransactionCoordinator(...))
    }
}
```

---

## 9. Specific File Recommendations

### TransactionsViewModel.swift ⚠️
**Lines: 963**
- ✅ Good: Proper `@MainActor` annotation
- ⚠️ **Action Required**: Migrate to `@Observable`
- ⚠️ **Action Required**: Remove `@Published` from all properties
- ✅ Good: Single Source of Truth pattern
- **Estimated effort:** 2 hours

### CategoriesViewModel.swift ⚠️
**Lines: 345**
- ⚠️ **Action Required**: Migrate to `@Observable`
- ✅ Good: Clean service delegation pattern
- ✅ Good: Combine publisher for cross-ViewModel updates
- **Estimated effort:** 1 hour

### AccountsViewModel.swift ⚠️
**Lines: 415**
- ⚠️ **Action Required**: Migrate to `@Observable`
- ✅ Good: Clean observer pattern with TransactionStore
- ✅ Good: Async/await for account operations
- **Estimated effort:** 1 hour

### TransactionStore.swift ⚠️
**Lines: 1140**
- ⚠️ **Action Required**: Migrate to `@Observable`
- ✅ Excellent: Event sourcing architecture
- ✅ Excellent: LRU cache implementation
- ✅ Excellent: Comprehensive error handling
- **Estimated effort:** 3 hours (most critical, test thoroughly)

### ContentView.swift ✅
**Lines: 403**
- ⚠️ **Action Required**: Change `NavigationView` to `NavigationStack`
- ⚠️ **Action Required**: Update after ViewModel migrations complete
- ✅ Good: Clean view decomposition
- ✅ Good: Proper local state management
- **Estimated effort:** 1 hour

### SettingsView.swift ⚠️
**Lines: 239**
- ⚠️ **Action Required**: Remove `@ObservedObject`, use `let`
- ⚠️ **Action Required**: Change `NavigationView` to `NavigationStack`
- ✅ Good: Props-based component architecture
- **Estimated effort:** 0.5 hours

---

## 10. Testing Strategy

### Before Migration
1. ✅ Ensure current test suite passes
2. ✅ Add integration tests for critical flows
3. ✅ Document current behavior

### During Migration
1. Migrate one ViewModel at a time
2. Run full test suite after each ViewModel
3. Test UI interactions manually

### After Migration
1. Verify no regressions
2. Check memory usage (should be same or better)
3. Profile view update performance (should improve)

---

## 11. Code Quality Highlights

### Excellent Patterns Found ✅

1. **Single Source of Truth Architecture:**
```swift
TransactionStore (SSOT)
    ↓ @Published
ViewModels (observers)
    ↓ Combine subscriptions
Views (reactive UI)
```

2. **Proper Error Handling:**
```swift
enum TransactionStoreError: LocalizedError {
    case invalidAmount
    case accountNotFound
    // ... with localized descriptions
}
```

3. **Clean Service Delegation:**
```swift
private lazy var crudService: CategoryCRUDServiceProtocol = {
    CategoryCRUDService(delegate: self, repository: repository)
}()
```

4. **Performance Optimization:**
- LRU caching
- Debounced updates
- Async/await for heavy operations

5. **Code Organization:**
- Clear MARK sections
- Single Responsibility Principle
- Dependency injection

---

## 12. Conclusion

### Current State: 7.5/10 🟢

**Strengths:**
- ✅ Solid architecture with Single Source of Truth
- ✅ Good concurrency handling
- ✅ Clean code organization
- ✅ Proper performance optimizations

**Areas for Improvement:**
- ⚠️ Legacy state management (ObservableObject)
- ⚠️ Deprecated API usage
- ⚠️ Property wrapper inconsistencies

### After Recommended Changes: 9.5/10 🚀

With the migration to `@Observable` and modern APIs, this codebase will be:
- **More performant** (fine-grained view updates)
- **More maintainable** (less boilerplate)
- **Future-proof** (modern SwiftUI patterns)
- **Easier to reason about** (simpler property wrappers)

### Estimated Total Migration Time
- **Phase 1 (Critical):** 3-5 days
- **Phase 2 (Medium):** 3-4 days
- **Phase 3 (Low):** 0.5 days
- **Total:** ~7-10 days for complete modernization

---

## Appendix A: Quick Reference

### Property Wrapper Migration Matrix

| Current | After @Observable |
|---------|-------------------|
| `@Published var` | `var` |
| `@StateObject` | `@State` |
| `@ObservedObject` | `let` |
| `@EnvironmentObject` | `@Environment` |

### API Migration Cheat Sheet

| Deprecated | Modern |
|-----------|--------|
| `foregroundColor()` | `foregroundStyle()` |
| `cornerRadius()` | `clipShape(.rect(cornerRadius:))` |
| `NavigationView` | `NavigationStack` |
| `tabItem()` | `Tab` API |
| `onChange(of:) { value in }` | `onChange(of:) { }` or `onChange(of:) { old, new in }` |

---

**Reviewer:** Claude Sonnet 4.5 (SwiftUI Expert Skill)
**Date:** 2026-02-11
**Next Review:** After Phase 1 migration completion
