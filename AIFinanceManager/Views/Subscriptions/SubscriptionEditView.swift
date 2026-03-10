//
//  SubscriptionEditView.swift
//  AIFinanceManager
//
//  Migrated to hero-style UI (Phase 16 - 2026-02-16)
//  Uses EditableHeroSection with EditSheetContainer and beautiful animations
//

import SwiftUI

struct SubscriptionEditView: View {
    // ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let subscription: RecurringSeries?

    @Environment(\.dismiss) private var dismiss

    @State private var description: String = ""
    @State private var amountText: String = ""
    @State private var currency: String = "USD"
    @State private var selectedCategory: String? = nil
    @State private var selectedAccountId: String? = nil
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var startDate: Date = Date()
    @State private var selectedIconSource: IconSource? = nil
    @State private var reminder: ReminderOption = .none
    @State private var showingNotificationPermission = false
    @State private var validationError: String? = nil
    @State private var isSaving = false
    @State private var availableCategories: [String] = []

    private func computeAvailableCategories() -> [String] {
        var categories: Set<String> = []
        for customCategory in transactionsViewModel.customCategories where customCategory.type == .expense {
            categories.insert(customCategory.name)
        }
        for tx in transactionsViewModel.allTransactions where tx.type == .expense {
            if !tx.category.isEmpty && tx.category != "Uncategorized" {
                categories.insert(tx.category)
            }
        }
        if categories.isEmpty {
            categories.insert("Uncategorized")
        }
        return Array(categories).sortedByCustomOrder(
            customCategories: transactionsViewModel.customCategories,
            type: .expense
        )
    }

    var body: some View {
        EditSheetContainer(
            title: subscription == nil ?
                String(localized: "subscription.newTitle") :
                String(localized: "subscription.editTitle"),
            isSaveDisabled: description.isEmpty || amountText.isEmpty || isSaving,
            wrapInForm: false,
            onSave: saveSubscription,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Hero Section with Icon, Name, Amount, and Currency
                    EditableHeroSection(
                        iconSource: $selectedIconSource,
                        title: $description,
                        balance: $amountText,
                        currency: $currency,
                        titlePlaceholder: String(localized: "subscription.namePlaceholder"),
                        config: .subscriptionHero
                    )
                    
                    // Validation Error
                    if let error = validationError {
                        InlineStatusText(message: error, type: .error)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.top, AppSpacing.md)
                    }
                    
                    // Account Selector
                    if let balanceCoordinator = transactionsViewModel.balanceCoordinator {
                        AccountSelectorView(
                            accounts: transactionsViewModel.accounts,
                            selectedAccountId: $selectedAccountId,
                            emptyStateMessage: transactionsViewModel.accounts.isEmpty ?
                                String(localized: "account.noAccountsAvailable") : nil,
                            warningMessage: selectedAccountId == nil ?
                                String(localized: "account.selectAccount") : nil,
                            balanceCoordinator: balanceCoordinator
                        )
                    }
                    
                    // Category Selector
                    CategorySelectorView(
                        categories: availableCategories,
                        type: .expense,
                        customCategories: transactionsViewModel.customCategories,
                        selectedCategory: $selectedCategory,
                        warningMessage: selectedCategory == nil ?
                        String(localized: "category.selectCategory") : nil
                    )

                    // Schedule & reminders
                    FormSection(header: String(localized: "subscription.scheduleSection", defaultValue: "Schedule")) {
                        MenuPickerRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: String(localized: "common.frequency"),
                            selection: $selectedFrequency
                        )
                        Divider()

                        DatePickerRow(
                            icon: "calendar",
                            title: String(localized: "common.startDate"),
                            selection: $startDate
                        )
                        Divider()

                        MenuPickerRow(
                            icon: "bell",
                            title: String(localized: "subscription.reminders"),
                            selection: $reminder
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
        }
        .onAppear {
            availableCategories = computeAvailableCategories()
            if let subscription = subscription {
                description = subscription.description
                amountText = NSDecimalNumber(decimal: subscription.amount).stringValue
                currency = subscription.currency
                selectedCategory = subscription.category.isEmpty ? nil : subscription.category
                selectedAccountId = subscription.accountId
                selectedFrequency = subscription.frequency
                if let date = DateFormatters.dateFormatter.date(from: subscription.startDate) {
                    startDate = date
                }
                selectedIconSource = subscription.iconSource
                reminder = ReminderOption.from(offsets: subscription.reminderOffsets ?? [])
            } else {
                currency = transactionsViewModel.appSettings.baseCurrency
                if !availableCategories.isEmpty {
                    selectedCategory = availableCategories[0]
                }
                // Set first account as default
                if !transactionsViewModel.accounts.isEmpty {
                    selectedAccountId = transactionsViewModel.accounts[0].id
                }
            }
        }
        .sheet(isPresented: $showingNotificationPermission) {
            NotificationPermissionView(
                onAllow: {
                    await NotificationPermissionManager.shared.requestAuthorization()
                },
                onSkip: { }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func saveSubscription() {
        // Prevent double-tap
        guard !isSaving else { return }

        // Validate required fields: description, amount, category, and account
        guard !description.isEmpty else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                validationError = String(localized: "error.subscriptionNameRequired")
            }
            HapticManager.error()
            return
        }

        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")),
              amount > 0 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                validationError = String(localized: "error.invalidAmount")
            }
            HapticManager.error()
            return
        }

        guard let category = selectedCategory, !category.isEmpty else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                validationError = String(localized: "error.categoryRequired")
            }
            HapticManager.error()
            return
        }

        guard let accountId = selectedAccountId, !accountId.isEmpty else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                validationError = String(localized: "error.accountRequired")
            }
            HapticManager.error()
            return
        }

        validationError = nil

        // Check if we should request notification permissions
        // Only ask when creating a new subscription with reminders
        if subscription == nil && reminder != .none {
            Task {
                let manager = NotificationPermissionManager.shared
                await manager.checkAuthorizationStatus()

                if manager.shouldRequestPermission {
                    // Show permission request sheet
                    showingNotificationPermission = true
                }
            }
        }

        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: startDate)

        let series = RecurringSeries(
            id: subscription?.id ?? UUID().uuidString,
            isActive: subscription?.isActive ?? true,
            amount: amount,
            currency: currency,
            category: category,
            subcategory: nil,
            description: description,
            accountId: accountId,
            targetAccountId: nil,
            frequency: selectedFrequency,
            startDate: dateString,
            lastGeneratedDate: subscription?.lastGeneratedDate,
            kind: .subscription,
            iconSource: selectedIconSource,
            reminderOffsets: reminder == .none ? nil : Array(reminder.asOffsets).sorted(),
            status: subscription?.status ?? .active
        )

        isSaving = true

        Task {
            do {
                if subscription == nil {
                    try await transactionStore.createSeries(series)
                } else {
                    try await transactionStore.updateSeries(series)
                }
                HapticManager.success()
                dismiss()
            } catch {
                isSaving = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    validationError = error.localizedDescription
                }
                HapticManager.error()
            }
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionEditView(
        transactionStore: coordinator.transactionStore,
        transactionsViewModel: coordinator.transactionsViewModel,
        subscription: nil
    )
}
