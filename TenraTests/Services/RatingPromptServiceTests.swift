//
//  RatingPromptServiceTests.swift
//  TenraTests
//
//  Pins the rating-survey eligibility rule (v2, 2026-09): enough tracked
//  transactions AND a returning user (a second session OR a couple of days).
//  v1 required sessions AND days AND transactions, which a small user base
//  practically never satisfied.
//

import Testing
@testable import Tenra

struct RatingPromptServiceTests {

    private func eligible(sessions: Int, tx: Int, days: Double) -> Bool {
        RatingPromptService.meetsThresholds(sessions: sessions, transactions: tx, daysSinceInstall: days)
    }

    @Test func tooFewTransactionsNeverEligible() {
        #expect(!eligible(sessions: 10, tx: 4, days: 30))
    }

    @Test func firstSessionSameDayNotEligible() {
        #expect(!eligible(sessions: 1, tx: 20, days: 0.5))
    }

    @Test func secondSessionIsEnough() {
        #expect(eligible(sessions: 2, tx: 5, days: 0))
    }

    @Test func twoDaysSinceInstallIsEnough() {
        #expect(eligible(sessions: 1, tx: 5, days: 2))
    }

    @Test func justUnderDayThresholdNeedsSecondSession() {
        #expect(!eligible(sessions: 1, tx: 5, days: 1.99))
    }
}
