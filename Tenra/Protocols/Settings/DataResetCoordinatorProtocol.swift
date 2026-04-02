//
//  DataResetCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation

/// Protocol for coordinating data reset and recalculation operations
/// Centralizes dangerous operations that affect multiple ViewModels
protocol DataResetCoordinatorProtocol {
    /// Reset all application data (transactions, accounts, categories, etc.)
    /// - Throws: DataResetError if reset fails
    func resetAllData() async throws

    /// Recalculate all account balances from transactions
    /// - Throws: DataResetError if recalculation fails
    func recalculateAllBalances() async throws
}

/// Errors that can occur during data reset operations
enum DataResetError: LocalizedError {
    case resetFailed(underlying: Error)
    case recalculationFailed(underlying: Error)
    case viewModelNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .resetFailed(let error):
            return String(localized: "error.reset.failed", defaultValue: "Failed to reset data: \(error.localizedDescription)")
        case .recalculationFailed(let error):
            return String(localized: "error.recalculation.failed", defaultValue: "Failed to recalculate balances: \(error.localizedDescription)")
        case .viewModelNotAvailable(let name):
            return String(localized: "error.reset.viewModelNotAvailable", defaultValue: "Required view model not available: \(name)")
        }
    }
}
