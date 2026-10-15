# Codebase Structure

**Analysis Date:** 2026-03-02

## Directory Layout

```
Tenra/
├── Tenra/                  # Localization folder (en.lproj, ru.lproj)
├── Assets.xcassets/                   # Image assets (bank logos, app icon, colors, icons)
├── CoreData/
│   ├── Entities/                      # Auto-generated CoreData entity classes (12 entities)
│   ├── Tenra.xcdatamodeld/ # CoreData schema definition
│   └── CoreDataStack.swift            # Core Data initialization & lifecycle management
├── Debug/                             # Debug configuration and utilities
├── Extensions/                        # Swift extensions (6 files: Date, Double, String, etc.)
├── Models/                            # Value type domain models (27 files)
├── Protocols/                         # Protocol definitions (19 files)
├── Services/                          # Business logic organized by domain (15 subdirectories)
│   ├── Audio/                         # Audio playback services
│   ├── Balance/                       # Balance calculation & coordination
│   ├── CSV/                           # CSV import/export services
│   ├── Cache/                         # Caching coordinators
│   ├── Categories/                    # Category operations & budgets
│   ├── Core/                          # Core protocols (DataRepositoryProtocol)
│   ├── Import/                        # PDF & statement text parsing
│   ├── Insights/                      # Financial insights computation (10 files)
│   ├── ML/                            # Machine learning services
│   ├── Recurring/                     # Recurring transaction generation & validation
│   ├── Repository/                    # Data persistence (5 specialized repos)
│   ├── Settings/                      # App settings management
│   ├── Transactions/                  # Transaction filtering, grouping, pagination
│   ├── Utilities/                     # Generic utility services
│   └── Voice/                         # Voice input parsing
├── Utils/                             # Helper utilities (19 files)
│   ├── Design system (6 files)        # AppColors, AppSpacing, AppTypography, AppShadow, AppAnimation, AppModifiers
│   ├── Formatters (3 files)           # Amount formatting, date formatters
│   ├── Helpers (6 files)              # Category helpers, carousel config, amount display, etc.
│   └── Tools (4 files)                # Performance profiler, ID generators, etc.
├── ViewModels/                        # Observable state management (16 files)
│   ├── Balance/                       # Balance-related view model helpers
│   ├── AppCoordinator.swift           # Central DI & initialization
│   ├── TransactionStore.swift         # Single source of truth for transaction domain
│   ├── TimeFilterManager.swift        # Shared time filter state
│   └── [Feature]ViewModel.swift       # Feature-specific ViewModels
├── Views/                             # SwiftUI views (11 subdirectories)
│   ├── Accounts/                      # Account management & display
│   ├── Categories/                    # Category management & display
│   ├── Components/                    # Shared reusable UI components (34 files)
│   ├── CSV/                           # CSV import flow views
│   ├── Deposits/                      # Deposit management views
│   ├── History/                       # Transaction history views
│   ├── Home/                          # Home screen (main entry point)
│   ├── Import/                        # PDF/statement import views
│   ├── Insights/                      # Financial insights views (7 files)
│   ├── Settings/                      # Settings and preferences
│   ├── Subscriptions/                 # Subscription/recurring views
│   ├── Transactions/                  # Transaction add/edit/detail
│   └── VoiceInput/                    # Voice input UI
└── TenraApp.swift          # App entry point (@main)

TenraTests/                # Unit tests
├── ViewModels/                        # ViewModel tests
├── Balance/                           # Balance calculation tests
├── Utils/                             # Utility & formatter tests
├── Models/                            # Model tests
└── Services/                          # Service tests
```

## Directory Purposes

**Tenra (Top Level):**
- Purpose: Main app target source code
- Contains: All view, model, service, and persistence code
- Entry point: `Tenra.swift` (@main app)

**CoreData/:**
- Purpose: Core Data persistence infrastructure
- Contains: `CoreDataStack.swift` (singleton, thread-safe), auto-generated entity classes, schema
- Key file: `Tenra.xcdatamodeld` (defines 12 entities: Transaction, Account, Category, Subcategory, RecurringSeries, RecurringOccurrence, etc.)
- Entity generation: Auto-generated from .xcdatamodeld (edit schema in Xcode, regenerate entities)

