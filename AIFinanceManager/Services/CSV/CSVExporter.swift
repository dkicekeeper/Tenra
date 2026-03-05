//
//  CSVExporter.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

class CSVExporter {

    /// Export transactions to CSV string.
    /// - Parameters:
    ///   - transactions: All transactions to export
    ///   - accounts: All accounts (for resolving accountId → name)
    ///   - subcategoryLinks: Transaction-subcategory links (for resolving subcategories per transaction)
    ///   - subcategories: All subcategories (for resolving subcategoryId → name)
    static func exportTransactions(
        _ transactions: [Transaction],
        accounts: [Account],
        subcategoryLinks: [TransactionSubcategoryLink] = [],
        subcategories: [Subcategory] = []
    ) -> String {
        var csv = "date,type,amount,currency,account,category,subcategories,note,targetAccount,targetCurrency,targetAmount\n"

        // Pre-build lookup dictionaries for O(1) resolution
        let accountById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let subcategoryById = Dictionary(uniqueKeysWithValues: subcategories.map { ($0.id, $0.name) })

        // Group subcategory links by transactionId for O(1) lookup
        let linksByTransaction = Dictionary(grouping: subcategoryLinks, by: { $0.transactionId })

        for transaction in transactions {
            let date = escapeCSVField(transaction.date)
            let type = escapeCSVField(exportTypeName(transaction.type))
            let amount = String(format: "%.2f", transaction.amount)
            let currency = escapeCSVField(transaction.currency)
            let note = escapeCSVField(transaction.description)

            // Resolve account and category columns.
            // For income: import expects account column = category, targetAccount = account
            // (CSVRow.effectiveAccountValue for income reads targetAccount; effectiveCategoryValue reads account)
            let accountName: String
            let category: String
            let targetAccountName: String

            if transaction.type == .income {
                // Swap: account column = category (import reads as income category)
                accountName = escapeCSVField(transaction.category)
                category = escapeCSVField(transaction.category)
                // targetAccount = actual account name (import reads as income account)
                let resolvedAccount = transaction.accountId.flatMap { accountById[$0] } ?? ""
                targetAccountName = escapeCSVField(resolvedAccount)
            } else {
                accountName = escapeCSVField(transaction.accountId.flatMap { accountById[$0] } ?? "")
                category = escapeCSVField(transaction.category)
                if let targetId = transaction.targetAccountId {
                    targetAccountName = escapeCSVField(accountById[targetId] ?? "")
                } else {
                    targetAccountName = ""
                }
            }

            // Resolve subcategories: prefer real links, fallback to legacy field
            let subcategoriesValue: String
            let links = linksByTransaction[transaction.id] ?? []
            if !links.isEmpty {
                let names = links.compactMap { subcategoryById[$0.subcategoryId] }
                subcategoriesValue = escapeCSVField(names.joined(separator: ","))
            } else {
                subcategoriesValue = escapeCSVField(transaction.subcategory ?? "")
            }

            // targetCurrency / targetAmount columns:
            // - For transfers: actual target account currency & amount
            // - For non-transfers: reuse for convertedAmount (distinguishable by type on import)
            let targetCurrency: String
            let targetAmount: String

            if transaction.type == .internalTransfer {
                targetCurrency = escapeCSVField(transaction.targetCurrency ?? "")
                targetAmount = transaction.targetAmount.map { String(format: "%.2f", $0) } ?? ""
            } else if let converted = transaction.convertedAmount, converted != 0 {
                // Non-transfer with convertedAmount — store in targetCurrency/targetAmount columns
                targetCurrency = escapeCSVField(transaction.currency)
                targetAmount = String(format: "%.2f", converted)
            } else {
                targetCurrency = ""
                targetAmount = ""
            }

            csv += "\(date),\(type),\(amount),\(currency),\(accountName),\(category),\(subcategoriesValue),\(note),\(targetAccountName),\(targetCurrency),\(targetAmount)\n"
        }

        return csv
    }

    // MARK: - Type Export Name

    /// Maps all TransactionTypes to stable export strings
    private static func exportTypeName(_ type: TransactionType) -> String {
        switch type {
        case .expense: return "expense"
        case .income: return "income"
        case .internalTransfer: return "internal"
        case .depositTopUp: return "deposit_topup"
        case .depositWithdrawal: return "deposit_withdrawal"
        case .depositInterestAccrual: return "deposit_interest"
        case .loanPayment: return "loan_payment"
        case .loanEarlyRepayment: return "loan_early_repayment"
        }
    }

    // MARK: - CSV Field Escaping

    private static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}

extension DateFormatter {
    static let exportFileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
