# Entity Detail Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `AccountDetailView` + `CategoryDetailView` and unify all five entity-detail screens (Subscription/Account/Category/Deposit/Loan) under a single `EntityDetailScaffold`, with one shared `GroupedTransactionList` replacing three parallel implementations.

**Architecture:** Three new shared components (`EntityDetailScaffold`, `HeroSection`, `GroupedTransactionList`) under `Views/Components/EntityDetail/` and `Views/Components/History/`. Each existing detail view is refactored in a single, reversible commit that preserves behavior. Navigation rewires from edit-on-tap to detail-on-tap; edit moves to the detail screen's toolbar menu.

**Tech Stack:** Swift 6 patterns (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), SwiftUI iOS 26+, Observation framework, CoreData through `TransactionStore`. No new dependencies.

**Reference:** [`docs/superpowers/specs/2026-04-23-entity-detail-unification-design.md`](../specs/2026-04-23-entity-detail-unification-design.md)

---

## Conventions for this plan

- **Build verification command** (used after each phase):
  ```bash
  xcodebuild build -scheme Tenra \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
    | grep -E "error:" | head -30
  ```
  Expected output: empty. If errors surface, fix and re-run before committing.

- **Commit conventions:** one phase = one commit. Commit message format: `feat(detail): <what changed>` or `refactor(detail): <what changed>`. Co-author tag per project convention.

- **SwiftUI "test" strategy:** XCTest for value-type logic (aggregates, filter helpers). Visual components verified via Xcode Previews + manual interaction on simulator. Do not attempt XCUITest for these screens — not part of project convention.

- **Localization contract:** every new user-visible string lands in BOTH `Tenra/en.lproj/Localizable.strings` AND `Tenra/ru.lproj/Localizable.strings` within the same phase. Format: `"feature.key" = "Value";`. Use `String(localized: "feature.key")` at call sites.

- **File discovery during execution:** some exact line numbers (tap targets in `AccountsManagementView`, `CategoriesManagementView`, `HomeView`) need to be located when that phase starts — this plan describes *what* to replace, not always *which line*. Use `Grep` on the file to find the NavigationLink / Button wrapping the row.

---

## Phase 1 — Foundation Components

**Goal:** Ship `EntityDetailScaffold`, `HeroSection`, `GroupedTransactionList`, and their supporting value types. No callers yet. Verified via Xcode Previews only.

### Task 1.1: Create value types — `ActionConfig`, `InfoRowConfig`, `ProgressConfig`

**Files:**
- Create: `Tenra/Views/Components/EntityDetail/EntityDetailTypes.swift`

- [ ] **Step 1: Create directory and file**

```bash
mkdir -p Tenra/Views/Components/EntityDetail
```

- [ ] **Step 2: Write the value types**

Write `Tenra/Views/Components/EntityDetail/EntityDetailTypes.swift`:

```swift
//
//  EntityDetailTypes.swift
//  Tenra
//
//  Value types consumed by EntityDetailScaffold + HeroSection.
//

import SwiftUI

/// Primary / secondary action button config for EntityDetailScaffold's actions bar.
struct ActionConfig: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let action: () -> Void

    init(title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }
}

/// Declarative info row (wraps UniversalRow(.info) at render time).
/// Use `icon` for SF Symbol; brand/custom icons pass through `iconConfig` escape hatch.
struct InfoRowConfig: Identifiable {
    let id = UUID()
    let icon: String?
    let label: String
    let value: String
    let iconColor: Color
    let trailing: AnyView?

    init(
        icon: String? = nil,
        label: String,
        value: String,
        iconColor: Color = AppColors.accent,
        trailing: AnyView? = nil
    ) {
        self.icon = icon
        self.label = label
        self.value = value
        self.iconColor = iconColor
        self.trailing = trailing
    }
}

/// Linear progress strip rendered under the primary amount in HeroSection.
/// Used for: category budget utilization, loan % paid off.
struct ProgressConfig {
    let current: Double
    let total: Double
    let label: String?
    let color: Color

    init(current: Double, total: Double, label: String? = nil, color: Color = .accentColor) {
        self.current = current
        self.total = total
        self.label = label
        self.color = color
    }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(current / total, 0), 1)
    }
}
```

- [ ] **Step 3: Build the project**

Run:
```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -30
```
Expected: empty output.

### Task 1.2: Create `HeroSection`

**Files:**
- Create: `Tenra/Views/Components/EntityDetail/HeroSection.swift`

- [ ] **Step 1: Write the view**

```swift
//
//  HeroSection.swift
//  Tenra
//
//  Standard hero for all entity-detail screens:
//  icon + title + primary amount + optional subtitle + optional progress + optional base-currency conversion.
//

import SwiftUI

struct HeroSection: View {
    let icon: IconSource?
    let title: String
    let primaryAmount: Double
    let primaryCurrency: String
    let subtitle: String?
    let progress: ProgressConfig?
    let showBaseConversion: Bool
    let baseCurrency: String

    init(
        icon: IconSource?,
        title: String,
        primaryAmount: Double,
        primaryCurrency: String,
        subtitle: String? = nil,
        progress: ProgressConfig? = nil,
        showBaseConversion: Bool = false,
        baseCurrency: String = ""
    ) {
        self.icon = icon
        self.title = title
        self.primaryAmount = primaryAmount
        self.primaryCurrency = primaryCurrency
        self.subtitle = subtitle
        self.progress = progress
        self.showBaseConversion = showBaseConversion
        self.baseCurrency = baseCurrency
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            IconView(source: icon, style: .glassHero())

            VStack(alignment: .center, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.h1)
                    .multilineTextAlignment(.center)

                FormattedAmountText(
                    amount: primaryAmount,
                    currency: primaryCurrency,
                    fontSize: AppTypography.h4,
                    color: .secondary
                )

                if showBaseConversion, !baseCurrency.isEmpty, primaryCurrency != baseCurrency {
                    ConvertedAmountView(
                        amount: primaryAmount,
                        fromCurrency: primaryCurrency,
                        toCurrency: baseCurrency,
                        fontSize: AppTypography.caption,
                        color: .secondary.opacity(0.7)
                    )
                }

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, AppSpacing.xs)
                }
            }

            if let progress {
                progressBar(progress)
                    .padding(.top, AppSpacing.sm)
                    .padding(.horizontal, AppSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func progressBar(_ cfg: ProgressConfig) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if let label = cfg.label {
                HStack {
                    Text(label)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((cfg.fraction * 100).rounded()))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(cfg.color.opacity(0.15))
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(cfg.color)
                        .frame(width: geo.size.width * cfg.fraction)
                        .animation(AppAnimation.progressBarSpring, value: cfg.fraction)
                }
            }
            .frame(height: 6)
        }
    }
}

#Preview("No progress") {
    HeroSection(
        icon: .sfSymbol("creditcard.fill"),
        title: "Kaspi Gold",
        primaryAmount: 1_245_300,
        primaryCurrency: "KZT",
        showBaseConversion: true,
        baseCurrency: "USD"
    )
    .padding()
}

#Preview("With budget progress") {
    HeroSection(
        icon: .sfSymbol("fork.knife"),
        title: "Food",
        primaryAmount: 185_000,
        primaryCurrency: "KZT",
        subtitle: "This month",
        progress: ProgressConfig(current: 185_000, total: 250_000, label: "Budget", color: .orange)
    )
    .padding()
}
```

- [ ] **Step 2: Build + open preview**

Build the project, then open `HeroSection.swift` in Xcode and verify both previews render without crashing. Fix any compile errors.

### Task 1.3: Create `GroupedTransactionList`

**Files:**
- Create: `Tenra/Views/Components/History/GroupedTransactionList.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p Tenra/Views/Components/History
```

- [ ] **Step 2: Write the component**

