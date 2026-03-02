# Coding Conventions

**Analysis Date:** 2026-03-02

## Naming Patterns

**Files:**
- Class/struct files: PascalCase (e.g., `TransactionStore.swift`, `AppCoordinator.swift`)
- Files containing extensions: PascalCase + descriptive suffix (e.g., `TransactionStore+Recurring.swift`, `InsightsService+Spending.swift`)
- Protocol files: end with `Protocol` suffix (e.g., `DataRepositoryProtocol.swift`, `TransactionQueryServiceProtocol.swift`)
- Test files: ClassNameTests or StructNameTests (e.g., `TransactionStoreTests.swift`, `BalanceCalculationTests.swift`)
- Utility/helper files: descriptive name in lowercase or camelCase (e.g., `AmountFormatter.swift`, `DateFormatters.swift`)

**Functions:**
- camelCase with verb prefix for actions: `loadAccounts()`, `saveTransactions()`, `calculateBalance()`, `applyTransaction()`
- Omit "get" prefix for simple accessors: `accounts` (property) not `getAccounts()` (method)
- Use "is" prefix for boolean properties/methods: `isImported`, `isEmpty`, `isFullyInitialized`
- Use "on" prefix for event handlers: `onTap`, `onChange(of:)`
- Use trailing closure syntax for completion/action callbacks

**Variables:**
- camelCase for all local and instance variables: `totalIncome`, `transactionStore`, `isFastPathDone`
- Constants at file scope: camelCase (e.g., `transferCategoryName`) or ALL_CAPS for singleton patterns
- @State variables: camelCase (e.g., `@State var visibleSectionLimit = 100`)
- @Observable properties that should NOT trigger UI updates: prefix with `@ObservationIgnored` (Phase 23 rule)

**Types:**
- Enum cases: camelCase (`.expense`, `.income`, `.internalTransfer`)
- Enum raw values: appropriate for context (String: `case depositTopUp = "deposit_topup"`)
- Generic type parameters: single uppercase letter (T, V, D) or descriptive (CategoryDestination)
- Protocol names: end with `Protocol` suffix (preferred) or `Service`/`Manager` suffix for logic containers

**@ObservationIgnored Rule (Phase 23 - CRITICAL):**
All `let` dependencies in `@Observable` classes MUST be marked `@ObservationIgnored`:
- Services, repositories, coordinators (e.g., `@ObservationIgnored let repository`)
- Other ViewModels, Stores, Coordinators passed as parameters
- Internal cache objects, formatters, loggers
- **Exception**: properties that are `var` and change after init AND should trigger UI updates don't need it

Example from codebase (`AppCoordinator.swift`):
```swift
@Observable @MainActor
class AppCoordinator {
    @ObservationIgnored let repository: DataRepositoryProtocol
    @ObservationIgnored let transactionStore: TransactionStore
    @ObservationIgnored let balanceCoordinator: BalanceCoordinator
    private(set) var isFastPathDone = false  // Observable, triggers UI
}
```

## Code Style

**Formatting:**
- No explicit linter configured (not detected in project root)
- 4-space indentation (Swift default)
- Line length: practical limit ~120 characters (observed in code)
- Brace style: opening brace on same line (K&R style): `func test() {`
- Import order: Foundation first, then SwiftUI/Frameworks, then local imports

**Linting:**
- No SwiftLint, ESLint, or Prettier config detected
- Manual code review style based on CLAUDE.md guidelines
- Swift 6 concurrency enforced via `SWIFT_STRICT_CONCURRENCY = targeted` compiler setting
- Warnings treated as errors per Phase 11 (164 concurrency warnings fixed)

**Comments:**
- JSDoc-style triple-slash documentation for public functions:
  ```swift
  /// Load transactions with optional date range filter
  /// - Parameter dateRange: Optional date range to filter transactions
  /// - Returns: Array of transactions matching the filter
  func loadTransactions(dateRange: DateInterval?) -> [Transaction]
  ```
- Single-line comments for inline clarifications: `// Expected`
- MARK: comments for section organization: `// MARK: - Setup & Teardown`
- Context-critical warnings inline (e.g., `// ⚠️ Намеренно НЕ применяем clipShape`)

## Import Organization

**Order:**
1. Foundation imports (`import Foundation`, `import CoreData`)
2. Framework imports (UIKit, SwiftUI, Combine, Charts)
3. Observation framework (`import Observation`)
4. OS/logging (`import os`)
5. Local project imports (`@testable import AIFinanceManager`)

**Path Aliases:**
- No custom path aliases detected
- Explicit relative imports not used (flat module structure)
- Test imports use `@testable` for accessing `internal` symbols

**Example from `TransactionStore.swift`:**
```swift
import Foundation
import SwiftUI
import CoreData
import Observation
import os
```

## Error Handling

**Patterns:**
- Custom error enums with `LocalizedError` conformance:
  ```swift
  enum TransactionStoreError: LocalizedError {
      case invalidAmount
      case accountNotFound
      case categoryNotFound
  }
  ```
