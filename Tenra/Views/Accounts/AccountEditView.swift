//
//  AccountEditView.swift
//  AIFinanceManager
//
//  Migrated to hero-style UI (Phase 16 - 2026-02-16)
//  Uses EditableHeroSection with inline balance and currency editing
//

import SwiftUI

struct AccountEditView: View {
    let accountsViewModel: AccountsViewModel
    let transactionsViewModel: TransactionsViewModel
    let account: Account?
    let onSave: (Account) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var balanceText: String = ""
    @State private var initialBalanceText: String = "" // snapshot of balanceText set on appear — detects user edits
    @State private var currency: String = "USD"
    @State private var selectedIconSource: IconSource? = nil
    @State private var validationError: String? = nil

    private var parsedBalance: Double {
        if balanceText.isEmpty { return 0.0 }
        guard let decimal = AmountFormatter.parse(balanceText) else { return 0.0 }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

    /// True when user actually edited the balance text field (not just format→parse round-trip)
    private var balanceWasEdited: Bool {
        balanceText != initialBalanceText
    }

    var body: some View {
        EditSheetContainer(
            title: account == nil ? String(localized: "modal.newAccount") : String(localized: "modal.editAccount"),
            isSaveDisabled: name.isEmpty,
            wrapInForm: false,
            onSave: saveAccount,
            onCancel: onCancel
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Hero Section with Icon, Name, Balance, and Currency
                    EditableHeroSection(
                        iconSource: $selectedIconSource,
                        title: $name,
                        balance: $balanceText,
                        currency: $currency,
                        titlePlaceholder: String(localized: "account.namePlaceholder"),
                        config: .accountHero,
                        currencies: AppSettings.availableCurrencies
                    )

                    // Validation Error
                    if let error = validationError {
                        InlineStatusText(message: error, type: .error)
                            .padding(.horizontal, AppSpacing.lg)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            }
        }
        .onAppear {
            if let account = account {
                name = account.name
                // Show current balance (not initialBalance) so user sees real value
                let formatted = AmountFormatter.format(Decimal(account.balance))
                balanceText = formatted
                initialBalanceText = formatted
                currency = account.currency
                selectedIconSource = account.iconSource
            } else {
                currency = transactionsViewModel.appSettings.baseCurrency
                selectedIconSource = nil
                balanceText = ""
            }
        }
    }

    // MARK: - Save Account

    private func saveAccount() {
        // Validate name
        guard !name.isEmpty else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "error.accountNameRequired")
            }
            HapticManager.error()
            return
        }

        // Clear validation error
        validationError = nil

        let newAccount: Account
        if let existing = account, !balanceWasEdited {
            // Balance not edited — copy existing account and update only non-balance fields.
            // This preserves exact initialBalance and balance, preventing spurious recalculation
            // from format→parse precision loss or minus-sign stripping.
            var updated = existing
            updated.name = name
            updated.currency = currency
            updated.iconSource = selectedIconSource
            newAccount = updated
        } else {
            newAccount = Account(
                id: account?.id ?? UUID().uuidString,
                name: name,
                currency: currency,
                iconSource: selectedIconSource,
                shouldCalculateFromTransactions: account?.shouldCalculateFromTransactions ?? false,
                initialBalance: parsedBalance,
                order: account?.order
            )
        }

        HapticManager.success()
        onSave(newAccount)
    }
}

#Preview("Account Edit View - New") {
    let coordinator = AppCoordinator()

    AccountEditView(
        accountsViewModel: coordinator.accountsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        account: nil,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Account Edit View - Edit") {
    let coordinator = AppCoordinator()
    let sampleAccount = Account(
        id: "preview",
        name: "Test Account",
        currency: "USD",
        iconSource: .brandService("kaspi.kz"),
        initialBalance: 10000
    )

    AccountEditView(
        accountsViewModel: coordinator.accountsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        account: sampleAccount,
        onSave: { _ in },
        onCancel: {}
    )
}