```swift
//
//  GroupedTransactionList.swift
//  Tenra
//
//  Shared date-grouped transaction list used by all entity-detail screens
//  and by LinkPaymentsView. Pure renderer — caller owns data & filtering.
//

import SwiftUI

struct GroupedTransactionList<Overlay: View>: View {
    let transactions: [Transaction]
    let displayCurrency: String?
    let accountsById: [String: Account]
    let styleHelper: (Transaction) -> CategoryStyleData
    let pageSize: Int
    let showCountBadge: Bool
    let titleKey: String
    let viewModel: TransactionsViewModel?
    let categoriesViewModel: CategoriesViewModel?
    let accountsViewModel: AccountsViewModel?
    let balanceCoordinator: BalanceCoordinator?
    let rowOverlay: (Transaction) -> Overlay

    @State private var visibleLimit: Int

    init(
        transactions: [Transaction],
        displayCurrency: String? = nil,
        accountsById: [String: Account],
        styleHelper: @escaping (Transaction) -> CategoryStyleData,
        pageSize: Int = 100,
        showCountBadge: Bool = true,
        titleKey: String = "history.section.title",
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil,
        @ViewBuilder rowOverlay: @escaping (Transaction) -> Overlay = { _ in EmptyView() }
    ) {
        self.transactions = transactions
        self.displayCurrency = displayCurrency
        self.accountsById = accountsById
        self.styleHelper = styleHelper
        self.pageSize = pageSize
        self.showCountBadge = showCountBadge
        self.titleKey = titleKey
        self.viewModel = viewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.balanceCoordinator = balanceCoordinator
        self.rowOverlay = rowOverlay
        self._visibleLimit = State(initialValue: pageSize)
    }

    private var sections: [(date: String, displayLabel: String, transactions: [Transaction])] {
        let slice = Array(transactions.prefix(visibleLimit))
        let grouped = Dictionary(grouping: slice) { $0.date }
        return grouped
            .sorted { $0.key > $1.key }
            .map { key, txs in
                (date: key, displayLabel: Self.formatDateKey(key), transactions: txs)
            }
    }

    private static func formatDateKey(_ isoDate: String) -> String {
        guard let date = DateFormatters.dateFormatter.date(from: isoDate) else { return isoDate }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "common.today", defaultValue: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "common.yesterday", defaultValue: "Yesterday") }
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return DateFormatters.displayDateFormatter.string(from: date)
        }
        return DateFormatters.displayDateWithYearFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text(String(localized: String.LocalizationValue(titleKey), defaultValue: "History"))
                    .font(AppTypography.h4)
                Spacer()
                if showCountBadge, !transactions.isEmpty {
                    Text("\(transactions.count)")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(sections, id: \.date) { section in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        DateSectionHeaderView(dateKey: section.displayLabel)
                            .padding(.top, AppSpacing.sm)

                        ForEach(section.transactions) { transaction in
                            let sourceAccount = transaction.accountId.flatMap { accountsById[$0] }
                            let targetAccount = transaction.targetAccountId.flatMap { accountsById[$0] }
                            let style = styleHelper(transaction)
                            let rowCurrency = displayCurrency ?? transaction.currency

                            ZStack {
                                TransactionCard(
                                    transaction: transaction,
                                    currency: rowCurrency,
                                    styleData: style,
                                    sourceAccount: sourceAccount,
                                    targetAccount: targetAccount,
                                    viewModel: viewModel,
                                    categoriesViewModel: categoriesViewModel,
                                    accountsViewModel: accountsViewModel,
                                    balanceCoordinator: balanceCoordinator
                                )
                                rowOverlay(transaction)
                            }
                        }
                    }
                }

                if visibleLimit < transactions.count {
                    ProgressView()
                        .padding(.vertical, AppSpacing.md)
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            visibleLimit = min(visibleLimit + pageSize, transactions.count)
                        }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run the build command. Expected: empty error output.

Known concern: `String.LocalizationValue(titleKey)` — if this produces a warning/error about using a variable as a localization key, fall back to `String(localized: "history.section.title", defaultValue: "History")` and accept that `titleKey` is effectively hardcoded for now. Parametric localization keys are not a goal of this component; remove the parameter if it won't build cleanly.

### Task 1.4: Create `EntityDetailScaffold`

**Files:**
- Create: `Tenra/Views/Components/EntityDetail/EntityDetailScaffold.swift`

- [ ] **Step 1: Write the scaffold**

```swift
//
//  EntityDetailScaffold.swift
//  Tenra
//
//  Common container for Subscription / Account / Category / Deposit / Loan detail screens.
//  Layout: Hero → Actions → Info rows → Custom sections → History.
//  Caller provides the hero, custom sections, and toolbar menu content via @ViewBuilder slots.
//

import SwiftUI

struct EntityDetailScaffold<Hero: View, CustomSections: View, Menu: View, HistoryOverlay: View>: View {
    let hero: Hero
    let primaryAction: ActionConfig?
    let secondaryAction: ActionConfig?
    let infoRows: [InfoRowConfig]
    let customSections: CustomSections
    let transactions: [Transaction]
    let historyCurrency: String?
    let accountsById: [String: Account]
    let styleHelper: (Transaction) -> CategoryStyleData
    let viewModel: TransactionsViewModel?
    let categoriesViewModel: CategoriesViewModel?
    let accountsViewModel: AccountsViewModel?
    let balanceCoordinator: BalanceCoordinator?
    let historyRowOverlay: (Transaction) -> HistoryOverlay
    let toolbarMenu: Menu
    let navigationTitle: String

