//
//  CoalescingTaskTests.swift
//  TenraTests
//
//  Pins CoalescingTask: requests made while its work runs collapse into one more run with the
//  latest argument, and a request after it went idle runs again. A statement import of 200 rows
//  must not queue 200 reschedules of the spending reminder.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CoalescingTaskTests {

    /// Holds the first run until `open()`.
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var isWaiting = false
        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                isWaiting = true
            }
        }
        func open() {
            isWaiting = false
            continuation?.resume()
            continuation = nil
        }
    }

    @Test("Fifty requests during a run become one more run with the last argument")
    func coalescesWhileRunning() async {
        let gate = Gate()
        var runs: [Int] = []
        let task = CoalescingTask<Int> { value in
            runs.append(value)
            if runs.count == 1 { await gate.wait() }
        }
        task.request(0)
        for _ in 0..<1000 where !gate.isWaiting { await Task.yield() }
        for value in 1...50 { task.request(value) }
        gate.open()
        await task.waitUntilIdle()
        #expect(runs == [0, 50])
    }

    @Test("A request after the work went idle runs again")
    func runsAgainAfterIdle() async {
        var runs: [Int] = []
        let task = CoalescingTask<Int> { runs.append($0) }
        task.request(1)
        await task.waitUntilIdle()
        task.request(2)
        await task.waitUntilIdle()
        #expect(runs == [1, 2])
    }
}
