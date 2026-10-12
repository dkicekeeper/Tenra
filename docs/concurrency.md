# Swift 6 Concurrency & CoreData Threading

Critical patterns for thread safety in this codebase. Project ships with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_STRICT_CONCURRENCY = minimal`.

## Implicit MainActor Isolation

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means **ALL types are implicitly `@MainActor`** unless explicitly `nonisolated`.

- `nonisolated` on a type opts it out of implicit MainActor — use for services that must run off main thread
- `Task {}` inside `@MainActor` class inherits MainActor — `Task { @MainActor in }` is redundant
- `Task { @MainActor in }` IS needed inside nonisolated closures, audio callbacks
- **Modifier order**: access modifier ALWAYS first — `private nonisolated func`, `private nonisolated(unsafe) var`. NEVER `nonisolated private` or `nonisolated(unsafe) private`
- **`@NSManaged` order**: `@NSManaged public nonisolated var` — attribute first, access level second, `nonisolated` third
- **`nonisolated(unsafe)`** only for mutable `static var` / stored properties with no actor protection, or non-`Sendable` state — always add a comment explaining the accepted race

### ⚠️ A plain `final class` service runs its blocking work on the main thread

This is the most common consequence of the default isolation, and it hides well: the code
reads like a background service, compiles clean, and stalls the UI.

Blocking work means **file I/O, image encode/decode, CoreAudio, CoreData on `viewContext`** —
anything that waits on something outside the CPU. Marking the type `nonisolated` is *not*
enough on its own: a synchronous `nonisolated` method still runs on the caller's thread. The
work has to be in a `nonisolated` **`async`** function, which runs on the cooperative pool.

```swift
// ❌ implicitly @MainActor — the read and decode happen on the main thread
final class LogoDiskCache {
    func load(for name: String) -> UIImage? { UIImage(data: try! Data(contentsOf: url(name))) }
}

