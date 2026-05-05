//
//  ImportTransactionPreviewView.swift
//  Tenra
//
//  Final step of the PDF/CSV import flow: review parsed transactions,
//  select which ones to import, assign accounts, and confirm.
//
//  Phase 16 (2026-02-17): Full localization, spring animations, BounceButtonStyle, accessibility
//  Moved from Views/Transactions/ → Views/Import/ (correct domain)
//  Renamed: TransactionPreviewView → ImportTransactionPreviewView
//

import SwiftUI

struct ImportTransactionPreviewView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    @Environment(TransactionStore.self) private var transactionStore
    let transactions: [Transaction]
    @Environment(\.dismiss) var dismiss

    @State private var selectedTransactions: Set<String> = Set()
    @State private var accountMapping: [String: String] = [:] // transactionId -> accountId

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: AppSpacing.sm) {
                    Text(String(format: String(localized: "transactionPreview.found"), transactions.count))
                        .font(AppTypography.h4)
                    Text(String(localized: "transactionPreview.selectHint"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .cardContentPadding()
                .frame(maxWidth: .infinity)
                .background(AppColors.surface)

                // Transaction list
                List {
                    ForEach(transactions) { transaction in
                        ImportTransactionPreviewRow(
                            transaction: transaction,
                            isSelected: selectedTransactions.contains(transaction.id),
                            selectedAccountId: accountMapping[transaction.id],
                            availableAccounts: accountsViewModel.accounts.filter { $0.currency == transaction.currency },
                            onToggle: {
                                withAnimation(AppAnimation.contentSpring) {
                                    if selectedTransactions.contains(transaction.id) {
                                        selectedTransactions.remove(transaction.id)
                                        accountMapping.removeValue(forKey: transaction.id)
                                    } else {
                                        selectedTransactions.insert(transaction.id)
                                        if let account = accountsViewModel.accounts.first(where: { $0.currency == transaction.currency }) {
                                            accountMapping[transaction.id] = account.id
                                        }
                                    }
                                }
                            },
                            onAccountSelect: { accountId in
                                accountMapping[transaction.id] = accountId
                            }
                        )
                    }
                }
                .listStyle(PlainListStyle())

                // Action buttons — Select All / Deselect All
                HStack(spacing: AppSpacing.md) {
                    Button {
                        withAnimation(AppAnimation.contentSpring) {
                            selectedTransactions = Set(transactions.map { $0.id })
                            for transaction in transactions {
                                if let account = accountsViewModel.accounts.first(where: { $0.currency == transaction.currency }) {
                                    accountMapping[transaction.id] = account.id
                                }
                            }
                        }
                    } label: {
                        Text("transactionPreview.selectAll")
                            .frame(maxWidth: .infinity)
                            .padding(AppSpacing.md)
                            .background(AppColors.accent.opacity(0.1))
                            .foregroundStyle(AppColors.accent)
                            .clipShape(.rect(cornerRadius: AppRadius.button))
                    }
                    .accessibilityLabel(String(localized: "transactionPreview.selectAll"))

                    Button {
                        withAnimation(AppAnimation.contentSpring) {
                            selectedTransactions.removeAll()
                            accountMapping.removeAll()
                        }
                    } label: {
                        Text("transactionPreview.deselectAll")
                            .frame(maxWidth: .infinity)
                            .padding(AppSpacing.md)
                            .background(AppColors.secondaryBackground)
                            .foregroundStyle(AppColors.textSecondary)
                            .clipShape(.rect(cornerRadius: AppRadius.button))
                    }
                    .accessibilityLabel(String(localized: "transactionPreview.deselectAll"))
                }
                .cardContentPadding()

                // Add selected button
                Button {
                    addSelectedTransactions()
                } label: {
                    Text(String(format: String(localized: "transactionPreview.addSelected"), selectedTransactions.count))
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.md)
                        .background(selectedTransactions.isEmpty ? AppColors.secondaryBackground : AppColors.accent)
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: AppRadius.button))
                }
                .buttonStyle(BounceButtonStyle())
                .disabled(selectedTransactions.isEmpty)
                .screenPadding()
                .padding(.bottom, AppSpacing.md)
                .accessibilityLabel(String(format: String(localized: "transactionPreview.addSelected"), selectedTransactions.count))
                .accessibilityAddTraits(selectedTransactions.isEmpty ? .isButton : [.isButton])
            }
            .navigationTitle(String(localized: "navigation.transactionPreview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                selectedTransactions = Set(transactions.map { $0.id })
                for transaction in transactions {
                    if let account = accountsViewModel.accounts.first(where: { $0.currency == transaction.currency }) {
                        accountMapping[transaction.id] = account.id
                    }
                }
            }
        }
    }

    private func addSelectedTransactions() {
        let transactionsToAdd = transactions.filter { selectedTransactions.contains($0.id) }

        Task {
            for transaction in transactionsToAdd {
                let accountId = accountMapping[transaction.id]
                let updatedTransaction = Transaction(
                    id: transaction.id,
                    date: transaction.date,
                    description: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    convertedAmount: transaction.convertedAmount,
                    type: transaction.type,
                    category: transaction.category,
                    subcategory: transaction.subcategory,
                    accountId: accountId,
                    targetAccountId: transaction.targetAccountId,
                    recurringSeriesId: transaction.recurringSeriesId,
                    recurringOccurrenceId: transaction.recurringOccurrenceId,
                    createdAt: transaction.createdAt
                )

                do {
                    _ = try await transactionStore.add(updatedTransaction)
                } catch {
                }
            }

            dismiss()
        }
    }
}

