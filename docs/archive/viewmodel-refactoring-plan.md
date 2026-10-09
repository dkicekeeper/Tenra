# 🏗️ ViewModel Refactoring Plan

**Date**: 15 января 2026
**Status**: 📋 Planning Phase
**Priority**: P1 (High - Architecture Issue)

---

## 📊 Current State Analysis

### TransactionsViewModel.swift Metrics:
```
Lines of Code:    2,486 lines  ❌ (God Object)
Functions:        52 methods   ❌ (Too many responsibilities)
@Published props: 14 properties ❌ (Mixed concerns)
```

### Current Architecture Issues:

#### 1. **God Object Anti-Pattern** ❌
TransactionsViewModel handles EVERYTHING:
- ✅ Transactions CRUD
- ✅ Accounts management
- ✅ Categories management
- ✅ Subscriptions (recurring series)
- ✅ Recurring occurrences
- ✅ Subcategories
- ✅ Category rules
- ✅ Deposits (interest calculations)
- ✅ App settings
- ✅ Summary calculations
- ✅ Currency conversions
- ✅ Data persistence (UserDefaults)
- ✅ CSV import/export

**Violation**: Single Responsibility Principle (SRP)

---

#### 2. **@Published Properties Sprawl** ❌
```swift
@Published var allTransactions: [Transaction] = []
@Published var categoryRules: [CategoryRule] = []
@Published var accounts: [Account] = []
@Published var customCategories: [CustomCategory] = []
@Published var recurringSeries: [RecurringSeries] = []
@Published var recurringOccurrences: [RecurringOccurrence] = []
@Published var subcategories: [Subcategory] = []
@Published var categorySubcategoryLinks: [CategorySubcategoryLink] = []
@Published var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []
@Published var selectedCategories: Set<String>? = nil
@Published var isLoading = false
@Published var errorMessage: String?
@Published var currencyConversionWarning: String?
@Published var appSettings: AppSettings
```

**Problem**: 14 published properties cause unnecessary view re-renders

---

#### 3. **Tight Coupling** ❌
All views depend on single massive ViewModel:
```swift
// Every view needs the entire ViewModel
@ObservedObject var viewModel: TransactionsViewModel
```

**Problem**:
- Can't test components independently
- Changes to one feature affect all views
- Difficult to maintain

---

#### 4. **Data Persistence Mixed with Business Logic** ❌
```swift
// Storage keys scattered throughout
private let storageKeyTransactions = "allTransactions"
private let storageKeyRules = "categoryRules"
// ... etc

// Direct UserDefaults calls in ViewModel
func saveToStorage() {
    // 200+ lines of serialization code
}
```

**Problem**: Violates separation of concerns

---

## 🎯 Refactoring Goals

### Goal 1: **Single Responsibility ViewModels**
Each ViewModel should handle ONE domain:
- ✅ TransactionsViewModel → ONLY transactions
- ✅ AccountsViewModel → ONLY accounts
- ✅ CategoriesViewModel → ONLY categories
- ✅ SubscriptionsViewModel → ONLY subscriptions/recurring
- ✅ DepositsViewModel → ONLY deposits

### Goal 2: **Separate Data Layer**
Extract persistence into dedicated services:
- ✅ DataRepository → All storage operations
- ✅ UserDefaultsStorage → UserDefaults wrapper
- ✅ (Future) CoreData/SwiftData migration path

### Goal 3: **Reduce @Published Properties**
Only publish what views actually need:
- ✅ Use computed properties where possible
- ✅ Group related data into structs
- ✅ Lazy loading for expensive operations

### Goal 4: **Dependency Injection**
ViewModels should receive dependencies:
```swift
class TransactionsViewModel {
    private let repository: DataRepository
    private let currencyService: CurrencyConversionService

    init(repository: DataRepository, currencyService: CurrencyConversionService) {
        self.repository = repository
        self.currencyService = currencyService
    }
}
```

---

## 📐 Proposed Architecture

### New Structure:

```
┌─────────────────────────────────────────────┐
│              View Layer                     │
│  HistoryView, AccountsView, SettingsView   │
└─────────────┬───────────────────────────────┘
              │ observes
              ▼
┌─────────────────────────────────────────────┐
│          ViewModel Layer (MVVM)             │
│                                             │
│  ┌─────────────────┐  ┌──────────────────┐ │
│  │ Transactions    │  │ Accounts         │ │
│  │ ViewModel       │  │ ViewModel        │ │
│  └────────┬────────┘  └────────┬─────────┘ │
│           │                    │            │
│  ┌────────┴────────┐  ┌────────┴─────────┐ │
│  │ Categories      │  │ Subscriptions    │ │
│  │ ViewModel       │  │ ViewModel        │ │
│  └────────┬────────┘  └────────┬─────────┘ │
│           │                    │            │
│  ┌────────┴────────┐           │            │
│  │ Deposits        │           │            │
│  │ ViewModel       │           │            │
│  └────────┬────────┘           │            │
└───────────┼────────────────────┼────────────┘
            │                    │
            │ uses               │
            ▼                    ▼
┌─────────────────────────────────────────────┐
│         Repository Layer                    │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │      DataRepository                  │  │
│  │  (Coordinates all data operations)   │  │
│  └──────────────┬───────────────────────┘  │
│                 │                           │
│                 │ uses                      │
│                 ▼                           │
│  ┌──────────────────────────────────────┐  │
│  │    Storage Services                  │  │
│  │  • UserDefaultsStorage               │  │
│  │  • (Future) CoreDataStorage          │  │
│  │  • (Future) CloudKitStorage          │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
            │
            │ uses
            ▼
┌─────────────────────────────────────────────┐
│         Business Logic Services             │
│                                             │
│  • CurrencyConversionService                │
│  • RecurringTransactionGenerator            │
│  • DepositInterestCalculator                │
│  • CategoryRuleEngine                       │
│  • CSVImportExportService                   │
└─────────────────────────────────────────────┘
```

---

## 🔧 Detailed Refactoring Plan

### Phase 1: Extract Repository Layer (4-6 hours)

#### Step 1.1: Create DataRepository Protocol
```swift
protocol DataRepositoryProtocol {
    func loadTransactions() -> [Transaction]
    func saveTransactions(_ transactions: [Transaction])
    func loadAccounts() -> [Account]
    func saveAccounts(_ accounts: [Account])
    // ... etc for all entities
}
```

#### Step 1.2: Implement UserDefaultsRepository
```swift
class UserDefaultsRepository: DataRepositoryProtocol {
    private let storage: UserDefaults

    init(storage: UserDefaults = .standard) {
        self.storage = storage
    }

    func loadTransactions() -> [Transaction] {
        // Extract from current saveToStorage/loadFromStorage
    }

    func saveTransactions(_ transactions: [Transaction]) {
        // Extract from current saveToStorage
    }
}
```

#### Step 1.3: Update TransactionsViewModel to Use Repository
```swift
class TransactionsViewModel: ObservableObject {
    private let repository: DataRepositoryProtocol

    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        self.allTransactions = repository.loadTransactions()
    }
}
```

---

### Phase 2: Extract AccountsViewModel (3-4 hours)

#### Responsibilities:
- ✅ Account CRUD operations
- ✅ Account balance calculations
- ✅ Bank logo management
- ✅ Deposit interest tracking

#### Interface:
```swift
@MainActor
class AccountsViewModel: ObservableObject {
    @Published var accounts: [Account] = []

    private let repository: DataRepositoryProtocol

    init(repository: DataRepositoryProtocol) {
        self.repository = repository
        self.accounts = repository.loadAccounts()
    }

    func addAccount(_ account: Account) { }
    func updateAccount(_ account: Account) { }
    func deleteAccount(_ id: String) { }
    func calculateDepositInterest(for accountId: String) -> Double { }
}
```

---

### Phase 3: Extract CategoriesViewModel (2-3 hours)

#### Responsibilities:
- ✅ Category CRUD operations
- ✅ Subcategory management
- ✅ Category-subcategory links
- ✅ Category rules

#### Interface:
```swift
@MainActor
class CategoriesViewModel: ObservableObject {
    @Published var customCategories: [CustomCategory] = []
    @Published var subcategories: [Subcategory] = []
    @Published var categoryRules: [CategoryRule] = []

    private let repository: DataRepositoryProtocol

    init(repository: DataRepositoryProtocol) {
        self.repository = repository
        self.customCategories = repository.loadCategories()
        self.subcategories = repository.loadSubcategories()
        self.categoryRules = repository.loadCategoryRules()
    }

    func addCategory(_ category: CustomCategory) { }
    func updateCategory(_ category: CustomCategory) { }
    func deleteCategory(_ id: String) { }
    func linkSubcategoryToCategory(_ subcategoryId: String, categoryId: String) { }
}
```

---

### Phase 4: Extract SubscriptionsViewModel (3-4 hours)

