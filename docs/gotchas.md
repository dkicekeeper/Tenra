# Gotchas

Known traps, performance hot-paths, and surprising behaviors. Domain-specific gotchas live in `docs/domains/<domain>.md`.

## SwiftUI Layout

General SwiftUI, Liquid Glass, `Menu`, animation and code-hygiene traps live in DesignKit's [docs/gotchas.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/gotchas.md); their precedents (the carousel item transition, `SnapCardPicker`'s first scroll alignment, `EditSheetContainer`, `MenuPickerRow`) are DesignKit components. Tenra-specific items:

- ⚠️ **Never attach `.sheet` / `.alert` / `.paywallSheet` (any presentation) to a `Section`, a `Group` with several children, or a custom view whose body is several `List` rows.** Such a modifier is copied onto every row, so one binding gets several presenters: the sheet opens and is dropped at once. Attach it to one row, or to the `List`/screen root. A `Group { if … else … }` with one view per branch is fine.
- **iOS 26 TabView lazy-renders non-active tab content**: `AnalyticsTab.body` doesn't run on launch while `.home` is selected, so non-active tab init is not on the launch critical path.
- **History search: system bottom bar, nothing interactive at the top (`.searchable` drawer).** A nav-bar `.searchable` drawer breaks interactive bars below the nav bar on iOS 26/27: its reveal gesture claims taps over a `.safeAreaInset(.top)` bar, on iOS 27 content in the safe-area-inset band loses every tap, and any nav-bar `.searchable` forces an opaque scroll-edge plate; `.navigationBarDrawer(displayMode: .always)` fixes the taps but forces the plate and an always-visible field. So [HistoryView](../Tenra/Views/History/HistoryView.swift) keeps only the system nav bar at the top; filters and search live in the system bottom toolbar (`ToolbarItemGroup(placement: .bottomBar)` + `ToolbarSpacer(.flexible, placement: .bottomBar)` + `DefaultToolbarItem(kind: .search, placement: .bottomBar)` + `.searchable`), with the tab bar hidden (`.toolbar(.hidden, for: .tabBar)`). Bottom-bar search facts (device-verified): without `.searchToolbarBehavior(.minimize)` it renders as a compact inline `SearchField`; with `.minimize` (History's choice) it is a prominent loupe-icon Button labeled `Search` that expands into the system SearchField (field and dismiss control render as one merged glass capsule: system-rendered, accepted). `.controlSize(.large)` scales the bottom-bar capsules up to main-tab-bar height. The expanded search's dismiss control is a Button labeled `close` (lowercase), and collapsing keeps a search element in the hierarchy (assert close/keyboard nonexistence, not field nonexistence). Custom search UI is banned (user rule). Verify changes ON DEVICE with `TenraUITests/HistoryFilterUITests`: Simulator runs pass where the device fails.

## Performance Hot-Paths

### List rendering

- ⚠️ **SwiftUI `List` + 500+ sections = hard freeze** — SwiftUI renders all `Section` headers eagerly. Always slice: `Array(sections.prefix(visibleSectionLimit))` with `@State var visibleSectionLimit = 100`. Add `ProgressView().onAppear { visibleSectionLimit += 100 }` as the last List row for infinite scroll. Precedent: `HistoryTransactionsList`.
- **Pre-resolve per-row data at ForEach call site**: Passing `[Account]` or `[CustomCategory]` arrays to a row view means any element change forces ALL rows to re-render. Pre-resolve per-row `let` bindings inside `ForEach` and pass `Equatable` scalars.
- **`@State` cache for 2k+ row lists**: Computed props for filter/group-by/lookup re-run per view-body eval and dominate tap latency. Move `filteredX`, `dateSections`, `accountById`, `allSatisfy`-flags into `@State`, rebuild in a single `rebuildDerivedCaches()` pass on input changes. See [`LinkPaymentsView`](../Tenra/Views/Components/LinkPayments/LinkPaymentsView.swift) (behind `SubscriptionLinkPaymentsView`).

### View triggers

- **`.onAppear` for synchronous cache warm-up**: Use `.onAppear { rebuildCache() }` (runs synchronously before next frame), NOT `.task { await rebuildCache() }` (async — fires after List body renders).
- ⚠️ **`onAppear` fires on every back-navigation** — use `.task(id: trigger)` instead: combine reactive inputs in `Equatable` struct (`SummaryTrigger` pattern); SwiftUI manages cancellation automatically. Use debounce inside `if !isFullyInitialized` so init-complete triggers are immediate.
- ⚠️ **`TimeFilter` freezes its date bounds at `init`** — relative presets (`.thisMonth`, `.today`) keep the month/day they were created in and go stale on rollover (incl. after a cold launch decoding saved bounds). Refresh via `TimeFilterManager.refreshRelativePresetIfNeeded()` on `scenePhase == .active` (`TenraApp`). Any `.task(id:)` keyed on `currentFilter.displayName` will NOT re-fire across a month boundary (name is unchanged) — key on the actual `dateRange()` start/end instead, as `TransactionCategoryPickerCoordinator.RefreshKey` does (bounds, preset, transactions, categories, rates, base currency, the day).
- ⚠️ **`TimeFilter` ranges are half-open `[start, end)`** — `end` is the first instant of the next period (`.lastMonth` on 5 Oct = [1 Sep, 1 Oct)). Compare with `date < end`, never `<=`: stored dates are local midnight, so `<=` pulls in every tx dated the 1st of the next period. Custom ranges are picked as inclusive days; build them with `TimeFilter.customDays(from:through:)` and display the end with `lastIncludedDay`. Pinned by `HistoryDateRangeTests`.

### Date parsing

- ⚠️ **`DateFormatter.date(from:)` costs ~13.4 µs per call — never call it in a loop over transactions.** Measured on 19k: `DateFormatter.date(from:)` 254 ms vs [`FastDateParser.date(from:)`](../Tenra/Utils/FastDateParser.swift) 4.8 ms (~53×). Formatting is far cheaper than parsing (`string(from:)` is only 18.6 ms/19k), so the expensive direction is String → Date. Use `FastDateParser` for the canonical `"yyyy-MM-dd"` storage format; keep `DateFormatters` for anything user-facing (localized month names depend on device locale by design).
- **`FastDateParser` is pinned to `DateFormatter` by `FastDateParserTests`** — every day 2015–2035 plus the whole month/day space. If you change its calendar/timeZone config, re-run that suite.
- **`DateFormatter` is not uniformly strict, and matching it matters**: it returns nil for a field outside its own range (`"2026-13-01"`, `"2026-07-32"`) but *rolls over* an in-range day that overflows the month (`"2026-02-30"` → 2026-03-02, `"2025-02-29"` → 2025-03-01). `Calendar.date(from:)` rolls over everything, so a naive swap silently accepts month 13. `FastDateParser` range-guards then delegates, reproducing DateFormatter exactly.
- ⚠️ **A `DateFormatter` parsing a stored key MUST set `locale = en_US_POSIX`.** Without it the formatter inherits the device region's calendar, so `"2026-07-28"` parses to a different date — or nil — on a device set to Thailand (Buddhist) or Saudi Arabia (Umm al-Qura). The app ships in 11 languages and region ≠ language.
- ⚠️ **A transaction's day is `TransactionEntity.dateSectionKey`, not `date` formatted now.** `date` stores the chosen day's local midnight as an instant; formatting it in the current time zone shifts the transaction a day after the user changes time zone, and a re-save would make that permanent. `toTransaction()` reads the key (written in the zone of the write that set `date`), and `willSave()` re-keys only on insert or a changed `date`. Fetch predicates on `date` (time filters, spending queries) still compare instants, so a day-boundary row can fall into the neighbouring period after a time-zone change.
- **Key a parsed-date cache by the date STRING, not `tx.id`** — 19k transactions span only ~1.8k unique dates, so an id-keyed cache does 10× the parses and holds 10× the entries. Precedents: `TransactionStore.parsedDateByDateString`, `InsightsService.PreAggregatedData.txDateMap`.

### Grouping indexes store ids, not values

`transactionsByAccount` / `transactionsByCategoryName` / `transactionsBySeriesId` are computed [`TransactionIndex`](../Tenra/Models/TransactionIndex.swift) views, not stored dictionaries. Storage holds ids only; values resolve through `transactionById` on subscript, so the indexes don't hold extra copies of the transaction set.

| Read as | Backed by |
|---|---|
| `transactionsByAccount` | `transactionIdsByAccount: [String: [String]]` (both legs — transfers appear under `accountId` and `targetAccountId`) |
| `transactionsByCategoryName` | `transactionIdsByCategoryName: [String: [String]]` (aggregatable types only) |
| `transactionsBySeriesId` | `transactionIdsBySeriesId: [String: [String]]` |

- Read sites look like a dictionary (`index[key] ?? []` yields `[Transaction]`), but **bind the bucket to a `let` before using it more than once** — each subscript re-resolves, O(bucket).
- **Never re-write a bucket to make an edit visible.** `updateState` refreshes `transactionById` before the index-maintenance helpers run, so edits show through automatically. Pinned by `TransactionIndexTests.editIsVisibleWithoutBucketRewrite`.
- ⚠️ **Any cold rebuild driven off the `transactions` array must call `ensureTransactionByIdInSync()` first** — otherwise buckets resolve to nothing. `rebuildCategoryIndexes`, `rebuildSeriesAndDateIndexes` and `seedCategoryAggregates` already do; it is O(1) when in sync. It is also what makes indexes built after assigning `store.transactions` directly (tests, fixtures) resolve.

### Currency conversion in bulk loops

- **Use [`RateSnapshot`](../Tenra/Services/Currency/RateSnapshot.swift), not `CurrencyConverter.convertSync`, inside any walk over the transaction set.** `convertSync` takes two `NSLock` acquisitions per call (38k per 19k-pass), and — more importantly — reads live state: a prewarm response landing mid-loop converts the first half of the set at old rates and the second half at new ones, producing a total that corresponds to no point in time. `aggregatesAreFXStale` catches a cold cache, not this. Single conversions should keep using `convertSync`.
- `CategoryBudgetCurrency.toBase(amount:from:base:rates:)` is the snapshot-taking overload; it preserves the `usedStaleFallback` contract exactly.

### Bulk store mutations

- ⚠️ **Never loop per-row `update`/`apply(.updated)`/`apply(.deleted)` over many transactions** — use `updateBatch(_:)` / `deleteTransactionsInBulk(_:)` (one event, one save, one balance recalc). See [domains/transactions.md](domains/transactions.md) §Bulk edits and deletes.
- ⚠️ **Never rebuild aggregates per transaction on the main actor** — `rebuildRealizedAggregates()` runs the cold-load builders off main. See [domains/categories.md](domains/categories.md) §Full rebuilds run off the main actor.
- **Link subcategories to many transactions with `batchLinkSubcategoriesToTransaction`**: each link-table write rebuilds the usage stats over all transactions.

### Background work

- **Heavy nonisolated scans off MainActor**: `Task.detached(priority: .userInitiated) { let result = Matcher.scan(...); await MainActor.run { self.baseline = result; self.applyFilters() } }` for O(N_transactions) filters on view open. SwiftUI `View` structs are auto-Sendable — capture is safe.
- **A search that re-derives something per transaction on every keystroke: derive it once per transaction set.** For History's numeric search, [`TransactionAmountSearch`](../Tenra/Services/Transactions/TransactionAmountSearch.swift) formats each distinct amount once, off the main actor while the query is typed (the 300 ms debounce covers the build), keyed by `mutationVersion` + count, and answers with a binary search. The FRC refetch that follows any search keystroke still runs on the main actor (three `CONTAINS[cd]` clauses plus the `id IN` set).
- **Don't fetch in a ViewModel's `init` what the store loads.** A `performAndWait` fetch in a ViewModel `init` runs inside `AppCoordinator.init`, before the first frame. `CategoriesViewModel` takes subcategories and both link tables only from the store (`syncCategoriesFromStore` after `loadData`).

### Build & profiling

- **`CompileAssetCatalogVariant` failure can be transient** — if `grep -E "error:"` returns nothing, just retry.
- **Don't profile under attached Xcode debugger** — `os.Logger.debug` flooding alone can inflate a <1 s launch to 4–6 s. Use Instruments Time Profiler or detach debugger before measuring.
- **`PerformanceProfiler.start/end` uses `CACurrentMediaTime()` synchronously** — measurements reflect actual elapsed time at the call site.

## `#Preview` crashes

- **A `#Preview` missing an `@Environment(T.self)` object CRASHES the preview process, it doesn't warn.** Non-optional `@Environment(SomeObservable.self)` is resolved during dynamic-property update, *before* and regardless of whether `body` reads it — a missing object traps in `EnvironmentValues.subscript.getter` → `_assertionFailure` (`EXC_BREAKPOINT`, "Thread 0 Crashed: … EnvironmentBox.update(property:phase:)"). The build stays green, so these only surface when someone opens the file in Xcode. When adding an `@Environment(T.self)` to a view, update every `#Preview` in that file. `PremiumManager.shared` is preview-safe (`private init() {}`; RevenueCat only wakes in `configure()`).

## Common Cross-Domain Pitfalls

- **PreAggregatedData "piggyback" pattern**: Add fields to `PreAggregatedData.build()` O(N) loop — never add separate O(N) loops when one already exists. See [domains/insights.md](domains/insights.md).
- **`filterService.filterByTimeRange` parses with `FastDateParser`**; inside Insights use the `txDateMap` overload (`filterByTimeRange(_:start:end:txDateMap:)`), which reuses the ~1.8k dates `PreAggregatedData.build` already parsed. See [domains/insights.md](domains/insights.md).
- **Subcategory CoreData relationship**: `Transaction.subcategory: String?` is legacy; real subcats live via `categoriesViewModel.linkSubcategoriesToTransaction(transactionId:subcategoryIds:)`. Generated recurring txs need explicit linking after creation. See [domains/recurring.md](domains/recurring.md).
- **Reconciliation callback pattern (deposits only)**: Never spawn `Task {}` inside synchronous `onTransactionCreated` callbacks — collect into array, batch-persist after reconciliation completes. Loans don't auto-reconcile (user-driven only). See [domains/deposits.md](domains/deposits.md).
- ⚠️ **Don't sum `convertedAmount ?? amount` for base-currency totals**: it is in *account* currency (CLAUDE.md ⚠️ #6, [domains/currency.md](domains/currency.md)).
- ⚠️ **Loan / deposit accounts are technical — never pass `accountsViewModel.accounts` to a user-facing picker**: it includes loan and deposit accounts which represent obligation/savings containers, not spendable funds. Use `accountsViewModel.regularAccounts` for income/expense/transfer flows, `accountsForTransactionEdit(tx:)` for editing system tx. See [domains/loans.md](domains/loans.md#loan-account-is-technical--never-in-user-pickers).
- ⚠️ **Loan-payment orientation: `accountId = SOURCE bank, targetAccountId = LOAN`** (mirrors `.expense`). Filters that find "all payments for a loan" must check `targetAccountId == loanId`, not `accountId`. See [domains/loans.md](domains/loans.md#transaction-orientation-contract).
- ⚠️ **Never add or update accounts or categories in a loop through the per-item CRUD (`addCategory`, `addAccount`, `updateAccount`)**: each call persists with its own detached, wholesale save (the whole table, deleting rows not in the snapshot). `CoreDataSaveCoordinator` queues them and writes the newest, but a burst still costs one table write per item. Add in memory with persistence suppressed and save once, as [TransactionStore+Onboarding](../Tenra/ViewModels/TransactionStore+Onboarding.swift) does, or use the batch entry points (`updateAccounts`, `deleteAccounts`, `deleteCategories`, `reorderCategories`). The full load keeps changes made while it runs (see [architecture.md §The load window](architecture.md#the-load-window)), so onboarding's synchronous save is about durability before `initialize()`, not about the load overwriting memory.
- ⚠️ **`Transaction.category` for system types is a technical key, not a user-facing string**. `"Loan Payment"` / `"Transfer"` are stored as locale-independent constants — render via `CategoryDisplay.displayName(for:type:)` (NOT `Text(tx.category)` directly).

## Localization

Rules for strings, locales and plurals: [localization.md](localization.md).

## iOS Simulator — System Warnings to Ignore

The following appear routinely in Xcode console on Simulator runs and are NOT bugs in our code. Don't try to fix them — none have application-side resolution:

- `Unable to simultaneously satisfy constraints ... TUIKeyplane.right.width == -1.5` — Apple's keyboard layout calculation in Simulator only. Doesn't appear on physical device.
- `Reading from public effective user settings` — informational from system Settings access.
- `Reporter disconnected { function=sendMessage, ... }` — telemetry/Instruments transport.
- `containerToPush is nil, will not push anything to candidate receiver` — SiriIntent candidate-receiver framework, no user-facing impact.

If a real symptom appears (UI freeze, missing label, broken constraint affecting layout), look at the stack trace — if it doesn't pass through `Tenra.` symbols, it's still not us.
