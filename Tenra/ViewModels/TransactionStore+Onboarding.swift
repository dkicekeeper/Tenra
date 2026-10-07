//
//  TransactionStore+Onboarding.swift
//  Tenra
//
//  The onboarding "Done" commit: the first account and the starter categories,
//  persisted once and before returning.
//
//  Why not addAccount + addCategory in a loop: every per-item add persists with
//  its own detached, wholesale save (the whole table, deleting rows not in the
//  snapshot). Fired as a burst of ~20, they collided in CoreDataSaveCoordinator,
//  which used to drop a save while another of the same name ran (it now queues
//  and coalesces them), so only the first snapshot (one category) reached
//  CoreData; a burst also costs ~20 table writes for one result. And on a fresh
//  install the first full load (`initialize()` → `loadData()`) starts the moment
//  onboarding completes and Home appears; it replaces the in-memory accounts and
//  categories with what CoreData holds, which was still nothing. Result: an
//  empty Home, then one account and one category after a relaunch.
//

import Foundation

extension TransactionStore {

    /// Adds the onboarding account and categories in memory, then writes them
    /// to CoreData synchronously, so the full load that follows reads them back.
    /// Duplicates (by id, or by name and type) are skipped as in `addCategory`.
    func commitOnboarding(account: Account?, categories newCategories: [CustomCategory]) throws {
        // Suppress the per-item detached saves; one save below covers them all.
        let wasImporting = isImporting
        isImporting = true
        if let account {
            addAccount(account)
        }
        for category in newCategories {
            addCategory(category)
        }
        isImporting = wasImporting

        // The UI order preferences the per-item paths skip in import mode.
        if let account, let order = account.order {
            AccountOrderManager.shared.setOrder(order, for: account.id)
        }
        let newIds = Set(newCategories.map(\.id))
        for category in categories where newIds.contains(category.id) {
            if let order = category.order {
                CategoryOrderManager.shared.setOrder(order, for: category.id)
            }
        }

        if let coreDataRepo = repository as? CoreDataRepository {
            try coreDataRepo.saveAccountsSync(accounts)
            try coreDataRepo.saveCategoriesSync(categories)
        } else {
            repository.saveAccounts(accounts)
            repository.saveCategories(categories)
        }
    }
}