    init(
        navigationTitle: String = "",
        primaryAction: ActionConfig? = nil,
        secondaryAction: ActionConfig? = nil,
        infoRows: [InfoRowConfig] = [],
        transactions: [Transaction] = [],
        historyCurrency: String? = nil,
        accountsById: [String: Account] = [:],
        styleHelper: @escaping (Transaction) -> CategoryStyleData = { _ in
            CategoryStyleData.fallback
        },
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder customSections: () -> CustomSections = { EmptyView() },
        @ViewBuilder historyRowOverlay: @escaping (Transaction) -> HistoryOverlay = { _ in EmptyView() },
        @ViewBuilder toolbarMenu: () -> Menu
    ) {
        self.navigationTitle = navigationTitle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.infoRows = infoRows
        self.hero = hero()
        self.customSections = customSections()
        self.transactions = transactions
        self.historyCurrency = historyCurrency
        self.accountsById = accountsById
        self.styleHelper = styleHelper
        self.viewModel = viewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.balanceCoordinator = balanceCoordinator
        self.historyRowOverlay = historyRowOverlay
        self.toolbarMenu = toolbarMenu()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                hero.screenPadding()

                if primaryAction != nil || secondaryAction != nil {
                    actionsBar.screenPadding()
                }

                if !infoRows.isEmpty {
                    infoRowsCard.screenPadding()
                }

                customSections

                if !transactions.isEmpty {
                    GroupedTransactionList(
                        transactions: transactions,
                        displayCurrency: historyCurrency,
                        accountsById: accountsById,
                        styleHelper: styleHelper,
                        viewModel: viewModel,
                        categoriesViewModel: categoriesViewModel,
                        accountsViewModel: accountsViewModel,
                        balanceCoordinator: balanceCoordinator,
                        rowOverlay: historyRowOverlay
                    )
                    .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    toolbarMenu
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }

    @ViewBuilder
    private var actionsBar: some View {
        HStack(spacing: AppSpacing.md) {
            if let primaryAction {
                Button(role: primaryAction.role, action: primaryAction.action) {
                    actionLabel(primaryAction)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if let secondaryAction {
                Button(role: secondaryAction.role, action: secondaryAction.action) {
                    actionLabel(secondaryAction)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func actionLabel(_ cfg: ActionConfig) -> some View {
        HStack(spacing: AppSpacing.xs) {
            if let systemImage = cfg.systemImage {
                Image(systemName: systemImage)
            }
            Text(cfg.title)
        }
    }

    @ViewBuilder
    private var infoRowsCard: some View {
        VStack(spacing: 0) {
            ForEach(infoRows) { row in
                InfoRow(icon: row.icon, label: row.label, value: row.value)
                if row.id != infoRows.last?.id {
                    Divider().padding(.leading, AppSpacing.lg)
                }
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}
```

- [ ] **Step 2: Add `CategoryStyleData.fallback` if missing**

Check `Tenra/Utils/CategoryStyleCache.swift` for a `fallback` static member on `CategoryStyleData`. If absent, add a minimal fallback so the scaffold's default `styleHelper` compiles:

```swift
// In CategoryStyleCache.swift (append to CategoryStyleData)
extension CategoryStyleData {
    static let fallback = CategoryStyleData(
        coinColor: .gray,
        coinBorderColor: .gray.opacity(0.3),
        iconColor: .gray,
        primaryColor: .gray,
        lightBackgroundColor: .gray.opacity(0.1),
        iconName: "questionmark.circle.fill"
    )
}
```

Inspect the actual `CategoryStyleData` struct first — field names may differ. Match existing field names; do not invent.

- [ ] **Step 3: Build**

Run the build command. Fix any compile issues (most likely: argument-label mismatches on `IconView`, `InfoRow`, or `GroupedTransactionList` — cross-reference the Task 1.2 / 1.3 definitions).

### Task 1.5: Commit Phase 1

- [ ] **Step 1: Verify build is clean**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -30
```
Expected: empty.

- [ ] **Step 2: Commit**

```bash
git add \
  Tenra/Views/Components/EntityDetail/EntityDetailTypes.swift \
  Tenra/Views/Components/EntityDetail/HeroSection.swift \
  Tenra/Views/Components/EntityDetail/EntityDetailScaffold.swift \
  Tenra/Views/Components/History/GroupedTransactionList.swift \
  Tenra/Utils/CategoryStyleCache.swift

git commit -m "$(cat <<'EOF'
feat(detail): add EntityDetailScaffold + HeroSection + GroupedTransactionList

Foundation for unifying all entity-detail screens. No callers yet.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — Migrate `SubscriptionDetailView` to scaffold

**Goal:** Prove the scaffold on the simplest existing detail view. Pure refactor — no behavior change.

### Task 2.1: Refactor SubscriptionDetailView body

**Files:**
- Modify: `Tenra/Views/Subscriptions/SubscriptionDetailView.swift`

- [ ] **Step 1: Back up current behavior**

Read `SubscriptionDetailView.swift` fully. Note the toolbar menu items (link/edit/pause-resume/unlink-all/delete), the alerts (delete-confirm, unlink-all-confirm), the `.sheet` and `.navigationDestination` attachments, the `.task(id:)` data refresh, and the `subscriptionInfoCard`/`transactionsSection` layouts. All of these must be preserved.

- [ ] **Step 2: Rewrite `body` using scaffold**

Replace the `var body: some View { ... }` block with the scaffold call. The existing `refreshTransactions()`, `formatTransactionDate()`, `nextChargeDate`, and computed properties stay. Only the view composition changes.

Skeleton:

```swift
var body: some View {
    let accountsById = Dictionary(uniqueKeysWithValues: transactionsViewModel.accounts.map { ($0.id, $0) })

    EntityDetailScaffold(
        navigationTitle: "",
        infoRows: infoRowConfigs(),
        transactions: cachedTransactions,
        historyCurrency: liveSubscription.currency,
        accountsById: accountsById,
        styleHelper: { tx in
            CategoryStyleHelper.cached(
                category: tx.category,
                type: tx.type,
                customCategories: categoriesViewModel.customCategories
            )
        },
        viewModel: transactionsViewModel,
        categoriesViewModel: categoriesViewModel,
        accountsViewModel: accountsViewModel,
        balanceCoordinator: accountsViewModel.balanceCoordinator,
        hero: {
            HeroSection(
                icon: liveSubscription.iconSource,
                title: liveSubscription.description,
                primaryAmount: NSDecimalNumber(decimal: liveSubscription.amount).doubleValue,
                primaryCurrency: liveSubscription.currency,
                showBaseConversion: true,
                baseCurrency: transactionsViewModel.appSettings.baseCurrency
            )
        },
        toolbarMenu: {
            subscriptionToolbarMenu
        }
    )
    .sheet(isPresented: $showingEditView) { /* existing sheet */ }
    .alert( /* existing delete alert */ ) { /* ... */ } message: { /* ... */ }
    .alert( /* existing unlink-all alert */ ) { /* ... */ } message: { /* ... */ }
    .navigationDestination(isPresented: $showingLinkPayments) { /* existing */ }
    .task(id: linkedTransactionCount) { await refreshTransactions() }
}
```

- [ ] **Step 3: Extract `infoRowConfigs()`**

Add a private helper that returns `[InfoRowConfig]` matching the existing `subscriptionInfoCard` rows:

```swift
private func infoRowConfigs() -> [InfoRowConfig] {
    var rows: [InfoRowConfig] = []
    rows.append(InfoRowConfig(
        icon: "tag.fill",
        label: String(localized: "subscriptions.category"),
        value: liveSubscription.category
    ))
    rows.append(InfoRowConfig(
        icon: "repeat",
        label: String(localized: "subscriptions.frequency"),
        value: liveSubscription.frequency.displayName
    ))
    if let nextDate = nextChargeDate {
        rows.append(InfoRowConfig(
            icon: "calendar.badge.clock",
            label: String(localized: "subscriptions.nextCharge"),
            value: formatDate(nextDate)
        ))
    }
    if let accountId = liveSubscription.accountId,
       let account = transactionsViewModel.accounts.first(where: { $0.id == accountId }) {
        rows.append(InfoRowConfig(
            icon: "creditcard.fill",
            label: String(localized: "subscriptions.account"),
            value: account.name
        ))
    }
    rows.append(InfoRowConfig(
        icon: "checkmark.circle.fill",
        label: String(localized: "subscriptions.status"),
        value: statusText
    ))
    rows.append(InfoRowConfig(
        icon: "sum",
        label: String(localized: "subscriptions.spentAllTime", defaultValue: "Spent all time"),
        value: spentAllTimeDisplay
    ))
    return rows
}
```

- [ ] **Step 4: Extract `subscriptionToolbarMenu`**

Move the `Menu { ... }` content from the old toolbar into a computed `@ViewBuilder` property. All button actions, the pause/resume logic, the unlink-all handler — copy verbatim from the original.

- [ ] **Step 5: Delete dead code**

Remove the old `subscriptionInfoCard` computed property, `transactionsSection` computed property, and the `visibleTxLimit` / pagination helpers — the scaffold + `GroupedTransactionList` cover all of this now. Keep `cachedTransactions`, `cachedSpentAllTimeInSubCurrency`, `refreshTransactions`, `computeSpentAllTime`, `nextChargeDate`, `transactionDateSections`, `formatTransactionDate`, `formatDate`, `spentAllTimeDisplay`, `statusText`, `liveSubscription`, `linkedTransactionCount`.

Actually — `transactionDateSections` and `formatTransactionDate` become dead. Delete them too. Keep what's still referenced.

- [ ] **Step 6: Build + run simulator**

Build. If clean, launch the app in simulator and open any subscription's detail page. Verify:
- Hero renders with icon, name, amount, converted amount.
- Info rows render in the same order as before.
- Transaction history lists sections with date headers + cards.
- Toolbar menu shows Link / Edit / Pause-or-Resume / Unlink-all (if linked) / Delete.
- Delete / unlink alerts still trigger.
- Edit sheet + link-payments navigation still work.

### Task 2.2: Commit Phase 2

- [ ] **Step 1: Verify clean build + functional parity**

- [ ] **Step 2: Commit**

```bash
git add Tenra/Views/Subscriptions/SubscriptionDetailView.swift
git commit -m "$(cat <<'EOF'
refactor(detail): migrate SubscriptionDetailView to EntityDetailScaffold

No behavior change. Hero, info rows, transaction history, toolbar menu,
and all sheets/alerts preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — `AccountDetailView` (new)

**Goal:** New detail view for regular accounts (not deposits, not loans). Rewire tap targets in `AccountsManagementView` and the home carousel.

### Task 3.1: Add `AccountAggregates` helper

**Files:**
- Create: `Tenra/Views/Accounts/AccountAggregates.swift`

- [ ] **Step 1: Write the aggregates**

```swift
//
//  AccountAggregates.swift
//  Tenra
//
//  Pure value-type aggregates for AccountDetailView.
//  Kept as `nonisolated` free functions so they can be computed off MainActor if needed.
//

import Foundation

struct AccountAggregates {
    let totalTransactions: Int
    let totalIncome: Double      // in account currency
    let totalExpense: Double     // in account currency
}

enum AccountAggregatesCalculator {
    static func compute(
        accountId: String,
        accountCurrency: String,
        transactions: [Transaction]
    ) -> AccountAggregates {
        var count = 0
        var income = 0.0
        var expense = 0.0
        for tx in transactions {
            let isSource = tx.accountId == accountId
            let isTarget = tx.targetAccountId == accountId
            guard isSource || isTarget else { continue }
            count += 1

            let amount = convertIfNeeded(
                amount: tx.amount,
                from: tx.currency,
                to: accountCurrency,
                stored: tx.convertedAmount
            )
            switch tx.type {
            case .income:
                if isSource { income += amount }
            case .expense:
                if isSource { expense += amount }
            case .internalTransfer:
                if isTarget { income += amount }
                if isSource { expense += amount }
            case .depositTopup, .depositInterestAccrual:
                if isTarget || isSource { income += amount }
            case .depositWithdrawal:
                if isSource { expense += amount }
            case .loanDisbursement:
                if isTarget { income += amount }
            case .loanPayment, .loanEarlyRepayment:
                if isSource { expense += amount }
            }
        }
        return AccountAggregates(totalTransactions: count, totalIncome: income, totalExpense: expense)
    }

    private static func convertIfNeeded(amount: Double, from: String, to: String, stored: Double?) -> Double {
        if from == to { return amount }
        if let converted = CurrencyConverter.convertSync(amount: amount, from: from, to: to) {
            return converted
        }
        return stored ?? amount
    }
}
```

**IMPORTANT:** The `switch tx.type` must be exhaustive over `TransactionType` cases. Open `Tenra/Models/Transaction.swift`, find `enum TransactionType`, and verify every case is handled. Add any missing ones with sensible defaults (typically treat as no-op). The case list above is based on current knowledge — it *will* miss something if types have been added; trust the compiler.

- [ ] **Step 2: Add unit test**

**Files:**
- Create: `TenraTests/Views/AccountAggregatesTests.swift`

```swift
import XCTest
@testable import Tenra

final class AccountAggregatesTests: XCTestCase {
    func test_emptyTransactions_returnsZeros() {
        let result = AccountAggregatesCalculator.compute(
            accountId: "a1",
            accountCurrency: "USD",
            transactions: []
        )
        XCTAssertEqual(result.totalTransactions, 0)
        XCTAssertEqual(result.totalIncome, 0)
        XCTAssertEqual(result.totalExpense, 0)
    }

    func test_incomeAndExpenseOnSameCurrency_sumsCorrectly() {
        let txs: [Transaction] = [
            makeTx(type: .income, amount: 1000, accountId: "a1", currency: "USD"),
            makeTx(type: .expense, amount: 200, accountId: "a1", currency: "USD"),
            makeTx(type: .expense, amount: 50, accountId: "a1", currency: "USD"),
        ]
        let result = AccountAggregatesCalculator.compute(
            accountId: "a1",
            accountCurrency: "USD",
            transactions: txs
        )
        XCTAssertEqual(result.totalTransactions, 3)
        XCTAssertEqual(result.totalIncome, 1000)
        XCTAssertEqual(result.totalExpense, 250)
    }

    func test_transferAddsToBothLegsWhenAccountIsSourceAndTarget() {
        // Defensive check: verify an unrelated account is ignored.
        let txs: [Transaction] = [
            makeTx(type: .internalTransfer, amount: 500, accountId: "a1", targetAccountId: "a2", currency: "USD"),
        ]
        let r1 = AccountAggregatesCalculator.compute(accountId: "a1", accountCurrency: "USD", transactions: txs)
        XCTAssertEqual(r1.totalExpense, 500)
        XCTAssertEqual(r1.totalIncome, 0)

        let r2 = AccountAggregatesCalculator.compute(accountId: "a2", accountCurrency: "USD", transactions: txs)
        XCTAssertEqual(r2.totalIncome, 500)
        XCTAssertEqual(r2.totalExpense, 0)
    }

    // Helper — adjust fields to match Transaction's actual initializer.
    private func makeTx(
        type: TransactionType,
        amount: Double,
        accountId: String?,
        targetAccountId: String? = nil,
        currency: String
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: "2026-04-23",
            description: "test",
            amount: amount,
            currency: currency,
            type: type,
            category: "Test",
            accountId: accountId,
            targetAccountId: targetAccountId
        )
    }
}
```

**IMPORTANT:** The `Transaction` initializer in the helper must match the actual struct's init. Open `Tenra/Models/Transaction.swift`, find the init, and adjust argument labels / add any required parameters. The field list you need is likely: `id`, `date`, `description`, `amount`, `currency`, `type`, `category`. Others may be optional with defaults.

- [ ] **Step 3: Run tests**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/AccountAggregatesTests
```
Expected: all tests pass.

### Task 3.2: Create `AccountDetailView`

**Files:**
- Create: `Tenra/Views/Accounts/AccountDetailView.swift`

- [ ] **Step 1: Write the view**

```swift
//
//  AccountDetailView.swift
//  Tenra
//
//  Detail screen for regular accounts (not deposits, not loans).
//  Built on EntityDetailScaffold.
//

import SwiftUI

struct AccountDetailView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    let account: Account

    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var showingAddTransaction = false
    @State private var showingTransfer = false
    @State private var cachedTransactions: [Transaction] = []
    @State private var aggregates = AccountAggregates(totalTransactions: 0, totalIncome: 0, totalExpense: 0)
    @Environment(\.dismiss) private var dismiss

    /// Live account lookup — reflects edits without re-navigation.
    private var liveAccount: Account {
        transactionsViewModel.accounts.first(where: { $0.id == account.id }) ?? account
    }

    private var refreshTrigger: Int {
        var n = 0
        for tx in transactionStore.transactions where tx.accountId == account.id || tx.targetAccountId == account.id {
            n += 1
        }
        return n
    }

    private func refreshData() async {
        let filtered = transactionStore.transactions
            .filter { $0.accountId == account.id || $0.targetAccountId == account.id }
            .sorted { $0.date > $1.date }
        cachedTransactions = filtered
        aggregates = AccountAggregatesCalculator.compute(
            accountId: account.id,
            accountCurrency: liveAccount.currency,
            transactions: filtered
        )
    }

    var body: some View {
        let accountsById = Dictionary(uniqueKeysWithValues: transactionsViewModel.accounts.map { ($0.id, $0) })

        EntityDetailScaffold(
            navigationTitle: liveAccount.name,
            primaryAction: ActionConfig(
                title: String(localized: "account.detail.actions.addTransaction", defaultValue: "Add transaction"),
                systemImage: "plus",
                action: { showingAddTransaction = true }
            ),
            secondaryAction: ActionConfig(
                title: String(localized: "account.detail.actions.transfer", defaultValue: "Transfer"),
                systemImage: "arrow.left.arrow.right",
                action: { showingTransfer = true }
            ),
            infoRows: infoRowConfigs(),
            transactions: cachedTransactions,
            historyCurrency: liveAccount.currency,
            accountsById: accountsById,
            styleHelper: { tx in
                CategoryStyleHelper.cached(
                    category: tx.category,
                    type: tx.type,
                    customCategories: categoriesViewModel.customCategories
                )
            },
            viewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            balanceCoordinator: accountsViewModel.balanceCoordinator,
            hero: {
                HeroSection(
                    icon: liveAccount.iconSource,
                    title: liveAccount.name,
                    primaryAmount: liveAccount.balance,
                    primaryCurrency: liveAccount.currency,
                    showBaseConversion: true,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency
                )
            },
            toolbarMenu: { toolbarMenu }
        )
        .sheet(isPresented: $showingEdit) {
            AccountEditView(
                account: liveAccount,
                accountsViewModel: accountsViewModel,
                transactionsViewModel: transactionsViewModel
            )
            // NOTE: AccountEditView's actual init signature must be cross-checked.
            // Adjust parameters to match the real view.
        }
        .sheet(isPresented: $showingAddTransaction) {
            // Open QuickAdd / TransactionEditView with accountId pre-filled.
            // Wiring is TBD at execution time — grep for how other views launch quick-add with pre-fill.
            // Fallback: inline a simple placeholder sheet with a TODO; ship the rest of the screen.
            Text("Add Transaction — wire to existing quick-add entry point")
        }
        .sheet(isPresented: $showingTransfer) {
            AccountActionView(
                mode: .transfer,
                sourceAccount: liveAccount,
                accountsViewModel: accountsViewModel,
                transactionStore: transactionStore
            )
            // NOTE: AccountActionView init signature must be cross-checked.
        }
        .alert(
            String(localized: "account.detail.delete.confirmTitle", defaultValue: "Delete account?"),
            isPresented: $showingDeleteConfirm
        ) {
            Button(String(localized: "quickAdd.cancel"), role: .cancel) {}
            Button(String(localized: "common.delete", defaultValue: "Delete"), role: .destructive) {
                Task {
                    // Match existing delete flow from AccountsManagementView.
                    await accountsViewModel.deleteAccount(id: account.id)
                    dismiss()
                }
            }
        } message: {
            Text(String(
                localized: "account.detail.delete.confirmMessage",
                defaultValue: "This will permanently delete the account."
            ))
        }
        .task(id: refreshTrigger) {
            await refreshData()
        }
    }

    private func infoRowConfigs() -> [InfoRowConfig] {
        var rows: [InfoRowConfig] = []
        rows.append(InfoRowConfig(
            icon: "creditcard",
            label: String(localized: "accounts.type", defaultValue: "Type"),
            value: accountTypeLabel()
        ))
        rows.append(InfoRowConfig(
            icon: "dollarsign.circle",
            label: String(localized: "accounts.currency", defaultValue: "Currency"),
            value: liveAccount.currency
        ))
        rows.append(InfoRowConfig(
            icon: "number",
            label: String(localized: "account.detail.transactionCount", defaultValue: "Transactions"),
            value: "\(aggregates.totalTransactions)"
        ))
        rows.append(InfoRowConfig(
            icon: "arrow.down.circle",
            label: String(localized: "account.detail.totalIncome", defaultValue: "Total income"),
            value: Formatting.formatCurrency(aggregates.totalIncome, currency: liveAccount.currency)
        ))
        rows.append(InfoRowConfig(
            icon: "arrow.up.circle",
            label: String(localized: "account.detail.totalExpense", defaultValue: "Total expense"),
            value: Formatting.formatCurrency(aggregates.totalExpense, currency: liveAccount.currency)
        ))
        return rows
    }

    private func accountTypeLabel() -> String {
        if liveAccount.isDeposit { return String(localized: "accounts.type.deposit", defaultValue: "Deposit") }
        if liveAccount.isLoan { return String(localized: "accounts.type.loan", defaultValue: "Loan") }
        return String(localized: "accounts.type.regular", defaultValue: "Account")
    }

    @ViewBuilder
    private var toolbarMenu: some View {
        Button {
            showingEdit = true
        } label: {
            Label(String(localized: "common.edit", defaultValue: "Edit"), systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Label(String(localized: "common.delete", defaultValue: "Delete"), systemImage: "trash")
        }
    }
}
```

**Known gaps to resolve at execution time:**
- `AccountEditView` init signature — grep its file and match.
- `AccountActionView` init signature + how to pre-set `mode: .transfer` — grep its file.
- Quick-add entry point with accountId pre-fill — grep for existing uses (look for `QuickAdd`, `TransactionEditView`, `AddTransactionView`, or similar). Wire to whichever entry point other screens use. If no pre-fill mechanism exists today, add a minimal TODO comment and ship without it; wire in a follow-up.
- `accountsViewModel.deleteAccount` — grep for the method. If it's synchronous or has a different signature, adjust.

- [ ] **Step 2: Add localization keys**

Append to `Tenra/en.lproj/Localizable.strings`:
```
"account.detail.actions.addTransaction" = "Add transaction";
"account.detail.actions.transfer" = "Transfer";
"account.detail.totalIncome" = "Total income";
"account.detail.totalExpense" = "Total expense";
"account.detail.transactionCount" = "Transactions";
"account.detail.delete.confirmTitle" = "Delete account?";
"account.detail.delete.confirmMessage" = "This will permanently delete the account.";
"accounts.type" = "Type";
"accounts.currency" = "Currency";
"accounts.type.deposit" = "Deposit";
"accounts.type.loan" = "Loan";
"accounts.type.regular" = "Account";
"common.edit" = "Edit";
"common.delete" = "Delete";
"history.section.title" = "History";
```

Append Russian translations to `Tenra/ru.lproj/Localizable.strings`:
```
"account.detail.actions.addTransaction" = "Добавить транзакцию";
"account.detail.actions.transfer" = "Перевод";
"account.detail.totalIncome" = "Всего доходов";
"account.detail.totalExpense" = "Всего расходов";
"account.detail.transactionCount" = "Транзакций";
"account.detail.delete.confirmTitle" = "Удалить счёт?";
"account.detail.delete.confirmMessage" = "Счёт будет удалён навсегда.";
"accounts.type" = "Тип";
"accounts.currency" = "Валюта";
"accounts.type.deposit" = "Депозит";
"accounts.type.loan" = "Кредит";
"accounts.type.regular" = "Счёт";
"common.edit" = "Изменить";
"common.delete" = "Удалить";
"history.section.title" = "История";
```

Skip any keys that already exist (grep each key first).

- [ ] **Step 3: Build**

### Task 3.3: Rewire navigation — `AccountsManagementView`

**Files:**
- Modify: `Tenra/Views/Accounts/AccountsManagementView.swift`

- [ ] **Step 1: Locate the row tap target**

Grep for `NavigationLink`, `onTapGesture`, `Button`, and `showingEdit` inside `AccountsManagementView.swift`. Identify the construct that opens edit today.

- [ ] **Step 2: Branch by account type**

Today: tap → edit. New behavior:
- If `account.isDeposit` → navigate to existing `DepositDetailView`.
- If `account.isLoan` → navigate to existing `LoanDetailView`.
- Otherwise → navigate to new `AccountDetailView`.

Pattern (adjust to the actual view structure):

```swift
NavigationLink {
    if account.isDeposit {
        DepositDetailView(/* existing args */)
    } else if account.isLoan {
        LoanDetailView(/* existing args */)
    } else {
        AccountDetailView(
            transactionStore: transactionStore,
            transactionsViewModel: transactionsViewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            account: account
        )
    }
} label: {
    AccountRow(/* existing args */)
}
```

Verify deposit and loan detail-view init signatures from their source files. Match the existing callers — the navigation to deposit/loan already happens somewhere in the codebase; reuse the same pattern.

- [ ] **Step 3: Build + functionally verify**

Launch simulator. From `AccountsManagementView`:
- Tap a regular account → `AccountDetailView` opens with correct balance and history.
- Tap a deposit → `DepositDetailView` opens (unchanged).
- Tap a loan → `LoanDetailView` opens (unchanged).

### Task 3.4: Rewire navigation — home carousel

**Files:**
- Modify: `Tenra/Views/Home/HomeView.swift` (or wherever the account carousel is rendered — the component may live in `Tenra/Views/Components/`)

- [ ] **Step 1: Locate the carousel tap target**

Grep for `AccountCard`, `accountsViewModel.accounts`, and `.onTapGesture` within `Tenra/Views/Home/` and `Tenra/Views/Components/`. Find the tap handler on each account card.

- [ ] **Step 2: Apply the same branch as Task 3.3**

Navigate to `DepositDetailView` / `LoanDetailView` / `AccountDetailView` based on `account.isDeposit` / `account.isLoan`. If the carousel is embedded in a view that can't navigate directly (e.g. a view that doesn't have a `NavigationStack` in scope), a binding or callback pattern may be needed — match how the current tap behavior is propagated and swap the destination.

If the tap currently opens `AccountActionView` (quick action) rather than edit, consult the user before changing behavior. Without clarity: preserve existing behavior in home carousel; update only `AccountsManagementView` (Task 3.3).

- [ ] **Step 3: Build + verify**

### Task 3.5: Commit Phase 3

```bash
git add \
  Tenra/Views/Accounts/AccountAggregates.swift \
  Tenra/Views/Accounts/AccountDetailView.swift \
  Tenra/Views/Accounts/AccountsManagementView.swift \
  Tenra/Views/Home/HomeView.swift \
  Tenra/en.lproj/Localizable.strings \
  Tenra/ru.lproj/Localizable.strings \
  TenraTests/Views/AccountAggregatesTests.swift

git commit -m "$(cat <<'EOF'
feat(detail): AccountDetailView for regular accounts

Tap on a regular account now opens a detail screen with balance hero,
income/expense aggregates, action buttons, and full transaction history.
Deposits and loans route to their existing detail views unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — `CategoryDetailView` (new)

**Goal:** New detail view for custom categories with period-scoped totals, budget progress in the hero, avg-monthly spend, and full transaction history. Rewire `CategoriesManagementView` tap.

### Task 4.1: Add `CategoryAggregates` helper

**Files:**
- Create: `Tenra/Views/Categories/CategoryAggregates.swift`
- Create: `TenraTests/Views/CategoryAggregatesTests.swift`

- [ ] **Step 1: Write the aggregates**

```swift
//
//  CategoryAggregates.swift
//  Tenra
//

import Foundation

struct CategoryAggregates {
    let amountInPeriod: Double      // in base currency
    let amountAllTime: Double       // in base currency
    let avgMonthlyLast6: Double     // in base currency
    let totalTransactions: Int
}

enum CategoryAggregatesCalculator {
    static func compute(
        categoryName: String,
        periodStart: Date,
        periodEnd: Date,
        baseCurrency: String,
        transactions: [Transaction]
    ) -> CategoryAggregates {
        let cal = Calendar.current
        let now = Date()
        let sixMonthsAgo = cal.date(byAdding: .month, value: -6, to: now) ?? now

        var amountPeriod = 0.0
        var amountAll = 0.0
        var amountLast6 = 0.0
        var count = 0
        var monthsSeenLast6 = Set<String>()

        for tx in transactions where tx.category == categoryName {
            count += 1
            let amount = convert(amount: tx.amount, from: tx.currency, to: baseCurrency, stored: tx.convertedAmount)
            amountAll += amount

            guard let date = DateFormatters.dateFormatter.date(from: tx.date) else { continue }
            if date >= periodStart && date <= periodEnd {
                amountPeriod += amount
            }
            if date >= sixMonthsAgo {
                amountLast6 += amount
                let ym = "\(cal.component(.year, from: date))-\(cal.component(.month, from: date))"
                monthsSeenLast6.insert(ym)
            }
        }

        let months = max(monthsSeenLast6.count, 1)
        let avg = amountLast6 / Double(months)

        return CategoryAggregates(
            amountInPeriod: amountPeriod,
            amountAllTime: amountAll,
            avgMonthlyLast6: avg,
            totalTransactions: count
        )
    }

    private static func convert(amount: Double, from: String, to: String, stored: Double?) -> Double {
        if from == to { return amount }
        if let converted = CurrencyConverter.convertSync(amount: amount, from: from, to: to) {
            return converted
        }
        return stored ?? amount
    }
}
```

- [ ] **Step 2: Write tests**

```swift
import XCTest
@testable import Tenra

final class CategoryAggregatesTests: XCTestCase {
    func test_emptyTransactions_returnsZeros() {
        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: Date(),
            periodEnd: Date(),
            baseCurrency: "USD",
            transactions: []
        )
        XCTAssertEqual(r.amountInPeriod, 0)
        XCTAssertEqual(r.amountAllTime, 0)
        XCTAssertEqual(r.avgMonthlyLast6, 0)
        XCTAssertEqual(r.totalTransactions, 0)
    }

    func test_sumsOnlyMatchingCategory() {
        let txs: [Transaction] = [
            makeTx(category: "Food", amount: 100, currency: "USD", date: "2026-04-10"),
            makeTx(category: "Food", amount: 200, currency: "USD", date: "2026-04-15"),
            makeTx(category: "Transport", amount: 999, currency: "USD", date: "2026-04-12"),
        ]
        let start = DateFormatters.dateFormatter.date(from: "2026-04-01")!
        let end = DateFormatters.dateFormatter.date(from: "2026-04-30")!

        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: start,
            periodEnd: end,
            baseCurrency: "USD",
            transactions: txs
        )
        XCTAssertEqual(r.totalTransactions, 2)
        XCTAssertEqual(r.amountInPeriod, 300)
        XCTAssertEqual(r.amountAllTime, 300)
    }

    private func makeTx(category: String, amount: Double, currency: String, date: String) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: date,
            description: "test",
            amount: amount,
            currency: currency,
            type: .expense,
            category: category
        )
    }
}
```

Adjust `Transaction` init to match the real signature (same caveat as Phase 3).

- [ ] **Step 3: Run tests**

### Task 4.2: Create `CategoryDetailView`

**Files:**
- Create: `Tenra/Views/Categories/CategoryDetailView.swift`

- [ ] **Step 1: Write the view**

Structure mirrors `AccountDetailView` — I won't re-paste the whole thing. Key differences:

- Dependencies: `transactionStore`, `transactionsViewModel`, `categoriesViewModel`, `accountsViewModel`, `category: CustomCategory`, `@Environment(TimeFilterManager.self) private var timeFilterManager`.
- `refreshTrigger` = count of `tx where tx.category == category.name`.
- `refreshData()` computes `cachedTransactions` (filtered by category name) + `aggregates` via `CategoryAggregatesCalculator.compute(...)` using `timeFilterManager.currentFilter.startDate` and `.endDate`.
- Hero:
  ```swift
  HeroSection(
      icon: category.iconSource,
      title: category.name,
      primaryAmount: aggregates.amountInPeriod,
      primaryCurrency: transactionsViewModel.appSettings.baseCurrency,
      subtitle: timeFilterManager.currentFilter.localizedName,
      progress: budgetProgress(),  // nil if no budget
      showBaseConversion: false
  )
  ```
- `budgetProgress()` → nil if `category.kind != .expense` or `category.budgetAmount == nil`. Otherwise:
  ```swift
  ProgressConfig(
      current: aggregates.amountInPeriod,
      total: category.budgetAmount!,
      label: String(localized: "category.detail.budget", defaultValue: "Budget"),
      color: budgetColor(utilization: aggregates.amountInPeriod / category.budgetAmount!)
  )
  ```
  where `budgetColor` = green (≤0.75), orange (≤1.0), red (>1.0).
- Info rows:
  - Type (expense / income)
  - Budget (only if expense + has budget): e.g. `"150 000 ₸ / 200 000 ₸ (75%)"`
  - Avg monthly (last 6 months) — base currency
  - Total transactions
  - Total amount, all time — base currency
  - Subcategories count (with chevron `→`) — implemented as `InfoRowConfig(..., trailing: AnyView(NavigationLink(...)))` OR wrap the row in a Button to navigate to `SubcategoriesManagementView`.
- Primary action: `Add transaction` (Add Transaction with `category.name` pre-filled — same TODO as Phase 3 if quick-add pre-fill doesn't exist).
- No secondary action.
- Toolbar menu:
  - Edit → `CategoryEditView`
  - Manage Subcategories → `SubcategoriesManagementView` (scoped to this category)
  - Delete → confirmation alert mentioning transaction count.

Wire `.sheet` / `.navigationDestination` attachments as needed. Preserve category filter history in the existing transactions flow — `cachedTransactions` is the local copy.

- [ ] **Step 2: Add localization keys**

Append to `en.lproj/Localizable.strings`:
```
"category.detail.actions.addTransaction" = "Add transaction";
"category.detail.totalSpent" = "Total spent";
"category.detail.totalEarned" = "Total earned";
"category.detail.avgMonthly" = "Avg. per month";
"category.detail.budget" = "Budget";
"category.detail.subcategories" = "Subcategories";
"category.detail.transactionCount" = "Transactions";
"category.detail.manageSubcategories" = "Manage subcategories";
"category.detail.delete.confirmTitle" = "Delete category?";
"category.detail.delete.confirmMessage" = "This will delete the category.";
```

Russian equivalents:
```
"category.detail.actions.addTransaction" = "Добавить транзакцию";
"category.detail.totalSpent" = "Всего потрачено";
"category.detail.totalEarned" = "Всего заработано";
"category.detail.avgMonthly" = "В среднем за месяц";
"category.detail.budget" = "Бюджет";
"category.detail.subcategories" = "Подкатегории";
"category.detail.transactionCount" = "Транзакций";
"category.detail.manageSubcategories" = "Управлять подкатегориями";
"category.detail.delete.confirmTitle" = "Удалить категорию?";
"category.detail.delete.confirmMessage" = "Категория будет удалена.";
```

### Task 4.3: Rewire `CategoriesManagementView` tap

**Files:**
- Modify: `Tenra/Views/Categories/CategoriesManagementView.swift`

- [ ] **Step 1: Locate the row tap target**

Grep for `CategoryEditView`, `NavigationLink`, `showingEdit`, `CategoryRow`. Identify the current edit-on-tap construct.

- [ ] **Step 2: Replace with navigation to `CategoryDetailView`**

```swift
NavigationLink {
    CategoryDetailView(
        transactionStore: transactionStore,
        transactionsViewModel: transactionsViewModel,
        categoriesViewModel: categoriesViewModel,
        accountsViewModel: accountsViewModel,
        category: category
    )
} label: {
    CategoryRow(/* existing */)
}
```

Add `TimeFilterManager` via environment if not already propagated to this view hierarchy.

- [ ] **Step 3: Build + verify**

### Task 4.4: Commit Phase 4

```bash
git add \
  Tenra/Views/Categories/CategoryAggregates.swift \
  Tenra/Views/Categories/CategoryDetailView.swift \
  Tenra/Views/Categories/CategoriesManagementView.swift \
  Tenra/en.lproj/Localizable.strings \
  Tenra/ru.lproj/Localizable.strings \
  TenraTests/Views/CategoryAggregatesTests.swift

git commit -m "$(cat <<'EOF'
feat(detail): CategoryDetailView with budget progress and period totals

Tap on a category now opens a detail screen scoped to the selected time
period, showing budget progress (when set), avg-monthly spend, and the
full history of transactions under that category.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5 — Migrate `DepositDetailView`

**Goal:** Port to `EntityDetailScaffold`. Move interest section into `customSections`. Remove the toolbar "history" icon and the separate `HistoryView` sheet — history is now inline.

### Task 5.1: Refactor `DepositDetailView`

**Files:**
- Modify: `Tenra/Views/Deposits/DepositDetailView.swift`

- [ ] **Step 1: Read and inventory existing behavior**

Read the full file. Note:
- `.task {}` reconciliation flow — preserved.
- Toolbar history icon — **removed**.
- Toolbar menu items (Edit / Change Rate / Link Interest / Recalculate / Delete) — preserved.
- Interest section (interest to today / next posting / rate / capitalization / posting day) — extracted into a private `@ViewBuilder` computed property.
- The existing separate `HistoryView` sheet attachment — **removed**.

- [ ] **Step 2: Compose scaffold**

```swift
var body: some View {
    let accountsById = Dictionary(uniqueKeysWithValues: transactionsViewModel.accounts.map { ($0.id, $0) })

    EntityDetailScaffold(
        navigationTitle: liveAccount.name,
        primaryAction: ActionConfig(
            title: String(localized: "deposit.detail.topUp", defaultValue: "Top up"),
            systemImage: "plus",
            action: { showingTopUp = true }
        ),
        secondaryAction: ActionConfig(
            title: String(localized: "deposit.detail.transferOut", defaultValue: "Transfer to account"),
            systemImage: "arrow.left.arrow.right",
            action: { showingTransferOut = true }
        ),
        infoRows: infoRowConfigs(),
        transactions: cachedTransactions,
        historyCurrency: liveAccount.currency,
        accountsById: accountsById,
        styleHelper: { tx in
            CategoryStyleHelper.cached(
                category: tx.category,
                type: tx.type,
                customCategories: categoriesViewModel.customCategories
            )
        },
        viewModel: transactionsViewModel,
        categoriesViewModel: categoriesViewModel,
        accountsViewModel: accountsViewModel,
        balanceCoordinator: accountsViewModel.balanceCoordinator,
        hero: {
            HeroSection(
                icon: liveAccount.iconSource,
                title: liveAccount.name,
                primaryAmount: liveAccount.balance,
                primaryCurrency: liveAccount.currency,
                subtitle: liveAccount.depositInfo?.bankName,
                showBaseConversion: true,
                baseCurrency: transactionsViewModel.appSettings.baseCurrency
            )
        },
        customSections: {
            interestSection.screenPadding()
        },
        toolbarMenu: { toolbarMenu }
    )
    // Existing sheets / alerts / task attachments
}
```

- [ ] **Step 3: Preserve reconciliation**

Keep `.task { await reconcileDepositInterest() }` verbatim on the scaffold.

- [ ] **Step 4: Refresh transaction cache**

Add `@State var cachedTransactions: [Transaction] = []` and a refresh pattern identical to `AccountDetailView`: filter `transactionStore.transactions` for `tx.accountId == account.id || tx.targetAccountId == account.id`, sort desc. Wire to `.task(id: refreshTrigger)`.

- [ ] **Step 5: Remove dead code**

Delete the old `HistoryView` sheet wiring and the toolbar's history icon button. Delete any inline transaction-list view if one existed.

- [ ] **Step 6: Build + manual test**

Open a deposit's detail. Verify:
- Hero, balance, bank name, converted amount.
- Interest section renders identically to before.
- Top Up / Transfer actions functional.
- Toolbar menu items all work.
- Transaction history appears inline below the interest section.

### Task 5.2: Commit Phase 5

```bash
git add Tenra/Views/Deposits/DepositDetailView.swift

git commit -m "$(cat <<'EOF'
refactor(detail): migrate DepositDetailView to EntityDetailScaffold

Interest breakdown moved to customSections slot. Transaction history is
now inline (history toolbar icon and separate HistoryView sheet removed).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6 — Migrate `LoanDetailView`

**Goal:** Port to scaffold. Move breakdown / stats / amortization into `customSections`. Surface loan progress in hero via `ProgressConfig`. Remove history toolbar icon.

### Task 6.1: Refactor `LoanDetailView`

**Files:**
- Modify: `Tenra/Views/Loans/LoanDetailView.swift`

- [ ] **Step 1: Read and inventory sections**

Loan detail has three existing cards: payment breakdown, stats, amortization schedule. Each is already a computed property or standalone `View`. They slot directly into `customSections` without internal changes.

- [ ] **Step 2: Compose scaffold**

Hero with `ProgressConfig`:

```swift
hero: {
    let info = liveAccount.loanInfo!
    let paid = info.originalPrincipal - info.remainingPrincipal
    HeroSection(
        icon: liveAccount.iconSource,
        title: liveAccount.name,
        primaryAmount: info.remainingPrincipal,
        primaryCurrency: liveAccount.currency,
        subtitle: nextPaymentSubtitle(),  // e.g. "Next payment 15 May"
        progress: ProgressConfig(
            current: paid,
            total: info.originalPrincipal,
            label: String(localized: "loan.detail.paidOff", defaultValue: "Paid off"),
            color: AppColors.accent
        ),
        showBaseConversion: true,
        baseCurrency: transactionsViewModel.appSettings.baseCurrency
    )
},
customSections: {
    VStack(spacing: AppSpacing.lg) {
        paymentBreakdownCard
        statsCard
        amortizationCard
    }
    .screenPadding()
}
```

Primary/secondary actions: `Make Payment` / `Early Repayment`.

- [ ] **Step 3: Remove history toolbar icon + sheet**

Same as deposit migration.

- [ ] **Step 4: Wire inline history**

`cachedTransactions` via same pattern — filter by `accountId == account.id || targetAccountId == account.id`.

- [ ] **Step 5: Build + manual test**

Verify:
- Hero shows remaining principal + % paid off bar.
- Payment breakdown / stats / amortization cards render unchanged.
- Make Payment / Early Repayment actions work.
- Toolbar menu items (edit / change rate / link / delete) work.
- Transaction history appears inline after amortization.

### Task 6.2: Add loan localization keys

Append to `en.lproj`:
```
"loan.detail.paidOff" = "Paid off";
"loan.detail.nextPayment" = "Next payment %@";
```
Russian:
```
"loan.detail.paidOff" = "Выплачено";
"loan.detail.nextPayment" = "Следующий платёж %@";
```

### Task 6.3: Commit Phase 6

```bash
git add \
  Tenra/Views/Loans/LoanDetailView.swift \
  Tenra/en.lproj/Localizable.strings \
  Tenra/ru.lproj/Localizable.strings

git commit -m "$(cat <<'EOF'
refactor(detail): migrate LoanDetailView to EntityDetailScaffold

Hero now shows % paid off via HeroSection's ProgressConfig. Payment
breakdown / stats / amortization preserved verbatim inside the scaffold's
customSections slot. History is inline.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 7 — Integrate `GroupedTransactionList` into `LinkPaymentsView`

**Goal:** Replace the internal `List { Section { ForEach } }` block (lines ~319–387) with `GroupedTransactionList` using a `rowOverlay` for the selection checkmark.

### Task 7.1: Add `tapAction` escape hatch to `TransactionCard`

**Files:**
- Modify: `Tenra/Views/Components/Cards/TransactionCard.swift`

- [ ] **Step 1: Inspect current tap behavior**

`TransactionCard` has a built-in `.onTapGesture` + `.sheet` that opens a transaction edit view. `LinkPaymentsView` wraps the card in a `Button` for selection — the inner gesture steals the tap. The fix: add an optional `tapAction` override.

- [ ] **Step 2: Add `tapAction` parameter**

Add to `TransactionCard`'s init:
```swift
let tapAction: (() -> Void)?
```

In the init parameter list, add:
```swift
tapAction: (() -> Void)? = nil
```

In the body, replace:
```swift
.onTapGesture {
    // open edit sheet
}
```
with:
```swift
.onTapGesture {
    if let tapAction {
        tapAction()
    } else {
        // existing open-edit-sheet behavior
    }
}
```

- [ ] **Step 3: Build + verify existing call sites unaffected**

Default is `nil`; all existing call sites continue with the built-in edit-sheet behavior.

### Task 7.2: Refactor `LinkPaymentsView` transaction list

**Files:**
- Modify: `Tenra/Views/Components/LinkPayments/LinkPaymentsView.swift`

- [ ] **Step 1: Identify the block to replace**

Lines ~319–387 contain a `List { Section { ForEach(cachedDateSections) { ... } } }` structure. That entire block is the replacement target.

- [ ] **Step 2: Replace with `GroupedTransactionList`**

Outside the checkbox rendering, selection state lives in `@State selectedIds: Set<String>`. Construct:

```swift
GroupedTransactionList(
    transactions: cachedFilteredCandidates,
    displayCurrency: nil,
    accountsById: accountsById,
    styleHelper: { tx in
        CategoryStyleHelper.cached(
            category: tx.category,
            type: tx.type,
            customCategories: categoriesViewModel.customCategories
        )
    },
    pageSize: 100,
    showCountBadge: true,
    viewModel: transactionsViewModel,
    categoriesViewModel: categoriesViewModel,
    accountsViewModel: accountsViewModel,
    balanceCoordinator: accountsViewModel.balanceCoordinator
) { tx in
    // rowOverlay — selection checkmark
    HStack {
        Spacer()
        Image(systemName: selectedIds.contains(tx.id) ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selectedIds.contains(tx.id) ? AppColors.accent : .secondary)
            .padding(.trailing, AppSpacing.lg)
    }
}
```

Wrap the card selection tap: either (a) pass `tapAction` into `TransactionCard` — but `TransactionCard` is instantiated inside `GroupedTransactionList`, so we can't override directly. Instead, the overlay absorbs taps:

```swift
.contentShape(Rectangle())
.onTapGesture {
    if selectedIds.contains(tx.id) {
        selectedIds.remove(tx.id)
    } else {
        selectedIds.insert(tx.id)
    }
}
```

Place the overlay Inside a `ZStack` with `.allowsHitTesting(true)` so the tap lands on the overlay, not the inner card.

**If this doesn't work cleanly** (i.e. the inner `TransactionCard` still consumes taps): add a `disableDefaultTap: Bool = false` parameter to `TransactionCard`, expose it through `GroupedTransactionList` as a pass-through, and let `LinkPaymentsView` set it to `true`. Then bind selection logic to the overlay's own `.onTapGesture`. Prefer the overlay solution; fall back to the pass-through if needed.

- [ ] **Step 3: Remove dead code**

Delete the old `List`/`Section`/`ForEach` block. Delete `cachedDateSections` if no longer referenced. Keep `cachedFilteredCandidates` (the data source), `selectedIds`, filters, action bar.

- [ ] **Step 4: Build + manual test**

Open Link Payments from a subscription, deposit (link interest), and loan. Verify:
- List renders grouped by date with the same headers as `HistoryView`.
- Tapping a row toggles the checkmark.
- Confirm button applies the link as before.
- Search + filter chips still narrow the list.

### Task 7.3: Commit Phase 7

```bash
git add \
  Tenra/Views/Components/Cards/TransactionCard.swift \
  Tenra/Views/Components/LinkPayments/LinkPaymentsView.swift

git commit -m "$(cat <<'EOF'
refactor(detail): use GroupedTransactionList inside LinkPaymentsView

Third parallel grouped-by-date transaction list replaced with the shared
component. Selection checkmark rendered via rowOverlay.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 8 — Align `HistoryView` visually

**Goal:** Ensure `HistoryView`'s section headers and row rendering use the same components (`DateSectionHeaderView(.compact)`, `TransactionCard`) as `GroupedTransactionList` so the three surfaces (history / detail / link-payments) look identical. No data-layer changes.

### Task 8.1: Inspect current header usage

**Files:**
- Modify (maybe): `Tenra/Views/Components/Cards/HistoryTransactionsList.swift`
- Modify (maybe): `Tenra/Views/History/HistoryView.swift`

- [ ] **Step 1: Read HistoryTransactionsList.swift**

Identify the section-header construct. If it's already `DateSectionHeaderView` (as the explore report suggests), there may be no changes needed — just confirm.

- [ ] **Step 2: If a different header style is used, switch to `.compact`**

Change only the header component. Do not touch the FRC-based data flow, pagination, or filtering.

- [ ] **Step 3: Build + visual comparison**

Place the three surfaces side-by-side mentally: global History, Subscription detail (after Phase 2 migration), Link Payments (after Phase 7). Headers and rows should look identical.

### Task 8.2: Commit Phase 8 (if any changes)

```bash
# If no changes were needed, skip the commit.

git add Tenra/Views/Components/Cards/HistoryTransactionsList.swift

git commit -m "$(cat <<'EOF'
style(history): align HistoryView section headers with shared component

Uses DateSectionHeaderView(.compact) to match GroupedTransactionList
and LinkPaymentsView.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 9 — Final sweep

**Goal:** Localization audit, empty-state polish, and any Russian-string review.

### Task 9.1: Localization audit

- [ ] **Step 1: Grep all new `String(localized: "...")` usages**

```bash
grep -rh 'String(localized: "' \
  Tenra/Views/Components/EntityDetail/ \
  Tenra/Views/Components/History/ \
  Tenra/Views/Accounts/AccountDetailView.swift \
  Tenra/Views/Categories/CategoryDetailView.swift \
  Tenra/Views/Subscriptions/SubscriptionDetailView.swift \
  Tenra/Views/Deposits/DepositDetailView.swift \
  Tenra/Views/Loans/LoanDetailView.swift \
  | sed -n 's/.*String(localized: "\([^"]*\)".*/\1/p' \
  | sort -u
```

- [ ] **Step 2: Confirm each key exists in both .strings files**

```bash
for KEY in $(above grep output); do
  grep -q "^\"$KEY\"" Tenra/en.lproj/Localizable.strings || echo "MISSING EN: $KEY"
  grep -q "^\"$KEY\"" Tenra/ru.lproj/Localizable.strings || echo "MISSING RU: $KEY"
done
```

Add any missing keys.

- [ ] **Step 3: Commit if changes**

```bash
git add Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "i18n(detail): finalize localization keys for entity-detail screens

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 9.2: Run full test suite

- [ ] **Step 1: Run all unit tests**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests
```

Expected: all tests pass. Fix any regressions before declaring the feature done.

- [ ] **Step 2: Manual smoke test**

Walk through each screen on simulator:
- Home carousel → tap regular account → `AccountDetailView` ✓
- AccountsManagementView → tap deposit → `DepositDetailView` (migrated) ✓
- AccountsManagementView → tap loan → `LoanDetailView` (migrated) ✓
- CategoriesManagementView → tap category → `CategoryDetailView` ✓
- Subscriptions list → tap subscription → `SubscriptionDetailView` (migrated) ✓
- LinkPayments from sub/deposit/loan → selects and confirms ✓
- Global History view → unchanged ✓

---

## Summary of deliverables

- **3 new shared components** under `Views/Components/EntityDetail/` + `Views/Components/History/`
- **2 new detail screens** (`AccountDetailView`, `CategoryDetailView`)
- **3 migrated detail screens** (`SubscriptionDetailView`, `DepositDetailView`, `LoanDetailView`)
- **1 refactored shared view** (`LinkPaymentsView`)
- **1 aligned view** (`HistoryView` — header consistency only)
- **~25 new localization keys** in EN + RU
- **2 new XCTest cases** covering account + category aggregates

All committed as 8–9 self-contained commits (Phase 9 may be empty).