#### Responsibilities:
- ✅ Recurring series CRUD
- ✅ Recurring occurrence tracking
- ✅ Next charge date calculations
- ✅ Subscription status management

#### Interface:
```swift
@MainActor
class SubscriptionsViewModel: ObservableObject {
    @Published var subscriptions: [RecurringSeries] = []
    @Published var occurrences: [RecurringOccurrence] = []

    private let repository: DataRepositoryProtocol
    private let generator: RecurringTransactionGenerator

    init(repository: DataRepositoryProtocol, generator: RecurringTransactionGenerator) {
        self.repository = repository
        self.generator = generator
        self.subscriptions = repository.loadRecurringSeries()
        self.occurrences = repository.loadRecurringOccurrences()
    }

    func createSubscription(_ series: RecurringSeries) { }
    func updateSubscription(_ series: RecurringSeries) { }
    func pauseSubscription(_ id: String) { }
    func resumeSubscription(_ id: String) { }
    func deleteSubscription(_ id: String) { }
    func nextChargeDate(for id: String) -> Date? { }
}
```

---

### Phase 5: Extract DepositsViewModel (2-3 hours)

#### Responsibilities:
- ✅ Deposit CRUD operations
- ✅ Deposit interest calculations (using DepositInterestService)
- ✅ Rate change management
- ✅ Deposit reconciliation

#### Interface:
```swift
@MainActor
class DepositsViewModel: ObservableObject {
    @Published var deposits: [Account] = [] // Only accounts with depositInfo
    
    private let repository: DataRepositoryProtocol
    private let transactionsViewModel: TransactionsViewModel
    
    init(repository: DataRepositoryProtocol, transactionsViewModel: TransactionsViewModel) {
        self.repository = repository
        self.transactionsViewModel = transactionsViewModel
        self.deposits = repository.loadAccounts().filter { $0.isDeposit }
    }
    
    func addDeposit(_ account: Account) { }
    func updateDeposit(_ account: Account) { }
    func deleteDeposit(_ id: String) { }
    func addRateChange(accountId: String, rate: Decimal, date: String) { }
    func reconcileAllDeposits() { }
    func reconcileDepositInterest(for accountId: String) { }
}
```

---

### Phase 6: Slim Down TransactionsViewModel (2-3 hours)

After extraction, TransactionsViewModel should ONLY handle:
- ✅ Transaction CRUD operations
- ✅ Transaction filtering by time
- ✅ Transaction filtering by category
- ✅ Summary calculations (using data from other ViewModels)
- ✅ Transaction-subcategory links
- ✅ Category rules application

#### Final Interface:
```swift
@MainActor
class TransactionsViewModel: ObservableObject {
    @Published var allTransactions: [Transaction] = []
    @Published var selectedCategories: Set<String>? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository: DataRepositoryProtocol
    private let currencyService: CurrencyConversionService
    private let accountsViewModel: AccountsViewModel
    private let categoriesViewModel: CategoriesViewModel

    init(
        repository: DataRepositoryProtocol,
        currencyService: CurrencyConversionService,
        accountsViewModel: AccountsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) {
        self.repository = repository
        self.currencyService = currencyService
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.allTransactions = repository.loadTransactions()
    }

    // ONLY transaction-related methods
    func addTransaction(_ transaction: Transaction) { }
    func updateTransaction(_ transaction: Transaction) { }
    func deleteTransaction(_ id: String) { }
    func filterTransactions(by timeRange: DateRange) -> [Transaction] { }
    func summary(for timeRange: DateRange) -> Summary { }
    func applyRules(to transactions: [Transaction]) -> [Transaction] { }
}
```

**Target LOC**: ~400-600 lines (down from 2,486)

---

## 📊 Refactoring Metrics

### Before:
```
TransactionsViewModel:     2,486 lines ❌
  - Transactions:           ~600 lines
  - Accounts:               ~400 lines
  - Categories:             ~300 lines
  - Subscriptions:          ~400 lines
  - Deposits:               ~200 lines
  - Persistence:            ~300 lines
  - Misc (rules, CSV):      ~286 lines
```

### After:
```
TransactionsViewModel:      ~500 lines ✅
AccountsViewModel:          ~350 lines ✅
CategoriesViewModel:        ~300 lines ✅
SubscriptionsViewModel:     ~400 lines ✅
DepositsViewModel:          ~200 lines ✅
DataRepository:             ~300 lines ✅
UserDefaultsStorage:        ~200 lines ✅
───────────────────────────────────────
Total:                    ~2,250 lines
Improvement:               + 236 lines (overhead), but:
  - Better separation
  - Easier testing
  - Independent features
```

