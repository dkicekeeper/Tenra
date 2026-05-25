//
//  AccountOrderManager.swift
//  Tenra
//
//  Manages account display order in UserDefaults
//  Separates UI preferences from business data
//

import Foundation

/// Manages account display order as a lightweight UI preference
final class AccountOrderManager {

    // MARK: - Storage Key

    private let userDefaults: UserDefaults
    private let storageKey = "accountOrderMap"

    // MARK: - Singleton

    static let shared = AccountOrderManager()

    private init() {
        self.userDefaults = .standard
    }

    /// Test seam — inject an isolated `UserDefaults` suite.
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    // MARK: - Public Methods

    /// Get order for a specific account
    func getOrder(for accountId: String) -> Int? {
        let orderMap = loadOrderMap()
        return orderMap[accountId]
    }

    /// Set order for a specific account
    func setOrder(_ order: Int, for accountId: String) {
        var orderMap = loadOrderMap()
        orderMap[accountId] = order
        saveOrderMap(orderMap)
    }

    /// Set order for multiple accounts at once
    func setOrders(_ orders: [String: Int]) {
        var orderMap = loadOrderMap()
        for (accountId, order) in orders {
            orderMap[accountId] = order
        }
        saveOrderMap(orderMap)
    }

    /// Remove order for a specific account
    func removeOrder(for accountId: String) {
        var orderMap = loadOrderMap()
        orderMap.removeValue(forKey: accountId)
        saveOrderMap(orderMap)
    }

    /// Apply stored orders to accounts
    func applyOrders(to accounts: [Account]) -> [Account] {
        let orderMap = loadOrderMap()

        return accounts.map { account in
            var updatedAccount = account
            updatedAccount.order = orderMap[account.id]
            return updatedAccount
        }
    }

    /// Save orders from accounts to UserDefaults
    func saveOrders(from accounts: [Account]) {
        let orderMap = accounts.reduce(into: [String: Int]()) { result, account in
            if let order = account.order {
                result[account.id] = order
            }
        }
        saveOrderMap(orderMap)
    }

    /// Clear all stored orders
    func clearAllOrders() {
        userDefaults.removeObject(forKey: storageKey)
    }

    /// Prune order keys for accounts that no longer exist (M-13). The order map
    /// lives in UserDefaults while accounts live in CoreData, so the two stores
    /// can drift — e.g. an account deleted while `isImporting` (delete paths skip
    /// `removeOrder` during import), or a wholesale account-set replacement via
    /// CSV import. Called on load with the authoritative account ids; returns the
    /// number of stale keys removed (0 when already in sync — no write).
    @discardableResult
    func reconcile(withAccountIds knownAccountIds: Set<String>) -> Int {
        let orderMap = loadOrderMap()
        let staleKeys = orderMap.keys.filter { !knownAccountIds.contains($0) }
        guard !staleKeys.isEmpty else { return 0 }
        var pruned = orderMap
        for key in staleKeys { pruned.removeValue(forKey: key) }
        saveOrderMap(pruned)
        return staleKeys.count
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
