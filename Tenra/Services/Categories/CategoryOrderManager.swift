//
//  CategoryOrderManager.swift
//  AIFinanceManager
//
//  Manages category display order in UserDefaults
//  Separates UI preferences from business data
//

import Foundation

/// Manages category display order as a lightweight UI preference
nonisolated final class CategoryOrderManager: @unchecked Sendable {

    // MARK: - Storage Key

    private let userDefaults = UserDefaults.standard
    private let storageKey = "categoryOrderMap"

    // MARK: - Singleton

    static let shared = CategoryOrderManager()

    private init() {}

    // MARK: - Public Methods

    /// Get order for a specific category
    func getOrder(for categoryId: String) -> Int? {
        let orderMap = loadOrderMap()
        return orderMap[categoryId]
    }

    /// Set order for a specific category
    func setOrder(_ order: Int, for categoryId: String) {
        var orderMap = loadOrderMap()
        orderMap[categoryId] = order
        saveOrderMap(orderMap)
    }

    /// Set order for multiple categories at once
    func setOrders(_ orders: [String: Int]) {
        var orderMap = loadOrderMap()
        for (categoryId, order) in orders {
            orderMap[categoryId] = order
        }
        saveOrderMap(orderMap)
    }

    /// Remove order for a specific category
    func removeOrder(for categoryId: String) {
        var orderMap = loadOrderMap()
        orderMap.removeValue(forKey: categoryId)
        saveOrderMap(orderMap)
    }

    /// Apply stored orders to categories
    func applyOrders(to categories: [CustomCategory]) -> [CustomCategory] {
        let orderMap = loadOrderMap()

        return categories.map { category in
            var updatedCategory = category
            updatedCategory.order = orderMap[category.id]
            return updatedCategory
        }
    }

    /// Save orders from categories to UserDefaults
    func saveOrders(from categories: [CustomCategory]) {
        let orderMap = categories.reduce(into: [String: Int]()) { result, category in
            if let order = category.order {
                result[category.id] = order
            }
        }
        saveOrderMap(orderMap)
    }

    /// Clear all stored orders
    func clearAllOrders() {
        userDefaults.removeObject(forKey: storageKey)
    }

    // MARK: - Private Methods

    private func loadOrderMap() -> [String: Int] {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveOrderMap(_ orderMap: [String: Int]) {
        if let encoded = try? JSONEncoder().encode(orderMap) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}
