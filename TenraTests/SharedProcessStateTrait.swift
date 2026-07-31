//
//  SharedProcessStateTrait.swift
//  TenraTests
//
//  Cross-suite serialization for tests that touch process-global state.
//
//  `.serialized` only orders tests *within* one suite. Several suites here
//  build in-memory NSPersistentContainers all named "Tenra"
//  (CoreDataRoundTripTests documents that same-named in-memory stores can share
//  a backing store), and several mutate the process-global
//  CurrencyRateStore.shared. Two such suites running concurrently corrupt each
//  other, which surfaced as a full-suite run failing roughly half the time with
//  a different random set of tests each run, and unrelated suites getting
//  blamed for it.
//
//  Apply `.sharedProcessState` to any suite that touches either resource.
//

import Testing

struct SharedProcessState: TestTrait, SuiteTrait, TestScoping {

    /// Applies to every test inside an annotated suite.
    var isRecursive: Bool { true }

    private static let gate = Gate()

    /// Scope individual test cases only, never the suite itself. Scoping both
    /// would have a suite hold the lock while its own tests wait for it, which
    /// deadlocks.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        await Self.gate.acquire()
        do {
            try await function()
        } catch {
            await Self.gate.release()
            throw error
        }
        await Self.gate.release()
    }
}

extension Trait where Self == SharedProcessState {
    /// Serializes this suite's tests against every other suite carrying the
    /// same trait.
    static var sharedProcessState: Self { Self() }
}

/// Async mutex. A semaphore would block a cooperative thread; this suspends
/// instead, and hands ownership straight to the next waiter so no test can be
/// starved.
private actor Gate {

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            // Stays held, ownership transfers to the resumed waiter.
            waiters.removeFirst().resume()
        }
    }
}
