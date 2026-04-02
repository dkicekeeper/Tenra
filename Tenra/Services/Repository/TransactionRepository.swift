//
//  TransactionRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Transaction-specific data persistence operations

import Foundation
import CoreData
import os

/// Protocol for transaction repository operations
protocol TransactionRepositoryProtocol: Sendable {
    nonisolated func loadTransactions(dateRange: DateInterval?) -> [Transaction]
    nonisolated func saveTransactions(_ transactions: [Transaction])
    nonisolated func saveTransactionsSync(_ transactions: [Transaction]) throws
    /// Immediately delete a single transaction from CoreData by ID (synchronous on background context).
    /// Use this for user-initiated deletions to guarantee the delete is persisted
    /// even if the app is killed shortly after.
    nonisolated func deleteTransactionImmediately(id: String)
    /// Insert a single new transaction. O(1) — does NOT fetch existing records.
    nonisolated func insertTransaction(_ transaction: Transaction)
    /// Update fields of an existing transaction by ID. O(1) — fetches by PK only.
    nonisolated func updateTransactionFields(_ transaction: Transaction)
    /// Batch-insert using NSBatchInsertRequest. O(N) — ideal for CSV import.
    nonisolated func batchInsertTransactions(_ transactions: [Transaction])
}

/// CoreData implementation of TransactionRepositoryProtocol
nonisolated final class TransactionRepository: TransactionRepositoryProtocol, @unchecked Sendable {

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "TransactionRepository")

    private let stack: CoreDataStack
    private let saveCoordinator: CoreDataSaveCoordinator
    private let userDefaultsRepository: UserDefaultsRepository

    init(
        stack: CoreDataStack = .shared,
        saveCoordinator: CoreDataSaveCoordinator,
        userDefaultsRepository: UserDefaultsRepository = UserDefaultsRepository()
    ) {
        self.stack = stack
        self.saveCoordinator = saveCoordinator
        self.userDefaultsRepository = userDefaultsRepository
    }

    // MARK: - Load Operations

    func loadTransactions(dateRange: DateInterval? = nil) -> [Transaction] {
        PerformanceProfiler.start("TransactionRepository.loadTransactions")

        // PERFORMANCE Phase 28-B: Use background context — never block the main thread for 19k entities.
        // performAndWait is synchronous but runs on the context's own serial queue (background thread).
        // Note: relationshipKeyPathsForPrefetching ["account", "targetAccount"] was removed.
        // toTransaction() uses string column fallbacks (accountId, accountName, etc.) for all
        // critical fields, so relationship faults are only triggered for legacy data.
        // Faults fire safely inside the performAndWait block; no batch prefetch needed.
        let bgContext = stack.newBackgroundContext()
        var transactions: [Transaction] = []
        var loadError: Error? = nil

        bgContext.performAndWait {
            let request = TransactionEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            // fetchBatchSize is meaningful here: CoreData loads entity data in batches of 500.
            request.fetchBatchSize = 500

            if let dateRange = dateRange {
                request.predicate = NSPredicate(
                    format: "date >= %@ AND date <= %@",
                    dateRange.start as NSDate,
                    dateRange.end as NSDate
                )
            }

            do {
                let entities = try bgContext.fetch(request)
                transactions = entities.map { $0.toTransaction() }
            } catch {
                loadError = error
            }
        }

        PerformanceProfiler.end("TransactionRepository.loadTransactions")

        if loadError != nil {
            return userDefaultsRepository.loadTransactions(dateRange: dateRange)
        }
        return transactions
    }

    // MARK: - Save Operations

    func saveTransactions(_ transactions: [Transaction]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            PerformanceProfiler.start("TransactionRepository.saveTransactions")
            let context = self.stack.newBackgroundContext()

            await context.perform {
                do {
                    let fetchRequest = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
                    let existingEntities = try context.fetch(fetchRequest)

                    var existingDict: [String: TransactionEntity] = [:]
                    for entity in existingEntities {
                        if let id = entity.id, !id.isEmpty {
                            existingDict[id] = entity
                        }
                    }

                    var keptIds = Set<String>()
                    for transaction in transactions {
                        keptIds.insert(transaction.id)
                        if let existing = existingDict[transaction.id] {
                            self.updateTransactionEntity(existing, from: transaction, context: context)
                        } else {
                            let entity = TransactionEntity.from(transaction, context: context)
                            self.setTransactionRelationships(entity, from: transaction, context: context)
                        }
                    }

                    for entity in existingEntities {
                        if let id = entity.id, !keptIds.contains(id) {
                            context.delete(entity)
                        }
                    }

                    if context.hasChanges {
                        try context.save()
                    }
                    PerformanceProfiler.end("TransactionRepository.saveTransactions")
                } catch {
                    Self.logger.error("saveTransactions failed: \(error.localizedDescription, privacy: .public)")
                    PerformanceProfiler.end("TransactionRepository.saveTransactions")
                }
            }
        }
    }

    func saveTransactionsSync(_ transactions: [Transaction]) throws {
        Self.logger.debug("🔄 [TransactionRepository] saveTransactionsSync START — \(transactions.count, privacy: .public) transactions to save")
        PerformanceProfiler.start("TransactionRepository.saveTransactionsSync")

        let backgroundContext = stack.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Capture the NSManagedObjectContextDidSave notification so we can merge it
        // SYNCHRONOUSLY into the viewContext after performAndWait returns.
        //
        // WHY: automaticallyMergesChangesFromParent dispatches the merge to the main queue
        // ASYNCHRONOUSLY. If saveTransactionsSync inserts objects that resolve uniqueness
        // constraint violations (old rows replaced with new IDs), the old NSManagedObjectIDs
        // in the FRC become stale. The async merge would fix this — but not before the main
        // thread continues executing (e.g., setting isImporting=false, which triggers
        // @Observable notifications and potential SwiftUI renders). Accessing a stale FRC
        // object before the merge completes → "persistent store is not reachable" crash.
        //
        // By capturing the notification and merging immediately after performAndWait, we
        // ensure the viewContext is up-to-date before any subsequent code can access stale objects.
        // NotificationBox: @unchecked Sendable wrapper so the @Sendable observer closure can
        // capture and store a Notification (which is not Sendable) without a warning.
        // This is safe because the closure and the reader (below performAndWait) run sequentially
        // on the same thread — no concurrent access occurs.
        final class NotificationBox: @unchecked Sendable { var value: Notification? }
        let notificationBox = NotificationBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: backgroundContext,
            queue: nil
        ) { notification in
            notificationBox.value = notification
        }

        try backgroundContext.performAndWait {
            // fetchBatchSize must be 0 here: intermediate saves within performAndWait
            // invalidate batch-fault buffers, causing "persistent store is not reachable"
            // when the delete loop accesses entities from a stale batch.
            // Also required for context.delete() on stale entities (see comment below).
            let fetchRequest = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
            fetchRequest.fetchBatchSize = 0

            let existingEntities = try backgroundContext.fetch(fetchRequest)
            Self.logger.debug("📋 [TransactionRepository] saveTransactionsSync: found \(existingEntities.count, privacy: .public) existing entities in CoreData")

            // Build ID → entity map; delete any duplicate-ID entities upfront
            var existingDict: [String: TransactionEntity] = [:]
            for entity in existingEntities {
                let id = entity.id ?? ""
                if !id.isEmpty && existingDict[id] == nil {
                    existingDict[id] = entity
                } else if !id.isEmpty {
                    backgroundContext.delete(entity)
                }
            }

            // Fetch accounts and recurring series for relationship wiring
            let accountFetchRequest = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
            let accountEntities = try backgroundContext.fetch(accountFetchRequest)
            var accountDict: [String: AccountEntity] = [:]
            for accountEntity in accountEntities {
                if let id = accountEntity.id {
                    accountDict[id] = accountEntity
                }
            }

            let seriesFetchRequest = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
            let seriesEntities = try backgroundContext.fetch(seriesFetchRequest)
            var seriesDict: [String: RecurringSeriesEntity] = [:]
            for seriesEntity in seriesEntities {
                if let id = seriesEntity.id {
                    seriesDict[id] = seriesEntity
                }
            }

            var keptIds = Set<String>(minimumCapacity: transactions.count)

            // Update existing entities or create new ones.
            // No intermediate saves — intermediate saves with fetchBatchSize > 0 cause
            // batch-fault invalidation and the "persistent store not reachable" crash.
            for transaction in transactions {
                keptIds.insert(transaction.id)

                if let existing = existingDict[transaction.id] {
                    updateTransactionEntity(
                        existing,
                        from: transaction,
                        accountDict: accountDict,
                        seriesDict: seriesDict
                    )
                } else {
                    let newEntity = TransactionEntity.from(transaction, context: backgroundContext)
                    setTransactionRelationships(
                        newEntity,
                        from: transaction,
                        accountDict: accountDict,
                        seriesDict: seriesDict
                    )
                }
            }

            // Delete stale entities using context.delete() — NOT NSBatchDeleteRequest.
            //
            // WHY NOT NSBatchDeleteRequest:
            // NSBatchDeleteRequest bypasses NSManagedObject lifecycle (writes directly to SQLite).
            // After executing it + calling mergeChanges(fromRemoteContextSave:into:backgroundContext),
            // the deleted objects end up in backgroundContext.deletedObjects. When backgroundContext.save()
            // runs, CoreData processes these deletedObjects and tries to nullify inverse relationships
            // (e.g. AccountEntity.transactions → remove the deleted TransactionEntity from the set).
            // To do this, CoreData needs to read the deleted entity's `account` relationship value
            // from the persistent store — but the batch delete already removed that row from SQLite.
            // Result: "Object TransactionEntity/pXXXX persistent store is not reachable" crash.
            //
            // WHY context.delete() IS SAFE HERE:
            // fetchBatchSize=0 at the top of this block ensures ALL TransactionEntity records are
            // materialized in memory before this point. The stale entities in existingDict are
            // already fully faulted-in (their data is in the context's row cache). context.delete()
            // marks them for deletion in the NSManagedObject lifecycle — CoreData reads their
            // relationship data from memory (not the store) during save(), correctly nullifying
            // inverse relationships without hitting the persistent store for already-live objects.
            let staleIds = existingDict.keys.filter { !keptIds.contains($0) }
            if !staleIds.isEmpty {
                Self.logger.debug("🗑️ [TransactionRepository] saveTransactionsSync: deleting \(staleIds.count, privacy: .public) stale entities")
                for staleId in staleIds {
                    if let entity = existingDict[staleId] {
                        backgroundContext.delete(entity)
                    }
                }
            }

            Self.logger.debug("💾 [TransactionRepository] saveTransactionsSync: saving — inserted=\(backgroundContext.insertedObjects.count, privacy: .public) updated=\(backgroundContext.updatedObjects.count, privacy: .public) deleted=\(backgroundContext.deletedObjects.count, privacy: .public)")

            // Single atomic save — safe because no intermediate saves polluted batch buffers
            if backgroundContext.hasChanges {
                try backgroundContext.save()
                Self.logger.debug("✅ [TransactionRepository] saveTransactionsSync: save succeeded")
            }
        }

        NotificationCenter.default.removeObserver(observer)

        // Merge the save SYNCHRONOUSLY into the viewContext on the main thread.
        // We're back on the calling thread (MainActor for finishImport) after performAndWait.
        // This ensures the viewContext (and its FRC) sees the new/updated/deleted objects
        // BEFORE any subsequent code runs (e.g., isImporting=false, @Observable notifications).
        // automaticallyMergesChangesFromParent will also process this later — double-merge is
        // idempotent (refresh already-refreshed objects = no-op).
        if let notification = notificationBox.value {
            stack.viewContext.mergeChanges(fromContextDidSave: notification)
        }

        PerformanceProfiler.end("TransactionRepository.saveTransactionsSync")
    }

    // MARK: - Delete Operations

    func deleteTransactionImmediately(id: String) {
        Self.logger.debug("🔵 [TransactionRepository] deleteTransactionImmediately called for id: \(id, privacy: .public)")
        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.performAndWait {
            let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            guard let entity = try? context.fetch(request).first else {
                Self.logger.warning("⚠️ [TransactionRepository] deleteTransactionImmediately: entity NOT FOUND for id: \(id, privacy: .public) (may not be persisted yet)")
                return
            }
            context.delete(entity)
            do {
                try context.save()
                Self.logger.debug("✅ [TransactionRepository] deleteTransactionImmediately: deleted and saved for id: \(id, privacy: .public)")
            } catch {
                Self.logger.error("deleteTransactionImmediately save failed for id \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Targeted Persist Methods (Phase 28-C)

    func insertTransaction(_ transaction: Transaction) {
        let bgContext = stack.newBackgroundContext()
        bgContext.performAndWait {
            // Create entity from Transaction model
            let entity = TransactionEntity.from(transaction, context: bgContext)

            // Resolve account relationship (best-effort; accountId String is the fallback)
            if let accountId = transaction.accountId, !accountId.isEmpty {
                let req = AccountEntity.fetchRequest()
                req.predicate = NSPredicate(format: "id == %@", accountId)
                req.fetchLimit = 1
                entity.account = try? bgContext.fetch(req).first
            }

            if let targetId = transaction.targetAccountId, !targetId.isEmpty {
                let req = AccountEntity.fetchRequest()
                req.predicate = NSPredicate(format: "id == %@", targetId)
                req.fetchLimit = 1
                entity.targetAccount = try? bgContext.fetch(req).first
            }

            if let seriesId = transaction.recurringSeriesId, !seriesId.isEmpty {
                let req = RecurringSeriesEntity.fetchRequest()
                req.predicate = NSPredicate(format: "id == %@", seriesId)
                req.fetchLimit = 1
                entity.recurringSeries = try? bgContext.fetch(req).first
            }

            do {
                try bgContext.save()
            } catch {
                Self.logger.error("⚠️ [TransactionRepository] insertTransaction save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func updateTransactionFields(_ transaction: Transaction) {
        let bgContext = stack.newBackgroundContext()
        // performAndWait (synchronous) — same reasoning as insertTransaction:
        // ensures the update completes before any subsequent deleteTransactionImmediately
        // on the same entity, preventing a race that leaves a stale CoreData record.
        bgContext.performAndWait {
            let req = TransactionEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", transaction.id)
            req.fetchLimit = 1
            guard let entity = (try? bgContext.fetch(req))?.first else { return }

            entity.date             = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
            entity.descriptionText  = transaction.description
            entity.amount           = transaction.amount
            entity.currency         = transaction.currency
            entity.convertedAmount  = transaction.convertedAmount ?? 0
            entity.type             = transaction.type.rawValue
            entity.category         = transaction.category
            entity.subcategory      = transaction.subcategory
            entity.targetAmount     = transaction.targetAmount ?? 0
            entity.targetCurrency   = transaction.targetCurrency
            entity.accountId        = transaction.accountId
            entity.targetAccountId  = transaction.targetAccountId
            entity.accountName      = transaction.accountName
            entity.targetAccountName = transaction.targetAccountName
            entity.recurringSeriesId = transaction.recurringSeriesId
            entity.createdAt        = Date(timeIntervalSince1970: transaction.createdAt)

            // Sync recurringSeries relationship
            if let seriesId = transaction.recurringSeriesId, !seriesId.isEmpty {
                let seriesReq = RecurringSeriesEntity.fetchRequest()
                seriesReq.predicate = NSPredicate(format: "id == %@", seriesId)
                seriesReq.fetchLimit = 1
                entity.recurringSeries = (try? bgContext.fetch(seriesReq))?.first
            } else {
                entity.recurringSeries = nil
            }

            do {
                try bgContext.save()
            } catch {
                Self.logger.error("⚠️ [TransactionRepository] updateTransactionFields save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func batchInsertTransactions(_ transactions: [Transaction]) {
        guard !transactions.isEmpty else { return }
        let bgContext = stack.newBackgroundContext()
        bgContext.perform {
            // NSBatchInsertRequest (iOS 14+): inserts directly into SQLite,
            // bypassing NSManagedObject lifecycle — ideal for CSV import of 1k+ records.
            // Relationships are NOT set; toTransaction() uses accountId/targetAccountId String columns.
            //
            // IMPORTANT: willSave() is NOT called for NSBatchInsertRequest, so dateSectionKey
            // must be set explicitly here. Without it every batch-imported record has nil
            // dateSectionKey, causing AppCoordinator.backfillDateSectionKeysIfNeeded() to run
            // on every subsequent launch (~700ms per launch for 18k transactions).
            let dicts: [[String: Any]] = transactions.map { tx in
                var dict: [String: Any] = [:]
                dict["id"]               = tx.id
                let dateValue            = DateFormatters.dateFormatter.date(from: tx.date) ?? Date()
                dict["date"]             = dateValue
                // Set dateSectionKey explicitly — NSBatchInsertRequest bypasses willSave(),
                // so the automatic TransactionEntity+SectionKey.swift override never fires.
                dict["dateSectionKey"]   = TransactionSectionKeyFormatter.string(from: dateValue)
                dict["descriptionText"]  = tx.description
                dict["amount"]           = tx.amount
                dict["currency"]         = tx.currency
                dict["convertedAmount"]  = tx.convertedAmount ?? 0.0
                dict["type"]             = tx.type.rawValue
                dict["category"]         = tx.category
                dict["subcategory"]      = tx.subcategory ?? ""
                dict["targetAmount"]     = tx.targetAmount ?? 0.0
                dict["targetCurrency"]   = tx.targetCurrency ?? ""
                dict["accountId"]        = tx.accountId ?? ""
                dict["targetAccountId"]  = tx.targetAccountId ?? ""
                dict["accountName"]      = tx.accountName ?? ""
                dict["targetAccountName"] = tx.targetAccountName ?? ""
                dict["recurringSeriesId"] = tx.recurringSeriesId ?? ""
                dict["createdAt"]        = Date(timeIntervalSince1970: tx.createdAt)
                return dict
            }

            let insertRequest = NSBatchInsertRequest(entityName: "TransactionEntity", objects: dicts)
            insertRequest.resultType = .objectIDs  // needed for viewContext merge in Task 7

            // NOTE: recurringSeries relationships are intentionally omitted here. NSBatchInsertRequest
            // bypasses NSManagedObject lifecycle and cannot resolve managed-object relationships.
            // recurringSeriesId String column is set directly so toTransaction() returns the correct value.
            do {
                let result = try bgContext.execute(insertRequest) as? NSBatchInsertResult
                // Merge inserted object IDs into viewContext so @Observable picks them up.
                // Must be dispatched to main queue because viewContext is main-thread-only.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stack.mergeBatchInsertResult(result)
                }
            } catch {
                Self.logger.error("⚠️ [TransactionRepository] batchInsertTransactions failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Private Helper Methods

    private nonisolated func updateTransactionEntity(
        _ entity: TransactionEntity,
        from transaction: Transaction,
        context: NSManagedObjectContext
    ) {
        // Mutate directly — caller is already inside context.perform { }, so nesting another
        // context.perform { } would make it async (fire-and-forget) and mutations would
        // execute AFTER context.save(), causing data loss on next launch.
        entity.date = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
        entity.descriptionText = transaction.description
        entity.amount = transaction.amount
        entity.currency = transaction.currency
        entity.convertedAmount = transaction.convertedAmount ?? 0
        entity.type = transaction.type.rawValue
        entity.category = transaction.category
        entity.subcategory = transaction.subcategory
        entity.targetAmount = transaction.targetAmount ?? 0
        entity.targetCurrency = transaction.targetCurrency
        entity.createdAt = Date(timeIntervalSince1970: transaction.createdAt)
        entity.accountName = transaction.accountName
        entity.targetAccountName = transaction.targetAccountName
        entity.accountId = transaction.accountId
        entity.targetAccountId = transaction.targetAccountId
        entity.recurringSeriesId = transaction.recurringSeriesId

        // Update relationships (also direct, same context.perform block)
        if let accountId = transaction.accountId {
            entity.account = fetchAccountSync(id: accountId, context: context)
        } else {
            entity.account = nil
        }
        if let targetAccountId = transaction.targetAccountId {
            entity.targetAccount = fetchAccountSync(id: targetAccountId, context: context)
        } else {
            entity.targetAccount = nil
        }
        if let seriesId = transaction.recurringSeriesId {
            entity.recurringSeries = fetchRecurringSeriesSync(id: seriesId, context: context)
        } else {
            entity.recurringSeries = nil
        }
    }

    private nonisolated func updateTransactionEntity(
        _ entity: TransactionEntity,
        from transaction: Transaction,
        accountDict: [String: AccountEntity],
        seriesDict: [String: RecurringSeriesEntity]
    ) {
        // Direct mutations — caller is already inside performAndWait { }, so nesting another
        // async perform { } would fire-and-forget and mutations would execute AFTER save(),
        // causing data loss on next launch.
        entity.date = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
        entity.descriptionText = transaction.description
        entity.amount = transaction.amount
        entity.currency = transaction.currency
        entity.convertedAmount = transaction.convertedAmount ?? 0
        entity.type = transaction.type.rawValue
        entity.category = transaction.category
        entity.subcategory = transaction.subcategory
        entity.targetAmount = transaction.targetAmount ?? 0
        entity.targetCurrency = transaction.targetCurrency
        entity.createdAt = Date(timeIntervalSince1970: transaction.createdAt)
        entity.accountName = transaction.accountName
        entity.accountId = transaction.accountId
        entity.targetAccountId = transaction.targetAccountId
        entity.targetAccountName = transaction.targetAccountName
        entity.recurringSeriesId = transaction.recurringSeriesId

        // Set relationships using pre-fetched dictionaries
        if let accountId = transaction.accountId {
            entity.account = accountDict[accountId]
        } else {
            entity.account = nil
        }

        if let targetAccountId = transaction.targetAccountId {
            entity.targetAccount = accountDict[targetAccountId]
        } else {
            entity.targetAccount = nil
        }

        if let seriesId = transaction.recurringSeriesId {
            entity.recurringSeries = seriesDict[seriesId]
        } else {
            entity.recurringSeries = nil
        }
    }

    private nonisolated func setTransactionRelationships(
        _ entity: TransactionEntity,
        from transaction: Transaction,
        context: NSManagedObjectContext
    ) {
        // Direct mutations — caller is already inside context.perform { }
        if let accountId = transaction.accountId {
            entity.account = fetchAccountSync(id: accountId, context: context)
        }
        if let targetAccountId = transaction.targetAccountId {
            entity.targetAccount = fetchAccountSync(id: targetAccountId, context: context)
        }
        if let seriesId = transaction.recurringSeriesId {
            entity.recurringSeries = fetchRecurringSeriesSync(id: seriesId, context: context)
        }
    }

    private nonisolated func setTransactionRelationships(
        _ entity: TransactionEntity,
        from transaction: Transaction,
        accountDict: [String: AccountEntity],
        seriesDict: [String: RecurringSeriesEntity]
    ) {
        // Direct mutations — caller is already inside performAndWait { }, so nesting another
        // async perform { } would fire-and-forget and mutations would execute AFTER save(),
        // causing data loss on next launch.
        if let accountId = transaction.accountId {
            entity.account = accountDict[accountId]
        }

        if let targetAccountId = transaction.targetAccountId {
            entity.targetAccount = accountDict[targetAccountId]
        }

        if let seriesId = transaction.recurringSeriesId {
            entity.recurringSeries = seriesDict[seriesId]
        }
    }

    private nonisolated func fetchAccountSync(id: String, context: NSManagedObjectContext) -> AccountEntity? {
        let request = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1

        return try? context.fetch(request).first
    }

    private nonisolated func fetchRecurringSeriesSync(id: String, context: NSManagedObjectContext) -> RecurringSeriesEntity? {
        let request = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1

        return try? context.fetch(request).first
    }
}