// ✅ nonisolated async — runs on the cooperative pool, awaited from the actor
nonisolated final class LogoDiskCache: @unchecked Sendable {
    func load(for name: String) async -> UIImage? { … }
}
```

When the surrounding type must stay MainActor (a view model, or a service whose state is
MainActor), put the blocking calls in a small `nonisolated` helper type instead of moving the
whole class. Precedents: [`VoiceAudioSession`](../Tenra/Services/Voice/VoiceAudioSession.swift),
[`VoiceRecordingEngine`](../Tenra/Services/Voice/VoiceRecordingEngine.swift), `WallpaperFileIO`
in [WallpaperManagementService](../Tenra/Services/Settings/WallpaperManagementService.swift).

⚠️ **Moving work off the actor makes the caller interruptible.** A sequence that was atomic
now has suspension points, so state can change mid-flight. `VoiceInputService.startToken` is
the pattern: the start claims a token, a stop bumps it, and the start tears down what it
built if the token changed. Check for this whenever you add an `await` to a setup path.

Cheaper than moving work: don't do it. `SettingsValidationService` checks that a wallpaper is
a valid image with a `CGImageSource` header probe instead of reading and decoding the photo.

## Sendable Types in iOS 26 SDK

These are `Sendable` in iOS 26 — use plain `nonisolated static let`, NOT `nonisolated(unsafe) static let`:

- `DateFormatter`
- `Logger`
- `Calendar`
- `NumberFormatter`

The same holds for constants of any `Sendable` type, e.g. `AppSettings.defaultCurrency`:

```swift
class AppSettings: Codable {
    nonisolated static let defaultCurrency = "KZT"
}
```

## DataSnapshot Pattern (capturing MainActor data into Sendable struct)

When you need to do heavy computation off MainActor, bundle MainActor-isolated data into a `Sendable` struct first, then pass it through the entire computation chain.

Example: [InsightsService.DataSnapshot](../Tenra/Services/Insights/InsightsService.swift) bundles transactions, categories, recurringSeries, accounts, and `balanceFor` closure — built on MainActor before `Task.detached`, threaded through the entire computation chain.

### Load-time snapshot builder (`TransactionStore.loadData`)

For "build N derived indexes from one array of 19k value-types" workloads, the established pattern is:

1. Define `Sendable` snapshot struct (e.g. [`TransactionStore.LoadedIndexSnapshot`](../Tenra/ViewModels/TransactionStore+LoadSnapshot.swift)).
2. `nonisolated static func` builder, pure over `Sendable` inputs — duplicates predicate helpers locally (e.g. `isAggregatableForLoad`) to avoid `MainActor`-isolated instance methods.
3. On MainActor: capture inputs as `Sendable` copies (`baseCurrency`, `accountsCurrencyById`, …), call `Task.detached(priority: .userInitiated)`, await the snapshot, then **only assign** the hash-maps. No per-tx loops on MainActor.
4. Optional fields on the snapshot for cold-start variants (e.g. `coldStartCategoryAggregates`) — same one-pass builder handles both warm and cold paths.

### Sendable conformance is opt-in for data structs

Even with all-value-type fields, structs don't auto-conform to `Sendable` if the source file doesn't declare it. When introducing a struct that will cross actor boundaries, add `: Sendable` explicitly. Precedents from this codebase: `Transaction`, `CategoryAggregate`, `AccountAggregates`, `CategoryExpense`.

Symptom of forgetting: `Task.detached` returning a `[String: YourType]` fails to compile with "captured value of non-sendable type ... in a `@Sendable` closure".

- Closures that cross actors are `@Sendable`.
- Reference types with internal synchronization are `@unchecked Sendable` (e.g. `BalancePersistQueue`, the repositories below).

### Render-frame yield after Observable mutations

When a SwiftUI reveal/transition is keyed off an Observable flag (e.g. `isFullyInitialized`), insert `try? await Task.sleep(for: .milliseconds(16))` **immediately after** the mutation if the next MainActor work is heavy. Without the yield, the new render and the heavy work both land in the same render cycle, stuttering the transition. 16 ms ≈ one 60fps frame. Precedent: [`AppCoordinator.initialize`](../Tenra/ViewModels/AppCoordinator.swift) after `isFullyInitialized = true`.

### Default isolation gotcha

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means plain `enum`/`class`/`struct static func` declarations are implicitly MainActor. Pure helpers called from `Task.detached` need explicit `nonisolated`. Precedent: `LedgerPolicyRule.isRealized` is `nonisolated static`. Symptom of forgetting: Swift 6 warning "call to main actor-isolated static method in a synchronous nonisolated context".

## CoreData Threading

All CoreData entity property mutations happen inside `context.perform { }` / `context.performAndWait { }`:

```swift
// ❌ WRONG — Causes Swift 6 concurrency violations
func updateAccount(_ entity: AccountEntity, balance: Double) {
    entity.balance = balance
}

// ✅ CORRECT — Thread-safe mutation
func updateAccount(_ entity: AccountEntity, balance: Double) {
    context.perform {
        entity.balance = balance
    }
}
```

### Repository pattern with CoreData

Repository classes are `nonisolated final class … @unchecked Sendable` — safe because every mutation runs inside `perform` / `performAndWait` on a background context. Private `*Internal(…, context:)` helpers assume the caller is already inside that block.

`CoreDataStack.newBackgroundContext()` must be `nonisolated` — repositories call it from nonisolated context.

Model struct `init` and computed properties accessed from nonisolated services need `nonisolated`.

```swift
// ✅ AccountRepository (same shape in CategoryRepository, TransactionRepository, …)
nonisolated final class AccountRepository: AccountRepositoryProtocol, @unchecked Sendable {
    func saveAccountsSync(_ accounts: [Account]) throws {
        let context = stack.newBackgroundContext()
        try context.performAndWait {
            try saveAccountsInternal(accounts, context: context)  // all mutations happen in here
            if context.hasChanges { try context.save() }
        }
    }
}

