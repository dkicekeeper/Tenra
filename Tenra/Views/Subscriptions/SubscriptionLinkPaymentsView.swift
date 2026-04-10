//
//  SubscriptionLinkPaymentsView.swift
//  Tenra
//
//  Full-screen view for selecting existing transactions to link to a subscription.
//  Uses SubscriptionTransactionMatcher for auto-matching and TransactionStore
//  for linking on confirm.
//

import SwiftUI

struct SubscriptionLinkPaymentsView: View {
    let subscription: RecurringSeries
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    @Environment(TransactionStore.self) private var transactionStore
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [Transaction] = []
    @State private var selectedIds: Set<String> = []
    @State private var searchText = ""
    @State private var isLinking = false
    @State private var showError = false
    @State private var errorMessage = ""

    // Filters
    @State private var filterAccountId: String?
    @State private var useExactAmount = false
    @State private var filterCategoryNames: Set<String>?
    @State private var filterSubcategoryNames: Set<String>?
    @State private var showingCategoryFilter = false

    // MARK: - Computed Properties

    /// Resolve account name from live accounts or fallback to transaction.accountName
    private func resolveAccountName(for accountId: String) -> String {
        if let account = transactionStore.accounts.first(where: { $0.id == accountId }) {
            return account.name
        }
        // Deleted account — find name from any candidate transaction
        if let tx = candidates.first(where: { $0.accountId == accountId }) {
            return tx.accountName ?? accountId
        }
        return accountId
    }

    /// When search is empty — show auto-matched candidates.
    /// When search is active — search ALL unlinked expense transactions globally.
    private var filteredCandidates: [Transaction] {
        var result: [Transaction]
        if searchText.isEmpty {
            result = candidates
        } else {
            let query = searchText.lowercased()
            let allTx = transactionStore.transactions.filter { tx in
                tx.type == .expense
                && tx.currency == subscription.currency
                && tx.recurringSeriesId == nil
            }
            result = allTx.filter { tx in
                tx.description.lowercased().contains(query)
                || tx.category.lowercased().contains(query)
                || (tx.subcategory?.lowercased().contains(query) ?? false)
                || String(format: "%.0f", tx.amount).contains(query)
                || tx.date.contains(query)
            }
        }
        if let accountId = filterAccountId {
            result = result.filter { $0.accountId == accountId }
        }
        if let categoryNames = filterCategoryNames {
            result = result.filter { categoryNames.contains($0.category) }
        }
        if let subcategoryNames = filterSubcategoryNames {
            result = result.filter { tx in
                guard let sub = tx.subcategory else { return false }
                return subcategoryNames.contains(sub)
            }
        }
        return result
    }

    private var selectedTransactions: [Transaction] {
        candidates.filter { selectedIds.contains($0.id) }
    }

    private var selectedTotal: Double {
        selectedTransactions.reduce(0) { $0 + $1.amount }
    }

    private var uniqueAccountIds: [String] {
        Array(Set(candidates.compactMap(\.accountId))).sorted()
    }

    /// Unique expense category names from candidates
    private var candidateExpenseCategories: [String] {
        Array(Set(candidates.map(\.category))).sorted()
    }

    /// Unique subcategory names from candidates (non-nil only)
    private var candidateSubcategories: [String] {
        Array(Set(candidates.compactMap(\.subcategory))).sorted()
    }

    // MARK: - Date Sections

    private var dateSections: [(date: String, displayLabel: String, transactions: [Transaction])] {
        let grouped = Dictionary(grouping: filteredCandidates) { $0.date }
        return grouped.sorted { $0.key > $1.key }.map { key, txs in
            (date: key, displayLabel: displayDateKey(from: key), transactions: txs)
        }
    }

    // MARK: - Body

