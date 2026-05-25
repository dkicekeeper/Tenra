//
//  CSVImportDurabilityTests.swift
//  TenraTests
//
//  H-10: balance persistence after a CSV import must be gated on the import's
//  durability. `finishImport()` persists transactions inside a do/catch that
//  re-throws on failure BEFORE its aggregate flush* calls — so aggregates are
//  never persisted from non-durable tx. Balances, however, are persisted by
//  BalanceCoordinator.recalculateAll / setInitialBalance, which are NOT gated by
//  isImporting and run AFTER the coordinator swallows the finishImport error.
//  Persisting a balance derived from transactions that never reached CoreData
//  leaves the next launch overcounting → drift. `mayPersistBalances` is the rule
//  that closes that path.
//

import Testing
@testable import Tenra

@MainActor
struct CSVImportDurabilityTests {

    @Test("balances may be persisted only when transactions were durably written")
    func mayPersistOnlyWhenDurable() {
        #expect(CSVImportCoordinator.mayPersistBalances(transactionsPersisted: true) == true)
        #expect(CSVImportCoordinator.mayPersistBalances(transactionsPersisted: false) == false,
                "finishImport failure → tx not on disk → must NOT persist balances (H-10 overcount)")
    }
}