**Models/:**
- Purpose: Value-type domain models (Codable, Equatable, Identifiable)
- Contains: Transaction, Account, CustomCategory, Subcategory, RecurringSeries, RecurringOccurrence, TimeFilter, InsightModels, etc. (27 files)
- Pattern: Struct with Codable conformance, custom init for defaults, CodingKeys for backward compatibility
- Mapping: Repository methods map CoreData entities ↔ value models

**ViewModels/:**
- Purpose: Observable state management and business logic orchestration
- Contains: `AppCoordinator` (central DI), `TransactionStore` (transaction SSOT), feature ViewModels, TimeFilterManager
- Pattern: @Observable @MainActor class with @ObservationIgnored dependencies
- Key file: `AppCoordinator.swift` — initializes all ViewModels, Stores, and Coordinators
- Core SSOT: `TransactionStore.swift` — all transaction-domain mutations go through this

**Services/:**
- Purpose: Domain-organized business logic
- Organization: 15 subdirectories by domain (Balance, CSV, Categories, Import, Insights, Recurring, Repository, Transactions, etc.)
- Core abstraction: `DataRepositoryProtocol` in Services/Core/
- Repository pattern: CoreDataRepository (facade) + 4 specialized repos (Transaction, Account, Category, Recurring) in Services/Repository/
- Key services:
  - `BalanceCoordinator` (Services/Balance/) — single entry point for balance operations
  - `InsightsService` (Services/Insights/) — financial insights (10 files: main + 9 extensions)
  - `TransactionRepository` (Services/Repository/) — transaction persistence (29.6 KB)
  - `RecurringTransactionGenerator` (Services/Recurring/) — future recurring transactions
  - `CSVImportCoordinator` (Services/CSV/) — orchestrate CSV import flow

**Views/:**
- Purpose: SwiftUI user interface
- Organization: 11 feature subdirectories (Accounts, Categories, Home, Insights, etc.) + shared Components
- Component files: Reusable UI elements (34 files: MessageBanner, UniversalCarousel, UniversalRow, SkeletonLoadingModifier, etc.)
- Feature views: Feature-specific pages and detail views
- Root: ContentView (Home), MainTabView (tab navigation)
- Pattern: Views access ViewModels via @Environment; use .onChange() and .task() for reactivity

**Utils/:**
- Purpose: Helper utilities, formatters, design tokens
- Design system (6 files):
  - `AppColors.swift` — semantic colors + CategoryColors palette (hex colors for 12+ categories)
  - `AppSpacing.swift` — padding, margin, radius constants
  - `AppTypography.swift` — font definitions (Inter variable font)
  - `AppShadow.swift` — shadow definitions
  - `AppAnimation.swift` — animation constants and BounceButtonStyle
  - `AppModifiers.swift` — View style extensions (cardStyle, filterChipStyle, transactionRowStyle, futureTransactionStyle, etc.)
- Formatters (3 files):
  - `AmountFormatter.swift` — format/parse/validate amounts (always 2 decimal places)
  - `AmountDisplayConfiguration.swift` — cached NumberFormatter (hot path: AmountDisplayConfiguration.formatter)
  - `AmountInputFormatting.swift` — input formatting logic (0-2 decimal places, no trailing zeros)
