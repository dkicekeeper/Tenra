//
//  ExportCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation
import Observation

/// Coordinator for data export operations
/// Handles CSV export with progress tracking and async operations
@Observable
@MainActor
final class ExportCoordinator: ExportCoordinatorProtocol {
    // MARK: - Observable State

    private(set) var exportProgress: Double = 0

    // MARK: - Dependencies (weak to prevent retain cycles)

    @ObservationIgnored private weak var transactionsViewModel: TransactionsViewModel?
    @ObservationIgnored private weak var accountsViewModel: AccountsViewModel?

    init(
        transactionsViewModel: TransactionsViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
    }

    // MARK: - ExportCoordinatorProtocol

    func exportAllData() async throws -> URL {

        guard let transactionsViewModel = transactionsViewModel else {
            throw ExportError.exportFailed(underlying: NSError(
                domain: "ExportCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "TransactionsViewModel not available"]
            ))
        }

        guard let accountsViewModel = accountsViewModel else {
            throw ExportError.exportFailed(underlying: NSError(
                domain: "ExportCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AccountsViewModel not available"]
            ))
        }

        let transactions = transactionsViewModel.allTransactions
        let accounts = accountsViewModel.accounts

        // Gather subcategory data for full export
        let subcategoryLinks = transactionsViewModel.transactionStore?.transactionSubcategoryLinks ?? []
        let subcategories = transactionsViewModel.transactionStore?.subcategories ?? []

        // Check if there's data to export
        guard !transactions.isEmpty else {
            throw ExportError.noDataToExport
        }

        // Reset progress
        exportProgress = 0

        // Capture all data on MainActor before switching to background
        let csvString = CSVExporter.exportTransactions(
            transactions,
            accounts: accounts,
            subcategoryLinks: subcategoryLinks,
            subcategories: subcategories
        )

        updateProgress(0.7)

        // Write file in background
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let dateString = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "transactions_export_\(dateString).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        updateProgress(0.9)

        try csvString.write(to: tempURL, atomically: true, encoding: .utf8)

        updateProgress(1.0)

        return tempURL
    }

    // MARK: - Dependency Injection

    func setDependencies(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
    }

    // MARK: - Private Helpers

    /// Update export progress (already on MainActor via class isolation)
    private func updateProgress(_ value: Double) {
        exportProgress = value
    }
}
