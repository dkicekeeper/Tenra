//
//  OrderedWorkTests.swift
//  TenraTests
//
//  OrderedWork runs what it is given one piece after another, in the order it was queued: a slow
//  first piece holds the second back, and each piece hands back its own result.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct OrderedWorkTests {

    /// What ran, in order, from any thread.
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []

        func append(_ line: String) {
            lock.lock()
            lines.append(line)
            lock.unlock()
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return lines
        }
    }

    @Test("A slow first piece holds the second back")
    func runsInTheOrderAsked() async {
        let work = OrderedWork()
        let log = Log()
        // Queued synchronously, in this order; the first is slow.
        let first = work.enqueue { try? await Task.sleep(for: .milliseconds(50)); log.append("first") }
        let second = work.enqueue { log.append("second") }
        await first.value
        await second.value
        #expect(log.all == ["first", "second"])
    }

    @Test("Each piece hands back its own result")
    func returnsResults() async {
        let work = OrderedWork()
        let one = work.enqueue { 1 }
        let bee = work.enqueue { "b" }
        #expect(await one.value == 1)
        #expect(await bee.value == "b")
    }
}
