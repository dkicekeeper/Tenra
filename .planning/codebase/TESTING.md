# Testing Patterns

**Analysis Date:** 2026-03-02

## Test Framework

**Runner:**
- **Primary:** Swift Testing framework (new, macro-based) with `@Test` attribute
- **Secondary:** XCTest (legacy, function-based) with `XCTestCase` subclasses
- Mixed usage in codebase: newer tests use Swift Testing, older tests use XCTest
- Config: No explicit test configuration file (uses Xcode defaults)

**Assertion Library:**
- Swift Testing: `#expect(condition)` and `#expect(condition, message)`
- XCTest: `XCTAssert*` family (`XCTAssertEqual`, `XCTAssertNotNil`, `XCTFail`)
- Both frameworks coexist; no plan to migrate entirely

**Run Commands:**
```bash
# Run all tests
xcodebuild test \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:AIFinanceManagerTests

# Watch mode (not built into Xcode CLI, use IDE)
# In Xcode: Cmd+U to run all tests

# Coverage (Xcode Code Coverage in test scheme settings)
# View in Xcode: Report Navigator > Coverage tab
```

## Test File Organization

**Location:**
- Mirror source structure in `AIFinanceManagerTests/`
- `AIFinanceManagerTests/Utils/` → `AIFinanceManager/Utils/` files
- `AIFinanceManagerTests/Services/` → `AIFinanceManager/Services/` files
- `AIFinanceManagerTests/ViewModels/` → `AIFinanceManager/ViewModels/` files
- `AIFinanceManagerTests/Balance/` → `AIFinanceManager/Services/Balance/` files
- `AIFinanceManagerTests/Models/` → `AIFinanceManager/Models/` files

**Naming:**
- Test struct/class: `TargetNameTests` or `TargetNameTests`
- Test methods: Swift Testing uses `@Test("description")` attribute or function name; XCTest uses `testSomethingSpecific()`
- File name matches class/struct being tested: `TransactionStoreTests.swift` tests `TransactionStore`

**Test Discovery:**
```
AIFinanceManagerTests/
├── Utils/
│   ├── AmountFormatterTests.swift
│   ├── FormattingTests.swift
│   ├── TransactionIDGeneratorTests.swift
│   └── DateFormattersTests.swift
├── Services/
│   ├── Transactions/
│   │   └── RecurringTransactionTests.swift
│   ├── Voice/
│   │   └── VoiceInputParserTests.swift
│   ├── AccountRepositoryTests.swift
│   └── BudgetSpendingCacheServiceTests.swift
├── Balance/
│   └── BalanceCalculationTests.swift
├── ViewModels/
│   ├── TransactionStoreTests.swift
│   └── TransactionPaginationControllerTests.swift
├── Models/
│   └── TimeFilterTests.swift
└── AIFinanceManagerTests.swift (root/shared)
```

## Test Structure

**Suite Organization (Swift Testing):**
```swift
import Testing
@testable import AIFinanceManager

struct AmountFormatterTests {  // Struct, not class
    // Tests as methods with @Test attribute
    @Test("Parse valid decimal amount")
    func testParseValidAmount() {
        let result = AmountFormatter.parse("1234.56")
        #expect(result == 1234.56)
    }
}
```

**Suite Organization (XCTest):**
```swift
import XCTest
@testable import AIFinanceManager

@MainActor
final class TransactionStoreTests: XCTestCase {
    // MARK: - Properties
    var store: TransactionStore!
    var mockRepository: MockRepository!

    // MARK: - Setup & Teardown
    override func setUp() async throws {
        try await super.setUp()
        // Initialize test fixtures
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    // MARK: - Test Group (by feature)
    func testAddTransaction_Success() async throws {
        // Given, When, Then pattern
    }
}
```

**Patterns:**
- **Setup method:** `setUp()` or `setUpWithError()` for initialization (called before each test)
- **Teardown method:** `tearDown()` or `tearDownWithError()` for cleanup (called after each test)
- **Async setup:** `override func setUp() async throws` in @MainActor classes
- **Assertion placement:** Immediately after action (not grouped at end)
- **Comment structure:** `// Given`, `// When`, `// Then` for Arrange-Act-Assert pattern

