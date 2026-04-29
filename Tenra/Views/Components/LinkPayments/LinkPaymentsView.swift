//
//  LinkPaymentsView.swift
//  Tenra
//
//  Reusable full-screen picker for linking existing transactions to a
//  subscription, loan, or any future owner entity. Handles:
//    • Amount-mode / account / category / subcategory filters via sheet pickers
//    • Native `.searchable` with debounce
//    • @State-cached derived data (filteredCandidates, dateSections,
//      accountById, areAllFilteredSelected, selectedTotalInBaseCurrency)
//    • Baseline scan off MainActor via `Task.detached`
//    • LazyVStack-equivalent via SwiftUI `List` with section pagination
//
//  Callers pass a `findCandidates` closure bound to their owner entity
//  (series/loan) and a `performLink` closure that persists the selection.
//

import SwiftUI

struct LinkPaymentsView: View {

    // MARK: - Configuration

    struct Options {
        /// Show the amount-mode chip (All / ±30% / Exact).
        var showAmountModeFilter: Bool = true
        /// Show the category filter chip.
        var showCategoryFilter: Bool = true
        /// Show the subcategory filter chip (only rendered when candidates have subcategories).
        var showSubcategoryFilter: Bool = true
        /// Initial amount-match mode.
        var defaultAmountMode: AmountMatchMode = .tolerance
        /// Auto-select all candidates on initial load.
        var autoSelectOnInitialLoad: Bool = true

        static let subscription = Options()
        static let loan = Options(
            showCategoryFilter: true,
            showSubcategoryFilter: true,
            defaultAmountMode: .tolerance,
            autoSelectOnInitialLoad: true
        )
        /// Deposit interest: income amounts vary widely with principal growth,
        /// so a broad default (`.all`) is friendlier than `.tolerance`.
        /// Don't auto-select — user picks explicitly.
        static let deposit = Options(
            showCategoryFilter: false,
            showSubcategoryFilter: false,
            defaultAmountMode: .all,
            autoSelectOnInitialLoad: false
        )
    }

    // MARK: - Inputs

    let title: String
    /// Displayed under the nav title: `%d selected · %@` in base currency.
    /// Pass the context currency used in `TransactionCard` for per-row display.
    let displayCurrency: String
    /// Closure bound to the caller's owner entity.
    let findCandidates: @Sendable ([Transaction], AmountMatchMode) -> [Transaction]
    /// Persist the selection. Called when the user taps the primary action.
    let performLink: @Sendable ([Transaction]) async throws -> Void
    var options: Options = .subscription

    // Dependencies
    let transactionStore: TransactionStore
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var candidates: [Transaction] = []
    @State private var baseline: [Transaction] = []
    @State private var selectedIds: Set<String> = []
    @State private var searchText = ""

    // Cached derived data — rebuilt via `rebuildDerivedCaches()` on input changes only.
    @State private var cachedFilteredCandidates: [Transaction] = []
    @State private var cachedAreAllFilteredSelected: Bool = false
    @State private var cachedAccountById: [String: Account] = [:]
    @State private var cachedSelectedTotalInBaseCurrency: Double = 0
    // Caches for filter-header / sheet-presented collections. Previously these were computed
    // properties that ran 3 Set-allocations × O(candidates) on every body re-eval.
    @State private var cachedUniqueAccountIds: [String] = []
    @State private var cachedCandidateExpenseCategories: [String] = []
    @State private var cachedCandidateSubcategories: [String] = []
    @State private var cachedCandidateAccounts: [Account] = []

    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var isBaselineLoading = false
    @State private var isLinking = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isInitialLoad = true

    // Filter state
    @State private var filterAccountId: String?
    @State private var amountMode: AmountMatchMode = .tolerance
    @State private var filterCategoryNames: Set<String>?
    @State private var filterSubcategoryNames: Set<String>?

    // Sheet toggles
    @State private var showingCategoryFilter = false
    @State private var showingAccountFilter = false
    @State private var showingSubcategoryFilter = false

    // MARK: - Body