---

## ⚠️ Migration Challenges

### Challenge 1: View Dependencies
**Problem**: All views currently depend on TransactionsViewModel
```swift
// Current (in every view)
@ObservedObject var viewModel: TransactionsViewModel
```

**Solution**: Gradual migration with backward compatibility
```swift
// Phase 1: Add new ViewModels alongside old one
@ObservedObject var viewModel: TransactionsViewModel // Keep for now
@StateObject private var accountsVM = AccountsViewModel()

// Phase 2: Update views to use specific ViewModels
// Phase 3: Remove TransactionsViewModel dependency
```

---

### Challenge 2: Cross-ViewModel Communication
**Problem**: Features need data from multiple domains
```swift
// Example: Summary needs transactions + accounts + categories
func summary() -> Summary {
    // Needs allTransactions + accounts + categories
}
```

**Solution 1**: Coordinator Pattern
```swift
class AppCoordinator: ObservableObject {
    let transactions: TransactionsViewModel
    let accounts: AccountsViewModel
    let categories: CategoriesViewModel
    let subscriptions: SubscriptionsViewModel

    init(repository: DataRepositoryProtocol) {
        let repo = repository
        self.accounts = AccountsViewModel(repository: repo)
        self.categories = CategoriesViewModel(repository: repo)
        self.transactions = TransactionsViewModel(
            repository: repo,
            accounts: accounts,
            categories: categories
        )
        self.subscriptions = SubscriptionsViewModel(repository: repo)
    }
}
```

**Solution 2**: Inject in Environment
```swift
@main
struct TenraApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator.transactions)
                .environmentObject(coordinator.accounts)
                .environmentObject(coordinator.categories)
                .environmentObject(coordinator.subscriptions)
        }
    }
}
```

---

### Challenge 3: Data Consistency
**Problem**: Multiple ViewModels modifying shared data
```swift
// Example: Deleting account should cascade delete transactions
accountsViewModel.deleteAccount(id)
// Must also delete transactions for that account
```

**Solution**: Repository as Single Source of Truth
```swift
class DataRepository {
    func deleteAccount(_ id: String) {
        // Delete account
        var accounts = loadAccounts()
        accounts.removeAll { $0.id == id }
        saveAccounts(accounts)

        // Cascade delete transactions
        var transactions = loadTransactions()
        transactions.removeAll { $0.accountId == id }
        saveTransactions(transactions)

        // Notify all ViewModels via Combine
        accountsSubject.send(accounts)
        transactionsSubject.send(transactions)
    }
}
```

---

## 🎯 Implementation Strategy

### Strategy: **Gradual Migration** (Recommended)

#### Advantages:
- ✅ App stays functional during refactoring
- ✅ Can test each phase independently
- ✅ Can roll back if issues arise
- ✅ Less risky than "big bang" rewrite

#### Phases:
1. **Week 1**: Extract Repository Layer (non-breaking)
2. **Week 2**: Extract AccountsViewModel + update AccountsManagementView
3. **Week 3**: Extract CategoriesViewModel + update CategoriesManagementView
4. **Week 4**: Extract SubscriptionsViewModel + update Subscriptions views
5. **Week 5**: Extract DepositsViewModel + update Deposit views
6. **Week 6**: Clean up TransactionsViewModel + final testing

**Total Time**: 6 weeks (part-time) or 3 weeks (full-time)

---

## 🔄 Data Synchronization Strategy

### Problem: Multiple ViewModels need to stay in sync

**Example**: When a transaction is deleted, account balance needs recalculation.

### Solution: Repository as Single Source of Truth + Combine Publishers

```swift
class DataRepository: DataRepositoryProtocol {
    // Combine publishers for reactive updates
    private let transactionsSubject = PassthroughSubject<[Transaction], Never>()
    private let accountsSubject = PassthroughSubject<[Account], Never>()
    
    var transactionsPublisher: AnyPublisher<[Transaction], Never> {
        transactionsSubject.eraseToAnyPublisher()
    }
    
    func saveTransactions(_ transactions: [Transaction]) {
        // Save to storage
        // ...
        // Notify subscribers
        transactionsSubject.send(transactions)
    }
}
```

### ViewModels Subscribe to Changes:

```swift
class AccountsViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    
    init(repository: DataRepositoryProtocol) {
        // Subscribe to transaction changes
        if let repo = repository as? DataRepository {
            repo.transactionsPublisher
                .sink { [weak self] _ in
                    self?.recalculateBalances()
                }
                .store(in: &cancellables)
        }
    }
}
```

