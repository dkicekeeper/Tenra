//
//  AccountOrderManagerTests.swift
//  TenraTests
//
//  M-13: account display order lives in UserDefaults (AccountOrderManager)
//  while accounts live in CoreData, so the two can drift (a stale order key
//  for a deleted account, or an account deleted during import which skips
//  removeOrder). `reconcile(withAccountIds:)` prunes stale keys on load.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct AccountOrderManagerTests {

    private func makeManager() -> (AccountOrderManager, UserDefaults) {
        let defaults = UserDefaults(suiteName: "tests.order.\(UUID().uuidString)")!
        return (AccountOrderManager(userDefaults: defaults), defaults)
    }

    @Test("reconcile prunes order keys for accounts that no longer exist")
    func reconcilePrunesStaleKeys() {
        let (manager, _) = makeManager()
        manager.setOrders(["a1": 0, "a2": 1, "ghost": 2])

        // Only a1 and a2 still exist; "ghost" was deleted.
        let removed = manager.reconcile(withAccountIds: ["a1", "a2"])

        #expect(removed == 1, "exactly one stale key should be pruned")
        #expect(manager.getOrder(for: "ghost") == nil, "stale key removed")
        #expect(manager.getOrder(for: "a1") == 0, "live key preserved")
        #expect(manager.getOrder(for: "a2") == 1, "live key preserved")
    }

    @Test("reconcile is a no-op when the order map is already in sync")
    func reconcileNoOpWhenInSync() {
        let (manager, _) = makeManager()
        manager.setOrders(["a1": 0, "a2": 1])

        let removed = manager.reconcile(withAccountIds: ["a1", "a2"])

        #expect(removed == 0, "no stale keys → no removal")
        #expect(manager.getOrder(for: "a1") == 0)
        #expect(manager.getOrder(for: "a2") == 1)
    }

    @Test("reconcile against empty account set clears all keys")
    func reconcileEmptyAccountsClearsAll() {
        let (manager, _) = makeManager()
        manager.setOrders(["a1": 0, "a2": 1])

        let removed = manager.reconcile(withAccountIds: [])

        #expect(removed == 2)
        #expect(manager.getOrder(for: "a1") == nil)
        #expect(manager.getOrder(for: "a2") == nil)
    }
}
