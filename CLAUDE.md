# Tenra — Project Guide for Claude

## gstack

Use the `/browse` skill from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools directly.

Available gstack skills:
- `/plan-ceo-review` — review plan from a CEO/product perspective
- `/plan-eng-review` — review plan from an engineering perspective
- `/review` — code review
- `/ship` — ship a feature end-to-end
- `/browse` — web browsing (use this instead of chrome MCP tools)
- `/qa` — QA testing
- `/setup-browser-cookies` — configure browser session cookies
- `/retro` — run a retrospective

## Quick Start

```bash
# Open project (requires Xcode 26+ beta)
open Tenra.xcodeproj

# Build via CLI
xcodebuild build \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run unit tests
xcodebuild test \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests

# Available destinations (Xcode 26 beta): iPhone 17 Pro (iOS 26.2), iPhone Air, iPhone 16e
# Physical device: name:Dkicekeeper 17

# ⚠️ If the user is testing on the physical device, build/run to it (-destination 'id=...' or
# 'platform=iOS,name=Dkicekeeper 17'). A Simulator build never reaches a connected device —
# the user will report "the fix didn't work" while running a stale binary.

# Quickly isolate build errors (skip swiftc log noise)
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30

# If xcodebuild reports "accessing build database ... database is locked", another
# xcodebuild instance is still finishing — wait ~5s and retry, no other action needed.

# Profiling on real device (xctrace, requires unlocked iPhone)
# Open Xcode → Window → Devices and Simulators to prime the connection.
# Disable iPhone auto-lock during recording. Performance perf needs a real
# device, not the simulator. If xctrace fails 2-3 times after retrying,
# abandon the trace and audit the code grounded in this file's patterns.
xcrun xctrace record --template SwiftUI \
  --output ~/Desktop/session.trace \
  --device "Dkicekeeper 17" --attach Tenra
```

## Project Overview

Tenra is a native iOS finance management application built with SwiftUI and CoreData. Tracks accounts, transactions, budgets, deposits, loans, and recurring payments.

**Tech Stack:**
- SwiftUI (iOS 26+ with Liquid Glass adoption)
- Swift 5.0 (project setting), targeting Swift 6 patterns; `SWIFT_STRICT_CONCURRENCY = minimal`; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- CoreData for persistence (v8 schema)
- Observation framework (@Observable)
- MVVM + Coordinator architecture

## Project Structure

```
Tenra/
├── Models/              # CoreData entities and business models
├── ViewModels/          # Observable view models (@MainActor)
│   └── Balance/         # Balance calculation helpers
├── Views/               # SwiftUI views and components
│   ├── Components/      # Shared reusable components
│   │   ├── Cards/       # Standalone card views
│   │   ├── Rows/        # List and form row views
│   │   ├── Forms/       # Form containers
│   │   ├── Icons/       # Icon display and picking
│   │   ├── Input/       # Interactive input
│   │   ├── Charts/      # Data visualization
│   │   ├── Headers/     # Section headers and hero displays
│   │   └── Feedback/    # Banners, badges, status, content reveal
│   ├── Accounts/        # Account management views
│   ├── Transactions/    # Transaction views
│   ├── Categories/      # Category views
│   ├── Subscriptions/   # Subscription views
│   ├── History/         # History views
│   ├── Deposits/        # Deposit views
│   ├── Settings/        # Settings views
│   ├── VoiceInput/      # Voice input views
│   ├── CSV/             # CSV views
│   ├── Import/          # Import views
│   └── Home/            # Home screen
├── Services/            # Business logic organized by domain
├── Protocols/           # Protocol definitions
├── Extensions/          # Swift extensions
├── Utils/               # Helper utilities and formatters
└── CoreData/            # CoreData stack and entities
```

**Note:** `Account`, `Transaction`, and several related structs (`DepositInfo`, `LoanInfo`, summaries) all live in `Tenra/Models/Transaction.swift` — don't grep for `Models/Account.swift`, it doesn't exist.

## Architecture at a Glance

