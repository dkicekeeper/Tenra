//
//  ActivationAttributesTests.swift
//  TenraTests
//
//  Pins the anonymous activation attributes sent to RevenueCat (ActivationAttributes,
//  docs/promotion-plan.md §7, the first-run funnel): how onboarding ended, the entry milestones
//  1, 5 and 10 (each written once, a jump writes only the highest), Ten opened once, and only
//  the person's own records move the entries.
//

import Testing
import Foundation
@testable import Tenra

// `.serialized`: the tests replace the process-wide `ActivationAttributes.write` seam.
@MainActor
@Suite("Activation attributes", .serialized)
struct ActivationAttributesTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "ActivationAttributesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Runs `body` with the writes captured, then puts the app's writer back.
    private func capturingWrites(_ body: () -> Void) -> [String] {
        let saved = ActivationAttributes.write
        var written: [String] = []
        ActivationAttributes.write = { name, value in written.append("\(name.rawValue)=\(value)") }
        body()
        ActivationAttributes.write = saved
        return written
    }

    private func transaction(createdAt: Date, type: TransactionType = .expense, series: String? = nil) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: "2026-11-06", description: "", amount: 1500, currency: "KZT",
            type: type, category: "Кафе", recurringSeriesId: series,
            createdAt: createdAt.timeIntervalSince1970
        )
    }

    @Test("The milestone is the highest of 1, 5 and 10 reached")
    func milestones() {
        #expect(ActivationAttributes.milestone(forEntries: 0) == nil)
        #expect(ActivationAttributes.milestone(forEntries: 1) == 1)
        #expect(ActivationAttributes.milestone(forEntries: 4) == 1)
        #expect(ActivationAttributes.milestone(forEntries: 5) == 5)
        #expect(ActivationAttributes.milestone(forEntries: 9) == 5)
        #expect(ActivationAttributes.milestone(forEntries: 10) == 10)
        #expect(ActivationAttributes.milestone(forEntries: 500) == 10)
    }

    @Test("Each milestone is written once, a jump writes only the highest")
    func entriesWrittenOncePerMilestone() {
        let defaults = freshDefaults()
        let written = capturingWrites {
            ActivationAttributes.noteEntries(1, defaults: defaults)
            ActivationAttributes.noteEntries(2, defaults: defaults)
            ActivationAttributes.noteEntries(12, defaults: defaults)
            ActivationAttributes.noteEntries(13, defaults: defaults)
        }
        #expect(written == ["entries=1", "entries=10"])
    }

    @Test("How onboarding ended, once per outcome")
    func onboardingOutcome() {
        let defaults = freshDefaults()
        let written = capturingWrites {
            ActivationAttributes.noteOnboarding(.finished, defaults: defaults)
            ActivationAttributes.noteOnboarding(.finished, defaults: defaults)
        }
        #expect(written == ["onboarding=finished"])
    }

    @Test("Ten opened is written the first time only")
    func tenOpenedOnce() {
        let defaults = freshDefaults()
        let written = capturingWrites {
            ActivationAttributes.noteTenOpened(defaults: defaults)
            ActivationAttributes.noteTenOpened(defaults: defaults)
        }
        #expect(written == ["ten_opened=yes"])
    }

    @Test("Only the person's records move the entries")
    func onlyPersonsRecordsCount() {
        let defaults = freshDefaults()
        let now = Date(timeIntervalSince1970: 1_793_900_000)
        let written = capturingWrites {
            // Deposit interest posted at launch and a series occurrence: Tenra's, not the person's.
            ActivationAttributes.noteRecorded(
                [transaction(createdAt: now, type: .depositInterestAccrual), transaction(createdAt: now, series: "s1")],
                total: 6, now: now, defaults: defaults
            )
            ActivationAttributes.noteRecorded([transaction(createdAt: now)], total: 7, now: now, defaults: defaults)
        }
        #expect(written == ["entries=5"])
    }
}
