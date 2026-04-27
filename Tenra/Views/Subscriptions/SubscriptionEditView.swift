//
//  SubscriptionEditView.swift
//  Tenra
//
//  Migrated to hero-style UI (Phase 16 - 2026-02-16)
//  Uses EditableHeroSection with EditSheetContainer and beautiful animations
//

import SwiftUI

struct SubscriptionEditView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let subscription: RecurringSeries?

    @Environment(\.dismiss) private var dismiss

    @State private var description: String = ""
    @State private var amountText: String = ""
    @State private var currency: String = "USD"
    @State private var selectedCategory: String = ""
    @State private var selectedAccountId: String? = nil
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var startDate: Date = Date()
    @State private var selectedIconSource: IconSource? = nil
    @State private var reminder: ReminderOption = .none
    @State private var showingNotificationPermission = false
    @State private var validationError: String? = nil
    @State private var isSaving = false
    @State private var availableCategories: [String] = []

    // Propagation alert (edit mode only)
    @State private var pendingSeries: RecurringSeries? = nil
    @State private var showingPropagationAlert = false

    /// Scope for propagating edits to linked transactions.
    private enum PropagationScope {
        case seriesOnly
        case future
        case all
    }

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

                    // Base-currency equivalent (only when entered currency differs)
                    if currency != transactionsViewModel.appSettings.baseCurrency,
                       let parsedAmount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")),
                       parsedAmount > 0 {
                        ConvertedAmountView(
                            amount: NSDecimalNumber(decimal: parsedAmount).doubleValue,
                            fromCurrency: currency,
                            toCurrency: transactionsViewModel.appSettings.baseCurrency,
                            fontSize: AppTypography.caption,
                            color: .secondary.opacity(0.7)
                        )
                    }

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
                    
                    // Schedule, category & reminders
                    FormSection(header: String(localized: "subscription.scheduleSection")) {
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
                            icon: "tag",
                            title: String(localized: "subscriptions.category"),
                            selection: $selectedCategory,
                            options: availableCategories.map { (label: $0, value: $0) }
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
                selectedCategory = subscription.category.isEmpty ? (availableCategories.first ?? "") : subscription.category
                selectedAccountId = subscription.accountId
                selectedFrequency = subscription.frequency
                if let date = DateFormatters.dateFormatter.date(from: subscription.startDate) {
                    startDate = date
                }
                selectedIconSource = subscription.iconSource
                reminder = ReminderOption.from(offsets: subscription.reminderOffsets ?? [])
            } else {
                currency = transactionsViewModel.appSettings.baseCurrency
                selectedCategory = availableCategories.first ?? ""
                // Set first account as default
                if !transactionsViewModel.accounts.isEmpty {
                    selectedAccountId = transactionsViewModel.accounts[0].id
                }
            }
        }
        .alert(
            String(localized: "subscription.edit.propagate.title", defaultValue: "Update linked transactions?"),
            isPresented: $showingPropagationAlert,
            presenting: pendingSeries
        ) { series in
            Button(String(localized: "subscription.edit.propagate.seriesOnly", defaultValue: "Only subscription")) {
                performSave(series: series, scope: .seriesOnly)
            }
            Button(String(localized: "subscription.edit.propagate.future", defaultValue: "Future transactions")) {
                performSave(series: series, scope: .future)
            }
            Button(String(localized: "subscription.edit.propagate.all", defaultValue: "All transactions"), role: .destructive) {
                performSave(series: series, scope: .all)
            }
            Button(String(localized: "quickAdd.cancel"), role: .cancel) {
                pendingSeries = nil
            }
        } message: { _ in
            Text(String(localized: "subscription.edit.propagate.message", defaultValue: "Apply changes to existing transactions linked to this subscription?"))
        }
        .sheet(isPresented: $showingNotificationPermission, onDismiss: { dismiss() }) {
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

        // Validate required fields: description, amount, and account
        guard !description.isEmpty else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "error.subscriptionNameRequired")
            }
            HapticManager.error()
            return
        }

        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")),
              amount > 0 else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "error.invalidAmount")
            }
            HapticManager.error()
            return
        }

        guard let accountId = selectedAccountId, !accountId.isEmpty else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "error.accountRequired")
            }
            HapticManager.error()
            return
        }

        validationError = nil

        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: startDate)

        let series = RecurringSeries(
            id: subscription?.id ?? UUID().uuidString,
            isActive: subscription?.isActive ?? true,
            amount: amount,
            currency: currency,
            category: selectedCategory,
            subcategory: description, // Subscription name doubles as subcategory (auto-linked below)
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

        // Decide between immediate save and propagation alert.
        if let existing = subscription, hasPropagatableChange(old: existing, new: series),
           hasLinkedTransactions(seriesId: existing.id) {
            pendingSeries = series
            showingPropagationAlert = true
        } else {
            performSave(series: series, scope: .seriesOnly)
        }
    }

    /// True if any field that would propagate to generated transactions has changed.
    /// `description` (name) is intentionally excluded — name renames are auto-propagated
    /// to all linked transactions in `performSave`, no scope prompt needed.
    private func hasPropagatableChange(old: RecurringSeries, new: RecurringSeries) -> Bool {
        old.amount != new.amount
            || old.currency != new.currency
            || old.category != new.category
            || old.accountId != new.accountId
            || old.iconSource != new.iconSource
    }

    private func hasLinkedTransactions(seriesId: String) -> Bool {
        transactionStore.transactions.contains { $0.recurringSeriesId == seriesId }
    }

    /// Save the series, optionally propagate changes to linked transactions,
    /// and ensure the subscription's name exists as a linked subcategory.
    private func performSave(series: RecurringSeries, scope: PropagationScope) {
        isSaving = true

        Task {
            // Check notification permission before saving so we can decide
            // whether to show the permission sheet instead of calling dismiss() directly.
            var needsPermissionSheet = false
            if subscription == nil && reminder != .none {
                let manager = NotificationPermissionManager.shared
                await manager.checkAuthorizationStatus()
                needsPermissionSheet = manager.shouldRequestPermission
            }

            do {
                // 1. Resolve or create subcategory named after subscription.
                let subcategory = resolveOrCreateSubcategory(name: series.description, categoryName: series.category)

                // 2. Save the series (create vs update).
                let isCreate = subscription == nil
                if isCreate {
                    try await transactionStore.createSeries(series)
                } else {
                    try await transactionStore.updateSeries(series)
                }

                // 3. Determine which transactions should receive propagated field updates + subcategory link.
                let oldSeries = subscription
                let scopedTxs = transactionsToUpdate(for: series, scope: scope)
                let didRename = oldSeries.map { $0.description != series.description } ?? false

                // 4a. Auto-propagate name rename to ALL linked transactions, regardless of scope.
                //     Renaming a subscription is a relabeling of the entity itself, so historical
                //     occurrences should reflect the new name without prompting the user.
                if didRename {
                    let allLinked = transactionStore.transactions.filter { $0.recurringSeriesId == series.id }
                    for tx in allLinked where tx.description != series.description {
                        let renamed = renameTransactionDescription(tx, to: series.description)
                        try await transactionStore.update(renamed)
                    }
                }

                // 4b. For edit with propagation → rewrite remaining fields on scoped transactions.
                if let oldSeries = oldSeries, scope != .seriesOnly {
                    let changes = propagatableChanges(old: oldSeries, new: series)
                    for tx in scopedTxs {
                        let updated = applyChanges(to: tx, changes: changes, newSeries: series)
                        if updated != tx {
                            try await transactionStore.update(updated)
                        }
                    }
                }

                // 5. Link subcategory to relevant transactions:
                //    - On create: all current series transactions
                //    - On rename: all linked transactions (subcategory mirrors the new name)
                //    - Otherwise: just the scoped set
                let txsToLink: [Transaction]
                if isCreate || didRename {
                    txsToLink = transactionStore.transactions.filter { $0.recurringSeriesId == series.id }
                } else {
                    txsToLink = scopedTxs
                }
                linkSubcategory(subcategory, toTransactions: txsToLink)

                HapticManager.success()

                if needsPermissionSheet {
                    // Show the sheet; dismiss() is called via sheet's onDismiss.
                    showingNotificationPermission = true
                } else {
                    dismiss()
                }
            } catch {
                isSaving = false
                withAnimation(AppAnimation.contentSpring) {
                    validationError = error.localizedDescription
                }
                HapticManager.error()
            }
        }
    }

    private func transactionsToUpdate(for series: RecurringSeries, scope: PropagationScope) -> [Transaction] {
        let all = transactionStore.transactions.filter { $0.recurringSeriesId == series.id }
        switch scope {
        case .seriesOnly:
            return []
        case .all:
            return all
        case .future:
            let today = DateFormatters.dateFormatter.string(from: Date())
            return all.filter { $0.date >= today }
        }
    }

    private struct PropagatableChanges {
        var amount: Bool
        var currency: Bool
        var category: Bool
        var accountId: Bool
        // description is auto-propagated unconditionally (see performSave step 4a).
    }

    private func propagatableChanges(old: RecurringSeries, new: RecurringSeries) -> PropagatableChanges {
        PropagatableChanges(
            amount: old.amount != new.amount,
            currency: old.currency != new.currency,
            category: old.category != new.category,
            accountId: old.accountId != new.accountId
        )
    }

    private func applyChanges(to tx: Transaction, changes: PropagatableChanges, newSeries series: RecurringSeries) -> Transaction {
        let newAmount = changes.amount ? NSDecimalNumber(decimal: series.amount).doubleValue : tx.amount
        let newCurrency = changes.currency ? series.currency : tx.currency
        let newCategory = changes.category ? series.category : tx.category
        let newAccountId = changes.accountId ? (series.accountId ?? tx.accountId) : tx.accountId
        return Transaction(
            id: tx.id,
            date: tx.date,
            description: tx.description,
            amount: newAmount,
            currency: newCurrency,
            convertedAmount: tx.convertedAmount,
            type: tx.type,
            category: newCategory,
            subcategory: tx.subcategory,
            accountId: newAccountId,
            targetAccountId: tx.targetAccountId,
            accountName: tx.accountName,
            targetAccountName: tx.targetAccountName,
            targetCurrency: tx.targetCurrency,
            targetAmount: tx.targetAmount,
            recurringSeriesId: tx.recurringSeriesId,
            recurringOccurrenceId: tx.recurringOccurrenceId,
            createdAt: tx.createdAt
        )
    }

    /// Returns a copy of `tx` with `description` swapped out — used by the auto-rename pass
    /// so historical occurrences match the subscription's current name.
    private func renameTransactionDescription(_ tx: Transaction, to newDescription: String) -> Transaction {
        Transaction(
            id: tx.id,
            date: tx.date,
            description: newDescription,
            amount: tx.amount,
            currency: tx.currency,
            convertedAmount: tx.convertedAmount,
            type: tx.type,
            category: tx.category,
            subcategory: tx.subcategory,
            accountId: tx.accountId,
            targetAccountId: tx.targetAccountId,
            accountName: tx.accountName,
            targetAccountName: tx.targetAccountName,
            targetCurrency: tx.targetCurrency,
            targetAmount: tx.targetAmount,
            recurringSeriesId: tx.recurringSeriesId,
            recurringOccurrenceId: tx.recurringOccurrenceId,
            createdAt: tx.createdAt
        )
    }

    /// Find subcategory by case-insensitive name; create + link to the category if missing.
    private func resolveOrCreateSubcategory(name: String, categoryName: String) -> Subcategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = categoriesViewModel.subcategories.first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            ensureSubcategoryLinkedToCategory(subcategoryId: existing.id, categoryName: categoryName)
            return existing
        }
        let created = categoriesViewModel.addSubcategory(name: trimmed)
        ensureSubcategoryLinkedToCategory(subcategoryId: created.id, categoryName: categoryName)
        return created
    }

    private func ensureSubcategoryLinkedToCategory(subcategoryId: String, categoryName: String) {
        guard let categoryId = transactionsViewModel.customCategories.first(where: { $0.name == categoryName })?.id
        else { return }
        let alreadyLinked = categoriesViewModel.categorySubcategoryLinks.contains {
            $0.subcategoryId == subcategoryId && $0.categoryId == categoryId
        }
        if !alreadyLinked {
            categoriesViewModel.linkSubcategoryToCategory(subcategoryId: subcategoryId, categoryId: categoryId)
        }
    }

    private func linkSubcategory(_ subcategory: Subcategory, toTransactions txs: [Transaction]) {
        for tx in txs {
            let existing = categoriesViewModel.getSubcategoriesForTransaction(tx.id).map(\.id)
            if existing.contains(subcategory.id) { continue }
            var updated = existing
            updated.append(subcategory.id)
            categoriesViewModel.linkSubcategoriesToTransaction(
                transactionId: tx.id,
                subcategoryIds: updated
            )
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionEditView(
        transactionStore: coordinator.transactionStore,
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        subscription: nil
    )
}