- **AppCoordinator** — central DI container; two-phase startup (fastPath → full)
- **TransactionStore** — single source of truth for transactions, accounts, categories; in-memory all 19k tx
- **BalanceCoordinator** — single entry point for balance ops + caching
- **Repository pattern** — `DataRepositoryProtocol` facade over 5 specialized repos in `Services/Repository/`. **Three places to update when extending the protocol or a sub-protocol** (e.g. `AccountRepositoryProtocol`): production impl (e.g. `AccountRepository`), `UserDefaultsRepository` (previews), and any test mock (e.g. `MockAccountRepository` in `TenraTests/Services/AccountRepositoryTests.swift`). Missing the test mock breaks `xcodebuild test` even though `xcodebuild build` passes.
- **InsightsService** — `nonisolated final class`, runs on background via `Task.detached`. Cannot read MainActor-isolated `TransactionStore` indexes (e.g. `categoryAggregatesByKey`); uses legacy O(N) snapshot-based APIs instead — see `CategoryBudgetService.budgetProgress(for:transactions:baseCurrency:)` static helper.
- **TransactionStore indexes** (`categoryById`, `subcategoryIdsByCategoryId`, `transactionsByCategoryName`, etc.) — declared `@ObservationIgnored internal(set) var`, NOT `private(set)`. Maintenance lives in extension files of the same module; `private(set)` would block setters across files. See [TransactionStore.swift](Tenra/ViewModels/TransactionStore.swift).

For deep details see [docs/architecture.md](docs/architecture.md).

## File Organization Decision Tree

```
New file needed?
├─ SwiftUI View?
│  ├─ Reusable component (card, row, input, chart, etc.)? → Views/Components/<subdir>/
│  └─ Screen, modal, or coordinator? → Views/FeatureName/
├─ UI state management?
│  └─ → ViewModels/ (mark with @Observable and @MainActor)
├─ Business logic?
│  ├─ Transactions? → Services/Transactions/
│  ├─ Account/CoreData? → Services/Repository/
│  ├─ Categories? → Services/Categories/
│  ├─ Balance? → Services/Balance/
│  ├─ CSV? → Services/CSV/
│  ├─ Voice? → Services/Voice/
│  ├─ PDF parsing? → Services/Import/
│  ├─ Recurring? → Services/Recurring/
│  ├─ Loans? → Services/Loans/
│  ├─ Caching? → Services/Cache/
│  ├─ Settings? → Services/Settings/
│  ├─ Core protocol/shared? → Services/Core/
│  └─ Generic utility? → Services/Utilities/
├─ Domain model? → Models/
├─ Protocol? → Protocols/
└─ Utility/helper?
   ├─ Extension? → Extensions/
   └─ Formatter, theme, animation token? → Utils/
```

## Naming Conventions

| Type | Suffix | Location | Purpose |
|------|--------|----------|---------|
| **AppCoordinator** | Coordinator | ViewModels/ | Central DI |
| **Feature Coordinators** | Coordinator | Views/Feature/ | Navigation & feature setup |
| **Service Coordinators** | Coordinator | Services/Domain/ | Orchestrate multiple services |
| **Domain Services** | Service | Services/Domain/ | Business logic operations |
| **Repositories** | Repository | Services/Repository/ | Data persistence |
| **Stores** | Store | ViewModels/ | Single source of truth |
| **ViewModels** | ViewModel | ViewModels/ | UI state management |

## When to Read Which Doc

