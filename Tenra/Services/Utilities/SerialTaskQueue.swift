//
//  SerialTaskQueue.swift
//  Tenra
//
//  Writes one after another, in the order they were asked for (finding A4 of the assets audit,
//  docs/archive/assets-audit-2026-11-02.md): the stores of assets, goals and debts write on a
//  fresh background context each time (the container can be replaced on a restore), and two
//  quick writes on two contexts could finish in the other order, the older copy last on disk.
//  The order is taken on the main actor, where the stores change their memory.
//

import Foundation

@MainActor
final class SerialTaskQueue {
    private var tail: Task<Void, Never>?

    /// Runs `work` once everything enqueued before it has finished, and waits for it.
    func run(_ work: @escaping () async -> Void) async {
        let previous = tail
        let task = Task {
            await previous?.value
            await work()
        }
        tail = task
        await task.value
    }
}
