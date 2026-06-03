//
//  CSVImportCoordinator.swift
//  Tenra
//
//  Coordinates CSV import: parsing, validation, mapping, and batch insertion.
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
    private let cache: ImportCacheManager
    private let logger = Logger(subsystem: "Tenra", category: "CSVImportCoordinator")

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

            // Convert to transaction
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

        // Whether the imported transactions were durably written to CoreData.
        // When finishImport() throws, the rows live only in memory — so we must
        // NOT persist balances derived from them (H-10): the balance write is NOT
        // gated by isImporting, so recalculateAll/setInitialBalance below would
        // persist a balance reflecting transactions that aren't on disk →
        // warm-start overcount. Aggregate persistence is already safe (the
        // finishImport re-throw runs before its flush* calls, and the debounced
        // schedulers are isImporting-gated).
        var transactionsPersisted = true
        if let transactionStore = transactionsViewModel.transactionStore {
            do {
                try await transactionStore.finishImport()
            } catch {
                // Capture persistence failure so the result screen can warn the user.
                // Imported data is in-memory but may not have been written to CoreData.
                stats.persistenceError = error.localizedDescription
                transactionsPersisted = false
            }
        }

        // End batch + recalculate balances
        transactionsViewModel.endBatchWithoutSave()

        // Rebuild indexes and caches
        transactionsViewModel.rebuildIndexes()

        // Register accounts in BalanceCoordinator — but only persist balances when
        // the transactions they're derived from were durably written. Persisting a
        // balance for non-durable tx leaves the next launch with a balance that
        // overcounts transactions absent from CoreData (H-10).
        if Self.mayPersistBalances(transactionsPersisted: transactionsPersisted),
           let accountsVM = accountsViewModel,
           let balanceCoordinator = transactionsViewModel.balanceCoordinator {
            await balanceCoordinator.registerAccounts(accountsVM.accounts)

            for account in accountsVM.accounts {
                let initialBalance = accountsVM.getInitialBalance(for: account.id) ?? 0
                await balanceCoordinator.setInitialBalance(initialBalance, for: account.id)
            }

            // ✅ CRITICAL: Recalculate balances after CSV import
            // This ensures all accounts reflect the imported transactions
            await balanceCoordinator.recalculateAll(
                accounts: accountsVM.accounts,
                transactions: transactionsViewModel.allTransactions
            )
        } else if !transactionsPersisted {
            logger.error("⚠️ [CSVImport] finishImport failed — skipping balance recalc/persist to avoid warm-start overcount (H-10)")
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

    // MARK: - Import Durability (H-10)

    /// THE rule for whether balances may be persisted after an import attempt.
    ///
    /// Balance persistence is NOT gated by `isImporting` (unlike the aggregate
    /// schedulers), so if `finishImport()` failed to write the transactions to
    /// CoreData, recalculating and persisting balances from those in-memory rows
    /// would leave the next launch with a balance that overcounts transactions
    /// absent from disk. Only persist balances when the tx write was durable.
    ///
    /// Pure + static so the decision is unit-testable without the full import
    /// integration harness.
    nonisolated static func mayPersistBalances(transactionsPersisted: Bool) -> Bool {
        transactionsPersisted
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