- Helpers (6 files): Category style caching, carousel configuration, amount display, transaction ID generation, date formatters, etc.
- Tools: PerformanceProfiler (#if DEBUG), validators, helpers

**Extensions/:**
- Purpose: Swift standard library and framework extensions
- Contains: Extensions for Date, Double, String, Color, View, etc. (6 files)
- Usage: Add convenience methods, computed properties

**Protocols/:**
- Purpose: Protocol definitions for abstraction
- Contains: ViewModel protocols, Service protocols (19 files)
- Key protocol: `DataRepositoryProtocol` (in Services/Core/) — core persistence abstraction
- Organization: Grouped by domain in Protocols/ subdirectories (Settings, etc.)

**Debug/:**
- Purpose: Debug utilities and configuration
- Contains: Debug helpers, logging utilities

**TenraTests/:**
- Purpose: Unit tests
- Organization: Mirrors source structure (ViewModels/, Services/, Models/, Utils/)
- Coverage: Repository tests, balance calculation tests, amount formatter tests, model tests
- Pattern: Test files use `@testable import Tenra`

## Key File Locations

**Entry Points:**
- `Tenra/TenraApp.swift`: App entry point (@main), CoreData pre-warm orchestration
- `Tenra/Views/Home/MainTabView.swift`: Tab bar navigation (Home, Transactions, Categories, Insights, Subscriptions, Settings)
- `Tenra/Views/Home/ContentView.swift`: Home screen (account summary, quick-add)

**Configuration:**
- `Tenra/CoreData/CoreDataStack.swift`: Core Data stack initialization, store management, lifecycle
- `Tenra/CoreData/Tenra.xcdatamodeld/`: CoreData schema (12 entities)
- `Tenra/ViewModels/AppCoordinator.swift`: Dependency injection, ViewModel initialization

**Core Logic:**
- `Tenra/ViewModels/TransactionStore.swift`: Single source of truth (transactions, accounts, categories, recurring data)
- `Tenra/Services/Core/DataRepositoryProtocol.swift`: Persistence abstraction protocol
- `Tenra/Services/Repository/CoreDataRepository.swift`: Facade delegating to specialized repos
- `Tenra/Services/Balance/BalanceCoordinator.swift`: Balance calculation coordination
- `Tenra/Services/Insights/InsightsService.swift`: Financial insights computation (main + 9 extensions)

**Testing:**
- `TenraTests/Services/AccountRepositoryTests.swift`: Repository persistence tests
- `TenraTests/Utils/AmountFormatterTests.swift`: Formatter tests
- `TenraTests/Balance/BalanceCalculationTests.swift`: Balance calculation tests
- `TenraTests/ViewModels/TransactionStoreTests.swift`: TransactionStore tests

## Naming Conventions

**Files:**
- ViewModel files: `[FeatureName]ViewModel.swift` (e.g., `TransactionsViewModel.swift`, `InsightsViewModel.swift`)
- Coordinator files: `[Name]Coordinator.swift` (e.g., `AppCoordinator.swift`, `BalanceCoordinator.swift`)
- Service files: `[Domain][Purpose]Service.swift` (e.g., `RecurringValidationService.swift`, `BalanceCalculationEngine.swift`)
- Repository files: `[Entity]Repository.swift` (e.g., `TransactionRepository.swift`, `AccountRepository.swift`)
- View files: `[Feature][Purpose]View.swift` (e.g., `ContentView.swift`, `TransactionDetailView.swift`)
- Component files: `[ComponentName].swift` (e.g., `MessageBanner.swift`, `UniversalCarousel.swift`)
- Model files: `[EntityName].swift` (e.g., `Transaction.swift`, `CustomCategory.swift`)
- Extension files: `+[Purpose].swift` OR `[Entity]+Extensions.swift` (e.g., `InsightsService+Spending.swift`, `Double+Extensions.swift`)
- Protocol files: `[Name]Protocol.swift` (e.g., `DataRepositoryProtocol.swift`)

**Directories:**
- Feature directories: PascalCase (Accounts, Categories, Home, Insights)
- Service domains: lowercase (balance, csv, cache, categories, import, insights, recurring, repository, transactions, voice)
- Protocol groups: Protocols/ subdirectories by domain (Protocols/Settings/)

## Where to Add New Code

**New Feature:**
- **Primary code:** `Services/[DomainName]/[FeatureName]Service.swift` (business logic)
- **ViewModel:** `ViewModels/[FeatureName]ViewModel.swift` (if UI state needed)
- **Views:** `Views/[FeatureName]/[Purpose]View.swift` (SwiftUI UI)
- **Tests:** `TenraTests/Services/[FeatureName]Tests.swift`

**New Transaction-Related Feature:**
- Use existing `TransactionStore` for state (no new store needed)
- Add methods to `TransactionStore` or new service in `Services/Transactions/`
- Example: New transaction filter → add to `Services/Transactions/TransactionFilterService.swift`

**New Component/Module:**
- **Implementation:** `Views/Components/[ComponentName].swift`
- **Style extensions:** `Utils/AppModifiers.swift` (add `.componentStyle()` modifier)
- **Constants:** `Utils/AppColors.swift` or `Utils/AppSpacing.swift` (if design tokens needed)

**New ViewModel:**
- Location: `ViewModels/[Name]ViewModel.swift`
- Pattern: `@Observable @MainActor class [Name]ViewModel { @ObservationIgnored let repository: DataRepositoryProtocol; ... }`
- Dependencies: Declare in `AppCoordinator.__init__()` and inject
- Register in `AppCoordinator`: add property, initialize in `init()`

**Utilities/Helpers:**
- Shared formatters: `Utils/[Purpose]Formatting.swift` (e.g., AmountInputFormatting.swift)
- Shared helpers: `Utils/[Purpose]Helper.swift` (e.g., CategoryStyleHelper.swift)
- Design tokens: `Utils/App[TokenType].swift` (AppColors.swift, AppSpacing.swift, etc.)

**Repository Operations:**
- **Query only:** Add method to `DataRepositoryProtocol` and `CoreDataRepository`, implement in specialized repo
- **Mutation:** Route through `TransactionStore.apply()` event pipeline
- **Batch operation:** Add `batch[Operation]()` method to repository

## Special Directories

**Views/Components/:**
- Purpose: Reusable UI elements (no extra nesting)
- Generated: No
- Committed: Yes
- Contains: 34 files including MessageBanner, UniversalCarousel, UniversalRow, UniversalFilterButton, SkeletonLoadingModifier, BudgetProgressCircle, StatusIndicatorBadge, etc.
- Rule: Add component here if used by 2+ feature views

**Services/Insights/**
- Purpose: Financial insights computation split across 10 files
- Contains: `InsightsService.swift` (782 LOC main + PreAggregatedData struct) + 9 extensions
- Extensions: `+Spending.swift`, `+Income.swift`, `+Budget.swift`, `+Recurring.swift`, `+CashFlow.swift`, `+Wealth.swift`, `+Savings.swift`, `+Forecasting.swift`, `+HealthScore.swift`
- Rule: Cross-file extensions need `internal` access (no `private`); each file imports `os` and `CoreData` independently
- Pattern: Generators accept `PreAggregatedData?` parameter and use pre-computed fields (O(1) lookups instead of O(N) scans)

**Services/Repository/**
- Purpose: Data persistence abstraction
- Contains: `DataRepositoryProtocol` (core), `CoreDataRepository` (facade), + 4 specialized repos
- Specialized repos: `TransactionRepository`, `AccountRepository`, `CategoryRepository`, `RecurringRepository`
- Rule: Add new persistence method to `DataRepositoryProtocol` first; implement in all concrete classes
- Pattern: Use `context.perform { }` for all CoreData mutations (thread-safe with Swift 6)

**CoreData/Entities/**
- Purpose: Auto-generated CoreData entity classes
- Generated: Yes (from .xcdatamodeld via Xcode)
- Committed: Yes (committed as source of truth)
- Edit: Modify schema in Xcode Data Model Inspector, regenerate
- Rule: Do NOT manually edit these files — they are overwritten on schema changes

**Utils/ (Design System)**
- Purpose: Centralized design tokens and style extensions
- Contains: 6 files (AppColors, AppSpacing, AppTypography, AppShadow, AppAnimation, AppModifiers)
- Rule: All hardcoded colors, spacing, shadows, animations must go here; Views import and use tokens
- Zero hardcoded colors in View code (enforced in Phase 32)

**ViewModels/Balance/**
- Purpose: Balance-related ViewModel helpers
- Contains: Balance calculation helpers, balance display formatters
- Rule: Complex balance state goes here; simple balance display logic stays in views

---

*Structure analysis: 2026-03-02*
