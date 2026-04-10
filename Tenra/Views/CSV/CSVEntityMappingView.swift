//
//  CSVEntityMappingView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI
import UIKit

private enum CSVMappingDestination: Hashable {
    case account(String)
    case incomeCategory(String)
    case expenseCategory(String)
}

struct CSVEntityMappingView: View {
    let csvFile: CSVFile
    let mapping: CSVColumnMapping
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    let onComplete: (EntityMapping) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var entityMapping = EntityMapping()
    @State private var uniqueAccounts: [String] = []
    @State private var uniqueCategories: [String] = []
    @State private var uniqueIncomeCategories: [String] = []
    @State private var accountMappings: [String: String] = [:] // CSV значение -> Account ID
    @State private var categoryMappings: [String: String] = [:] // CSV значение -> Category name
    @State private var showingAccountCreation = false
    @State private var showingCategoryCreation = false
    @State private var selectedAccountValue: String?
    @State private var selectedCategoryValue: String?
    
    var body: some View {
        NavigationStack {
            Form {
                if !uniqueAccounts.isEmpty {
                    Section(header: Text(String(localized: "csvMapping.accountsSection", defaultValue: "Account Mapping"))) {
                        ForEach(uniqueAccounts, id: \.self) { accountValue in
                            NavigationLink(value: CSVMappingDestination.account(accountValue)) {
                                HStack {
                                    Text(accountValue)
                                    Spacer()
                                    if let accountId = accountMappings[accountValue],
                                       let account = accountsViewModel.accounts.first(where: { $0.id == accountId }) {
                                        Text(account.name)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(String(localized: "csvMapping.notSelected", defaultValue: "Not Selected"))
                                            .foregroundStyle(AppColors.warning)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if mapping.categoryColumn != nil, !uniqueCategories.isEmpty {
                    Section(header: Text(String(localized: "csvMapping.categoriesSection", defaultValue: "Category Mapping"))) {
                        ForEach(uniqueCategories, id: \.self) { categoryValue in
                            NavigationLink(value: CSVMappingDestination.expenseCategory(categoryValue)) {
                                HStack {
                                    Text(categoryValue)
                                    Spacer()
                                    if let categoryName = categoryMappings[categoryValue] {
                                        Text(categoryName)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(String(localized: "csvMapping.notSelected", defaultValue: "Not Selected"))
                                            .foregroundStyle(AppColors.warning)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if !uniqueIncomeCategories.isEmpty {
                    Section(header: Text(String(localized: "csvMapping.incomeCategoriesSection", defaultValue: "Income Category Mapping"))) {
                        ForEach(uniqueIncomeCategories, id: \.self) { categoryValue in
                            NavigationLink(value: CSVMappingDestination.incomeCategory(categoryValue)) {
                                HStack {
                                    Text(categoryValue)
                                    Spacer()
                                    if let categoryName = categoryMappings[categoryValue] {
                                        Text(categoryName)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(String(localized: "csvMapping.notSelected", defaultValue: "Not Selected"))
                                            .foregroundStyle(AppColors.warning)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: CSVMappingDestination.self) { dest in
                switch dest {
                case .account(let csvValue):
                    AccountMappingDetailView(
                        csvValue: csvValue,
                        accounts: accountsViewModel.accounts,
                        selectedAccountId: Binding(
                            get: { accountMappings[csvValue] },
                            set: { accountMappings[csvValue] = $0 }
                        ),
                        onCreateNew: {
                            Task { await createAccount(name: csvValue) }
                        }
                    )
                case .expenseCategory(let csvValue):
                    CategoryMappingDetailView(
                        csvValue: csvValue,
                        categories: categoriesViewModel.customCategories.filter { $0.type == .expense },
                        categoryType: .expense,
                        selectedCategoryName: Binding(
                            get: { categoryMappings[csvValue] },
                            set: { categoryMappings[csvValue] = $0 }
                        ),
                        onCreateNew: {
                            createCategory(name: csvValue, type: .expense)
                        }
                    )
                case .incomeCategory(let csvValue):
                    CategoryMappingDetailView(
                        csvValue: csvValue,
                        categories: categoriesViewModel.customCategories.filter { $0.type == .income },
                        categoryType: .income,
                        selectedCategoryName: Binding(
                            get: { categoryMappings[csvValue] },
                            set: { categoryMappings[csvValue] = $0 }
                        ),
                        onCreateNew: {
                            createCategory(name: csvValue, type: .income)
                        }
                    )
                }
            }
            .navigationTitle(String(localized: "csvMapping.title", defaultValue: "Entity Mapping"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.left")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        entityMapping.accountMappings = accountMappings
                        entityMapping.categoryMappings = categoryMappings
                        // Закрываем модалку сопоставления сущностей перед началом импорта
                        dismiss()
                        // Запускаем импорт после sheet dismiss animation (~300ms)
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            onComplete(entityMapping)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .glassProminentButton()
                }
            }
            .onAppear {
                extractUniqueValues()
            }
        }
    }
    
    private func parseType(_ typeString: String) -> TransactionType? {
        let n = typeString.lowercased().trimmingCharacters(in: .whitespaces)
        if let t = mapping.typeMappings[n] { return t }
        for (key, type) in mapping.typeMappings {
            if n.contains(key) || key.contains(n) { return type }
        }
        return nil
    }
    
    private func extractUniqueValues() {
        let headers = csvFile.headers
        let typeIdx = mapping.typeColumn.flatMap { headers.firstIndex(of: $0) }
        let accountIdx = mapping.accountColumn.flatMap { headers.firstIndex(of: $0) }
        let targetIdx = mapping.targetAccountColumn.flatMap { headers.firstIndex(of: $0) }
        let categoryIdx = mapping.categoryColumn.flatMap { headers.firstIndex(of: $0) }
        
        let reserved = ["другое", "other"]
        
        var accountSet: Set<String> = []
        var expenseCategorySet: Set<String> = []
        var incomeCategorySet: Set<String> = []
        
        for row in csvFile.rows {
            let typeStr = typeIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            let type = parseType(typeStr)
            let accountVal = accountIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            let targetVal = targetIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            let categoryVal = categoryIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            
            switch type {
            case .income:
                if !targetVal.isEmpty { accountSet.insert(targetVal) }
                if !accountVal.isEmpty { incomeCategorySet.insert(accountVal) }
            case .expense, .internalTransfer, .depositTopUp, .depositWithdrawal, .depositInterestAccrual,
                 .loanPayment, .loanEarlyRepayment:
                if !accountVal.isEmpty, !reserved.contains(accountVal.lowercased()) { accountSet.insert(accountVal) }
                if type == .expense, !categoryVal.isEmpty { expenseCategorySet.insert(categoryVal) }
            case .none:
                if !accountVal.isEmpty, !reserved.contains(accountVal.lowercased()) { accountSet.insert(accountVal) }
                if !categoryVal.isEmpty { expenseCategorySet.insert(categoryVal) }
            }
        }
        
        uniqueAccounts = Array(accountSet).sorted()
        uniqueCategories = Array(expenseCategorySet).sorted()
        uniqueIncomeCategories = Array(incomeCategorySet).sorted()
    }
    
    private func createAccount(name: String) async {
        await accountsViewModel.addAccount(name: name, initialBalance: 0, currency: "KZT", iconSource: nil, shouldCalculateFromTransactions: true)
        if let account = accountsViewModel.accounts.first(where: { $0.name == name }) {
            accountMappings[name] = account.id
        }
    }
    
    private func createCategory(name: String, type: TransactionType = .expense) {
        let iconName = CategoryIcon.iconName(for: name, type: type, customCategories: categoriesViewModel.customCategories)
        let colorHex = CategoryColors.hexColor(for: name, customCategories: categoriesViewModel.customCategories)
        let hexString = colorToHex(colorHex)

        let newCategory = CustomCategory(
            name: name,
            iconSource: .sfSymbol(iconName),
            colorHex: hexString,
            type: type
        )
        categoriesViewModel.addCategory(newCategory)
        categoryMappings[name] = name
    }
    
    // Конвертирует Color в hex строку
    private func colorToHex(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct AccountMappingDetailView: View {
    let csvValue: String
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    let onCreateNew: () -> Void
    
    var body: some View {
        Form {
            Section(header: Text("csvMapping.selectAccount \(csvValue)")) {
                ForEach(accounts.sortedByOrder()) { account in
                    Button(action: {
                        selectedAccountId = account.id
                    }) {
                        HStack {
                            IconView(source: account.iconSource, size: AppIconSize.lg)
                            Text(account.name)
                            Spacer()
                            if selectedAccountId == account.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                }
            }
            
            Section {
                Button(action: onCreateNew) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("csvMapping.createAccount \(csvValue)")
                    }
                }
            }
        }
        .navigationTitle(String(localized: "csvMapping.accountMappingTitle", defaultValue: "Account Mapping"))
    }
}

struct CategoryMappingDetailView: View {
    let csvValue: String
    let categories: [CustomCategory]
    var categoryType: TransactionType = .expense
    @Binding var selectedCategoryName: String?
    let onCreateNew: () -> Void
    
    private var categoryLabel: String {
        categoryType == .income
            ? String(localized: "csvMapping.incomeCategoryLabel", defaultValue: "income category")
            : String(localized: "csvMapping.categoryLabel", defaultValue: "category")
    }
    
    var body: some View {
        Form {
            Section(header: Text("csvMapping.selectCategory \(categoryLabel) \(csvValue)")) {
                ForEach(categories, id: \.name) { category in
                    Button(action: {
                        selectedCategoryName = category.name
                    }) {
                        HStack {
                            Group {
                                if case .sfSymbol(let symbolName) = category.iconSource {
                                    Image(systemName: symbolName)
                                        .foregroundStyle(category.color)
                                }
                            }
                            Text(category.name)
                            Spacer()
                            if selectedCategoryName == category.name {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                }
            }
            
            Section {
                Button(action: onCreateNew) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("csvMapping.createCategory \(categoryLabel) \(csvValue)")
                    }
                }
            }
        }
        .navigationTitle(categoryType == .income
            ? String(localized: "csvMapping.incomeCategoryMappingTitle", defaultValue: "Income Category Mapping")
            : String(localized: "csvMapping.categoryMappingTitle", defaultValue: "Category Mapping"))
    }
}

