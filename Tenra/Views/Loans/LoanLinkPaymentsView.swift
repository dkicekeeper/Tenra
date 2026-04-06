//
//  LoanLinkPaymentsView.swift
//  Tenra
//
//  Sheet view for selecting existing transactions to link to a loan.
//  Uses LoanTransactionMatcher for auto-matching and LoansViewModel
//  for conversion on confirm.
//

import SwiftUI

struct LoanLinkPaymentsView: View {
    let loan: Account
    let transactionStore: TransactionStore
    let loansViewModel: LoansViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [Transaction] = []
    @State private var selectedIds: Set<String> = []
    @State private var searchText = ""
    @State private var isLinking = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var filterAccountId: String?

    // MARK: - Computed Properties

    private var filteredCandidates: [Transaction] {
        var result = candidates
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.description.lowercased().contains(query)
                || String(format: "%.0f", $0.amount).contains(query)
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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summarySection
                searchBar
                if uniqueAccountIds.count > 1 {
                    accountFilter
                }
                transactionList
                actionBar
            }
            .navigationTitle(String(localized: "loan.linkPayments.title", defaultValue: "Link Payments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .task {
                loadCandidates()
            }
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(String(format: String(localized: "loan.linkPayments.selected", defaultValue: "%d selected"), selectedIds.count))
                .font(AppTypography.h4)
            Text(Formatting.formatCurrency(selectedTotal, currency: loan.currency))
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondaryAccessible)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "loan.linkPayments.search", defaultValue: "Search by description or amount"),
                text: $searchText
            )
            .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(AppSpacing.sm)
        .padding(.horizontal, AppSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.md))
        .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Account Filter

    private var accountFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                UniversalFilterButton(
                    title: String(localized: "loan.filterAll", defaultValue: "All"),
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
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        List {
            ForEach(filteredCandidates) { tx in
                transactionRow(tx)
                    .listRowInsets(EdgeInsets(
                        top: AppSpacing.sm,
                        leading: AppSpacing.lg,
                        bottom: AppSpacing.sm,
                        trailing: AppSpacing.lg
                    ))
            }
        }
        .listStyle(.plain)
        .overlay {
            if candidates.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "loan.linkPayments.empty", defaultValue: "No matching transactions"), systemImage: "doc.text.magnifyingglass")
                }
            } else if filteredCandidates.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        let isSelected = selectedIds.contains(tx.id)
        return Button {
            if isSelected {
                selectedIds.remove(tx.id)
            } else {
                selectedIds.insert(tx.id)
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppColors.accent : .secondary)
                    .font(.system(size: AppIconSize.md))

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(tx.description)
                        .font(AppTypography.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(DateFormatters.displayString(from: tx.date))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(Formatting.formatCurrency(tx.amount, currency: tx.currency))
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                linkSelected()
            } label: {
                if isLinking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(String(format: String(localized: "loan.linkPayments.link", defaultValue: "Link %d Payments"), selectedIds.count))
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

    // MARK: - Actions

    private func loadCandidates() {
        let matched = LoanTransactionMatcher.findCandidates(
            for: loan,
            in: transactionStore.transactions
        )
        candidates = matched
        // Pre-select all auto-matched candidates
        selectedIds = Set(matched.map(\.id))
    }

    private func linkSelected() {
        guard !selectedIds.isEmpty else { return }
        isLinking = true
        showError = false

        Task {
            do {
                try await loansViewModel.linkTransactions(
                    toLoan: loan.id,
                    transactions: selectedTransactions,
                    transactionStore: transactionStore
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
