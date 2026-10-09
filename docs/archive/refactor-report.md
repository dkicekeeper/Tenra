# SwiftUI Performance & Refactoring Report

## Step 1: Project Scan Results

### TOP-10 Heaviest / "God" SwiftUI Views

1. **HistoryView** (1171 lines) - Most complex view
   - Large body with multiple computed properties
   - Complex filtering, grouping, and sorting logic
   - Multiple nested conditionals and view builders
   - TransactionCard embedded (440+ lines)

2. **TransactionsViewModel** (1970 lines) - Massive view model
   - Too many responsibilities
   - Business logic mixed with data management

3. **ContentView** (714 lines) - Main screen
   - Multiple sections (accounts, analytics, subscriptions, quick add)
   - PDF processing logic
   - Wallpaper management
   - Many state variables

4. **AccountActionView** (451 lines)
   - Complex form with currency conversion
   - Multiple conditional sections

5. **VoiceInputConfirmationView** (367 lines)
   - Complex form with validation
   - Multiple state variables

6. **TransactionCard** (~440 lines, embedded in HistoryView)
   - Many computed properties (amountText, accessibilityText, transferAmountView)
   - Complex conditional rendering
   - Heavy formatting logic

7. **QuickAddTransactionView** (643 lines)
   - Category grid with caching
   - AddTransactionModal embedded (372 lines)

8. **SettingsView** (248 lines)
   - Multiple sections and modals

9. **AddTransactionModal** (372 lines, embedded in QuickAddTransactionView)
   - Complex form with subcategories

10. **SubscriptionsListView** - Moderate complexity

### Repeated UI Patterns

1. **Account Cards/Buttons**
   - AccountRadioButton (in QuickAddTransactionView, AccountActionView)
   - Account cards in ContentView (accountsSection)
   - Similar styling but duplicated code

2. **Category Chips/Buttons**
   - CategoryRadioButton (in AccountActionView)
   - CoinView (in QuickAddTransactionView)
   - Similar category display patterns

3. **Filter Chips**
   - Time filter chip (HistoryView, ContentView)
   - Account filter menu (HistoryView)
   - Category filter button (HistoryView)
   - Similar styling but not extracted

4. **Card Styles**
   - analyticsCard (ContentView)
   - subscriptionsCard (ContentView)
   - Similar card styling with gradients and shadows

5. **Empty States**
   - EmptyStateView exists but not used everywhere
   - Some views have custom empty states

6. **Date Headers**
   - dateHeader in HistoryView
   - Similar date formatting patterns

### SwiftUI Performance / Code-Smell Issues

#### 1. Heavy Computed Properties in `body`
- **HistoryView**: `filteredTransactions`, `groupedTransactions` - complex filtering/sorting on every render
- **TransactionCard**: `amountText`, `accessibilityText`, `transferAmountView` - heavy formatting
- **ContentView**: `analyticsCard` - complex VStack with calculations

#### 2. Overuse of `@ObservedObject`
- Many views observe entire `TransactionsViewModel` when they only need specific data
- **CoinView** receives full `viewModel` but only uses `customCategories`
- **TransactionCard** receives full `viewModel` but only uses it for subcategories lookup

#### 3. Inline Closures Recreating Frequently
- `ForEach` closures in HistoryView creating new views on every render
- Button actions defined inline in body

#### 4. Unstable Identity in Lists
- Some `ForEach` uses `\.self` for String arrays (categories) - should use stable IDs
- TransactionCard uses transaction.id (good) but could benefit from Equatable

#### 5. Excessive View Nesting
- HistoryView has deep nesting: VStack > ScrollView > List > Section > ForEach > TransactionCard
- ContentView has multiple nested conditionals

#### 6. Re-render Storms
- Multiple `onChange` handlers in HistoryView triggering updates
- `viewModel.allTransactions.count` changes trigger full re-renders
- Caching exists but could be improved

#### 7. Unnecessary Bindings
- Some `@State` variables could be derived from other state
- `debouncedSearchText` could be computed property

#### 8. Misuse of `onAppear`/`onChange`
- HistoryView has 7+ `onChange` handlers
- Some views call expensive operations in `onAppear` without debouncing

#### 9. Business Logic in Views
- Filtering logic in HistoryView (`filteredTransactions`, `groupedTransactions`)
- Sorting logic in HistoryView (`sortedKeys`)
- Date formatting scattered across views

#### 10. Passing Full ViewModels
- Child views receive entire `TransactionsViewModel` when they only need specific data
- Should pass only required data or use smaller view models

### UI Consistency Issues

1. **Spacing**: Some views use hardcoded values (16, 12, 8) instead of `AppSpacing`
2. **Corner Radius**: Inconsistent use (16, 20, 10) - should use `AppRadius`
3. **Shadows**: Some hardcoded, some use `AppShadow`
4. **Typography**: Mix of direct font usage and `AppTypography`
5. **Colors**: Some hardcoded colors instead of semantic colors

## Step 2: Refactoring Plan

### View Decomposition Strategy

#### HistoryView → Extract:
1. `HistoryFilterSection` - Filter chips row
2. `TransactionListSection` - List with grouping
3. `DateSectionHeader` - Date header with totals
4. `TransactionCard` - Already separate but needs optimization

#### ContentView → Extract:
1. `AccountsSectionView` - Horizontal scroll of accounts
2. `AnalyticsCardView` - History summary card
3. `SubscriptionsCardView` - Already exists
4. `QuickAddSectionView` - Already exists (QuickAddTransactionView)
5. `PrimaryActionButtons` - Floating action buttons

#### TransactionCard → Extract:
1. `TransactionIconView` - Category icon with recurring badge
2. `TransactionInfoView` - Category, subcategories, account info
3. `TransactionAmountView` - Amount display (handles transfers)

### Reusable Components to Create

1. `AccountCard` - Reusable account display
2. `CategoryChip` - Reusable category button/chip
3. `FilterChip` - Reusable filter button
4. `DateSectionHeader` - Reusable date header
5. `CardContainer` - Standard card wrapper

### MVVM Improvements

1. Move filtering logic from HistoryView to ViewModel
2. Move grouping logic from HistoryView to ViewModel
3. Move sorting logic from HistoryView to ViewModel
4. Create computed properties in VM for derived state
5. Pass only needed data to child views

### Performance Optimizations

1. Make TransactionCard Equatable
2. Use stable IDs in ForEach
3. Extract computed properties to avoid recalculation
4. Use LazyVStack where appropriate
5. Cache expensive computations in ViewModel
6. Reduce onChange handlers by combining related updates
