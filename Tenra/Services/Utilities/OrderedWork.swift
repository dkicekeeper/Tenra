//
//  OrderedWork.swift
//  Tenra
//
//  Work done one piece after another, in the order it was asked for, from any isolation. The
//  assistant's thread and fact stores (AgentThreadStore, AgentFactStore) use a fresh background
//  context per call (the container can be replaced on a restore), so two calls could run side
//  by side: two saves of one thread both inserted it (no uniqueness constraint), and a delete
//  could finish before a save that started earlier, bringing the chat back. Each call is queued
//  behind the ones before it. SerialTaskQueue does the same for the main-actor stores.
//

import Foundation

nonisolated final class OrderedWork: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    /// Runs `work` once everything asked for before it has finished, and returns its result.
    func run<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
        lock.lock()
        let previous = tail
        let task = Task { () -> T in
            await previous?.value
            return await work()
        }
        tail = Task { _ = await task.value }
        lock.unlock()
        return await task.value
    }
}
