//
//  SubscriptionCandidateDetectorTests.swift
//  TenraTests
//
//  Pins which merchants the subscriptions screen offers as "looks like a subscription":
//  monthly, same amount, recent, untracked and not dismissed.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct SubscriptionCandidateDetectorTests {

    private let now = FastDateParser.date(from: "2026-10-20")!.addingTimeInterval(12 * 3600)

    private func charge(
        _ id: String,
        _ date: String,
        _ amount: Double = 4_990,
        _ description: String = "NETFLIX.COM",
        currency: String = "KZT",
        series: String? = nil
    ) -> Transaction {
        Transaction(
            id: id, date: date, description: description, amount: amount, currency: currency,
            type: .expense, category: "Подписки", accountId: "a1", recurringSeriesId: series
        )
    }

    private var netflix: [Transaction] {
        [charge("n1", "2026-07-14"), charge("n2", "2026-08-14"), charge("n3", "2026-09-14"), charge("n4", "2026-10-14", 5_200)]
    }

    private func candidates(_ transactions: [Transaction], tracked: [String] = [], dismissed: Set<String> = []) -> [SubscriptionCandidateDetector.Candidate] {
        SubscriptionCandidateDetector.candidates(in: transactions, trackedDescriptions: tracked, dismissed: dismissed, now: now)
    }

    @Test("Monthly charges of about the same amount are a candidate, priced as the latest")
    func monthlyCharges() throws {
        let candidate = try #require(candidates(netflix).first)
        #expect(candidate.merchant == "netflix com")
        #expect(candidate.amount == 5_200)
        #expect(candidate.charges == 4)
        #expect(candidate.lastDate == "2026-10-14")
        #expect(Calendar.current.component(.day, from: candidate.nextDate) == 14)
        #expect(Calendar.current.component(.month, from: candidate.nextDate) == 11)
    }

    @Test("Two charges are not enough")
    func tooFewCharges() {
        #expect(candidates([charge("n1", "2026-09-14"), charge("n2", "2026-10-14")]).isEmpty)
    }

    @Test("A shop visited every week is never a candidate")
    func weeklyShop() {
        let shop = (0..<12).map { week in
            charge("g\(week)", DateFormatters.dateFormatter.string(from: now.addingTimeInterval(-Double(week) * 7 * 86_400)), 3_000, "GREENMART 12")
        }
        #expect(candidates(shop).isEmpty)
    }

    @Test("A different amount breaks the run")
    func amountBreaksRun() {
        let mixed = [charge("n1", "2026-08-14", 2_000), charge("n2", "2026-09-14", 9_000), charge("n3", "2026-10-14", 4_990)]
        #expect(candidates(mixed).isEmpty)
    }

    @Test("A merchant not charged for more than 40 days is not offered")
    func stale() {
        let old = [charge("n1", "2026-05-01"), charge("n2", "2026-06-01"), charge("n3", "2026-07-01")]
        #expect(candidates(old).isEmpty)
    }

    @Test("Tracked, linked or dismissed merchants are not offered")
    func excluded() {
        #expect(candidates(netflix, tracked: ["Netflix"]).isEmpty)
        #expect(candidates(netflix, dismissed: ["netflix com"]).isEmpty)
        #expect(candidates(netflix.map { charge($0.id, $0.date, $0.amount, series: "s1") }).isEmpty)
    }

    @Test("A service its billing company charges is tracked under the company's name")
    func trackedByBillingCompany() {
        let apple = [charge("a1", "2026-08-10", 450, "APPLE.COM/BILL"), charge("a2", "2026-09-10", 450, "APPLE.COM/BILL"), charge("a3", "2026-10-10", 450, "APPLE.COM/BILL")]
        #expect(candidates(apple, tracked: ["iCloud+"]).isEmpty)
        #expect(candidates(apple).count == 1)
    }

    @Test("The same merchant in two currencies is two runs")
    func currenciesSeparate() {
        let usd = netflix.map { charge($0.id + "u", $0.date, 10, currency: "USD") }
        #expect(candidates(netflix + usd).count == 2)
    }
}