| Working on... | Read first |
|---|---|
| AppCoordinator, TransactionStore role, BalanceCoordinator, Repository pattern, CoreData v8 model | [docs/architecture.md](docs/architecture.md) |
| `@Observable`, `Task`, `MainActor`, `nonisolated`, CoreData threading, `Sendable` | [docs/concurrency.md](docs/concurrency.md) |
| `Views/Components/**`, animations, IconView, AppSpacing/Colors/Animation tokens, cardStyle, AnimatedInputComponents, amount formatting | [docs/design-system.md](docs/design-system.md) |
| `Services/Insights/**` (operational guide) | [docs/domains/insights.md](docs/domains/insights.md) |
| Per-metric formulas, granularity, severity behavior | [docs/INSIGHTS_METRICS_REFERENCE.md](docs/INSIGHTS_METRICS_REFERENCE.md) |
| TransactionStore CRUD, FRC, addBatch, NSBatchDeleteRequest | [docs/domains/transactions.md](docs/domains/transactions.md) |
| Categories, subcategories, budgets, category/subcategory indexes, style cache, reorder | [docs/domains/categories.md](docs/domains/categories.md) |
| Accounts indexes (accountAggregatesByAccountId, transactionsBySeriesId, parsedDateById), AccountDetailView, ranking | [docs/domains/accounts.md](docs/domains/accounts.md) |
| Deposits, DepositInfo, interest accrual, capitalization | [docs/domains/deposits.md](docs/domains/deposits.md) |
| Loans, LoanInfo, LoanPaymentService, manual payments, linking | [docs/domains/loans.md](docs/domains/loans.md) |
| Recurring transactions, RecurringStore, series + occurrences | [docs/domains/recurring.md](docs/domains/recurring.md) |
| Swift Charts (PeriodChart, IncomeExpense, scrollable, MiniSparkline) | [docs/domains/charts.md](docs/domains/charts.md) |
| CSV import/export round-trip rules | [docs/domains/csv.md](docs/domains/csv.md) |
| VoiceInput, speech recognition, SiriGlowView | [docs/domains/voice.md](docs/domains/voice.md) |
| FX rates, currency conversion, prewarm, providers, base-currency aggregation (`convertSync` vs `convertedAmount`) | [docs/domains/currency.md](docs/domains/currency.md) |
| Logo providers, ServiceLogoRegistry, jsDelivr | [docs/domains/logos.md](docs/domains/logos.md) |
| Performance hot-paths, SwiftUI Layout gotchas, common cross-domain pitfalls | [docs/gotchas.md](docs/gotchas.md) |

**Rule**: before editing files in a domain, Read the matching doc.

## Critical Red Flags

These cause silent data corruption or crashes — internalize even without reading the domain doc:

1. ⚠️ **`TransactionStore.allTransactions` setter is a no-op.** To delete transactions, use `TransactionStore.deleteTransactions(for...)` (routes through `apply(.deleted)`). See [domains/transactions.md](docs/domains/transactions.md).
2. ⚠️ **Never mutate `Account.depositInfo.principalBalance` outside `DepositInterestService.reconcileDepositInterest`.** It's a cached result. Link-interest flow reclassifies tx type only — must NOT touch principalBalance / interestAccruedNotCapitalized. See [domains/deposits.md](docs/domains/deposits.md).
3. ⚠️ **NEVER use `NSBatchDeleteRequest` then `context.save()` on the SAME context** when deleted objects have inverse relationships. Use `context.delete()` instead. See [concurrency.md](docs/concurrency.md).
4. ⚠️ **SwiftUI `List` with 500+ Sections = hard freeze.** Always slice via `Array(sections.prefix(visibleSectionLimit))` with infinite-scroll trigger. See [gotchas.md](docs/gotchas.md).
5. ⚠️ **Generated recurring tx subcategories require explicit linking.** Always `await transactionStore.createSeries(series)` then call `categoriesViewModel.linkSubcategoriesToTransaction(...)`. See [domains/recurring.md](docs/domains/recurring.md).
6. ⚠️ **`Transaction.convertedAmount` is in *account* currency, NOT base currency.** Never sum `convertedAmount ?? amount` across multi-currency transactions to get a base-currency total — bug shows as `$20 + $100 = "120 KZT"`. Always convert via `CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency)` with `convertedAmount ?? amount` as a cold-cache fallback only. See [domains/currency.md](docs/domains/currency.md).
7. ⚠️ **NEVER render a money amount without a canonical formatter.** Forbidden in UI code: `Text("\(amount) \(currency)")`, `Text(String(format: "%.2f", amount))`, ad-hoc `NumberFormatter()` inside `body`/`List`/`ForEach`, raw `Formatting.formatCurrency(...)` for display (it always shows `.00`). Required: `FormattedAmountText` for standalone views, `InfoRow(... amount: currency:)` / `InfoRowConfig(... amount: currency:)` for info rows, `Formatting.formatCurrencySmart(_:currency:)` only when a `String` is needed (composed strings, hero subtitles). See [design-system.md §6 Amount Formatting](docs/design-system.md).

## Common Tasks

### Adding a New Feature
1. Create model (if needed) in `Models/`
2. Add service logic in `Services/` or enhance existing Store
3. Create/update ViewModel in `ViewModels/`
4. Build SwiftUI view in `Views/`
5. Wire up dependencies in `AppCoordinator`

### Working with Transactions
- Use `TransactionStore` for all transaction operations
- Subscribe to `TransactionStoreEvent` for reactive updates
- Read [domains/transactions.md](docs/domains/transactions.md) before mutating CRUD/FRC/batch paths

