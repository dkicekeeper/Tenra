# Design system: Tenra on DesignKit

Tokens and shared components live in the **DesignKit** package
([github.com/dkicekeeper/DesignKit](https://github.com/dkicekeeper/DesignKit)), shared with Dalada.
This file covers what is Tenra's own: how the app wires DesignKit, which views stay in Tenra and
why, how its screens are built, and its rules for amounts, dates, categories and motion. For a
token, a modifier or a component, read DesignKit's docs (§1).

*Checked against the code on 2026-10-12, DesignKit 3.5.0.*

## Contents

1. [Where things live](#1-where-things-live)
2. [DesignKitBridge](#2-designkitbridge)
3. [What stays in Tenra](#3-what-stays-in-tenra)
4. [Screen patterns](#4-screen-patterns)
5. [Amounts](#5-amounts)
6. [Dates, categories, transaction colours](#6-dates-categories-transaction-colours)
7. [Motion and effects](#7-motion-and-effects)
8. [Checklist for a UI change](#8-checklist-for-a-ui-change)

---

## 1. Where things live

| Looking for | Read in DesignKit |
|---|---|
| Tokens (`AppColors`, `AppSpacing`, `AppRadius`, `AppIconSize`, `AppTypography`, `AppAnimation`), modifiers (`cardStyle`, `screenPadding`, `filterChipStyle`, …), every component with its skeleton, the decision trees, the `cardStyle` padding contract, haptics, formatting internals | [design-system.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/design-system.md) (§0 is the inventory, §0.1 the host hooks) |
| Springs, transitions, effects, Reduce Motion, `AmbientMotionGate` | [motion.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/motion.md) |
| Charts, gauges, progress | [charts.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/charts.md) |
| Package and SwiftUI layout traps | [gotchas.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/gotchas.md) (Tenra's own: [gotchas.md](gotchas.md)) |
| Names that changed in 2.0 and were removed in 3.0 | [migration-2.0.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/migration-2.0.md), [migration-3.0.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/migration-3.0.md) |
| Localization keys the components read from Tenra's strings | [localization-keys.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/localization-keys.md) |

**What a component looks like:** the **DesignKit Gallery** app in TestFlight. Every public
component has a page with its styles, its states (the "Loading" state is its skeleton) and
controls for its parameters, in light and dark.

**Version.** Tenra pins an exact DesignKit version (`Tenra.xcodeproj` → Package Dependencies).
The **DesignKit update** workflow (`.github/workflows/designkit.yml`) checks for a new release
daily, builds, runs TenraTests and commits the bump to `main`. What each version added and
changed, and how to move to it, is DesignKit's
[CHANGELOG.md](https://github.com/dkicekeeper/DesignKit/blob/main/CHANGELOG.md) (the same text
is its release notes and the Gallery's Updates screen). A visual change is listed under
**Changed**, and the changed snapshot PNGs in its PR show exactly what changed: check it on
device.

**A shared component or token changes by DesignKit PR**, never by a copy in Tenra. DesignKit's CI
builds Tenra and Dalada against the change. Develop with Xcode's local package override: drag a
DesignKit checkout into the project.

**No raw design values** (`python3 scripts/design_lint.py`, CI `design-lint`): colours, fonts,
spacing, radii and animations come from the tokens. The baseline is empty, so any literal fails;
a justified exception carries `// design-lint:ignore <reason>`. A category's stored hex is data,
not a design value.

---

## 2. DesignKitBridge

[`Tenra/Utils/DesignKitBridge.swift`](../Tenra/Utils/DesignKitBridge.swift) is the seam:

- **Re-exports** `DesignTokens`, `DesignSupport` and `DesignComponents` (`@_exported import`):
  every Tenra file and TenraTests see DesignKit with no per-file imports.
- **`DesignKitBridge.configure()`**, called once from `TenraApp.init()`, wires the host hooks:

  | Hook | Tenra's side |
  |---|---|
  | `DesignKitFonts.registerIfNeeded()` | Inter from DesignKit's bundle; Tenra has no font files or `UIAppFonts` |
  | `DesignKitLogoLoader.loader` | `LogoService.logoImage(brandName:)`: brand logos in `Icon(source: .brandService)`, `.heroAccentGlow`, `DominantColorExtractor` |
  | `DesignKitCurrencyConverter.convert` / `.convertSync` | `CurrencyConverter` (async, and instant from cached rates while the user types) |
  | `DesignKitLogoCatalog.sections` / `.search` / `.domainSuffixes` | `ServiceLogoRegistry` for the icon picker's brands tab; typed names try `.com` and `.kz` |

  `DesignKitTheme.accent` keeps DesignKit's default, system indigo (= Tenra's `AccentColor`):
  Tenra's look is DesignKit's reference.
- **Adapters over Tenra models**, as extensions: `CategoryColors.color(for:opacity:customCategories:)`
  and `(store:)` (custom category colours), the `IconSource` brand registry,
  `DonutSlice.from([CategoryBreakdownItem])` and `.from([SubcategoryBreakdownItem], baseColor:)`,
  `LimitProgress(BudgetProgress)` (a budget as a ring), and `InsightsStatCard where Trend ==
  InsightsStatTrend` (the stat card's sparkline).

---

## 3. What stays in Tenra

Every component that can be generic lives in DesignKit, even if only Tenra uses it (owner's
decision, 2026-10). `Tenra/Views/Components/` keeps two kinds of views:

- **Adapters**: a view under its old Tenra name that maps a Tenra model onto a DesignKit
  component and keeps the tap, swipe, navigation and VoiceOver copy. No layout of their own.
- **Parts of screens and flows**: views that read a store, a ViewModel, a service or
  `AppCoordinator`, or drive navigation.

| Folder | Adapters (→ DesignKit component) | Screen parts |
|---|---|---|
| `Cards` | `AccountCard` → `BalanceCard`, `CategoryChip` → `ProgressRingTile`, `CategoryGradientBackground` → `AuroraBackground`, `HealthScoreCardView` → `ScoreCard`, `HealthScoreHeroCard` → `ScoreGaugeCard`, `HealthScoreWeightingCard` → `WeightBreakdownCard`, `HealthComponentCard` → `TargetProgressCard`, `InsightFormulaCard` → `CalculationCard`, `InsightsCardView` → `MetricCard`, `InsightsTotalsCard` → `TotalsCard`, `LoanCard` → `PayoffProgressCard`, `PeriodComparisonCard` → `ComparisonCard`, `SubscriptionCard` → `RecurringPaymentCard`, `TransactionCardView` → `TransactionRow`, `TransactionsSummaryCard` → `CashFlowCard` | `TransactionCard` (tap → edit, swipe, context menu), `HistoryTransactionsList`, the Finances cards (`AccountsCardView`, `DepositsCardView`, `SubscriptionsCardView`, `LoansCardView`, `CategoriesCardView`, `SubcategoriesCardView`) |
| `Charts` | `PeriodChartAdapters` (`PeriodDataPoint: ChartPoint`, `PeriodChartSeries` → `ChartSeries`) | |
| `EntityDetail` | | `EntityDetailScaffold` |
| `Feedback` | `AnimatedTranscriptionText` → `StreamingText`, `InsightTrendBadge` → `TrendBadge`, `LoanTypeBadge` / `LoanMonthStatusBadge` → `Badge`, `StatusIndicatorBadge` (status mapping) | `RatingSurveyView`, `ExportActivityView` |
| `Forms` | `EditableHeroSection` → `EditableHero` | `BudgetSettingsSection`, the loan and deposit sheets (§4) |
| `Headers` | | `InsightsSectionView` |
| `History` | | `GroupedTransactionList` |
| `Icons` | `IconPickerView` → `IconPicker` | |
| `Input` | `AccountRadioButton` → `SelectableBalanceCard`, `AmountInputView` → `CurrencyAmountInput`, `CurrencySelectorView` → `CurrencyPickerMenu`, `SubscriptionCalendarView` → `MonthCalendar` | the filter sheets, the selectors, carousels and grids that load data, `HomeBackgroundPicker`, the import sheets |
| `LinkPayments` | | `LinkPaymentsView` |
| `Rows` | `AccountRow` / `CategoryRow` / `CategoryBreakdownRow` → `AmountRow`, `AmortizationScheduleRow` → `ScheduleRow`, `BudgetProgressRow` → `LimitProgressCard`, `MenuPickerRow` (domain inits) | `PeriodBreakdownRow` |

Each file's header comment names what it adapts. Tenra keeps its screens over its own models by
choice: filter sheets, home sections, transaction lists, entity detail screens, the lock screen,
`PremiumLockedView`.

---

## 4. Screen patterns

Build a new screen from the closest pattern. Every one is made of DesignKit pieces; the structure
is Tenra's.

### Entity edit sheet (hero form)

`AccountEditView`, `CategoryEditView`, `SubscriptionEditView`, `DepositEditView`, `LoanEditView`,
`OnboardingAccountStep`.

```
EditSheetContainer(title:, wrapInForm: false, onSave:, onCancel:)   ✕ and ✓ in the toolbar
└── ScrollView
    └── VStack(spacing: AppSpacing.xl)
        ├── EditableHeroSection(…)           icon (opens the picker), name, optional amount
        ├── FormSection(header:) {           a card of rows, dividers inset by AppSpacing.lg
        │   UniversalRow / MenuPickerRow / DatePickerRow / FormTextField(style: .inline)
        │   }
        └── FormSection(…) { … }
```

Entity heroes type on the system keyboard: they are forms, not calculators.

### Action sheet (rate change, pay all)

`LoanRateChangeView`, `DepositRateChangeView`, `LoanPayAllView`. The same container and cards
without a hero: `EditSheetContainer(wrapInForm: false)` → `ScrollView` → a `FormSection` with the
fields, then a conditional impact `FormSection`. **Tenra has no system `Form` sheets left:**
`wrapInForm: true` is unused, and a new sheet is built from cards.

### Money entry (calculator)

`TransactionAddModal`, `TransactionEditView`, `AccountActionView`, `LoanPaymentView`,
`LoanEarlyRepaymentView`: a `ScrollView` with `HeroSection`, `AmountInputView(calculatorModel:)`,
the source and category selectors under `SectionHeader`s and `FormSection`s for the rest, with the
`CalculatorKeypad` in `.safeAreaInset(edge: .bottom)`. Rules in §5.

### Entity detail

`AccountDetailView`, `CategoryDetailView`, `SubscriptionDetailView`, `DepositDetailView`,
`LoanDetailView`, all through `EntityDetailScaffold`:

```
ScrollView
└── VStack(spacing: AppSpacing.lg)
    ├── hero (HeroSection)         .screenPadding().scrollHero()
    ├── actions bar                primary + secondary DSButton
    ├── info rows card             InfoRow list in .cardStyle()
    ├── custom sections            the screen's own cards
    └── GroupedTransactionList     day headers SectionHeader (default style), TransactionCard rows
+ .heroAccentGlow(icon:tint:) on the screen; the title and amount appear in the nav bar once the
  hero scrolls out; the toolbar menu (edit, delete, …)
```

### Lists

- **Management** (`AccountsManagementView`, `CategoriesManagementView`): `List` of `AccountRow` /
  `CategoryRow`, `.onMove` while reordering, swipe to delete in the row adapter.
- **Cards** (`SubscriptionsListView`, `LoansListView`): `ScrollView` of `SubscriptionCard` /
  `LoanCard` in `NavigationLink`s, `EmptyState` when there are none.
- **Deposits** (`DepositsListView`): `List` of `AccountRow`; `AmountRowSkeleton(style: .list)`
  rows while loading, replaced through `.transition(.skeletonReveal)` (§7).
- **Subcategories** (`SubcategoriesManagementView`): `List` of `SubcategoryManagementRow`, a
  plain `Button` over `ItemRow(style: .large, titleFont: AppTypography.h4)` with the usage in a
  `MetaLine` ("Used 14 times · Oct 9, 2026").

### History

`HistoryTransactionsList`: a `List` of day `Section`s whose header is
`SectionHeader(day, style: .card) { day total }` and whose rows are
`TransactionCard(…).equatable()` with `listRowInsets`. `TransactionCard` adds the edit sheet,
swipe and context menu to `TransactionCardView`, which maps the transaction onto DesignKit's
`TransactionRow`. Sections are sliced with an infinite-scroll trigger: 500+ sections in a `List`
freeze (CLAUDE.md rule #4). Per-row data (style, accounts) is resolved at the `ForEach` (§6).

### Settings

`List` of `Section(header: SectionHeader(title, style: .compact))` with
`UniversalRow(config: .settings)` rows: `.navigationRow {}`, `.actionRow(role:) {}` or a trailing
`Toggle`. The list insets the rows, so `.settings` has no horizontal padding of its own.

- **Backups** (`BackupRowView`): `ItemRow(style: .large)` with the date, the "Auto" badge, a
  `MetaLine` of counts and size, and the restore arrow as its accessory; tap restores, swipe
  deletes.
- **Quick-access currencies** (`QuickAccessCurrencyPickerView`): DesignKit's `CurrencyRow`, the
  row `CurrencyList` draws; an account's currency with `isLocked: true` (grey check), the others
  in a plain `Button` with `.contentShape(Rectangle())`.

### Tabs

- **Home** (`ContentView`): `ScrollView` → `VStack(spacing: AppSpacing.lg)`: `AccountsCarousel`
  (`AccountCard` = `BalanceCard(isLive: true)`) or `EmptyCard`; `TransactionsSummaryCard` in a
  `NavigationLink` to History (`.buttonStyle(.bounce)`); the category grid
  (`TransactionCategoryPickerView`). Background by the user's choice: none, the spending gradient
  (`CategoryGradientBackground`, still) or a wallpaper.
- **Finances** (`FinancesView`): `ScrollView` of `FinanceCard` summaries (accounts, deposits,
  subscriptions, loans, categories, subcategories), each with `PackedCircleIcons` in the default
  `.glossy` style. The `.fan` and `.orbit` styles (DesignKit 3.3.0) are not used: the owner keeps
  the marbles.
- **Analytics** (`InsightsView`): sections through `InsightsSectionView`
  (`SectionHeader(title, systemImage:, style: .large)`); detail screens put
  `SectionHeader(style: .large)` over their charts.
- **Filter sheets** (`AccountFilterView`, `CategoryFilterView`, `TimeFilterView`):
  `SectionHeader(title)` (default style) over selectable rows.

### Search

System search only (CLAUDE.md): `.searchable` places the field (History: the bottom bar,
`.searchToolbarBehavior(.minimize)`), and DesignKit's `.dsSearchSuggestions` (3.5.0) puts the
recent queries and suggestions in the system's own suggestion list. Each screen keeps its
`RecentSearches` with `@AppStorage` under its own key:

| Screen | Recent queries key | Suggestions |
|---|---|---|
| History (`HistorySearchSuggestions`) | `history.recentSearches` | the user's categories and subcategories (the search matches them by name; accounts are left out, the text search does not match them) |
| `LinkPaymentsView` | `linkPayments.recentSearches` | none |
| `SubcategorySearchView` | `subcategorySearch.recentSearches` | none |

The suggestions cover the screen while the field is focused and something matches; a tap fills
the field and hides them until the text changes, so the live list shows again.

### Empty, loading, error

- Loading: the component's `<Name>Skeleton` in its place, not a `ProgressView()`.
- Empty: `EmptyState` (`.standard` on a screen, `.compact` in a card, `.error` for a failure).
- A card that switches between empty and loaded animates the switch:

```swift
if items.isEmpty {
    EmptyState(…).transition(.opacity)
} else {
    loadedContent.transition(.opacity)
}
// outside the conditional
.animation(AppAnimation.gentleSpring, value: items.isEmpty)
```

---

## 5. Amounts

### Hard rule

**A money value never reaches the user without a canonical formatter** (CLAUDE.md rule #7). No
exceptions for temporary code, debug screens or committed previews. Every type below is
DesignKit's (`DesignSupport`, `DesignComponents`) except `AmountInputView`; the internals, the
overflow policy and the formatter cache are in DesignKit's design-system.md §6 and §12.

### What to use

```
Rendering a money amount?
├── Standalone view (card, header, a row's trailing amount, chart label)
│   └── FormattedAmountText(amount:currency:prefix:fontSize:fontWeight:color:)
├── Label-value row in a detail screen
│   ├── One amount → InfoRow(… amount:, currency:, prefix:) / InfoRowConfig(… amount:, currency:)
│   └── Composite ("X / Y (Z%)", "spent / budget", "+A · −B")
│       → InfoRowConfig(… value: "<VoiceOver text>", valueContent: AnyView(
│             HStack { FormattedAmountText(…); Text("/"); FormattedAmountText(…) }))
│         never Text("\(spent) / \(total)"): the amounts lose smart decimals and the dimmed .XX
├── A String is needed (HeroSection.subtitle, a sentence, accessibilityLabel)
│   └── Formatting.formatCurrencySmart(amount, currency:)
├── The user types an amount
│   └── AmountInputView (Tenra) over CurrencyAmountInput / AmountInput; never bypass
│       AmountInputFormatting
├── Compact chart axis label
│   └── ChartValueFormat.compactString(amount)
├── Storage, CSV, search key, persistence
│   └── AmountFormatter.format(_:) / .parse(_:)
└── A NumberFormatter in a List / ForEach
    └── AmountDisplayConfiguration.formatter (cached; never .makeNumberFormatter())
```

### Overflow

`FormattedAmountText` handles a narrow container itself (`AmountDisplayPolicy.adaptive`, the
default): the full number, then "1,2 млн ₸", then "1 млн ₸". A value that fits always renders in
full, and VoiceOver always reads the full amount. Never pre-shorten with
`Formatting.formatCurrencyCompact` at the call site. `.full` is for amount editors and the
calculator display, `.compact` for very tight chrome.

### Sign and prefix

- Negative is automatic: `-1 200 ₸` for a negative `Double`.
- Positive needs `prefix: "+"`: `prefix: diff > 0 ? "+" : ""` on `FormattedAmountText` or `InfoRow`.
- Income and expense in transaction lists: `TransactionDisplayHelper.amountPrefix(for:)` and
  `.amountColor(for:)` (§6), passed to `FormattedAmountText`.

### Forbidden (flagged in review)

| Pattern | Why | Use |
|---|---|---|
| `Text("\(amount) \(currency)")` | no grouping, no symbol, no smart decimals | `FormattedAmountText` |
| `Text(String(format: "%.2f", amount))` | no currency, ignores the locale | `FormattedAmountText` / `formatCurrencySmart` |
| `String(format: "%@%@", "+", Formatting.formatCurrency(…))` | hand-built sign | `prefix: "+"` |
| `NumberFormatter()` in `body` / `List` / `ForEach` | an allocation per frame | `AmountDisplayConfiguration.formatter` |
| `Formatting.formatCurrency(…)` for display | always shows `.00` ("14 924 515.00 ₸") | `formatCurrencySmart` / `FormattedAmountText`; `formatCurrency` is for VoiceOver and storage |
| A `Decimal` in string interpolation | no symbol, no grouping | `NSDecimalNumber(decimal:).doubleValue` into a formatter |

### Calculator input

`AmountInputView(calculatorModel:)` swaps the system keyboard for DesignKit's `CalculatorKeypad`
over `CalculatorInputModel` (its `ExpressionEvaluator`: `+ − × ÷` on `Decimal`, no `=`, a live
result). Used in `TransactionAddModal`, `TransactionEditView`, `AccountActionView`,
`LoanPaymentView`, `LoanEarlyRepaymentView`.

- The host owns `@State CalculatorInputModel`, puts `CalculatorKeypad` in
  `.safeAreaInset(edge: .bottom)` and mirrors `calc.amountText` into its form's amount with
  `.onChange` (validation, save and conversion keep reading that binding).
- Pre-fill with `CalculatorInputModel(seed:)` at init, or `.seed(_:)` in `onAppear` for a default
  computed late.
- ⚠️ **A sheet with the keypad and an inline `FormTextField` (the note) coordinates focus, or two
  keyboards stack.** The host keeps `@FocusState descriptionFocused`, passes
  `externalFocus: $descriptionFocused` to the field, shows the keypad only
  `if !descriptionFocused`, and sets it to `false` from `AmountInputView(onCalculatorTap:)`.

---

## 6. Dates, categories, transaction colours

These helpers are Tenra's (`Tenra/Utils`): they read Tenra models.

**Dates** (`DateFormatters`, cached, `nonisolated`):

| Member | Format | For |
|---|---|---|
| `dateFormatter` | `yyyy-MM-dd` | storage, parsing |
| `displayDateFormatter` | `d MMMM` (device locale) | display |
| `displayDateWithYearFormatter` | `d MMMM yyyy` | display with the year |
| `displayDateOmittingCurrentYear(_:)` | the year only outside the current one | next-charge dates and the like |
| `displayString(from:)` | ISO string → `d MMMM` | a stored date string |
| `timeFormatter` | `HH:mm` | time |

**Category style.** Resolve it at the `ForEach`, not inside the row:

```swift
let styleData = CategoryStyleHelper.cached(
    category: tx.category,
    type: tx.type,
    customCategories: customCategories
)
// pass styleData (an Equatable struct) to TransactionCard
```

`CategoryStyleCache.shared` holds the results; a category edit drops its entry with
`invalidateCategory(_:type:)`. Category colours in DesignKit components come through
`CategoryColors.color(for:opacity:customCategories:)` (§2).

**Transaction amount colour and sign.** `TransactionDisplayHelper.amountColor(for:)` and
`.amountPrefix(for:)`; the deposit-aware overloads take `targetAccountId`, `depositAccountId` and
`isPlanned`. Future-dated rows dim through `displayOpacity(for:)`.

---

## 7. Motion and effects

The rules are DesignKit's ([motion.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/motion.md)):

- Animations come from `AppAnimation`: `.snappy` answers a touch, `.smooth` is content that
  changes. No bare `withAnimation {}`, `.easeInOut(duration:)` or inline `.spring(…)`.
- Movement goes through the Reduce Motion aware tokens or
  `@Environment(\.accessibilityReduceMotion)`; opacity-only fades stay under Reduce Motion.
- A `TimelineView` decoration that never ends goes behind `AmbientMotionGate` and draws a still
  frame when the gate is closed.

Where each DesignKit effect is used in Tenra, so a new screen reuses the pattern:

| Where | Effect | Rule |
|---|---|---|
| Home background | `AuroraBackground` by spending (`CategoryGradientBackground`) | **still**: a moving background under Liquid Glass redraws every glass card each frame |
| Accounts carousel | `BalanceCard(isLive: true)` | rolls up once per card identity; flashes the direction of a change |
| Financial health hero | `ScoreGaugeCard(decodesScore: true, style: .hero, showsMaximum: true)` (DesignKit 4.2.0: edge to edge, a gauge wider than the screen, on a gradient of the grade colour; the weighting card rises over its end), with a trend in points against the score at the end of last month (4.3.0, `FinancialHealthScore.previousScore`) | not on the feed's `HealthScoreCardView`: a lazy feed would replay it on scroll |
| Savings rate detail | `SavingsRateHeroCard` over `ScoreGaugeCard(value:unit: "%", style: .hero)` (4.3.0): the rate on 0–40% with the 10% and 20% marks, its band, the saved amount; in place of the header and the hero gauge, the formula card rises over its end; `entranceDelay` waits for the zoom into the detail | the insight's feed card keeps its mini gauge |
| Insight details | DesignKit 4.5.0: the header (`HeroSection` with its trend) and the hero visual on `.heroBackground(insight.severity.color)`, edge to edge from the screen's top edge (`.heroScrollEdge()` on the scroll view; 4.5.1); in dark mode a deep gradient with the pieces in white, in light mode a pale tint with black text (4.5.1); the chart and detail cards rise over the gradient's end. A long amount shrinks inside the gauge's arc (4.5.1). Large expense: `LargeTransactionHeroCard` over `ScoreGaugeCard(amount:…norm:)`, the expense against the usual one ("13,9× the usual"). Budget headroom: `BudgetHeadroomHeroCard`, what is left of the budgets ("left of 380 000 ₸") | the colour is the insight's tone; the paged category breakdown keeps its own layout |
| Entity detail | `.scrollHero()` on the hero (from `EntityDetailScaffold`), `.heroAccentGlow` on the screen | every detail screen; the glow's colour comes from the hero icon |
| Voice screen | `EdgeGlow`, `VoiceWave(style: .orb)` stop button, `.thinkingShimmer`, `StreamingText`, `.cascadeIn`, `.borderBeam` on the live card, a one-time `.spotlight` | [domains/voice.md](domains/voice.md) |
| Loan detail | `.celebration` on the false → true edge of `isPaidOffLoan`, with the banner and the haptic | the moment only, never the state |
| Detail histories (`GroupedTransactionList`), voice cards | `.dissolve` removal, opacity insertion | for deleting something the person owned, not every disappearance |
| One-time hints | `.spotlight` + `FeatureTourState` | points at content the person can see, not at system chrome (tab bar, toolbar) |
| Settings, Tenra Pro | `.shine` once each time the purchase row appears; `.holographic()` on the Active / Founder badge | foil only on the badge, so the row's taps stay the row's |
| Toasts (`MessageBanner` over a screen), selection checkmarks in edit mode | `.transition(.popIn)` | edge-attached bars keep `.move(edge: .bottom)` |
| A list replacing its skeleton (accounts, deposits, link payments) | content `.transition(.skeletonReveal)`, skeleton `.transition(.opacity)`, `.animation(AppAnimation.smooth, value: <is loading>)` on the container | the Insights feed keeps its `ContentRevealModifier` |
| Finances cards | `PackedCircleIcons(style: .shelf)` (DesignKit 4.4.0): app icons in a row in a pocket, a light running across them; `FinanceCard` centres them in the card (4.5.0); 36 pt tiles in every card, the largest that fit and a "+N" for the rest, the row at the card's trailing edge (4.5.1) | no `.orbit` |
| Assistant | `ParticleCreature` (DesignKit 4.6.0; a sphere of light without glass since 4.7.0): interactive hero in the greeting, 120 pt under the navigation bar in a thread, `.compact` next to the working step and on "Ten writes" cards; the action tab is `CreatureTabLabel` (4.8.0, the still `CreatureGlyph`) with the unread count as its badge, the field `MessageComposer(leading:onVoice:)` with a paperclip `MessageComposerAccessory` and the microphone; questions in `MessageBubble`, reply text as `ArticleBody` (Markdown split by `AgentReplyMarkdown`, streamed as it is written), a 120 pt `ParticleCreature` under the navigation bar in a thread, recent chats as `ItemRow`s in a card, presets and follow-ups in `SuggestionChips`, reply blocks with `.cascadeIn`, the working step with `.thinkingShimmer`; the voice sheet reuses the voice screen's `EdgeGlow`, stop orb and `StreamingText`; attachment and confirm cards are `AssistantCard` (a `cardStyle()` card under an optional `SectionHeader`) with `InfoRow`, `InlineStatusText` and a full-width `DSButton`; "Ask Ten" on other screens shows `CreatureGlyph.templateImage(size:)` | the mascot's mood follows the screen (thinking while it works, the reply's mood after, confused or sad on a failure); one still frame under Reduce Motion; since 4.7.0 it has no glass: the particles, a thin lit rim and a soft halo, drawn in coloured ink on a light page and glowing on a dark one, over a soft blurred shadow |

---

## 8. Checklist for a UI change

1. Look for the component in the DesignKit Gallery and in DesignKit's design-system.md §0 first.
2. Missing, or needs a new parameter → a DesignKit PR (the porting checklist in its CLAUDE.md:
   neutral name, skeleton, Gallery page, snapshot test), then a thin adapter here if it takes a
   Tenra model.
3. Build the screen from the closest pattern in §4; amounts per §5.
4. Strings in all 11 locales (CLAUDE.md rule #13); no em dashes in user-facing text.
5. `python3 scripts/design_lint.py` passes.
6. Don't change a shipped screen's layout as a side effect; the owner checks UI on device.
