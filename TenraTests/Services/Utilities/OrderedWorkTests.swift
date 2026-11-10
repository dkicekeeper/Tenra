//
//  OrderedWorkTests.swift
//  TenraTests
//
//  OrderedWork runs what it is given one piece after another, in the order asked: a slow first
//  piece holds the second back, and each caller gets its own result.
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
        // Tasks made on the main actor start in the order they were made.
        let first = Task { await work.run { try? await Task.sleep(for: .milliseconds(50)); log.append("first") } }
        let second = Task { await work.run { log.append("second") } }
        await first.value
        await second.value
        #expect(log.all == ["first", "second"])
    }

    @Test("Each caller gets its own result")
    func returnsResults() async {
        let work = OrderedWork()
        async let a = work.run { 1 }
        async let b = work.run { "b" }
        let (one, bee) = await (a, b)
        #expect(one == 1)
        #expect(bee == "b")
    }
}
