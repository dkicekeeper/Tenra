//
//  ParsedOperation.swift
//  Tenra
//
//  Created on 2024
//

import Foundation

struct ParsedOperation: Identifiable, Hashable {
    let id = UUID()
    var type: TransactionType
    var amount: Decimal?
    var currencyCode: String?
    var date: Date
    var accountId: String?
    var categoryName: String?
    var subcategoryNames: [String]
    var note: String
    /// No keyword named the category: `categoryName` is the "Other" fallback.
    var categoryIsGuess = false
    
    init(
        type: TransactionType = .expense,
        amount: Decimal? = nil,
        currencyCode: String? = nil,
        date: Date = Date(),
        accountId: String? = nil,
        categoryName: String? = nil,
        subcategoryNames: [String] = [],
        note: String = ""
    ) {
        self.type = type
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.accountId = accountId
        self.categoryName = categoryName
        self.subcategoryNames = subcategoryNames
        self.note = note
    }
}
