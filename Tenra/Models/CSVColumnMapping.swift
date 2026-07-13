//
//  CSVColumnMapping.swift
//  Tenra
//
//  Created on 2024
//

import Foundation

struct CSVColumnMapping {
    var dateColumn: String?
    var dateFormat: DateFormatType = .auto
    var typeColumn: String?
    var amountColumn: String?
    var currencyColumn: String?
    var accountColumn: String?
    var targetAccountColumn: String? // Счет получателя
    var targetCurrencyColumn: String? // Валюта счета получателя
    var targetAmountColumn: String? // Сумма на счете получателя
    var categoryColumn: String?
    var subcategoriesColumn: String?
    var subcategoriesSeparator: String = ","
    var noteColumn: String?
    
    // Маппинг значений типа
    var typeMappings: [String: TransactionType] = [
        "expense": .expense,
        "expenses": .expense,
        "расход": .expense,
        "расходы": .expense,
        "-": .expense,
        "out": .expense,
        "income": .income,
        "incomes": .income,
        "доход": .income,
        "доходы": .income,
        "+": .income,
        "in": .income,
        "transfer": .internalTransfer,
        "перевод": .internalTransfer,
        "переводы": .internalTransfer,
        "трансфер": .internalTransfer,
        "internal": .internalTransfer,
        "internaltransfer": .internalTransfer,
        // DE
        "ausgabe": .expense,
        "ausgaben": .expense,
        "einnahme": .income,
        "einnahmen": .income,
        "überweisung": .internalTransfer,
        "umbuchung": .internalTransfer,
        // ES
        "gasto": .expense,
        "gastos": .expense,
        "ingreso": .income,
        "ingresos": .income,
        "transferencia": .internalTransfer,
        // FR
        "dépense": .expense,
        "dépenses": .expense,
        "revenu": .income,
        "revenus": .income,
        "virement": .internalTransfer,
        // TR
        "gider": .expense,
        "giderler": .expense,
        "gelir": .income,
        "gelirler": .income,
        // PT-BR
        "despesa": .expense,
        "despesas": .expense,
        "receita": .income,
        "receitas": .income,
        "transferência": .internalTransfer,
        // IT
        "spesa": .expense,
        "spese": .expense,
        "entrata": .income,
        "entrate": .income,
        "bonifico": .internalTransfer,
        // UK
        "витрата": .expense,
        "витрати": .expense,
        "дохід": .income,
        "доходи": .income,
        "переказ": .internalTransfer,
        // Deposit types (exported by CSVExporter)
        "deposit_topup": .depositTopUp,
        "deposit_withdrawal": .depositWithdrawal,
        "deposit_interest": .depositInterestAccrual,
        // Loan types (exported by CSVExporter)
        "loan_payment": .loanPayment,
        "loan_early_repayment": .loanEarlyRepayment
    ]
}

enum DateFormatType: String, CaseIterable {
    case iso = "ISO (yyyy-MM-dd)"
    case ddmmyyyy = "dd.MM.yyyy"
    case auto = "Автоопределение"
}

struct EntityMapping {
    var accountMappings: [String: String] = [:] // CSV значение -> Account ID
    var categoryMappings: [String: String] = [:] // CSV значение -> Category name
    var subcategoryMappings: [String: (category: String, subcategory: String)] = [:] // CSV значение -> (category, subcategory)
}

struct ImportResult {
    let importedCount: Int
    let skippedCount: Int
    let duplicatesSkipped: Int  // Transactions skipped due to fingerprint match
    let createdAccounts: Int
    let createdCategories: Int
    let createdSubcategories: Int
    let errors: [String]
    
    /// Total rows processed
    var totalProcessed: Int {
        return importedCount + skippedCount
    }
    
    /// Success rate (0.0 to 1.0)
    var successRate: Double {
        guard totalProcessed > 0 else { return 0.0 }
        return Double(importedCount) / Double(totalProcessed)
    }
}
