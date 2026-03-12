//
//  CSVImportCoordinator.swift
//  AIFinanceManager
//
//  Simplified CSV Import Architecture - Phase 11
//  Removed CSVStorageCoordinator - direct TransactionStore interaction
//

import Foundation
import os

/// Simplified coordinator for CSV import operations
/// Works directly with TransactionStore - removed CSVStorageCoordinator layer
@MainActor
class CSVImportCoordinator: CSVImportCoordinatorProtocol {

    // MARK: - Dependencies

    private let parser: CSVParsingServiceProtocol
    private let validator: CSVValidationServiceProtocol
    private let mapper: EntityMappingServiceProtocol
    // Phase 37: converter removed — convertRow() merged into EntityMappingServiceProtocol.
    // Use mapper.convertRow(...) directly.
    private let cache: ImportCacheManager
    private let logger = Logger(subsystem: "AIFinanceManager", category: "CSVImportCoordinator")

    // MARK: - Initialization

    init(
        parser: CSVParsingServiceProtocol,
        validator: CSVValidationServiceProtocol,
        mapper: EntityMappingServiceProtocol,
        cache: ImportCacheManager
    ) {
        self.parser = parser
        self.validator = validator
        self.mapper = mapper
        self.cache = cache
    }

    // MARK: - CSVImportCoordinatorProtocol

