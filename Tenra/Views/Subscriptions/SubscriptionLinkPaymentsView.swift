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
    @State private var filterAccountId: String?

    // MARK: - Computed Properties

    /// When search is empty -- show auto-matched candidates.
    /// When search is active -- search ALL unlinked expense transactions globally.
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
                if uniqueAccountIds.count > 1 {
                    accountFilter
                        .padding(.vertical, AppSpacing.sm)
                }
            }
            .safeAreaBar(edge: .bottom) {
                actionBar
            }
            .searchable(text: $searchText, prompt: String(localized: "subscription.linkPayments.search", defaultValue: "Search by description or amount"))
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
    }

    // MARK: - Account Filter

    private var accountFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                UniversalFilterButton(
                    title: String(localized: "subscription.filterAll", defaultValue: "All"),
                    isSelected: filterAccountId == nil,
                    showChevron: false,
                    onTap: { filterAccountId = nil }
                )

                ForEach(uniqueAccountIds, id: \.self) { accountId in
                    let accountName = transactionStore.accounts.first(where: { $0.id == accountId })?.name ?? accountId
                    UniversalFilterButton(
                        title: accountName,
                        isSelected: filterAccountId == accountId,
                        showChevron: false,
                        onTap: { filterAccountId = accountId }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
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
        .overlay(alignment: .top) {
            if showError {
                MessageBanner.error(errorMessage)
                    .padding(.horizontal, AppSpacing.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
        let matched = SubscriptionTransactionMatcher.findCandidates(
            for: subscription,
            in: transactionStore.transactions
        )
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