    var body: some View {
        transactionList
            .safeAreaBar(edge: .top) {
                filterHeader
            }
            .safeAreaBar(edge: .bottom) {
                actionBar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title)
                            .font(AppTypography.body.weight(.semibold))
                        Text(String(format: String(localized: "subscription.linkPayments.selectedWithAmount", defaultValue: "%d selected \u{00B7} %@"), selectedIds.count, Formatting.formatCurrency(cachedSelectedTotalInBaseCurrency, currency: transactionStore.baseCurrency)))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(String(localized: "subscription.linkPayments.searchPlaceholder", defaultValue: "Search"))
            )
            .task {
                amountMode = options.defaultAmountMode
                reloadBaseline()
            }
            .onChange(of: amountMode) { _, _ in reloadBaseline() }
            .onChange(of: filterCategoryNames) { _, _ in applyFilters() }
            .onChange(of: filterSubcategoryNames) { _, _ in applyFilters() }
            .onChange(of: searchText) { _, _ in handleSearchChanged() }
            .onChange(of: selectedIds) { _, _ in
                cachedAreAllFilteredSelected = !cachedFilteredCandidates.isEmpty
                    && cachedFilteredCandidates.allSatisfy { selectedIds.contains($0.id) }
                recomputeSelectedTotal()
            }
            .onChange(of: filterAccountId) { _, _ in rebuildDerivedCaches() }
            .sheet(isPresented: $showingCategoryFilter) {
                CategoryFilterView(
                    expenseCategories: candidateExpenseCategories,
                    incomeCategories: [],
                    customCategories: categoriesViewModel.customCategories,
                    currentFilter: filterCategoryNames,
                    onFilterChanged: { newFilter in
                        filterCategoryNames = newFilter
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingAccountFilter) {
                AccountFilterView(
                    accounts: candidateAccounts,
                    selectedAccountId: $filterAccountId,
                    balanceCoordinator: accountsViewModel.balanceCoordinator
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingSubcategoryFilter) {
                TransactionSubcategoryFilterSheet(
                    subcategories: candidateSubcategories,
                    selectedNames: $filterSubcategoryNames
                )
                .presentationDetents([.medium, .large])
            }
    }

    // MARK: - Derived Data (Cached @State accessors)
    // These were previously computed properties — each body re-eval allocated 3+ Sets across
    // up to ~1000 candidates. Now they're rebuilt once per `applyFilters()` call inside
    // `rebuildDerivedCaches()` and read directly from @State.

    private var uniqueAccountIds: [String] { cachedUniqueAccountIds }
    private var candidateExpenseCategories: [String] { cachedCandidateExpenseCategories }
    private var candidateSubcategories: [String] { cachedCandidateSubcategories }
    private var candidateAccounts: [Account] { cachedCandidateAccounts }

    private var selectedTransactions: [Transaction] {
        cachedFilteredCandidates.filter { selectedIds.contains($0.id) }
    }

    private func resolveAccountName(for accountId: String) -> String {
        if let account = accountsViewModel.accounts.first(where: { $0.id == accountId }) {
            return account.name
        }
        if let account = transactionStore.accounts.first(where: { $0.id == accountId }) {
            return account.name
        }
        if let tx = candidates.first(where: { $0.accountId == accountId }),
           let name = tx.accountName, !name.isEmpty {
            return name
        }
        if let tx = transactionStore.transactions.first(where: { $0.accountId == accountId }),
           let name = tx.accountName, !name.isEmpty {
            return name
        }
        return String(localized: "subscription.linkPayments.unknownAccount", defaultValue: "Unknown account")
    }

    // MARK: - Filter Header

    private var filterHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            UniversalCarousel(config: .filter) {
                if options.showAmountModeFilter {
                    UniversalFilterButton(
                        title: title(for: amountMode),
                        isSelected: amountMode != options.defaultAmountMode,
                        showChevron: true
                    ) {
                        Image(systemName: amountModeIcon)
                    } menuContent: {
                        ForEach(AmountMatchMode.allCases, id: \.self) { mode in
                            Button {
                                amountMode = mode
                            } label: {
                                Label(title(for: mode), systemImage: amountMode == mode ? "checkmark" : "")
                            }
                        }
                    }
                }

                if uniqueAccountIds.count > 1 {
                    UniversalFilterButton(
                        title: accountFilterTitle,
                        isSelected: filterAccountId != nil,
                        showChevron: true,
                        onTap: { showingAccountFilter = true }
                    )
                }

                if options.showCategoryFilter {
                    UniversalFilterButton(
                        title: CategoryFilterHelper.displayText(for: filterCategoryNames),
                        isSelected: filterCategoryNames != nil,
                        onTap: { showingCategoryFilter = true }
                    ) {
                        CategoryFilterHelper.iconView(
                            for: filterCategoryNames,
                            customCategories: categoriesViewModel.customCategories,
                            incomeCategories: []
                        )
                    }
                }

                if options.showSubcategoryFilter && !candidateSubcategories.isEmpty {
                    UniversalFilterButton(
                        title: subcategoryFilterTitle,
                        isSelected: filterSubcategoryNames != nil,
                        showChevron: true,
                        onTap: { showingSubcategoryFilter = true }
                    )
                }
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Filter titles / icons

    private func title(for mode: AmountMatchMode) -> String {
        switch mode {
        case .all:       return String(localized: "subscription.linkPayments.amountAll", defaultValue: "All")
        case .tolerance: return String(localized: "subscription.linkPayments.amountTolerance", defaultValue: "\u{00B1}30%")
        case .exact:     return String(localized: "subscription.linkPayments.amountExact", defaultValue: "Exact")
        }
    }

    private var amountModeIcon: String {
        switch amountMode {
        case .all:       return "infinity"
        case .tolerance: return "plusminus"
        case .exact:     return "equal"
        }
    }

    private var subcategoryFilterTitle: String {
        guard let names = filterSubcategoryNames else {
            return String(localized: "filter.allSubcategories", defaultValue: "All subcategories")
        }
        if names.count == 1 {
            return names.first ?? String(localized: "filter.allSubcategories", defaultValue: "All subcategories")
        }
        return String(format: String(localized: "subscription.linkPayments.subcategoriesCount", defaultValue: "%d subcategories"), names.count)
    }

    private var accountFilterTitle: String {
        if let id = filterAccountId {
            return resolveAccountName(for: id)
        }
        return String(localized: "filter.allAccounts", defaultValue: "All accounts")
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        let baseCurrency = transactionStore.baseCurrency
        return ScrollView {
            if !cachedFilteredCandidates.isEmpty {
                GroupedTransactionList(
                    transactions: cachedFilteredCandidates,
                    displayCurrency: displayCurrency,
                    accountsById: cachedAccountById,
                    styleHelper: { tx in
                        CategoryStyleHelper.cached(
                            category: tx.category,
                            type: tx.type,
                            customCategories: categoriesViewModel.customCategories
                        )
                    },
                    pageSize: 100,
                    showCountBadge: true,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    balanceCoordinator: accountsViewModel.balanceCoordinator,
                    tapAction: { tx in
                        if selectedIds.contains(tx.id) {
                            selectedIds.remove(tx.id)
                        } else {
                            selectedIds.insert(tx.id)
                        }
                        HapticManager.selection()
                    },
                    summaryCurrencyOverride: baseCurrency,
                    summaryAmountFor: { tx in
                        if tx.currency == baseCurrency { return tx.amount }
                        if let converted = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) {
                            return converted
                        }
                        return tx.convertedAmount ?? tx.amount
                    },
                    rowOverlay: { tx in
                        Image(systemName: selectedIds.contains(tx.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedIds.contains(tx.id) ? AppColors.accent : .secondary)
                            .font(.system(size: AppIconSize.md))
                            .padding(.leading, AppSpacing.md)
                    }
                )
                .screenPadding()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if isBaselineLoading && cachedFilteredCandidates.isEmpty {
                ProgressView()
            } else if cachedFilteredCandidates.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "subscription.linkPayments.empty", defaultValue: "No matching transactions"), systemImage: "doc.text.magnifyingglass")
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                HStack(spacing: AppSpacing.sm) {
                    Button(action: toggleSelectAll) {
                        Text(cachedAreAllFilteredSelected
                             ? String(localized: "subscription.linkPayments.deselectAll", defaultValue: "Deselect All")
                             : String(localized: "subscription.linkPayments.selectAll", defaultValue: "Select All"))
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryButton()
                    .disabled(cachedFilteredCandidates.isEmpty)

                    Button {
                        linkSelected()
                    } label: {
                        if isLinking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(String(format: String(localized: "subscription.linkPayments.link", defaultValue: "Link %d"), selectedIds.count))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .primaryButton(disabled: selectedIds.isEmpty || isLinking)
                }
                .padding(AppSpacing.lg)
            }

            if showError {
                MessageBanner.error(errorMessage)
                    .padding(.horizontal, AppSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation(AppAnimation.contentSpring) { showError = false }
                    }
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(AppAnimation.contentSpring) { showError = false }
                    }
            }
        }
    }

    // MARK: - Pipeline

    /// Rebuild the amount-mode baseline off MainActor so the UI doesn't freeze on open.
    private func reloadBaseline() {
        isBaselineLoading = true
        let allTransactions = transactionStore.transactions
        let mode = amountMode
        let matcher = findCandidates

        Task.detached(priority: .userInitiated) {
            let matched = matcher(allTransactions, mode)
            await MainActor.run {
                self.baseline = matched
                self.isBaselineLoading = false
                self.applyFilters()
            }
        }
    }

    /// Apply cheap in-memory filters over the cached baseline.
    private func applyFilters() {
        var matched = baseline

        if let categoryNames = filterCategoryNames {
            matched = matched.filter { categoryNames.contains($0.category) }
        }
        if let subcategoryNames = filterSubcategoryNames {
            matched = matched.filter { tx in
                guard let sub = tx.subcategory else { return false }
                return subcategoryNames.contains(sub)
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            matched = matched.filter { tx in
                tx.description.lowercased().contains(query)
                    || tx.category.lowercased().contains(query)
                    || (tx.subcategory?.lowercased().contains(query) ?? false)
                    || String(format: "%.0f", tx.amount).contains(query)
                    || tx.date.contains(query)
            }
        }
        candidates = matched

        if isInitialLoad {
            if options.autoSelectOnInitialLoad {
                selectedIds = Set(matched.map(\.id))
            }
            isInitialLoad = false
        } else {
            let candidateIds = Set(matched.map(\.id))
            selectedIds = selectedIds.intersection(candidateIds)
        }
        rebuildDerivedCaches()
    }

    private func rebuildDerivedCaches() {
        let filtered: [Transaction]
        if let accountId = filterAccountId {
            filtered = candidates.filter { $0.accountId == accountId }
        } else {
            filtered = candidates
        }
        cachedFilteredCandidates = filtered

        cachedAreAllFilteredSelected = !filtered.isEmpty && filtered.allSatisfy { selectedIds.contains($0.id) }

        // Reuse the store's O(1) accountById index — no need to allocate a fresh dict on each
        // filter change. Only sync if the store's account count changed since last rebuild.
        if cachedAccountById.count != transactionStore.accountById.count {
            cachedAccountById = transactionStore.accountById
        }

        rebuildCandidateCollectionCaches()
        recomputeSelectedTotal()
    }

    /// Rebuilds derived collections that depend on `candidates` only. Called from the same
    /// path as `rebuildDerivedCaches()` so the two stay in sync.
    private func rebuildCandidateCollectionCaches() {
        var accountIdSet = Set<String>()
        var categorySet = Set<String>()
        var subcategorySet = Set<String>()
        // First sighting per accountId for the fallback Account fabrication path
        var firstCurrencyByAccountId: [String: String] = [:]
        for tx in candidates {
            if let aid = tx.accountId {
                accountIdSet.insert(aid)
                if firstCurrencyByAccountId[aid] == nil {
                    firstCurrencyByAccountId[aid] = tx.currency
                }
            }
            categorySet.insert(tx.category)
            if let sub = tx.subcategory { subcategorySet.insert(sub) }
        }
        let sortedAccountIds = accountIdSet.sorted()
        cachedUniqueAccountIds = sortedAccountIds
        cachedCandidateExpenseCategories = categorySet.sorted()
        cachedCandidateSubcategories = subcategorySet.sorted()
        // Build candidate accounts using O(1) dict lookups — replaces 2× `accounts.first(where:)`
        // per id (was O(N×M) where N=accounts, M=candidates).
        cachedCandidateAccounts = sortedAccountIds.map { id in
            if let a = transactionStore.accountById[id] { return a }
            let name = resolveAccountName(for: id)
            let currency = firstCurrencyByAccountId[id] ?? displayCurrency
            return Account(id: id, name: name, currency: currency)
        }
    }

    private func recomputeSelectedTotal() {
        let base = transactionStore.baseCurrency
        let idSet = selectedIds
        var total = 0.0
        for tx in candidates where idSet.contains(tx.id) {
            if tx.currency == base {
                total += tx.amount
            } else if let converted = tx.convertedAmount {
                total += converted
            } else if let fx = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: base) {
                total += fx
            } else {
                total += tx.amount
            }
        }
        cachedSelectedTotalInBaseCurrency = total
    }

    private func handleSearchChanged() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            applyFilters()
        }
    }

