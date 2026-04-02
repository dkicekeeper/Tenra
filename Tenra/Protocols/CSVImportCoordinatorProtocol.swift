//
//  CSVImportCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Protocol for the main CSV import coordinator
/// Orchestrates the entire import flow with dependency injection
@MainActor
protocol CSVImportCoordinatorProtocol {
    /// Imports transactions from a CSV file with progress tracking and cancellation support
    /// - Parameters:
    ///   - csvFile: Parsed CSV file structure
    ///   - columnMapping: Column-to-field mapping configuration
    ///   - entityMapping: Account and category mapping configuration
    ///   - transactionsViewModel: Transactions view model for import
    ///   - categoriesViewModel: Categories view model for entity management
    ///   - accountsViewModel: Optional accounts view model for account management
    ///   - progress: Progress tracker with cancellation support
    /// - Returns: Comprehensive import statistics including performance metrics
    func importTransactions(
        csvFile: CSVFile,
        columnMapping: CSVColumnMapping,
        entityMapping: EntityMapping,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel?,
        progress: ImportProgress
    ) async -> ImportStatistics
}