// MARK: - ImportTransactionPreviewRow

struct ImportTransactionPreviewRow: View {
    let transaction: Transaction
    let isSelected: Bool
    let selectedAccountId: String?
    let availableAccounts: [Account]
    let onToggle: () -> Void
    let onAccountSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                // Checkbox button with spring animation
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                        .font(AppTypography.h4)
                        .animation(AppAnimation.contentSpring, value: isSelected)
                }
                .accessibilityLabel(isSelected
                    ? String(localized: "button.select")
                    : String(localized: "transactionPreview.selectHint")
                )
                .accessibilityAddTraits(.isButton)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(transaction.description)
                        .font(AppTypography.body)
                        .fontWeight(.medium)

                    Text(transaction.date)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)

                    Text(transaction.category)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(AppColors.accent.opacity(0.1))
                        .clipShape(.rect(cornerRadius: AppRadius.xs))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    FormattedAmountText(
                        amount: transaction.amount,
                        currency: transaction.currency,
                        fontSize: AppTypography.body.weight(.semibold),
                        color: transaction.type == .income ? AppColors.income : AppColors.expense
                    )

                    Text(transactionTypeLabel)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // Account selector (visible only when selected)
            if isSelected && !availableAccounts.isEmpty {
                Picker(String(localized: "transactionPreview.account"), selection: Binding(
                    get: { selectedAccountId ?? "" },
                    set: { onAccountSelect($0) }
                )) {
                    Text("transactionPreview.noAccount").tag("")
                    ForEach(availableAccounts) { account in
                        Text("\(account.name) (\(Formatting.currencySymbol(for: account.currency)))").tag(account.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.leading, AppSpacing.xl)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var transactionTypeLabel: String {
        switch transaction.type {
        case .income: return String(localized: "transactionType.income")
        case .expense: return String(localized: "transactionType.expense")
        default: return String(localized: "transactionType.transfer")
        }
    }
}

// MARK: - Preview

#Preview("Empty") {
    let coordinator = AppCoordinator()
    ImportTransactionPreviewView(
        transactionsViewModel: coordinator.transactionsViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactions: []
    )
    .environment(coordinator.transactionStore)
}

#Preview("With Transactions") {
    let coordinator = AppCoordinator()
    let mockAccountId = "acc-kaspi"
    let sampleTransactions: [Transaction] = [
        Transaction(
            id: "prev-1",
            date: DateFormatters.dateFormatter.string(from: Date()),
            description: "Supermarket",
            amount: 8500,
            currency: "KZT",
            type: .expense,
            category: "Food",
            accountId: mockAccountId
        ),
        Transaction(
            id: "prev-2",
            date: DateFormatters.dateFormatter.string(from: Date().addingTimeInterval(-86400)),
            description: "Зарплата",
            amount: 450000,
            currency: "KZT",
            type: .income,
            category: "Salary",
            accountId: mockAccountId
        ),
        Transaction(
            id: "prev-3",
            date: DateFormatters.dateFormatter.string(from: Date().addingTimeInterval(-172800)),
            description: "Netflix",
            amount: 4990,
            currency: "KZT",
            type: .expense,
            category: "Subscriptions",
            accountId: mockAccountId
        )
    ]

    ImportTransactionPreviewView(
        transactionsViewModel: coordinator.transactionsViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactions: sampleTransactions
    )
    .environment(coordinator.transactionStore)
}