## Test Structure Examples

**Swift Testing Pattern (from `BalanceCalculationTests.swift`):**
```swift
@Test func testBalanceCalculationServiceInitialState() async throws {
    let service = BalanceCalculationService()

    #expect(!service.isImported("test-account"))
    #expect(service.getInitialBalance(for: "test-account") == nil)
}

@Test("Mark account as imported") func testMarkAccountAsImported() async throws {
    let service = BalanceCalculationService()
    service.markAsImported("imported-account")

    #expect(service.isImported("imported-account"))
}
```

**XCTest Pattern (from `TransactionStoreTests.swift`):**
```swift
func testAddTransaction_Success() async throws {
    // Given
    let transaction = createTestTransaction(
        amount: 1000,
        type: .expense,
        category: "Food"
    )

    // When
    try await store.add(transaction)

    // Then
    XCTAssertEqual(store.transactions.count, 1, "Should have 1 transaction")
    XCTAssertEqual(store.transactions.first?.amount, 1000)
}
```

**Error Testing Pattern:**
```swift
func testAddTransaction_InvalidAmount() async {
    // Given
    let transaction = createTestTransaction(amount: -100, type: .expense, category: "Food")

    // When/Then
    do {
        try await store.add(transaction)
        XCTFail("Should throw invalidAmount error")
    } catch TransactionStoreError.invalidAmount {
        // Expected
    } catch {
        XCTFail("Wrong error type: \(error)")
    }
}
```

## Mocking

**Framework:** Manual mock implementations (no Mockito, no automatic mocking)

**Pattern:**
Implement protocol directly in test file:
```swift
@MainActor
class MockRepository: DataRepositoryProtocol {
    var saveTransactionsCallCount = 0
    var saveAccountsCallCount = 0
    var storedTransactions: [Transaction] = []
    var storedAccounts: [Account] = []

    func saveTransactions(_ transactions: [Transaction]) async throws {
        saveTransactionsCallCount += 1
        storedTransactions = transactions
    }

    func saveAccounts(_ accounts: [Account]) async throws {
        saveAccountsCallCount += 1
        storedAccounts = accounts
    }

    // Implement remaining protocol methods (even if no-op)
    func loadTransactions(dateRange: DateInterval?) -> [Transaction] {
        return storedTransactions
    }
}
```

**What to Mock:**
- External dependencies: `DataRepositoryProtocol`, services with side effects
- Time-dependent behavior: Date/time services (if needed; seen in fixture setups)
- File I/O: rarely mocked (not heavy in this app)
- Network: not applicable (no network in current codebase)

**What NOT to Mock:**
- Value types (Transaction, Account, CustomCategory) — construct directly
- Swift standard library (Array, String, Dictionary)
- Pure utility functions (formatters, parsers)
- CoreData entities — use in-memory mock repository instead

**Mock Lifecycle:**
- Initialize in `setUp()` or test method start
- Pass to tested object in constructor/property
- Call count assertions in `// Then` section: `XCTAssertEqual(mockRepository.saveTransactionsCallCount, 1)`
- Clean up in `tearDown()`: `mockRepository = nil`

## Fixtures and Factories

**Test Data:**
```swift
// Factory function in test class
private func createTestTransaction(
    amount: Double,
    type: TransactionType,
    category: String,
    date: String = "2026-02-05"
) -> Transaction {
    return Transaction(
        id: "",  // Will be auto-generated
        date: date,
        description: "Test transaction",
        amount: amount,
        currency: "KZT",
        type: type,
        category: category,
        accountId: testAccount.id
    )
}

// Usage in test
let transaction = createTestTransaction(amount: 1000, type: .expense, category: "Food")
```

**Test Accounts/Categories (from `VoiceInputParserTests.swift`):**
```swift
override func setUpWithError() throws {
    mockAccounts = [
        Account(id: "1", name: "Kaspi Gold", balance: 10000, currency: "KZT", ...),
        Account(id: "2", name: "Halyk Bank", balance: 5000, currency: "KZT", ...)
    ]

    mockCategories = [
        CustomCategory(name: "Transport", iconName: "car.fill", colorHex: "#FF0000", type: .expense),
        CustomCategory(name: "Food", iconName: "fork.knife", colorHex: "#00FF00", type: .expense)
    ]
}
```