    // MARK: - Actions

    private func toggleSelectAll() {
        let filteredIds = cachedFilteredCandidates.map(\.id)
        if cachedAreAllFilteredSelected {
            selectedIds.subtract(filteredIds)
        } else {
            selectedIds.formUnion(filteredIds)
        }
        HapticManager.selection()
    }

    private func linkSelected() {
        guard !selectedIds.isEmpty else { return }
        let selection = selectedTransactions
        isLinking = true
        showError = false

        Task {
            do {
                try await performLink(selection)
                isLinking = false
                dismiss()
            } catch {
                isLinking = false
                errorMessage = error.localizedDescription
                withAnimation(AppAnimation.contentSpring) {
                    showError = true
                }
            }
        }
    }
}

// MARK: - Subcategory Filter Sheet

/// Multi-select subcategory filter sheet — mirrors the look of `AccountFilterView`.
struct TransactionSubcategoryFilterSheet: View {
    let subcategories: [String]
    @Binding var selectedNames: Set<String>?

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    UniversalRow(config: .settings) {
                        Text(String(localized: "subscription.filterAll", defaultValue: "All"))
                            .font(AppTypography.h4)
                            .fontWeight(.medium)
                    } trailing: {
                        if selectedNames == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    .selectableRow(isSelected: selectedNames == nil) {
                        HapticManager.selection()
                        selectedNames = nil
                    }
                }

                Section {
                    ForEach(subcategories, id: \.self) { name in
                        let isSelected = selectedNames?.contains(name) == true
                        UniversalRow(
                            config: .settings,
                            leadingIcon: .sfSymbol("tag", color: AppColors.accent, size: AppIconSize.md)
                        ) {
                            Text(name)
                                .font(AppTypography.h4)
                                .fontWeight(.medium)
                        } trailing: {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                        .selectableRow(isSelected: isSelected) {
                            HapticManager.selection()
                            toggle(name)
                        }
                    }
                } header: {
                    SectionHeaderView(String(localized: "subscription.linkPayments.subcategories", defaultValue: "Subcategories"))
                }
            }
            .navigationTitle(String(localized: "subscription.linkPayments.subcategories", defaultValue: "Subcategories"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    private func toggle(_ name: String) {
        var current = selectedNames ?? []
        if current.contains(name) {
            current.remove(name)
        } else {
            current.insert(name)
        }
        selectedNames = current.isEmpty ? nil : current
    }
}
