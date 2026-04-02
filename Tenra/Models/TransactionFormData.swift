//
//  TransactionFormData.swift
//  AIFinanceManager
//
//  Unified form data model for transaction creation and editing
//

import Foundation

/// Unified form data for transaction creation/editing
struct TransactionFormData {
    var amountText: String = ""
    var currency: String
    var description: String = ""
    var accountId: String?
    var category: String
    var type: TransactionType
    var selectedDate: Date = Date()
    var recurring: RecurringOption = .never
    var subcategoryIds: Set<String> = []

    // MARK: - Computed Properties

    /// Parsed decimal amount from text input
    var parsedAmount: Decimal? {
        AmountFormatter.parse(amountText)
    }

    /// Amount as Double (convenience)
    var amountDouble: Double? {
        parsedAmount.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    // MARK: - Initialization

    /// Initialize with category and type
    init(
        category: String,
        type: TransactionType,
        currency: String,
        suggestedAccountId: String? = nil
    ) {
        self.category = category
        self.type = type
        self.currency = currency
        self.accountId = suggestedAccountId
    }

    /// Initialize with existing transaction (for editing)
    init(from transaction: Transaction, currency: String) {
        self.amountText = String(transaction.amount)
        self.currency = currency
        self.description = transaction.description
        self.accountId = transaction.accountId
        self.category = transaction.category
        self.type = transaction.type

        // Parse date from string
        if let date = DateFormatters.dateFormatter.date(from: transaction.date) {
            self.selectedDate = date
        }

        // Recurring info
        self.recurring = transaction.recurringSeriesId != nil ? .frequency(.monthly) : .never
    }
}