**Location:**
- Fixture data defined in `setUp()` method (instance properties)
- Factory functions as private methods in test class
- Reusable builders defined near top of test class (after properties, before tests)

## Coverage

**Requirements:** Not explicitly enforced (no test coverage gate in CI)

**View Coverage:**
```bash
# In Xcode:
1. Run tests: Cmd+U
2. Open Report Navigator: Cmd+9
3. Select latest test run
4. Click "Coverage" tab
5. Drill down by file to see line coverage
```

**Current Coverage Status:**
- 13 test files across main domains (Utils, Services, ViewModels, Balance, Models)
- Focused on business logic (repositories, parsers, calculations)
- UI tests present: `AIFinanceManagerUITests/` directory exists but empty/stub
- No automated coverage reporting

## Test Types

**Unit Tests:**
- **Scope:** Single class/function in isolation with mocks for dependencies
- **Framework:** Swift Testing (newer) or XCTest (legacy)
- **Example:** `AmountFormatterTests` tests `AmountFormatter.parse()` with literal strings
- **Approach:** Construct object, call method, assert result; no async I/O

**Integration Tests:**
- **Scope:** Multiple classes working together (Coordinator + ViewModels + Repository)
- **Framework:** XCTest with `@MainActor` decorator
- **Example:** `TransactionStoreTests` creates Store + MockRepository, adds transaction, verifies balance update
- **Approach:** Setup test data, call public APIs, verify state + side effects (mock call counts)

**E2E/Functional Tests:**
- **Framework:** XCTest UI tests in `AIFinanceManagerUITests/` (placeholder directory)
- **Status:** Not used/implemented
- **Example:** Would test full flow: open app → add transaction → verify UI update

## Common Patterns

**Async Testing:**
```swift
// Swift Testing
@Test func testAsyncLoad() async throws {
    let result = try await service.load()
    #expect(!result.isEmpty)
}

// XCTest
func testAsyncLoad() async throws {
    let result = try await service.load()
    XCTAssertFalse(result.isEmpty)
}
```

**Error Testing:**
```swift
// Expected error
do {
    try await store.add(invalidTransaction)
    XCTFail("Should throw error")
} catch TransactionStoreError.invalidAmount {
    // Expected — pass
} catch {
    XCTFail("Wrong error type: \(error)")
}

// No error expected
do {
    try await store.add(validTransaction)
    // Success — no catch needed
} catch {
    XCTFail("Unexpected error: \(error)")
}
```

**Verification with Call Counts:**
```swift
// Verify repository was called correct number of times
XCTAssertEqual(mockRepository.saveTransactionsCallCount, 1)
XCTAssertEqual(mockRepository.saveAccountsCallCount, 1)

// Verify state was modified
XCTAssertEqual(mockRepository.storedTransactions.count, 1)
XCTAssertEqual(mockRepository.storedTransactions.first?.amount, 1000)
```

**Performance Testing (XCTest):**
```swift
func testParsingPerformance() {
    measure {
        for _ in 0..<100 {
            _ = parser.parse("Потратил 5000 тенге на такси")
        }
    }
}
```

## Test Maintenance

**Common Issues:**
- **Mock setup incomplete:** Add `func` stubs for all protocol methods, even if `return []` or no-op
- **@MainActor isolation:** Test class must be `@MainActor final class` if testing @MainActor objects
- **Async setup:** Override `setUp() async throws` not just `setUp()`
- **Fixture mutation:** Create new fixture in each test method or use defensive copies

**Running Subset:**
```bash
# Run single test class
xcodebuild test \
  -scheme AIFinanceManager \
  -only-testing:AIFinanceManagerTests/TransactionStoreTests

# Run single test method (XCTest)
xcodebuild test \
  -scheme AIFinanceManager \
  -only-testing:AIFinanceManagerTests/TransactionStoreTests/testAddTransaction_Success
```

---

*Testing analysis: 2026-03-02*
