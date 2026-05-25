# Tenra — Data Integrity Audit & Refactor Plan

**Date:** 2026-05-25
**Scope:** All entities — transactions, accounts, balances, categories/subcategories/budgets, deposits, loans, recurring, currency/FX, insights, persistence/CSV.
**Trigger:** The future-dated-transaction balance bug (deleting a future expense inflated the balance) turned out to be one instance of a *systemic* anti-pattern. This audit hunts that pattern everywhere.

---

## 1. Executive Summary

The balance bug had four contributing shapes. The same four shapes recur across the whole data layer:

1. **Duplicated "how a transaction moves money" logic.** The per-type signed-amount table is copy-pasted across balance (×5–6), account aggregates (×2), category aggregates, deposit interest, and loan debt. Rules like *exclude future-dated tx* (`txDate <= today`) and *skip events before `depositStartDate`* live in **some** copies, not all. Any divergence = silent corruption.
2. **No "today changed" maturation.** Balance now *excludes* future-dated tx — but recurring transactions intentionally generate future-dated rows, and **nothing recomputes** when their date arrives (no `NSCalendarDayChanged`/launch/foreground recalc). The persisted balance stays wrong until an unrelated recalc fires.
3. **Two parallel aggregation engines.** The live MainActor store indexes (`categoryAggregatesByKey`, `accountAggregatesByAccountId`) and the background `InsightsService` snapshot path use **different** type-eligibility, currency-conversion, and future-date rules. The same metric shows different numbers on different screens.
4. **Multiple writers to cached/persisted values + fragmented reactivity.** `AccountEntity.balance` has ≥2 writers (one zeroes it on account-create-miss). Base-currency change is *inert*. Two separate FX-version signals. `convertedAmount` (account currency) gets summed as if it were base currency on cold-cache paths.

**Verified live, high-impact issues:**
- **Base-currency change does nothing** to aggregates/balances/insights — `transactionStore.updateBaseCurrency` has no callers (confirmed via grep). [C-1]
- **No maturation trigger** — confirmed no day-change observer anywhere. [C-2]
- **Loan debt has 3 divergent sources**; incremental balance skips the loan target leg that full-recalc applies. [C-3, C-4]
- **Account & category aggregates include future tx**, but balance excludes them — same screen contradicts itself. [C-5, C-6]
- **`AccountEntity.from` zeroes `balance`** on the create-miss path (already instrumented with a `🛑` log). [C-7]

---

## 2. Findings by Severity

### Critical

