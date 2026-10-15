# Refactor Map

## Screen → Extracted Views → Responsibility

### HistoryView
**Before:** 1171 lines, complex filtering/grouping logic in view
**After:** Modular with extracted components

**Extracted Components:**
- `HistoryFilterSection` → Filter chips row (time, account, category)
- `AccountFilterMenu` → Account dropdown filter
- `CategoryFilterButton` → Category filter button with icon
- `DateSectionHeader` → Date header with expense totals
- `TransactionIconView` → Category icon with recurring badge
- `TransactionInfoView` → Transaction details (category, subcategories, account)
- `TransferAccountInfo` → Account info for transfers
- `RegularAccountInfo` → Account info for regular transactions

**Responsibility:**
- Container: Layout and navigation
- Filter Section: User filtering controls
- Transaction List: Display grouped transactions
- Transaction Cards: Individual transaction display

### ContentView
**Before:** 714 lines, multiple sections mixed together
**After:** Uses reusable components

**Extracted Components:**
- `AccountCard` → Reusable account display
- `CardContainer` → Standard card wrapper
- (Analytics card logic remains but uses CardContainer)

**Responsibility:**
- Container: Main screen layout
- Accounts Section: Account cards horizontal scroll
- Analytics Card: Summary with progress bar
- Subscriptions Card: Subscription summary
- Quick Add: Category grid
- Primary Actions: Floating action buttons

### QuickAddTransactionView
**Before:** 643 lines, CoinView embedded
**After:** Uses CategoryChip component

**Extracted Components:**
- `CategoryChip` → Reusable category button (replaces CoinView)

**Responsibility:**
- Container: Category grid layout
- Category Chips: Category selection
- Add Transaction Modal: Transaction creation form

### TransactionCard
**Before:** ~440 lines, all logic in one view
**After:** Extracted subviews

**Extracted Components:**
- `TransactionIconView` → Icon display
- `TransactionInfoView` → Details display
- `TransferAccountInfo` → Transfer-specific info
- `RegularAccountInfo` → Regular transaction info

**Responsibility:**
- Display: Transaction information
- Interaction: Tap to edit, swipe actions
- Formatting: Amount display (handles transfers)

## Reusable Component Library

### Layout Components
- `CardContainer` → Standard card with material background, border, shadow

### Data Display Components
- `AccountCard` → Account information card
- `CategoryChip` → Category selection button
- `FilterChip` → Filter button/chip
- `DateSectionHeader` → Date section header with totals

### Transaction Components
- `TransactionIconView` → Transaction category icon
- `TransactionInfoView` → Transaction details
- `TransferAccountInfo` → Transfer account information
- `RegularAccountInfo` → Regular transaction account info

### Filter Components
- `HistoryFilterSection` → Complete filter section
- `AccountFilterMenu` → Account filter dropdown
- `CategoryFilterButton` → Category filter button

## Key Changes Reducing Recomputation

1. **Extracted Components**: Smaller views re-render only when their specific data changes
2. **Design Tokens**: Compile-time constants reduce runtime calculations
3. **Focused Views**: Each component has single responsibility
4. **Reduced Nesting**: Flatter view hierarchy improves performance
5. **Stable Identities**: Using proper IDs in ForEach

## Risks & TODOs

### Low Risk
- ✅ Component extraction (preserves behavior)
- ✅ UI consistency (visual identical)
- ✅ Design token usage (compile-time)

### Medium Risk
- ⚠️ CategoryChip totalText display (needs testing)
- ⚠️ Filter section extraction (verify all filters work)

### TODOs
- [ ] Move filtering logic to ViewModel (requires careful testing)
- [ ] Split TransactionsViewModel (large refactor)
- [ ] Add Equatable to TransactionCard
- [ ] Add more comprehensive previews
- [ ] Performance testing with large datasets
