//
//  VoiceInputConfirmationView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct VoiceInputConfirmationView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    @Environment(TransactionStore.self) private var transactionStore // Phase 7.5: TransactionStore integration
    @Environment(\.dismiss) var dismiss
    
    let parsedOperation: ParsedOperation
    let originalText: String
    
    @State private var selectedType: TransactionType
    @State private var selectedDate: Date
    @State private var amountText: String
    @State private var selectedCurrency: String
    @State private var selectedAccountId: String?
    @State private var selectedCategoryName: String?
    @State private var selectedSubcategoryNames: Set<String>
    @State private var selectedSubcategoryIds: Set<String> = []
    @State private var showingSubcategorySearch = false
    @State private var noteText: String
    
    @State private var accountWarning: String?
    @State private var amountWarning: String?
    @State private var categoryWarning: String?

    // Debounce tasks для предотвращения избыточных вызовов валидации
    @State private var amountValidationTask: Task<Void, Never>?
    @State private var accountValidationTask: Task<Void, Never>?
    @State private var categoryValidationTask: Task<Void, Never>?
    
    init(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        categoriesViewModel: CategoriesViewModel,
        parsedOperation: ParsedOperation,
        originalText: String
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.parsedOperation = parsedOperation
        self.originalText = originalText
        
        _selectedType = State(initialValue: parsedOperation.type)
        _selectedDate = State(initialValue: parsedOperation.date)
        // Парсим сумму - просто конвертируем Decimal в строку без форматирования
        _amountText = State(initialValue: parsedOperation.amount.map { 
            let amountValue = NSDecimalNumber(decimal: $0).doubleValue
            // Используем простой формат без группировки тысяч
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = "" // Убираем разделители тысяч
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 0
            formatter.usesGroupingSeparator = false
            return formatter.string(from: NSNumber(value: amountValue)) ?? String(format: "%.2f", amountValue)
        } ?? "")
        _selectedCurrency = State(initialValue: parsedOperation.currencyCode ?? accountsViewModel.accounts.first?.currency ?? "KZT")
        // Устанавливаем счет - сначала из parsedOperation, потом по умолчанию
        let initialAccountId = parsedOperation.accountId ?? accountsViewModel.accounts.first?.id
        _selectedAccountId = State(initialValue: initialAccountId)
        _selectedCategoryName = State(initialValue: parsedOperation.categoryName)
        _selectedSubcategoryNames = State(initialValue: Set(parsedOperation.subcategoryNames))
        _noteText = State(initialValue: parsedOperation.note.isEmpty ? originalText : parsedOperation.note)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // 1. Picker типа операции
                    SegmentedPickerView(
                        title: String(localized: "common.type"),
                        selection: $selectedType,
                        options: [
                            (label: String(localized: "transactionType.expense"), value: TransactionType.expense),
                            (label: String(localized: "transactionType.income"), value: TransactionType.income)
                        ]
                    )
                    
                    // 2. Сумма с выбором валюты
                    AmountInputView(
                        amount: $amountText,
                        selectedCurrency: $selectedCurrency,
                        errorMessage: amountWarning,
                        baseCurrency: transactionsViewModel.appSettings.baseCurrency,
                        onAmountChange: { _ in
                            // Очищаем предупреждение сразу при вводе
                            amountWarning = nil

                            // Отменяем предыдущую задачу валидации
                            amountValidationTask?.cancel()

                            // Создаем новую задачу с debounce
                            amountValidationTask = Task {
                                try? await Task.sleep(for: .milliseconds(VoiceInputConstants.validationDebounceMs))

                                // Проверяем, не была ли задача отменена
                                guard !Task.isCancelled else { return }

                                await MainActor.run {
                                    validateAmount()
                                }
                            }
                        }
                    )
                    
                    // 3. Счет
                    AccountSelectorView(
                        accounts: accountsViewModel.accounts,
                        selectedAccountId: $selectedAccountId,
                        onSelectionChange: { _ in
                            validateAccount()
                        },
                        emptyStateMessage: String(localized: "voiceConfirmation.noAccounts"),
                        warningMessage: accountWarning,
                        balanceCoordinator: accountsViewModel.balanceCoordinator!
                    )
                    
                    // 4. Категория
                    CategorySelectorView(
                        categories: categoriesViewModel.customCategories
                            .filter { $0.type == selectedType }
                            .sortedByOrder()
                            .map { $0.name },
                        type: selectedType,
                        customCategories: categoriesViewModel.customCategories,
                        selectedCategory: $selectedCategoryName,
                        onSelectionChange: { _ in
                            validateCategory()
                        },
                        emptyStateMessage: String(localized: "transactionForm.noCategories"),
                        warningMessage: categoryWarning
                    )
                    
                    // 5. Подкатегории
                    if let categoryName = selectedCategoryName,
                       let category = categoriesViewModel.customCategories.first(where: { $0.name == categoryName }) {
                        SubcategorySelectorView(
                            categoriesViewModel: categoriesViewModel,
                            categoryId: category.id,
                            selectedSubcategoryIds: $selectedSubcategoryIds,
                            onSearchTap: {
                                showingSubcategorySearch = true
                            }
                        )
                    }
                    
                    // 6. Дата (скрыта, но оставляем для DatePicker)
                    DatePicker(String(localized: "transaction.date"), selection: $selectedDate, displayedComponents: .date)
                        .opacity(0)
                        .frame(height: 0)
                    
                    // 7. Описание
                    FormTextField(
                        text: $noteText,
                        placeholder: String(localized: "quickAdd.descriptionPlaceholder"),
                        style: .multiline(min: VoiceInputConstants.descriptionMinLines, max: VoiceInputConstants.descriptionMaxLines)
                    )
                }
            }
            .navigationTitle(String(localized: "voiceConfirmation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveTransaction()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingSubcategorySearch) {
                if let categoryName = selectedCategoryName,
                   let category = categoriesViewModel.customCategories.first(where: { $0.name == categoryName }) {
                    SubcategorySearchView(
                        categoriesViewModel: categoriesViewModel,
                        categoryId: category.id,
                        selectedSubcategoryIds: $selectedSubcategoryIds,
                        searchText: .constant("")
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .onAppear {
                // Убеждаемся, что счет выбран правильно при появлении
                if selectedAccountId == nil && !accountsViewModel.accounts.isEmpty {
                    selectedAccountId = parsedOperation.accountId ?? accountsViewModel.accounts.first?.id
                }
                // Конвертируем имена подкатегорий в ID
                if !selectedSubcategoryNames.isEmpty {
                    selectedSubcategoryIds = Set(categoriesViewModel.subcategories
                        .filter { selectedSubcategoryNames.contains($0.name) }
                        .map { $0.id })
                }
                validateFields()
            }
            .onChange(of: selectedAccountId) {
                // Отменяем предыдущую задачу валидации
                accountValidationTask?.cancel()

                // Создаем новую задачу с debounce
                accountValidationTask = Task {
                    try? await Task.sleep(for: .milliseconds(VoiceInputConstants.validationDebounceMs))

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        validateAccount()
                    }
                }
            }
            .onChange(of: selectedCategoryName) {
                // Отменяем предыдущую задачу валидации
                categoryValidationTask?.cancel()

                // Создаем новую задачу с debounce
                categoryValidationTask = Task {
                    try? await Task.sleep(for: .milliseconds(VoiceInputConstants.validationDebounceMs))

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        validateCategory()
                    }
                }
            }
            .onDisappear {
                // Отменяем все задачи валидации при закрытии view
                amountValidationTask?.cancel()
                accountValidationTask?.cancel()
                categoryValidationTask?.cancel()
            }
        }
    }

    private var canSave: Bool {
        !amountText.isEmpty && selectedAccountId != nil && selectedCategoryName != nil
    }
    
    
    private func validateFields() {
        validateAccount()
        validateAmount()
        validateCategory()
    }
    
    private func validateAccount() {
        // Проверяем, что выбранный счет существует
        if let accountId = selectedAccountId {
            if accountsViewModel.accounts.contains(where: { $0.id == accountId }) {
                accountWarning = nil
            } else {
                // Счет не найден, выбираем по умолчанию
                accountWarning = String(localized: "voiceConfirmation.warning.accountNotFound")
                if let defaultAccount = accountsViewModel.accounts.first {
                    selectedAccountId = defaultAccount.id
                }
            }
        } else {
            accountWarning = String(localized: "voiceConfirmation.warning.accountNotRecognized")
            // Устанавливаем счет по умолчанию (первый счет)
            if let defaultAccount = accountsViewModel.accounts.first {
                selectedAccountId = defaultAccount.id
            }
        }
    }
    
    private func validateAmount() {
        // Проверка суммы - парсим, убирая валютные символы и пробелы
        let cleanedAmountText = amountText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "₸", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        if cleanedAmountText.isEmpty || Double(cleanedAmountText) == nil {
            amountWarning = String(localized: "voiceConfirmation.warning.enterAmount")
        } else {
            amountWarning = nil
            // НЕ обновляем amountText автоматически - это вызывает бесконечный цикл обновлений
            // Очистка будет происходить только при сохранении
        }
    }
    
    private func validateCategory() {
        if selectedCategoryName == nil {
            categoryWarning = String(localized: "voiceConfirmation.warning.categoryNotRecognized")
            // Устанавливаем категорию "Другое"
            let otherCategoryName = selectedType == .expense ? "Другое" : "Другое"
            if let otherCategory = categoriesViewModel.customCategories.first(where: { $0.name == otherCategoryName && $0.type == selectedType }) {
                selectedCategoryName = otherCategory.name
            } else {
                // Создаем категорию "Другое" если её нет
                let otherCategory = CustomCategory(name: otherCategoryName, iconSource: .sfSymbol("banknote.fill"), colorHex: "#3b82f6", type: selectedType)
                categoriesViewModel.addCategory(otherCategory)
                // Ждем одного runloop-тика — достаточно для propagation @Observable update
                Task { @MainActor in
                    await Task.yield()
                    selectedCategoryName = otherCategoryName
                }
            }
        } else {
            categoryWarning = nil
        }
    }
    
    private func saveTransaction() {
        // Валидируем перед сохранением
        validateAmount()
        
        // Парсим сумму, убирая валютные символы и пробелы
        let cleanedAmountText = amountText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "₸", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        // Проверяем, что все поля заполнены
        guard let amount = Double(cleanedAmountText), amount > 0 else {
            amountWarning = String(localized: "voiceConfirmation.warning.enterValidAmount")
            return
        }
        
        guard let accountId = selectedAccountId, accountsViewModel.accounts.contains(where: { $0.id == accountId }) else {
            accountWarning = String(localized: "voiceConfirmation.warning.selectAccount")
            // Устанавливаем счет по умолчанию, если не выбран
            if let defaultAccount = accountsViewModel.accounts.first {
                selectedAccountId = defaultAccount.id
                accountWarning = String(localized: "voiceConfirmation.warning.accountNotSelected")
            }
            return
        }
        
        // Проверяем и устанавливаем категорию
        var categoryName: String
        if let selectedCategory = selectedCategoryName, 
           categoriesViewModel.customCategories.contains(where: { $0.name == selectedCategory && $0.type == selectedType }) {
            categoryName = selectedCategory
        } else {
            categoryWarning = String(localized: "voiceConfirmation.warning.selectCategory")
            // Устанавливаем категорию "Другое", если не выбрана
            let otherCategoryName = "Другое"
            if let otherCategory = categoriesViewModel.customCategories.first(where: { $0.name == otherCategoryName && $0.type == selectedType }) {
                selectedCategoryName = otherCategory.name
                categoryName = otherCategory.name
                categoryWarning = String(localized: "voiceConfirmation.warning.categoryNotSelected")
            } else {
                categoryWarning = String(localized: "voiceConfirmation.warning.categoryNotFound")
                return
            }
        }
        
        // Получаем валюту счета
        guard let account = accountsViewModel.accounts.first(where: { $0.id == accountId }) else {
            return
        }
        let accountCurrency = account.currency
        
        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: selectedDate)
        
        // Получаем первую подкатегорию для обратной совместимости (subcategory поле)
        var subcategoryId: String? = nil
        if !selectedSubcategoryIds.isEmpty {
            let firstSubcategory = categoriesViewModel.subcategories.first(where: { selectedSubcategoryIds.contains($0.id) })
            subcategoryId = firstSubcategory?.name
        }
        
        // Конвертируем валюту, если она отличается от валюты счета
        Task {
            var convertedAmount: Double? = nil
            if selectedCurrency != accountCurrency {
                convertedAmount = await CurrencyConverter.convert(
                    amount: amount,
                    from: selectedCurrency,
                    to: accountCurrency
                )
            }
            
            let transaction = Transaction(
                id: "",
                date: dateString,
                description: noteText.isEmpty ? originalText : noteText,
                amount: amount,
                currency: selectedCurrency,
                convertedAmount: convertedAmount,
                type: selectedType,
                category: categoryName,
                subcategory: subcategoryId,
                accountId: accountId,
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil
            )
            
            // Phase 7.5: Use TransactionStore for add operation
            do {
                _ = try await transactionStore.add(transaction)

                await MainActor.run {
                    // Получаем ID транзакции после добавления из TransactionStore
                    let addedTransaction = transactionStore.transactions.first { tx in
                        tx.date == dateString &&
                        tx.description == (noteText.isEmpty ? originalText : noteText) &&
                        tx.amount == amount &&
                        tx.category == categoryName &&
                        tx.accountId == accountId &&
                        tx.type == selectedType
                    }

                    // Связываем подкатегории с транзакцией
                    if let transactionId = addedTransaction?.id, !selectedSubcategoryIds.isEmpty {
                        categoriesViewModel.linkSubcategoriesToTransaction(
                            transactionId: transactionId,
                            subcategoryIds: Array(selectedSubcategoryIds)
                        )
                    }
                    HapticManager.success()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    // TODO: Show error alert to user
                    HapticManager.error()
                }
            }
        }
    }
}

#Preview("Expense Confirmation") {
    let coordinator = AppCoordinator()
    let parsedOperation = ParsedOperation(
        type: .expense,
        amount: Decimal(1000),
        currencyCode: "KZT",
        date: Date(),
        categoryName: "Food",
        note: "Обед в кафе"
    )
    NavigationStack {
        VoiceInputConfirmationView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            parsedOperation: parsedOperation,
            originalText: "Потратил тысячу тенге на еду"
        )
    }
    .environment(coordinator.transactionStore)
}

#Preview("Income Confirmation") {
    let coordinator = AppCoordinator()
    let parsedOperation = ParsedOperation(
        type: .income,
        amount: Decimal(150000),
        currencyCode: "KZT",
        date: Date(),
        categoryName: "Salary",
        note: "Зарплата"
    )
    NavigationStack {
        VoiceInputConfirmationView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            parsedOperation: parsedOperation,
            originalText: "Получил зарплату 150 тысяч"
        )
    }
    .environment(coordinator.transactionStore)
}