    func importTransactions(
        csvFile: CSVFile,
        columnMapping: CSVColumnMapping,
        entityMapping: EntityMapping,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel?,
        progress: ImportProgress
    ) async -> ImportStatistics {

        let startTime = Date()

        // Initialize statistics builder
        let stats = ImportStatisticsBuilder()
        stats.totalRows = csvFile.rowCount

        // Build fingerprint set for duplicate detection
        let existingFingerprints = Set(
            transactionsViewModel.allTransactions.map { TransactionFingerprint(from: $0) }
        )
        logger.debug("📊 [CSVImport] START — rows:\(csvFile.rowCount) existingFingerprints:\(existingFingerprints.count)")
        var debugValidationSkips = 0
        var debugDuplicateSkips = 0
        var debugBatchSkips = 0
        var debugFirstSkipDetails: [(Int, String)] = [] // (rowIndex, reason)

        // Begin import mode in TransactionStore (defers persistence)
        if let transactionStore = transactionsViewModel.transactionStore {
            transactionStore.beginImport()
        }

        // Begin batch mode
        transactionsViewModel.beginBatch()

        // Process rows in batches
        var transactionsBatch: [Transaction] = []
        var subcategoryLinksBatch: [String: [String]] = [:]
        transactionsBatch.reserveCapacity(500)

        for (rowIndex, row) in csvFile.rows.enumerated() {

            // Check cancellation
            if progress.isCancelled {
                break
            }

            // Update progress
            progress.currentRow = rowIndex + 1

            // Yield to allow UI updates every 10 rows
            if rowIndex % 10 == 0 {
                await Task.yield()
            }

            // Validate row
            let validationResult = validator.validateRow(
                row,
                at: rowIndex,
                mapping: columnMapping
            )

            guard case .success(let csvRow) = validationResult else {
                if case .failure(let error) = validationResult {
                    stats.addError(error)
                    debugValidationSkips += 1
                    if debugFirstSkipDetails.count < 20 {
                        debugFirstSkipDetails.append((rowIndex, "validation: \(error.code) col=\(error.column ?? "?") val=\(error.context)"))
                    }
                }
                stats.incrementSkipped()
                continue
            }

            // Resolve account
            let accountResult = await mapper.resolveAccount(
                name: csvRow.effectiveAccountValue,
                currency: csvRow.currency,
                mapping: entityMapping
            )

            let accountId: String?
            switch accountResult {
            case .existing(let id), .created(let id):
                accountId = id
                if case .created = accountResult {
                    stats.incrementCreatedAccounts()
                }
            case .skipped:
                accountId = nil
            }

            // Resolve target account (for transfers)
            var targetAccountId: String? = nil
            if csvRow.type != .income,
               let targetAccountValue = csvRow.rawTargetAccountValue,
               !targetAccountValue.isEmpty {

                let targetResult = await mapper.resolveAccount(
                    name: targetAccountValue,
                    currency: csvRow.targetCurrency ?? csvRow.currency,
                    mapping: entityMapping
                )

                switch targetResult {
                case .existing(let id), .created(let id):
                    targetAccountId = id
                    if case .created = targetResult {
                        stats.incrementCreatedAccounts()
                    }
                case .skipped:
                    break
                }
            }

            // Resolve category
            let categoryName = resolveCategoryName(for: csvRow)

            let categoryResult = await mapper.resolveCategory(
                name: categoryName,
                type: csvRow.type,
                mapping: entityMapping
            )

            let categoryId: String
            let finalCategoryName: String
            switch categoryResult {
            case .existing(let id, let name):
                categoryId = id
                finalCategoryName = name
            case .created(let id, let name):
                categoryId = id
                finalCategoryName = name
                stats.incrementCreatedCategories()
            }

            // Resolve subcategories
            var subcategoryIds: [String] = []
            if !csvRow.subcategoryNames.isEmpty {
                let subcategoryResults = await mapper.resolveSubcategories(
                    names: csvRow.subcategoryNames,
                    categoryId: categoryId
                )

                for result in subcategoryResults {
                    switch result {
                    case .existing(let id):
                        subcategoryIds.append(id)
                    case .created(let id):
                        subcategoryIds.append(id)
                        stats.incrementCreatedSubcategories()
                    }
                }
            }

            // Convert to transaction (convertRow merged into mapper — Phase 37)
            let transaction = mapper.convertRow(
                csvRow,
                accountId: accountId,
                targetAccountId: targetAccountId,
                categoryName: finalCategoryName,
                categoryId: categoryId,
                subcategoryIds: subcategoryIds,
                rowIndex: rowIndex
            )

            // Check duplicates
            let fingerprint = TransactionFingerprint(from: transaction)
            if existingFingerprints.contains(fingerprint) {
                debugDuplicateSkips += 1
                if debugFirstSkipDetails.count < 20 {
                    debugFirstSkipDetails.append((rowIndex, "duplicate: date=\(transaction.date) amount=\(transaction.amount) type=\(transaction.type) cat=\(transaction.category)"))
                }
                stats.incrementDuplicates()
                stats.incrementSkipped()
                continue
            }

            // Add to batch
            transactionsBatch.append(transaction)
            if !subcategoryIds.isEmpty {
                subcategoryLinksBatch[transaction.id] = subcategoryIds
            }

            stats.incrementImported()

            // Process batch if full or last row
            if transactionsBatch.count >= 500 || rowIndex == csvFile.rowCount - 1 {
                // ✨ Phase 11: Direct TransactionStore interaction (no CSVStorageCoordinator)
                if let transactionStore = transactionsViewModel.transactionStore {
                    do {
                        try await transactionStore.addBatch(transactionsBatch)
                    } catch {
                        // Batch-level validation failed for at least one transaction.
                        // Fallback: try adding transactions individually to salvage valid ones.
                        logger.warning("⚠️ [CSVImport] addBatch FAILED for \(transactionsBatch.count) rows: \(error.localizedDescription). Falling back to individual adds.")

                        var batchSalvaged = 0
                        var batchSkippedInFallback = 0
                        for tx in transactionsBatch {
                            do {
                                _ = try await transactionStore.add(tx)
                                batchSalvaged += 1
                            } catch {
                                batchSkippedInFallback += 1
                                debugBatchSkips += 1
                                if debugFirstSkipDetails.count < 20 {
                                    debugFirstSkipDetails.append((-1, "batchValidation: \(error.localizedDescription) date=\(tx.date) type=\(tx.type) cat='\(tx.category)' acctId=\(tx.accountId ?? "nil") targetAcctId=\(tx.targetAccountId ?? "nil")"))
                                }
                            }
                        }

                        // Adjust stats: only count actually-skipped rows, not the whole batch
                        stats.skippedCount += batchSkippedInFallback
                        stats.importedCount -= batchSkippedInFallback

                        logger.debug("📊 [CSVImport] batch fallback: salvaged \(batchSalvaged), skipped \(batchSkippedInFallback)")
                    }

                    // Batch link subcategories
                    if !subcategoryLinksBatch.isEmpty {
                        var updatedLinks = transactionStore.transactionSubcategoryLinks
                        let transactionIds = Set(subcategoryLinksBatch.keys)
                        updatedLinks.removeAll { transactionIds.contains($0.transactionId) }

                        for (transactionId, subcategoryIds) in subcategoryLinksBatch {
                            for subcategoryId in subcategoryIds {
                                let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
                                updatedLinks.append(link)
                            }
                        }

                        transactionStore.updateTransactionSubcategoryLinks(updatedLinks)
                    }
                }

                transactionsBatch.removeAll(keepingCapacity: true)
                subcategoryLinksBatch.removeAll(keepingCapacity: true)
            }
        }

        // ✨ Phase 11: Finalize import - direct TransactionStore interaction
        if let transactionStore = transactionsViewModel.transactionStore {
            do {
                try await transactionStore.finishImport()
            } catch {
                // Capture persistence failure so the result screen can warn the user.
                // Imported data is in-memory but may not have been written to CoreData.
                stats.persistenceError = error.localizedDescription
            }
        }

        // End batch + recalculate balances
        transactionsViewModel.endBatchWithoutSave()

        // Rebuild indexes and caches
        transactionsViewModel.rebuildIndexes()
        transactionsViewModel.precomputeCurrencyConversions()

        // Register accounts in BalanceCoordinator
        if let accountsVM = accountsViewModel,
           let balanceCoordinator = transactionsViewModel.balanceCoordinator {
            await balanceCoordinator.registerAccounts(accountsVM.accounts)

            for account in accountsVM.accounts {
                let initialBalance = accountsVM.getInitialBalance(for: account.id) ?? 0
                await balanceCoordinator.setInitialBalance(initialBalance, for: account.id)

                if !account.shouldCalculateFromTransactions {
                    await balanceCoordinator.markAsManual(account.id)
                }
            }

            // ✅ CRITICAL: Recalculate balances after CSV import
            // This ensures all accounts reflect the imported transactions
            await balanceCoordinator.recalculateAll(
                accounts: accountsVM.accounts,
                transactions: transactionsViewModel.allTransactions
            )
        }

        // Rebuild aggregate cache
        await transactionsViewModel.rebuildAggregateCacheAfterImport()

        // @Observable handles UI updates automatically - no need for objectWillChange.send()

        // Clear cache
        cache.clear()

        // Build final statistics
        let duration = Date().timeIntervalSince(startTime)

        // Diagnostic summary
        logger.debug("📊 [CSVImport] DONE — imported:\(stats.importedCount) validationSkips:\(debugValidationSkips) duplicateSkips:\(debugDuplicateSkips) batchSkips:\(debugBatchSkips) totalSkipped:\(stats.skippedCount)")
        for (idx, reason) in debugFirstSkipDetails {
            logger.debug("📊 [CSVImport] skip row[\(idx)]: \(reason, privacy: .public)")
        }

        return stats.build(duration: duration)
    }