| ID | Domain | Issue | Anchor |
|----|--------|-------|--------|
| C-1 | Currency | Base-currency change is inert: `SettingsViewModel.updateBaseCurrency` only sets `settings.baseCurrency`; `transactionStore.updateBaseCurrency` (rebuild aggregates + `recalculateAll`) has **0 callers**. Aggregates stay in old currency forever. | [SettingsViewModel.swift:113](../Tenra/ViewModels/SettingsViewModel.swift#L113), [TransactionStore.swift:449](../Tenra/ViewModels/TransactionStore.swift#L449) |
| C-2 | Recurring/Balance | No maturation recompute. Future recurring occurrence excluded from balance today; when its date arrives nothing recomputes → balance permanently too high until unrelated recalc. No day-change/foreground/launch recalc exists. | [TenraApp.swift:49](../Tenra/TenraApp.swift#L49), [BalanceCoordinator.swift:59](../Tenra/Services/Balance/BalanceCoordinator.swift#L59) |
| C-3 | Loans | "Remaining debt" has 3 sources: `loanInfo.remainingPrincipal` (principal-split), full-recalc loan balance (full payment amount), incremental loan balance (skips target leg → 0). All drift apart. | [LoanPaymentService.swift:283](../Tenra/Services/Loans/LoanPaymentService.swift#L283), [BalanceCalculationEngine.swift:126](../Tenra/Services/Balance/BalanceCalculationEngine.swift#L126) |
| C-4 | Loans/Balance | Incremental path applies the loan **target leg** only for `.internalTransfer`; full recalc & `calculateInitialBalance` apply it for `.loanPayment`/`.loanEarlyRepayment` → permanent offset that flips on every recalc. | [BalanceCoordinator.swift:242](../Tenra/Services/Balance/BalanceCoordinator.swift#L242) |
| C-5 | Accounts | `accountAggregatesByAccountId` (total income/expense in AccountDetailView) includes future tx; balance excludes them → header balance and totals contradict. | [TransactionStore+AccountAggregates.swift](../Tenra/ViewModels/) |
| C-6 | Categories/Budgets | Two budget "spent" algorithms disagree on **type** (store counts income/deposit/loan flows; Insights counts only `.expense`), **sign**, and **future-date window** (monthly fast-path includes rest-of-month; daily/legacy exclude). | [CategoryBudgetService.swift:51](../Tenra/Services/Categories/CategoryBudgetService.swift#L51) |
| C-7 | Persistence | `AccountEntity.from` create-miss path sets `balance = initialBalance` (0 for calc-from-tx accounts) → zeroes a running balance. Live `🛑` diagnostic already present. | [AccountRepository.swift:263](../Tenra/Services/Repository/AccountRepository.swift#L263), [AccountEntity+CoreDataClass.swift:84](../Tenra/CoreData/Entities/AccountEntity+CoreDataClass.swift#L84) |

### High

| ID | Domain | Issue | Anchor |
|----|--------|-------|--------|
| H-1 | Accounts | Two account-aggregate algorithms (incremental `patchBucket` vs legacy `AccountAggregatesCalculator.compute`) — "byte-for-byte" only by hand; divergence is silent. | TransactionStore+AccountAggregates.swift, Views/Accounts/AccountAggregates.swift |
| H-2 | Deposits | `depositStartDate` cutoff present in full recalc, **missing** in `applyTransaction`/`revertTransaction`/`calculateTransactionDelta`/`calculateInitialBalance` → editing a pre-start tx shifts deposit balance until next recalc. | [BalanceCalculationEngine.swift:91](../Tenra/Services/Balance/BalanceCalculationEngine.swift#L91) |
| H-3 | Categories | `CategoryAggregatesCalculator` (CategoryDetailView) month/year fast-path returns whole bucket incl. future tx → "this month" total > budget "spent" elsewhere; inflated avg/6mo. | Views/Categories/CategoryAggregates.swift |
| H-4 | Categories | Budget period-start differs: store ignores `budgetStartDate`; legacy returns `Date()` (≈0 spent) when nil. | CategoryBudgetService.swift |
| H-5 | Insights | Future-date handling inconsistent *within* Insights: `calculateMonthlySummary` excludes; `computePeriodDataPoints` / `PreAggregatedData.build` include → switching granularity changes totals. | InsightsService.swift |
| H-6 | Insights | Insights vs store use different eligible **types** for category totals (store: expense+income+deposit+loan; Insights: expense/income only). | InsightsService.swift, TransactionStore+CategoryIndex.swift:296 |
| H-7 | Currency | Cold-FX-cache fallback sums `convertedAmount ?? amount` (account currency) as base currency; store self-heals on FX-version bump, **Insights does not**. | InsightsService.swift:1031 |
| H-8 | Persistence | `parseType` substring matching: `"in"` ⊂ `"internal"`, etc. (nondeterministic dict order) → CSV import can misclassify transfer/deposit/loan rows → sign/balance corruption. | CSVValidationService.swift:298 |
| H-9 | Persistence | Two writers of `AccountEntity.balance` with no single authority; fire-and-forget `updateAccountBalancesSync` swallows errors. | AccountRepository.swift:185, BalanceCoordinator.swift:460 |
| H-10 | Persistence | CSV import partial-write: aggregates persisted from in-memory tx even if `finishImport()` failed to write tx → warm-start aggregates overcount. | CSVImportCoordinator.swift:279 |

### Medium

| ID | Domain | Issue |
|----|--------|-------|
| M-1 | Deposits | `DepositInterestService.principalDelta` is a separate definition of "how a tx moves the deposit" (uses `convertedAmount`; counts `.income/.expense`) vs balance engine (uses `targetAmount`; deposit-types only) → interest accrues on a principal the balance doesn't show. |
| M-2 | Deposits | Interest accrues only on view `.task` reconcile, not on day-change/launch → capitalization can post late. |
| M-3 | Deposits | Future-dated loan/deposit rows mutate `loanInfo`/principal synchronously while the balance leg waits for the date → debt representations diverge by the future amount. |
| M-4 | Loans | `recalculateAfterLinking` assumes every payment == `monthlyPayment`; `createManualPayment` uses actual amounts → different `remainingPrincipal` after re-link. |
| M-5 | Recurring | `pauseSubscription` deletes future tx but not occurrences → orphan occurrence; resume jumps a period / gaps. |
| M-6 | Recurring | Three divergent "should I generate?" guards (occurrence key vs tx-id vs "any future tx") can disagree → series silently stops or duplicates. |
| M-7 | Currency | Cold-cache `convertedAmount`-as-base misuse in both Insights resolvers (latent; unbounded if recompute doesn't fire). |
| M-8 | Currency | Cash-flow projection mixes future-excluded balance with future-included flow averages → over/under-stated runway. |
| M-9 | Currency | Two FX-version signals (`CurrencyRatesNotifier.version` auto-bumps; `TransactionStore.currencyRatesVersion` only on post-prewarm call) → late rate landings don't reconcile aggregates. |
| M-10 | Persistence | `DataRepositoryProtocol` facade omits the `*Sync`/balance/aggregate API; `BalanceCoordinator.persistBalance` downcasts to `CoreDataRepository` or silently no-ops. |
| M-11 | Persistence | `UserDefaultsRepository` balance updates are no-ops & balance never persisted on its path (fallback/preview only). |
| M-12 | Persistence | `MockAccountRepository` records balance on save; real `AccountRepository` deliberately does NOT write balance on update → tests give false confidence on the exact clobber class. |
| M-13 | Persistence | `account.order` lives in `AccountOrderManager` (UserDefaults), not CoreData → ordering split across two stores, can drift. |
| M-14 | Persistence | `saveAccountAggregates` is fire-and-forget `Task.detached`; not ordered vs `saveTransactionsSync` → kill between leaves aggregates lagging raw tx. |
| M-15 | CSV | `convertedAmount` exported into the dual-purpose `targetAmount` column with no currency tag → hand-edited/foreign CSV can skew base aggregation. |

### Low

| ID | Domain | Issue |
|----|--------|-------|
| L-1 | Categories | `lastTransactionDate` stale after deletes in incremental path (display/sort only; self-heals). |
| L-2 | Recurring | `batchInsertTransactions` sets `recurringSeriesId` string but not the CoreData inverse relationship (single-add does) — parity gap; masked because readers use the string. |
| L-3 | Currency | `LinkPaymentsView` uses raw `Formatting.formatCurrency` for display (always `.00`); should be `formatCurrencySmart`. |
| L-4 | CSV | `docs/domains/csv.md` lists 6 types; exporter writes 8 (loan types). Doc drift. |
| L-5 | Persistence | `loadAllAccountBalances` fetch has no noted index on `id` (fine at ~50 accounts). |

**Confirmed NON-issues (good):** `apply()` pipeline updates all indexes for every event type; batch delete uses `context.delete()` (red flag #3 respected); `allTransactions` no-op setter has no assigning callers; `convertSync` formula consistent; v9 schema additive-only.

> Note: the prior balance fix already makes **CSV import balances correct** for future-dated rows (full recalc excluded them; incremental now matches). The residual CSV/future problem is aggregates (C-5/C-6), not balance.

---

## 3. Root Cause Analysis — Four Themes

**Theme A — One rule, many copies.** The per-transaction signed-contribution table (income +, expense −, transfer source −/target +, deposit/loan legs) exists independently in: `calculateBalanceFromInitial`, `applyTransaction`, `revertTransaction`, `calculateTransactionDelta`, `calculateInitialBalance` (balance ×5), `applyAccountAggregateDelta` + `AccountAggregatesCalculator.compute` (aggregates ×2), `applyAggregateDelta` (category), `DepositInterestService.principalDelta` (deposit), and loan debt math (loans). Eligibility rules (`txDate <= today`, `depositStartDate` cutoff, account match) are applied unevenly. **This is the direct generator of C-3/C-4/C-5/C-6/H-2/M-1.**

**Theme B — No temporal recompute.** "Future" is relative to *now*; the data layer treats it as static. Recurring generates future rows; balance excludes future; nothing bridges the gap when the day advances. **Generates C-2; amplifies every future-date inconsistency.**

**Theme C — Two aggregation worlds.** MainActor store indexes vs background Insights snapshot. They re-implement the same metrics with different rules because Insights *cannot* read MainActor indexes. **Generates C-6/H-5/H-6/H-7/M-7.**

**Theme D — Cache writers & reactivity sprawl.** `AccountEntity.balance` written by recalc, by `persistBalance`, and (wrongly) by `AccountEntity.from`. Base-currency and FX reactivity wired through multiple uncoordinated signals. **Generates C-1/C-7/H-9/M-9/M-10.**

---

## 4. Target Architecture

### 4.1 One transaction-contribution function (kills Theme A)
A single pure definition every consumer derives from:

```swift
struct LedgerContribution { var balanceDelta: Double; var incomeDelta: Double; var expenseDelta: Double; var count: Int }

enum LedgerPolicy { case currentBalance(asOf: Date)   // applies txDate<=today + depositStartDate
                    case allTime }                     // history/raw

// THE single source of truth for "how this tx affects this account".
func contribution(of tx: Transaction, to accountId: String, accountCurrency: String,
                  account: AccountBalance, policy: LedgerPolicy) -> LedgerContribution
```

- Full recalc = `initial + Σ contribution(...).balanceDelta`.
- Incremental add = `+contribution`, remove = `−contribution`, update = `−old +new`.
- Account aggregates = `incomeDelta/expenseDelta/count` from the same call.
- Category aggregates and budget "spent" derive from the same eligibility + a shared `BudgetSpendRule` (expense contributions only, `txDate <= today`, base currency).
- Deposit principal & loan debt derive from the same contribution (one signed table).

By construction, incremental and full recalc *cannot* disagree, and the future/depositStartDate gates exist exactly once.

### 4.2 Maturation trigger (kills Theme B)
`recalculateIfDayChanged()`:
- Persist `lastLedgerRecalcDate`.
- On launch (post-`loadData`) and `scenePhase == .active`, if `today > lastLedgerRecalcDate`, recompute balances + aggregates for accounts/categories touched by any tx whose `parsedDate ∈ (lastLedgerRecalcDate, today]`.
- Also runs deposit interest reconcile (fixes M-2).
- Uses the same `contribution` + `affects` predicate — no new rule copy.

### 4.3 One aggregation source (kills Theme C)
Make `InsightsService` consume a **serializable snapshot** produced by the same code that builds the store indexes (build a `LedgerSnapshot` on MainActor, hand it to the background service), OR have both derive from `contribution(...)`. Either way: identical type-eligibility, currency conversion (`convertSync` only, never `convertedAmount`-as-base), and future-date policy. Insights reconciles on the single FX-version.

### 4.4 Currency + balance-persistence authority (kills Theme D)
- **Base currency:** one source of truth — make `transactionStore.baseCurrency` a computed proxy over `appSettings.baseCurrency`, and route `SettingsViewModel.updateBaseCurrency` → `transactionStore.updateBaseCurrency` (rebuild + recalc + insights invalidate). (Fixes C-1.)
- **FX version:** `CurrencyRateStore.updateCurrentRates` drives one version that gates *all* reconciles. (Fixes M-9.)
- **Balance writer:** `BalanceCoordinator` is the **only** writer of `AccountEntity.balance`; `AccountEntity.from` never writes `balance` on create for calc-from-tx accounts (preserve incoming). (Fixes C-7/H-9.)

---

## Implementation Progress

- **2026-05-25 — Phase 1 (balance keystone) DONE.** Unified `BalanceCalculationEngine.contribution(of:to:policy:)` is the single per-transaction money rule; full recalc + incremental add/remove/update all derive from it. Fixed C-4 (loan target leg now applied incrementally) and H-2 (deposit startDate cutoff incremental) by construction. Invariant test (`BalanceLedgerInvariantTests`) pins incremental == recalc.
- **2026-05-25 — Phase 1 (account aggregates) DONE.** `accountAggregatesByAccountId` now excludes future tx via the shared `LedgerPolicyRule.isRealized` (C-5); dead legacy `AccountAggregatesCalculator.compute(...transactions:)` removed (H-1).
- **2026-05-25 — Phase 0 (maturation + repair) DONE.** `TransactionStore.recalculateLedgerIfDayChanged()` recomputes realized balances+aggregates on day rollover and once on first launch after update (repairs pre-existing drift, incl. balances corrupted by the shipped bugs). Wired into `AppCoordinator.initialize()` (post-prewarm) and the `applicationDidBecomeActive` handler (C-2). 305 unit tests green.
- **2026-05-25 — Phase 4 (base-currency reactivity) C-1 DONE.** `transactionStore.baseCurrency` was hardcoded "KZT" with no caller of `updateBaseCurrency` → non-KZT users had aggregates/insights computed in the wrong currency. Now synced from settings at startup (`AppCoordinator.initializeFastPath`/`initialize`) and propagated on change (`SettingsViewModel.updateBaseCurrency` → `transactionStore.updateBaseCurrency` + insights recompute); the day-change repair rebuilds any stale persisted aggregate snapshot in the correct currency. 308 unit tests green. (M-9 single FX-version still open.)
- **2026-05-25 — Phase 6 (partial) C-7 + H-8 DONE.** C-7: `AccountEntity.from` now preserves `account.balance` instead of resetting to `initialBalance` (was zeroing the running balance for calc-from-tx accounts on a create-miss); obsolete balance-zero diagnostics removed. H-8: CSV `parseType` replaced the nondeterministic bidirectional substring match (where "in" matched "internal transfer" → income) with exact-match + length-guarded longest-first containment. 313 unit tests green.
- **2026-05-25 — Phase 3 (loan) C-3 DONE.** DECISION: loan account balance = `loanInfo.remainingPrincipal` (single source). `contribution` loan target leg now returns 0 (a payment reduces the source bank by the full amount but the loan debt only by principal — interest is a bank expense); `BalanceCoordinator.registerAccounts` and both recalc paths derive the loan balance from `remainingPrincipal`; loan payment / early-repayment / rate-change flows call `updateLoan` so the balance re-syncs immediately. The day-change repair recomputes existing loans from `remainingPrincipal`. 316 unit tests green.
- **2026-05-25 — Phase 3 deposit M-2 DONE.** Deposit interest is now reconciled at launch (`AppCoordinator.reconcileDepositsOnLaunch`), not only when a deposit screen appears — so interest posts promptly even if the user never opens the deposit view on the posting day. Idempotent; runs before the day-change recalc so newly-posted interest is folded into balances. M-1 (unify `DepositInterestService.principalDelta` with `contribution`) DEFERRED: it touches interest-accrual math and is high-risk; needs its own focused pass.
- **2026-05-25 — Phase 5 (partial) C-6 core + H-3 + H-4 DONE.** Category aggregate buckets (`categoryAggregatesByKey`) now exclude future-dated tx via the shared `LedgerPolicyRule.isRealized` — so budget "spent" and category totals no longer over-count not-yet-charged recurring tx (the everyday store-vs-Insights divergence), and the day-change repair folds them in on maturity. Removed the `budgetStartDate == nil → now` short-circuit in `legacyBudgetPeriodStart` so the store and Insights budget periods agree. 317 unit tests green.
- **Residual in C-6 (rare):** the store budget bucket still sums ALL aggregatable types tagged to a category while the Insights legacy path is expense-only — only diverges if a non-expense tx (loan payment / deposit op / income) is tagged to a *budgeted expense category*. Needs an expense-only budget read to fully close.
- **2026-05-25 — Phase 5 H-5 DONE.** `InsightsService` realized aggregation now excludes future-dated tx consistently: `PreAggregatedData.build` (monthly/category totals) and `computePeriodDataPoints` (.week scan) gate on `LedgerPolicyRule.isRealized`, matching `calculateMonthlySummary`. Switching granularity no longer changes realized totals; projections still add future explicitly (CashFlow `recurringNet`), which also reduces the M-8 double-count. Structural fields (txDateMap, account counts, first/last date) still include all tx. 318 unit tests green.
- **2026-05-25 — M-9 DONE (and H-7 largely mitigated).** `AppCoordinator.startObservingCurrencyRateChanges()` observes `CurrencyRatesNotifier.version` (which auto-bumps on every fetch/restore) and drives `transactionStore.bumpCurrencyRatesVersion()` + `insightsViewModel.invalidateAndRecompute()`. So a late prewarm landing, a manual refresh, or a second-provider response now reconciles FX-stale aggregates AND recomputes Insights — previously only the single post-prewarm bump did this. This also self-heals H-7: the cold-FX `convertedAmount`-as-base fallback in `resolveAmount*` is recomputed with proper rates on the next bump (the residual is only the brief pre-recompute window). 318 unit tests green.
- **2026-05-25 — M-4 DONE.** `recalculateAfterLinking` now reduces the loan principal by the ACTUAL linked payment amounts (split via `paymentBreakdown`), not by the annuity `monthlyPayment × count` — important now that the loan balance derives from `remainingPrincipal` (C-3). The caller converts each linked tx to the loan currency. 321 unit tests green.
- **Next (lower impact / interrelated):** H-6 + C-6 residual (store category bucket sums all aggregatable types vs Insights expense-only — only diverges when a loan/deposit/income tx is tagged to a *budgeted expense category*; needs an expense-scoped category total), H-7 residual (change the cold-FX fallback to not blend units), M-1 (deposit principalDelta unify — high-risk, deferred), H-10 (import partial-write atomicity).
- **⚠️ Pre-existing flaky test (unrelated):** `SubscriptionTransactionMatcherTests.findCandidates_matchesCrossCurrencyViaConvertedAmount` intermittently fails in the full run from shared `CurrencyRateStore.shared` state; passes in isolation. Needs `clearAll()` in the suite `init()` (per CLAUDE.md currency-test rule).
- **⚠️ Note:** base-currency change end-to-end is verified by build + the `updateBaseCurrency` primitive test; the full UI flow (Settings → currency picker → all screens reflect new currency) needs manual in-app verification.

## 5. Phased Implementation Plan

Each phase is independently shippable, test-gated, and ordered by leverage/risk.

### Phase 0 — Safety nets & stop-gap (small, ship first)
- Characterization tests capturing **current** balances/aggregates for a representative dataset (golden master) so refactors are provably behavior-preserving where intended.
- Stop-gap maturation: call `recalculateAll` on launch + foreground (coarse, correctness over perf) — immediately stops C-2 bleeding before Phase 2 refines it.
- One-time repair pass: recompute all balances+aggregates once on next launch (heals data already corrupted by the shipped bugs).
- **Tests:** golden-master snapshot; launch-recalc fires once per day.

### Phase 1 — Unify the contribution function (Theme A) ⟵ highest leverage
- Introduce `contribution(of:to:...)` + `LedgerPolicy` + `affects(...)` (folds `txDate<=today` and `depositStartDate`).
- Rewrite the 5 balance methods, both account-aggregate algorithms, and category aggregate apply to call it. Delete the legacy `AccountAggregatesCalculator.compute` duplicate (H-1).
- Fix C-4 (loan target leg) and H-2 (deposit cutoff) automatically by construction.
- **Tests:** property test — for any tx list, `Σ incremental == full recalc == aggregates` for balance/income/expense; existing engine tests stay green; add loan-target-leg and deposit-startDate regressions.

### Phase 2 — Maturation trigger (Theme B)
- Replace Phase-0 coarse recalc with targeted `recalculateIfDayChanged()` (only matured-tx accounts/categories) + deposit reconcile.
- **Tests:** future tx dated tomorrow → excluded today, included after simulated day advance; idempotent within a day.

### Phase 3 — Loan & deposit debt single-source (Theme A cont.)
- Make `remainingPrincipal` the single loan-debt source; derive loan account balance from it (or vice versa) — resolve C-3. Unify `recalculateAfterLinking` with actual amounts (M-4). Gate future loan/deposit `loanInfo` mutations (M-3).
- Unify `DepositInterestService.principalDelta` with `contribution` (M-1).
- **Tests:** annuity loan payment updates debt consistently across incremental/recalc/UI; re-link preserves actual amounts.

### Phase 4 — Currency reactivity (Theme D, part 1)
- Base-currency proxy + wire `updateBaseCurrency` end-to-end (C-1). Single FX-version (M-9). Remove `convertedAmount`-as-base fallbacks (M-7); on `convertSync` miss, mark stale + force recompute, never blend units.
- **Tests:** changing base currency rebuilds aggregates & balances & insights; multi-currency total uses `convertSync`; cold-cache then rate-landing reconciles.

### Phase 5 — Insights ↔ store unification (Theme C)
- `LedgerSnapshot` shared between store and Insights; identical type/currency/future rules (C-6/H-3/H-4/H-5/H-6/H-7). Fix cash-flow projection boundary (M-8).
- **Tests:** same metric equal on Home vs Insights across granularities & currencies.

### Phase 6 — Persistence integrity (Theme D, part 2)
- Single balance-writer authority; fix `AccountEntity.from` create-miss zeroing (C-7/H-9). Order persistence (M-13/M-14). CSV `parseType` exact-map (H-8). Import partial-write atomicity (H-10). Align `MockAccountRepository` + `UserDefaultsRepository` to real contract (M-11/M-12). Facade API completeness (M-10).
- **Tests:** account save never zeroes balance; CSV round-trip preserves all types; import failure doesn't persist aggregates.

### Phase 7 — Cleanup & docs
- Remove dead `transactionStore.updateBaseCurrency` duplication, stale CSV doc (L-4), formatter misuse (L-3). Update `docs/` domain files + `CLAUDE.md` red flags to point at the single contribution function.

---

## 6. Decisions (product)

1. **Future-dated transactions — DECIDED 2026-05-25: realized excludes, projections include.**
   - **Realized / actuals** — account balance, account income/expense aggregates, category "spent", budget progress — **exclude** future-dated tx (`txDate <= today`). This is the single eligibility rule (`LedgerPolicy.currentBalance(asOf:)`).
   - **Projections / forecasts** — cash-flow projection, runway, forecasting/savings insights — **include** future tx (and generated recurring) as *projected* values, behind an **explicit realized↔projected boundary** (the projection must not double-count a future tx already folded into a baseline — fixes M-8).
   - Implication: Insights splits into a *realized* layer (reuses the excluded-future actuals) and a *projected* layer (adds future flows explicitly).
2. **Loan account balance** — derive from `remainingPrincipal` (single source); do not independently sum loan payment legs into the balance. *(Pending final confirmation; default assumed.)*
3. **Budget "spent"** — expense contributions only, `txDate <= today`, base currency, calendar-or-`budgetStartDate` window. *(Pending final confirmation; default assumed.)*

---

## 7. Suggested Sequencing

`Phase 0 → 1 → 2` delivers the bulk of the correctness wins (kills Themes A & B, repairs existing data). `3–6` close the remaining divergences. Phases are independently mergeable; each lands behind its own tests with the Phase-0 golden master guarding against unintended behavior change.
