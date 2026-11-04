//
//  CoalescingTask.swift
//  Tenra
//
//  Runs async work one run at a time; requests made while it runs collapse into one more run
//  with the latest argument. For work that only needs the newest state, such as replacing the
//  spending reminder's notifications after every row of a statement import.
//

import Foundation

@MainActor
final class CoalescingTask<Argument> {
    private let work: (Argument) async -> Void
    /// The argument of the run still to come, if any.
    private var latest: Argument?
    private var running: Task<Void, Never>?

    init(_ work: @escaping (Argument) async -> Void) {
        self.work = work
    }

    /// Runs `work(argument)` now, or once more after the current run with the latest argument.
    func request(_ argument: Argument) {
        latest = argument
        guard running == nil else { return }
        running = Task { [weak self] in
            while let self, let next = self.latest {
                self.latest = nil
                await self.work(next)
            }
            self?.running = nil
        }
    }

    /// Returns once no run is going and none is waiting.
    func waitUntilIdle() async {
        while let running {
            await running.value
        }
    }
}