### Working with Balance
- Use `BalanceCoordinator` as single entry point
- Balance operations are cached automatically
- Public methods modifying balance MUST update `self.balances` AND call `persistBalance()` — see [architecture.md](docs/architecture.md)

### UI Components
- Reusable components live in `Views/Components/`
- See [design-system.md](docs/design-system.md) for tokens, components, decision trees, padding contract

### Snapshot `@State` driven by store mutation versions
Pattern used in CategoriesManagementView, CategoryDetailView, CategorySubcategoriesView for O(1) reads with controlled invalidation.
- `@ObservationIgnored` data (e.g. `store.subcategoryIdsByCategoryId`) read in `body` does NOT register a SwiftUI subscription. Touch a sibling Observable scalar (`store.categoriesMutationVersion`, `mutationVersion`, etc.) — even as `_ = store.xxx` — so the body re-evaluates when the index changes.
- `@State` snapshot populated via `.task(id: key)` is empty on first render. NEVER gate `if snapshot.isEmpty { EmptyState }` on it — the user sees an empty-state flash. Gate on source-of-truth instead: `if !store.categories.contains { $0.type == selectedType }`. Precedent: `CategoriesManagementView.hasCategoriesForCurrentType`.

## CoreData Schema Bumps

`Tenra.xcdatamodeld` is currently at v9. Bump checklist when adding an entity (additive — lightweight migration auto-handles):
1. `cp -r Tenra/CoreData/Tenra.xcdatamodeld/Tenra\ vN.xcdatamodel Tenra/CoreData/Tenra.xcdatamodeld/Tenra\ vN+1.xcdatamodel`, edit `contents` XML.
2. Update `Tenra/CoreData/Tenra.xcdatamodeld/.xccurrentversion` plist to point to vN+1.
3. Create `Tenra/CoreData/Entities/<Entity>+CoreDataClass.swift` + `<Entity>+CoreDataProperties.swift` (mirror `AccountAggregateEntity` for aggregate-style entities).
4. Add load/save to the matching `Services/Repository/<Domain>Repository.swift`, then forward in `CoreDataRepository.swift`, then add no-op stubs in `UserDefaultsRepository.swift` and any test mocks.

Lightweight migration only works for ADDITIVE changes (new entity, new optional attribute). Removing/renaming requires a mapping model — none in this project yet.

## iOS Simulator — System Warnings to Ignore

The following appear routinely in Xcode console on Simulator runs and are NOT bugs in our code. Don't try to fix them — none have application-side resolution:
- `Unable to simultaneously satisfy constraints ... TUIKeyplane.right.width == -1.5` — Apple's keyboard layout calculation in Simulator only. Doesn't appear on physical device.
- `Reading from public effective user settings` — informational from system Settings access.
- `Reporter disconnected { function=sendMessage, ... }` — telemetry/Instruments transport.
- `containerToPush is nil, will not push anything to candidate receiver` — SiriIntent candidate-receiver framework, no user-facing impact.

If a real symptom appears (UI freeze, missing label, broken constraint affecting layout), look at the stack trace — if it doesn't pass through `Tenra.` symbols, it's still not us.

## Testing

- Unit tests: `TenraTests/`
- UI tests: `TenraUITests/`
- Test ViewModels with mock repositories
- Test CoreData operations with in-memory stores
- ⚠️ Currency conversion tests must call `CurrencyRateStore.shared.clearAll()` in suite `init()` — see [domains/currency.md](docs/domains/currency.md)
- ⚠️ `xcodebuild test -only-testing:...` does NOT skip compilation — one broken test file fails the whole target. When a test file's API has drifted, wrap it in `#if false` / `#endif` with a header comment (existing precedent: `TenraTests/Onboarding/OnboardingViewModelTests.swift`, `TenraTests/Services/Voice/VoiceInputParserTests.swift`).
- ⚠️ Swift filenames must be unique within a target. Xcode rejects two `.swift` files with the same name even in different directories of the same target. When replacing a legacy test file with a fresh-API rewrite, rename the new one (precedent: `CategoryBudgetServiceStoreBackedTests.swift` replaces the legacy `CategoryBudgetServiceTests.swift`).
- Extract crash details from `.xcresult`: `xcrun xcresulttool get test-results tests --path <bundle.xcresult> --filter-by-test-id 'TenraTests/<Suite>/<test>'`