// ✅ CoreDataStack
final class CoreDataStack: @unchecked Sendable {
    nonisolated static let shared = CoreDataStack()
    nonisolated func newBackgroundContext() -> NSManagedObjectContext { … }
}
```

CoreData pitfalls (FRC, predicates, batch deletes, `viewContext.perform`) are in [domains/transactions.md §CoreData gotchas](domains/transactions.md#coredata-gotchas); save ordering (tickets, `BalancePersistQueue`) and whole-table saves during a load are in [architecture.md §Background saves](architecture.md#background-saves-coredatasavecoordinator) and [§The load window](architecture.md#the-load-window).

## Main Actor Isolation Patterns

- Use `.main` queue for `NotificationCenter` observers in ViewModels

```swift
// ✅ NotificationCenter observers
NotificationCenter.default.addObserver(
    forName: .someNotification,
    queue: .main  // ← Ensures MainActor context
) { ... }
```

## Cross-File Extension Access Control

- `private` is file-scoped — extensions in OTHER files can't access it
- Shared helpers → `internal` (no modifier); same file only → `private`
- `TransactionStore` indexes maintained from extension files (category, subcategory, series, account-aggregate maps) are therefore plain `var`, not `private(set)`; the ones written only in `TransactionStore.swift` (`transactionById`, `accountById`, `transactionIdsByAccount`) are `private(set)`.
- **Extension file imports are not inherited**: Each file needs its own `import os`, `import CoreData`, etc.

## Compiler Warnings to Watch

- **`internal(set) var` on internal properties** — redundant (default is already internal), generates warning; just use `var`
- **`defer` at end of scope** — generates "execution is not deferred" warning; replace with direct inline assignment
- **`@ObservationIgnored` only works inside `@Observable` classes** — on a regular `class`, `struct`, or `@MainActor`-class without `@Observable`, the attribute is silently ignored. Remove it if `@Observable` is removed from the class.

## @Observable Rules

### `@ObservationIgnored` for Dependencies

Any property that is a service, repository, cache, formatter, or reference to another VM/Coordinator **must** be marked `@ObservationIgnored`:

```swift
// ❌ WRONG — SwiftUI tracks repository and currencyService
@Observable @MainActor class SomeViewModel {
    let repository: DataRepositoryProtocol
    let currencyService = TransactionCurrencyService()
    var isLoading = false
}

// ✅ CORRECT — only isLoading is tracked
@Observable @MainActor class SomeViewModel {
    @ObservationIgnored let repository: DataRepositoryProtocol
    @ObservationIgnored let currencyService = TransactionCurrencyService()
    var isLoading = false
}
```

**Rule of thumb**: if a property doesn't change after `init` or its change shouldn't trigger UI — use `@ObservationIgnored`.

**Important**: `weak var` dependencies also need `@ObservationIgnored`, not just `let`. SwiftUI tracks accesses at instance level.

### ViewModel Storage in Views

| Situation | Correct Pattern |
|-----------|----------------|
| VM created inside View | `@State var vm = SomeViewModel()` |
| VM passed from outside (read-only) | `let vm: SomeViewModel` |
| VM passed from outside (need `$binding`) | `@Bindable var vm: SomeViewModel` |
| VM from environment | `@Environment(SomeViewModel.self) var vm` |

Never use `@StateObject`, `@ObservedObject`, `@EnvironmentObject` — those are for old `ObservableObject`.

### Current Exceptions (intentionally observable)

- `TransactionStore.baseCurrency` — `var` without `@ObservationIgnored`, because currency change must trigger UI recalc
- `DepositsViewModel.balanceCoordinator` — `var?` without `@ObservationIgnored`, assigned after `init` (late injection)

### Reading `@Observable` Collections

⚠️ Reading `.count` / `.isEmpty` / `dict[key]` on an `@Observable` collection subscribes the body to the whole collection. For hot paths over 19k transactions, maintain a separate Observable scalar mirror (e.g. `TransactionStore.transactionsCount`, which moves on add/delete only) and read that instead. Reading an `@ObservationIgnored` property (e.g. `TransactionStore.mutationVersion`) registers nothing.

### Making `@Observable` Property Reactive

To make a property reactive: remove `@ObservationIgnored`, change to `private(set) var`; in the observing View add `.onChange(of: vm.property) { ... }`.