---

## 📋 View Migration Examples

### Example 1: AccountsManagementView

**Before**:
```swift
struct AccountsManagementView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    
    var body: some View {
        List(viewModel.accounts) { account in
            // ...
        }
    }
}
```

**After**:
```swift
struct AccountsManagementView: View {
    @ObservedObject var accountsViewModel: AccountsViewModel
    
    var body: some View {
        List(accountsViewModel.accounts) { account in
            // ...
        }
    }
}
```

### Example 2: HistoryView (needs multiple ViewModels)

**Before**:
```swift
struct HistoryView: View {
    @ObservedObject var viewModel: TransactionsViewModel
}
```

**After**:
```swift
struct HistoryView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
}
```

**Or using Coordinator**:
```swift
struct HistoryView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        // Use coordinator.transactions, coordinator.accounts, etc.
    }
}
```

---

## 📝 Testing Strategy

### Unit Tests (Currently: 0% coverage ❌)

After refactoring, add tests for:
```swift
// TransactionsViewModelTests.swift
func testAddTransaction() {
    let repository = MockRepository()
    let vm = TransactionsViewModel(repository: repository)

    let transaction = Transaction(...)
    vm.addTransaction(transaction)

    XCTAssertEqual(vm.allTransactions.count, 1)
    XCTAssertTrue(repository.saveWasCalled)
}

// AccountsViewModelTests.swift
func testDeleteAccountCascadesTransactions() {
    let repository = MockRepository()
    let vm = AccountsViewModel(repository: repository)

    vm.deleteAccount("account-1")

    XCTAssertEqual(repository.deletedAccountIds, ["account-1"])
}
```

**Target Coverage**: 70-80% for ViewModels

### Integration Tests

Test cross-ViewModel interactions:
```swift
func testDeleteAccountCascadesTransactions() {
    let repository = MockRepository()
    let accountsVM = AccountsViewModel(repository: repository)
    let transactionsVM = TransactionsViewModel(repository: repository, ...)
    
    // Create account and transaction
    let account = Account(...)
    accountsVM.addAccount(account)
    transactionsVM.addTransaction(Transaction(accountId: account.id, ...))
    
    // Delete account
    accountsVM.deleteAccount(account.id)
    
    // Verify transaction is deleted
    XCTAssertTrue(transactionsVM.allTransactions.isEmpty)
}
```

---

## 🚀 Next Steps

### Immediate Actions (This Session):
1. ✅ **Analyze current architecture** (DONE)
2. ✅ **Create refactoring plan** (DONE - this document)
3. ⏳ **Get user approval** for approach
4. ⏳ **Start Phase 1**: Extract Repository Layer

### Decision Required:
**Should we proceed with ViewModelrefactoring, or focus on other priorities?**

Options:
- **Option A**: Start ViewModel refactoring now (6 weeks effort)
- **Option B**: Focus on performance optimizations first (lighter weight)
- **Option C**: Focus on remaining localization (Deposits, CSV) (lighter weight)
- **Option D**: Focus on testing + App Store submission (recommended)

---

## 💡 Recommendations

### For Immediate Release (Recommended):
**Skip ViewModel refactoring for now**. Current architecture works, just needs:
1. ✅ Localization (DONE)
2. ✅ Accessibility (DONE)
3. ⏳ Manual testing (3-4 hours)
4. ⏳ App Store submission

**Why**:
- Refactoring is 6 weeks of work
- Risk of introducing bugs
- Current app is functional
- Better to ship and iterate

---

### For Post-Release v2.0 (Recommended):
**Full ViewModel refactoring**:
1. Extract Repository Layer
2. Split ViewModels by domain
3. Add unit tests (70-80% coverage)
4. Migrate to SwiftData/CoreData

**Why**:
- Cleaner architecture for future features
- Easier onboarding for new developers
- Better testability
- Easier maintenance

---

## 📚 References

### Design Patterns:
- MVVM (Model-View-ViewModel)
- Repository Pattern
- Coordinator Pattern
- Dependency Injection

### Apple Documentation:
- [Managing Model Data in Your App](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [SwiftUI Data Flow](https://developer.apple.com/documentation/swiftui/managing-user-interface-state)
- [Combine Framework](https://developer.apple.com/documentation/combine)

---

**Status**: ✅ Plan Complete, Awaiting Decision
**Prepared by**: Claude Sonnet 4.5
**Date**: 15 января 2026
**Estimated Effort**: 6 weeks (full refactoring) or 0 weeks (skip for now)