## Git Workflow

Current branch: `main`
- Commit messages should be descriptive and concise
- Follow conventional commits when possible
- Always review changes before committing
- Include co-author tag for AI assistance

## AI Assistant Instructions

When working with this project:

1. **Always read before editing**: Use Read tool to understand existing code
2. **Check the trigger table**: before touching domain files, read the matching doc from `docs/`
3. **Follow architecture**: respect MVVM + Coordinator patterns
4. **Use existing patterns**: check similar implementations before creating new ones
5. **Update AppCoordinator**: when adding new ViewModels or dependencies
6. **Maintain consistency**: follow existing code style and conventions
7. **Performance first**: consider performance implications; consult [gotchas.md](docs/gotchas.md) for known hot-paths
8. **Test changes**: verify builds and runs after modifications
9. **Document refactoring**: update affected docs in `docs/` when architecture changes

### Preferred Tools
- Use SwiftUI Expert skill for SwiftUI-specific tasks
- Use Read/Edit tools for file operations (not Bash cat/sed)
- Use Grep for searching code patterns
- Use Glob for finding files by pattern

### Don't
- Don't create unnecessary abstractions
- Don't ignore existing architectural patterns
- Don't add features without understanding context
- Don't skip reading existing code before modifications
- Don't use Combine when Observation framework is preferred
- Don't flag `#Preview` block inconsistencies as production drifts in audits — distinguish preview-only from production usage when grep'ing
- Don't write CLAUDE.md inline rules for things that fit in a domain doc — keep this file thin

## Questions?

When unsure about architecture decisions:
1. Check the trigger table above and read the matching doc
2. Check existing similar implementations
3. Review `AppCoordinator` for dependency patterns
4. Look at recent commits for refactoring context
5. Ask user for clarification on business requirements

---

## Reference Docs Index

Active reference docs in `docs/`:

| File | Purpose |
|------|---------|
| [architecture.md](docs/architecture.md) | MVVM+Coordinator deep dive, TransactionStore, BalanceCoordinator, Repository, CoreData v8 |
| [concurrency.md](docs/concurrency.md) | Swift 6 concurrency, CoreData threading, @Observable rules |
| [design-system.md](docs/design-system.md) | Design tokens, components, animations, padding contract, amount formatting |
| [gotchas.md](docs/gotchas.md) | SwiftUI Layout, Performance hot-paths, code hygiene |
| [INSIGHTS_METRICS_REFERENCE.md](docs/INSIGHTS_METRICS_REFERENCE.md) | Per-metric reference for InsightsService |
| [domains/transactions.md](docs/domains/transactions.md) | TransactionStore CRUD, FRC, batch ops |
| [domains/categories.md](docs/domains/categories.md) | Category / subcategory / budget aggregate indexes (O(1) reads), style cache invalidation, reorder |
| [domains/accounts.md](docs/domains/accounts.md) | Account / series / parsed-date indexes, AccountDetailView read contract, ranking helpers |
| [domains/insights.md](docs/domains/insights.md) | InsightsService architecture, DataSnapshot, PreAggregatedData |
| [domains/deposits.md](docs/domains/deposits.md) | Interest accrual, capitalization, conversion |
| [domains/loans.md](docs/domains/loans.md) | Manual payments, linking, amortization |
| [domains/recurring.md](docs/domains/recurring.md) | Series + occurrences, frequency cases |
| [domains/charts.md](docs/domains/charts.md) | Swift Charts patterns, scrollable, mini-charts |
| [domains/csv.md](docs/domains/csv.md) | CSV round-trip rules |
| [domains/voice.md](docs/domains/voice.md) | VoiceInput architecture, speech recognition |
| [domains/currency.md](docs/domains/currency.md) | FX rates, providers, prewarm |
| [domains/logos.md](docs/domains/logos.md) | Logo provider chain, ServiceLogoRegistry |

Historical docs (305 files) archived to `docs/archive/`.

---

**Last Updated**: 2026-05-05
**iOS Target**: 26.0+ (requires Xcode 26+ beta)
**Swift Version**: 5.0 project setting; Swift 6 patterns; `SWIFT_STRICT_CONCURRENCY = minimal`; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