    // MARK: - Private Helpers

    private func resolveCategoryName(for csvRow: CSVRow) -> String {
        if csvRow.type == .internalTransfer {
            return TransactionType.transferCategoryName
        } else if csvRow.effectiveCategoryValue.isEmpty {
            return String(localized: "category.other")
        } else {
            return csvRow.effectiveCategoryValue
        }
    }
}

// MARK: - Statistics Builder

/// Helper class for building import statistics
private class ImportStatisticsBuilder {
    var totalRows: Int = 0
    var importedCount: Int = 0
    var skippedCount: Int = 0
    var duplicatesSkipped: Int = 0
    var createdAccounts: Int = 0
    var createdCategories: Int = 0
    var createdSubcategories: Int = 0
    var errors: [CSVValidationError] = []
    var persistenceError: String? = nil

    func incrementImported() { importedCount += 1 }
    func incrementSkipped() { skippedCount += 1 }
    func incrementDuplicates() { duplicatesSkipped += 1 }
    func incrementCreatedAccounts() { createdAccounts += 1 }
    func incrementCreatedCategories() { createdCategories += 1 }
    func incrementCreatedSubcategories() { createdSubcategories += 1 }
    func addError(_ error: CSVValidationError) { errors.append(error) }

    func build(duration: TimeInterval) -> ImportStatistics {
        let rowsPerSecond = totalRows > 0 ? Double(totalRows) / duration : 0.0

        return ImportStatistics(
            totalRows: totalRows,
            importedCount: importedCount,
            skippedCount: skippedCount,
            duplicatesSkipped: duplicatesSkipped,
            createdAccounts: createdAccounts,
            createdCategories: createdCategories,
            createdSubcategories: createdSubcategories,
            duration: duration,
            rowsPerSecond: rowsPerSecond,
            errors: errors,
            persistenceError: persistenceError
        )
    }
}
