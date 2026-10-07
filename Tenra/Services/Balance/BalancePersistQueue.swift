//
//  BalancePersistQueue.swift
//  Tenra
//
//  One serial writer for account balances.
//
//  Every balance change used to start its own detached save of the full value. A
//  burst (a bulk add, a statement import, the deposits pass at launch) could finish
//  out of order, and the next launch trusts whatever landed last: registerAccounts
//  shows the persisted `account.balance` until something recalculates it. So an
//  older balance could outlive a newer one.
//
//  This queue keeps the latest value per account and writes from one task at a
//  time. Values submitted while a write runs merge into the next write, so the
//  newest value of every account is always the last one written.
//

import Foundation

nonisolated final class BalancePersistQueue: @unchecked Sendable {

    private let lock = NSLock()
    /// Account id → newest balance not yet handed to `write`.
    private var pending: [String: Double] = [:]
    private var isWriting = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private let write: @Sendable ([String: Double]) async -> Void

    /// - Parameter write: Persists one batch and returns once it is saved. Never called
    ///   twice at the same time.
    init(write: @escaping @Sendable ([String: Double]) async -> Void) {
        self.write = write
    }

    /// Queues the newest balance of each given account. Call in the order the values
    /// were computed (BalanceCoordinator does, on the main actor).
    func submit(_ balances: [String: Double]) {
        guard !balances.isEmpty else { return }
        let startsWriter: Bool = lock.withLock {
            pending.merge(balances) { _, newer in newer }
            guard !isWriting else { return false }
            isWriting = true
            return true
        }
        if startsWriter {
            Task.detached(priority: .userInitiated) { [self] in
                await drain()
            }
        }
    }

    /// Returns once nothing is waiting to be written and no write is running.
    func waitUntilIdle() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isIdle: Bool = lock.withLock {
                guard isWriting || !pending.isEmpty else { return true }
                idleWaiters.append(continuation)
                return false
            }
            if isIdle { continuation.resume() }
        }
    }

    private func drain() async {
        while true {
            let step: (batch: [String: Double]?, waiters: [CheckedContinuation<Void, Never>]) = lock.withLock {
                guard !pending.isEmpty else {
                    isWriting = false
                    let waiters = idleWaiters
                    idleWaiters = []
                    return (nil, waiters)
                }
                let batch = pending
                pending = [:]
                return (batch, [])
            }
            guard let batch = step.batch else {
                for waiter in step.waiters { waiter.resume() }
                return
            }
            await write(batch)
        }
    }
}