- Throwing functions use `throws` keyword: `func add(_ transaction: Transaction) throws`
- Error propagation with `try` keyword explicit at call sites: `try await store.add(transaction)`
- Guard statements for optional unwrapping with early exit:
  ```swift
  guard let account = accounts.first(where: { $0.id == accountId }) else {
      throw TransactionStoreError.accountNotFound
  }
  ```
- Do-catch blocks for error recovery: seen in test files with error type checking
- Result type not preferred; direct throwing is idiomatic

**Testing pattern** (from `TransactionStoreTests.swift`):
```swift
do {
    try await store.add(transaction)
    XCTFail("Should throw invalidAmount error")
} catch TransactionStoreError.invalidAmount {
    // Expected
} catch {
    XCTFail("Wrong error type: \(error)")
}
```

## Logging

**Framework:** OS Logger (`import os`)

**Pattern:**
- Create static logger in `@Observable` classes:
  ```swift
  @ObservationIgnored private let logger = Logger(subsystem: "AIFinanceManager", category: "ComponentName")
  ```
- Use `.debug()`, `.info()`, `.error()` log levels
- Performance profiling via `PerformanceProfiler.start/end()` (#if DEBUG blocks)

**Where to log:**
- Initialization and async operations start
- Error conditions and recovery attempts
- Performance-critical sections (balance calculations, data migrations)
- State transitions in coordinators

## Function Design

**Size:**
- Target: 20-40 lines per function (observed average across codebase)
- Extract helper methods when function exceeds 60 lines
- Computed properties preferred for simple calculations (Phase 16 pattern)

**Parameters:**
- Explicit parameter names at call sites (no positional arguments)
- Default values for optional parameters: `func cardStyle(radius: CGFloat = AppRadius.pill)`
- Use parameter groups for related inputs (e.g., dates, filters)
- @escaping closures for callbacks: rare, prefer delegates or closure return types

**Return Values:**
- Explicit return type annotation required
- Use `some View` in SwiftUI views with `@ViewBuilder` for implicit returns
- Computed properties (`var`) for simple transformations; methods for logic
- Optional returns only when value may legitimately not exist (not for error cases)

**Async pattern:**
```swift
@MainActor
func load() async throws -> [Transaction] {
    let result = try await repository.loadTransactions(dateRange: dateRange)
    return result
}
```

## Module Design

**Exports:**
- Public API explicitly marked: `public` keyword for frameworks; omitted for app code
- `internal` (no modifier) for cross-module friend access (e.g., extensions in different files)
- `private` for file-scoped helpers and extension-only methods
- `fileprivate` rarely used (prefer `private` + extension organization)

**Barrel Files:**
- Not used in this codebase
- Each module (`Services/Balance/`, `Views/Components/`) has separate files
- `AppCoordinator.swift` acts as single entry point for ViewModels

**Example from `Services/Core/` architecture:**
- `DataRepositoryProtocol.swift` defines interface
- `CoreDataRepository.swift` implements facade
- Specialized repos: `TransactionRepository.swift`, `AccountRepository.swift`, etc.
- Each file is independent; no barrel re-exports

## Swift 6 Concurrency

**Critical Pattern (@MainActor isolation):**
- All ViewModels marked `@MainActor @Observable`:
  ```swift
  @Observable @MainActor
  class TransactionStore {
      @ObservationIgnored let repository: DataRepositoryProtocol
  }
  ```
- CoreData operations wrapped in `context.perform { }` for thread safety:
  ```swift
  context.perform {
      entity.balance = newBalance  // Safe mutate on context thread
  }
  ```

**DateFormatter Thread Safety:**
- Store as `@MainActor private static let` or `nonisolated(unsafe)`:
  ```swift
  @MainActor private static let dateFormatter = DateFormatters.dateFormatter
  ```
- Never create DateFormatter inside `Task.detached`
- Pass formatted `String` across actor boundaries, not formatter

**Sendable Conformance:**
- Request types: `@Sendable struct BalanceUpdateRequest { let completion: @Sendable () -> Void }`
- Singletons with internal sync: `@unchecked Sendable` on `CoreDataStack`

## Naming Coordinator vs Service vs ViewModel

| Type | Pattern | Location | Example |
|------|---------|----------|---------|
| **ViewModel** | Holds UI state, @Observable @MainActor | `ViewModels/` | `TransactionsViewModel`, `InsightsViewModel` |
| **Store** | Single source of truth, @Observable @MainActor | `ViewModels/` | `TransactionStore`, `BalanceStore` |
| **Service** | Business logic, stateless | `Services/Domain/` | `VoiceInputParser`, `TransactionQueryService` |
| **Repository** | Data persistence abstraction | `Services/Repository/` | `TransactionRepository`, `CoreDataRepository` |
| **Coordinator** | Dependency injection, orchestration | `Services/Domain/` or `ViewModels/` | `AppCoordinator`, `BalanceCoordinator`, `DataResetCoordinator` |

---

*Convention analysis: 2026-03-02*
