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

    /// Queues `work` behind everything queued before it and returns its task. Synchronous on
    /// purpose: the place in the queue is taken when this is called, so callers on one actor
    /// (the stores' methods are `@MainActor`) keep the order of their calls. An async `run` would
    /// first hop to the global executor, and two callers could reach the queue in either order.
    func enqueue<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> Task<T, Never> {
        lock.lock()
        defer { lock.unlock() }
        let previous = tail
        let task = Task { () -> T in
            await previous?.value
            return await work()
        }
        tail = Task { _ = await task.value }
        return task
    }
}