    var body: some View {
        transactionList
            .safeAreaBar(edge: .top) {
                filterHeader
            }
            .safeAreaBar(edge: .bottom) {
                actionBar
            }
            .navigationTitle(String(localized: "subscription.linkPayments.title", defaultValue: "Link Payments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(String(localized: "subscription.linkPayments.title", defaultValue: "Link Payments"))
                            .font(AppTypography.body.weight(.semibold))
                        Text(String(format: String(localized: "subscription.linkPayments.selectedWithAmount", defaultValue: "%d selected \u{00B7} %@"), selectedIds.count, Formatting.formatCurrency(selectedTotal, currency: subscription.currency)))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .task {
                loadCandidates()
            }
            .onChange(of: useExactAmount) { _, _ in
                loadCandidates()
            }
            .onChange(of: filterCategoryNames) { _, _ in
                loadCandidates()
            }
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
    }

    // MARK: - Filter Header

    private var filterHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            // Inline search field
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: AppIconSize.sm))

                TextField(
                    String(localized: "subscription.linkPayments.searchPlaceholder", defaultValue: "Search"),
                    text: $searchText
                )
                .font(AppTypography.body)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: AppIconSize.sm))
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.md))
            .padding(.horizontal, AppSpacing.lg)

            // Filter carousel
            UniversalCarousel(config: .filter) {
                // Amount mode toggle
                UniversalFilterButton(
                    title: useExactAmount
                        ? String(localized: "subscription.linkPayments.amountExact", defaultValue: "Exact")
                        : String(localized: "subscription.linkPayments.amountTolerance", defaultValue: "\u{00B1}10%"),
                    isSelected: useExactAmount,
                    showChevron: false,
                    onTap: { useExactAmount.toggle() }
                ) {
                    Image(systemName: useExactAmount ? "equal" : "plusminus")
                }

                // Account filter
                if uniqueAccountIds.count > 1 {
                    UniversalFilterButton(
                        title: filterAccountId == nil
                            ? String(localized: "subscription.filterAll", defaultValue: "All")
                            : resolveAccountName(for: filterAccountId!),
                        isSelected: filterAccountId != nil,
                        showChevron: true
                    ) {
                        Image(systemName: "creditcard")
                    } menuContent: {
                        Button {
                            filterAccountId = nil
                        } label: {
                            Label(String(localized: "subscription.filterAll", defaultValue: "All"), systemImage: filterAccountId == nil ? "checkmark" : "")
                        }
                        ForEach(uniqueAccountIds, id: \.self) { accountId in
                            Button {
                                filterAccountId = accountId
                            } label: {
                                Label(resolveAccountName(for: accountId), systemImage: filterAccountId == accountId ? "checkmark" : "")
                            }
                        }
                    }
                }

                // Category filter
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

                // Subcategory filter
                if !candidateSubcategories.isEmpty {
                    UniversalFilterButton(
                        title: subcategoryFilterTitle,
                        isSelected: filterSubcategoryNames != nil,
                        showChevron: true
                    ) {
                        Image(systemName: "tag")
                    } menuContent: {
                        Button {
                            filterSubcategoryNames = nil
                        } label: {
                            Label(String(localized: "subscription.filterAll", defaultValue: "All"), systemImage: filterSubcategoryNames == nil ? "checkmark" : "")
                        }
                        ForEach(candidateSubcategories, id: \.self) { subcategory in
                            Button {
                                if filterSubcategoryNames == nil {
                                    filterSubcategoryNames = [subcategory]
                                } else if filterSubcategoryNames!.contains(subcategory) {
                                    filterSubcategoryNames!.remove(subcategory)
                                    if filterSubcategoryNames!.isEmpty {
                                        filterSubcategoryNames = nil
                                    }
                                } else {
                                    filterSubcategoryNames!.insert(subcategory)
                                }
                            } label: {
                                Label(subcategory, systemImage: filterSubcategoryNames?.contains(subcategory) == true ? "checkmark" : "")
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }

    private var subcategoryFilterTitle: String {
        guard let names = filterSubcategoryNames else {
            return String(localized: "subscription.linkPayments.subcategories", defaultValue: "Subcategories")
        }
        if names.count == 1 {
            return names.first ?? String(localized: "subscription.linkPayments.subcategories", defaultValue: "Subcategories")
        }
        return String(format: String(localized: "subscription.linkPayments.subcategoriesCount", defaultValue: "%d subcategories"), names.count)
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        List {
            ForEach(dateSections, id: \.date) { section in
                Section {
                    ForEach(section.transactions) { transaction in
                        let isSelected = selectedIds.contains(transaction.id)
                        let styleData = CategoryStyleHelper.cached(
                            category: transaction.category,
                            type: transaction.type,
                            customCategories: categoriesViewModel.customCategories
                        )
                        let sourceAccount = accountsViewModel.accounts.first { $0.id == transaction.accountId }
                        let targetAccount = accountsViewModel.accounts.first { $0.id == transaction.targetAccountId }

                        Button {
                            if isSelected {
                                selectedIds.remove(transaction.id)
                            } else {
                                selectedIds.insert(transaction.id)
                            }
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? AppColors.accent : .secondary)
                                    .font(.system(size: AppIconSize.md))

                                TransactionCard(
                                    transaction: transaction,
                                    currency: subscription.currency,
                                    styleData: styleData,
                                    sourceAccount: sourceAccount,
                                    targetAccount: targetAccount
                                )
                                .allowsHitTesting(false)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(
                            top: AppSpacing.sm,
                            leading: AppSpacing.lg,
                            bottom: AppSpacing.sm,
                            trailing: AppSpacing.lg
                        ))
                    }
                } header: {
                    DateSectionHeaderView(dateKey: section.displayLabel)
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if filteredCandidates.isEmpty {
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
            // Button at bottom
            VStack(spacing: 0) {
                Button {
                    linkSelected()
                } label: {
                    if isLinking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(String(format: String(localized: "subscription.linkPayments.link", defaultValue: "Link %d Payments"), selectedIds.count))
                            .frame(maxWidth: .infinity)
                    }
                }
                .primaryButton(disabled: selectedIds.isEmpty || isLinking)
                .padding(AppSpacing.lg)
            }

            // Error banner above the button
            if showError {
                MessageBanner.error(errorMessage)
                    .padding(.horizontal, AppSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation(AppAnimation.contentSpring) {
                            showError = false
                        }
                    }
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(AppAnimation.contentSpring) {
                            showError = false
                        }
                    }
            }
        }
    }

    // MARK: - Helpers

    private func displayDateKey(from isoDate: String) -> String {
        guard let date = DateFormatters.dateFormatter.date(from: isoDate) else { return isoDate }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sectionDay = calendar.startOfDay(for: date)

        if sectionDay == today {
            return String(localized: "common.today", defaultValue: "Today")
        }
        if let diff = calendar.dateComponents([.day], from: sectionDay, to: today).day, diff == 1 {
            return String(localized: "common.yesterday", defaultValue: "Yesterday")
        }

        let currentYear = calendar.component(.year, from: Date())
        let sectionYear = calendar.component(.year, from: date)
        if sectionYear == currentYear {
            return DateFormatters.displayDateFormatter.string(from: date)
        }
        return DateFormatters.displayDateWithYearFormatter.string(from: date)
    }

    // MARK: - Actions

    private func loadCandidates() {
        var matched = SubscriptionTransactionMatcher.findCandidates(
            for: subscription,
            in: transactionStore.transactions,
            exactMatch: useExactAmount
        )
        // Apply category filter at candidate level so selection reflects filter
        if let categoryNames = filterCategoryNames {
            matched = matched.filter { categoryNames.contains($0.category) }
        }
        candidates = matched
        selectedIds = Set(matched.map(\.id))
    }

    private func linkSelected() {
        guard !selectedIds.isEmpty else { return }
        isLinking = true
        showError = false

        Task {
            do {
                try await transactionStore.linkTransactionsToSubscription(
                    seriesId: subscription.id,
                    transactions: selectedTransactions
                )
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
