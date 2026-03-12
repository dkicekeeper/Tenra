//
//  CategoryAggregate.swift
//  AIFinanceManager
//
//  Created on 2026
//

import Foundation

/// In-memory модель агрегированных данных по категориям/подкатегориям
/// Supports 4 levels of granularity:
/// - Daily: year > 0, month > 0, day > 0 (last 90 days)
/// - Monthly: year > 0, month > 0, day = 0 (all months)
/// - Yearly: year > 0, month = 0, day = 0 (all years)
/// - All-time: year = 0, month = 0, day = 0 (total)
struct CategoryAggregate: Identifiable, Equatable {
    let id: String // Формат: "{category}_{subcategory}_{year}_{month}_{day}"
    let categoryName: String
    let subcategoryName: String? // nil для агрегата категории без подкатегории
    let year: Int16 // 0 = all-time
    let month: Int16 // 0 = yearly или all-time
    let day: Int16 // 0 = monthly/yearly/all-time, >0 = daily (1-31)
    let totalAmount: Double // В базовой валюте
    let transactionCount: Int32
    let currency: String // Базовая валюта для агрегата
    let lastUpdated: Date
    let lastTransactionDate: Date?

    init(
        categoryName: String,
        subcategoryName: String? = nil,
        year: Int16,
        month: Int16,
        day: Int16 = 0,
        totalAmount: Double,
        transactionCount: Int32,
        currency: String,
        lastUpdated: Date = Date(),
        lastTransactionDate: Date? = nil
    ) {
        self.categoryName = categoryName
        self.subcategoryName = subcategoryName
        self.year = year
        self.month = month
        self.day = day
        self.totalAmount = totalAmount
        self.transactionCount = transactionCount
        self.currency = currency
        self.lastUpdated = lastUpdated
        self.lastTransactionDate = lastTransactionDate

        // Генерация ID
        let subcatPart = subcategoryName ?? ""
        self.id = "\(categoryName)_\(subcatPart)_\(year)_\(month)_\(day)"
    }

    /// Создать ID для поиска агрегата
    static func makeId(
        category: String,
        subcategory: String? = nil,
        year: Int16,
        month: Int16,
        day: Int16 = 0
    ) -> String {
        let subcatPart = subcategory ?? ""
        return "\(category)_\(subcatPart)_\(year)_\(month)_\(day)"
    }
}
