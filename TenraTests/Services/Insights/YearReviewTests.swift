//
//  YearReviewTests.swift
//  TenraTests
//
//  Pins the year in review (YearReviewBuilder, docs/plan-release-1.9.md §3): realized rows of
//  the year only, income and expenses by the shared money rule, months, top categories and
//  merchants, subscriptions, the habit (records, days, the longest run), the biggest one-off
//  expense, the thresholds and their light check for Ten's message, the pages left out, the
//  message's life, and the 15 December - 31 January window. Rates come from a pinned
//  RateSnapshot, so no global FX state is touched. All data invented.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct YearReviewTests {

    private let calendar = FastDateParser.calendar

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func tx(
        _ date: String,
        _ amount: Double,
        type: TransactionType = .expense,
        category: String = "Food",
        description: String = "",
        currency: String = "KZT",
        series: String? = nil
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: date, description: description, amount: amount,
            currency: currency, type: type, category: category, accountId: "a1",
            recurringSeriesId: series
        )
    }

    /// `count` one-off expenses of `amount` on consecutive days from `start` ("yyyy-MM-dd").
    private func daily(from start: Date, count: Int, amount: Double = 1_000, category: String = "Food") -> [Transaction] {
        (0..<count).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return tx(FastDateParser.string(from: day), amount, category: category)
        }
    }

    private func build(
        _ transactions: [Transaction],
        series: [RecurringSeries] = [],
        year: Int = 2026,
        now: Date? = nil,
        rates: [String: Double] = [:]
    ) -> YearReview? {
        YearReviewBuilder.build(
            year: year,
            transactions: transactions,
            recurringSeries: series,
            baseCurrency: "KZT",
            rates: RateSnapshot(rates: rates),
            now: now ?? date(2026, 12, 20),
            calendar: calendar
        )
    }

    @Test("Income and expenses of the year, by the shared money rule")
    func totals() throws {
        var rows = daily(from: date(2026, 3, 1), count: 30)                       // 30 000 food
        rows.append(tx("2026-05-10", 500_000, type: .income, category: "Salary"))
        rows.append(tx("2026-06-01", 40_000, type: .loanPayment, category: ""))   // an expense
        rows.append(tx("2026-06-02", 10_000, type: .depositInterestAccrual, category: "Interest")) // income
        rows.append(tx("2026-06-03", 99_000, type: .internalTransfer, category: "Transfer"))      // neither
        rows.append(tx("2025-12-31", 77_000))                                     // last year
        rows.append(tx("2026-12-25", 66_000))                                     // still ahead on 20.12

        let review = try #require(build(rows))
        #expect(review.year == 2026)
        #expect(review.expenses == 70_000)
        #expect(review.income == 510_000)
        #expect(review.saved == 440_000)
        #expect(abs((review.savingsRate ?? 0) - 440_000.0 / 510_000.0) < 0.0001)
        #expect(!review.usedStaleFallback)
    }

    @Test("Another currency at the pinned rate; without a rate the row is left out and flagged")
    func currencies() throws {
        var rows = daily(from: date(2026, 2, 1), count: 30)
        rows.append(tx("2026-04-01", 100, currency: "USD"))
        rows.append(tx("2026-04-02", 50, currency: "EUR"))
        // KZT is the pivot: 1 USD = 500 KZT.
        let review = try #require(build(rows, rates: ["USD": 500]))
        #expect(review.expenses == 30_000 + 50_000)
        #expect(review.usedStaleFallback)
    }

    @Test("Months up to the current one; the month still running is never the calmest")
    func months() throws {
        var rows = daily(from: date(2026, 1, 1), count: 31, amount: 1_000)       // January 31 000
        rows += daily(from: date(2026, 2, 1), count: 10, amount: 1_000)         // February 10 000
        rows += daily(from: date(2026, 3, 1), count: 5, amount: 10_000)          // March 50 000
        rows.append(tx("2026-12-01", 100))                                       // December 100, running
        let review = try #require(build(rows))
        #expect(review.monthlyExpenses.count == 12)
        #expect(review.monthlyExpenses[0] == 31_000)
        #expect(review.monthlyExpenses[11] == 100)
        #expect(review.lastCompleteMonth == 11)
        #expect(review.busiestMonth == 3)
        #expect(review.calmestMonth == 2)

        // In January the year is over: all twelve months are complete.
        let january = try #require(build(rows, now: date(2027, 1, 10)))
        #expect(january.lastCompleteMonth == 12)
        #expect(january.calmestMonth == 12)
    }

    @Test("Top categories with their shares, the synthetic loan key labelled")
    func categories() throws {
        var rows = daily(from: date(2026, 1, 1), count: 30, amount: 1_000, category: "Food")      // 30 000
        rows += daily(from: date(2026, 3, 1), count: 2, amount: 20_000, category: "Rent")        // 40 000
        rows.append(tx("2026-04-01", 30_000, type: .loanPayment, category: ""))
        let review = try #require(build(rows))
        #expect(review.topCategories.map(\.key) == ["Rent", "Food", TransactionType.loanPaymentCategoryName])
        #expect(review.topCategories[0].share == 0.4)
        #expect(review.topCategories[2].label == InsightsService.categoryLabel(for: TransactionType.loanPaymentCategoryName))
        #expect(review.topCategories.count <= YearReviewBuilder.topCategoryCount)
    }

    @Test("Top merchants as the insight finds them, only from three merchants")
    func merchants() throws {
        var rows = daily(from: date(2026, 1, 1), count: 30, amount: 100)
        rows.append(tx("2026-05-01", 9_000, description: "MAGNUM 12"))
        rows.append(tx("2026-05-02", 6_000, description: "MAGNUM 34"))
        rows.append(tx("2026-05-03", 8_000, description: "Small Coffee"))
        let two = try #require(build(rows))
        #expect(two.topMerchants.isEmpty)

        rows.append(tx("2026-05-04", 1_000, description: "Book House"))
        rows.append(tx("2026-05-05", 2_000, description: "Food"))                // the category's name: not a merchant
        let review = try #require(build(rows))
        #expect(review.topMerchants.count == 3)
        #expect(review.topMerchants[0].amount == 15_000)
        #expect(review.topMerchants[0].visits == 2)
        #expect(review.topMerchants[0].usualCategory == "Food")
        #expect(review.topMerchants[0].description == "MAGNUM 34")
        #expect(review.topMerchants[1].amount == 8_000)
    }

    @Test("Subscriptions: charges of subscription series in the year, and how many charged")
    func subscriptions() throws {
        let music = RecurringSeries(amount: 2_000, currency: "KZT", category: "Music", description: "Music",
                                    frequency: .monthly, startDate: "2026-01-05", kind: .subscription)
        let rent = RecurringSeries(amount: 200_000, currency: "KZT", category: "Rent", description: "Rent",
                                   frequency: .monthly, startDate: "2026-01-01")
        var rows = daily(from: date(2026, 1, 1), count: 30)
        rows += (1...11).map { tx(String(format: "2026-%02d-05", $0), 2_000, category: "Music", series: music.id) }
        rows.append(tx("2026-02-01", 200_000, category: "Rent", series: rent.id))
        let review = try #require(build(rows, series: [music, rent]))
        #expect(review.subscriptionsTotal == 22_000)
        #expect(review.subscriptionsCount == 1)
        #expect(review.subscriptions == [YearReview.SubscriptionTotal(seriesId: music.id, amount: 22_000)])
        // Generated charges are not the person's records; the biggest one-off skips them too.
        #expect(review.habit.records == 30)
        #expect(review.biggestExpense?.amount == 1_000)
    }

    @Test("The habit: records, days with one, the longest run of days")
    func habit() throws {
        var rows = daily(from: date(2026, 1, 1), count: 20)                       // 1-20 January
        rows += daily(from: date(2026, 2, 1), count: 12)                          // 1-12 February
        rows.append(tx("2026-02-01", 500))                                        // a second record that day
        rows.append(tx("2026-02-02", 10, type: .depositInterestAccrual, category: "Interest")) // not a record
        let review = try #require(build(rows))
        #expect(review.habit.records == 33)
        #expect(review.habit.days == 32)
        #expect(review.habit.longestStreak == 20)
        #expect(review.recordsByDay["2026-02-01"] == 2)
        #expect(review.recordsByDay["2026-02-02"] == 1)
        #expect(review.recordsByDay.values.reduce(0, +) == 33)
        #expect(YearReviewBuilder.longestStreak(["2026-02-28", "2026-03-01", "2026-03-02", "2026-03-05"]) == 3)
        #expect(YearReviewBuilder.longestStreak([]) == 0)
    }

    @Test("The biggest one-off expense names its merchant, or its category without one")
    func biggest() throws {
        var rows = daily(from: date(2026, 1, 1), count: 30)
        rows.append(tx("2026-07-14", 350_000, category: "Travel", description: "AIR ASTANA"))
        let review = try #require(build(rows))
        let biggest = try #require(review.biggestExpense)
        #expect(biggest.amount == 350_000)
        #expect(biggest.date == "2026-07-14")
        #expect(biggest.categoryKey == "Travel")
        #expect(!biggest.title.isEmpty)

        rows.append(tx("2026-08-01", 400_000, category: "Car"))
        #expect(build(rows)?.biggestExpense?.title == "Car")
    }

    @Test("Too little to review: under 30 records in the year, or under 30 days of history")
    func thresholds() {
        #expect(build(daily(from: date(2026, 1, 1), count: 29)) == nil)
        #expect(build(daily(from: date(2026, 1, 1), count: 30)) != nil)
        // Thirty records, three a day from 5 December: fifteen days of history, too new.
        let recent = (0..<3).flatMap { _ in daily(from: date(2026, 12, 5), count: 10) }
        #expect(build(recent, now: date(2026, 12, 20)) == nil)
        #expect(build(recent, now: date(2027, 1, 10)) != nil)
        // A year not reached yet.
        #expect(build(daily(from: date(2026, 1, 1), count: 40), year: 2027) == nil)
    }

    @Test("The light check for Ten's message agrees with the build's thresholds")
    func eligibility() {
        let now = date(2026, 12, 20)
        let enough = daily(from: date(2026, 1, 1), count: 30)
        #expect(YearReviewBuilder.isEligible(year: 2026, transactions: enough, now: now, calendar: calendar))
        #expect(!YearReviewBuilder.isEligible(year: 2026, transactions: Array(enough.prefix(29)), now: now, calendar: calendar))
        // Generated charges are not records.
        let series = (1...5).map { tx(String(format: "2026-%02d-05", $0), 100, series: "s1") }
        #expect(!YearReviewBuilder.isEligible(year: 2026, transactions: Array(enough.prefix(29)) + series, now: now, calendar: calendar))
        // Thirty records but fifteen days of history; in January the history is long enough.
        let recent = (0..<3).flatMap { _ in daily(from: date(2026, 12, 5), count: 10) }
        #expect(!YearReviewBuilder.isEligible(year: 2026, transactions: recent, now: now, calendar: calendar))
        #expect(YearReviewBuilder.isEligible(year: 2026, transactions: recent, now: date(2027, 1, 10), calendar: calendar))
        // A record still ahead does not count.
        let ahead = Array(enough.prefix(29)) + [tx("2026-12-28", 100)]
        #expect(!YearReviewBuilder.isEligible(year: 2026, transactions: ahead, now: now, calendar: calendar))
        #expect(build(ahead) == nil)
    }

    @Test("A page with nothing to show is left out")
    func pages() throws {
        // January only, one category, no income, no merchants, no subscriptions.
        let bare = try #require(build(daily(from: date(2026, 1, 1), count: 30)))
        #expect(YearReviewPage.pages(for: bare) == [.cover, .money, .categories, .habit, .biggest, .finale])

        let music = RecurringSeries(amount: 2_000, currency: "KZT", category: "Music", description: "Music",
                                    frequency: .monthly, startDate: "2026-01-05", kind: .subscription)
        var rows = daily(from: date(2026, 1, 1), count: 30)
        rows += daily(from: date(2026, 2, 1), count: 5)
        rows.append(tx("2026-03-01", 500_000, type: .income, category: "Salary"))
        rows.append(tx("2026-03-05", 2_000, category: "Music", series: music.id))
        rows += ["MAGNUM 12", "Small Coffee", "Book House"].map { tx("2026-04-01", 3_000, description: $0) }
        let full = try #require(build(rows, series: [music]))
        #expect(YearReviewPage.pages(for: full) == YearReviewPage.allCases)
    }

    @Test("Ten's message: once a year, kept only while its year shows")
    func notice() {
        let notice = AssistantNotices.yearReview(year: 2026, now: date(2026, 12, 15))
        #expect(notice.id == "yearReview:2026")
        #expect(notice.kind == .yearReview)
        #expect(notice.subjectId == "2026")
        var subjects = AssistantNotices.Subjects(subscriptions: [], debts: [], goals: [])
        subjects.reviewYear = 2026
        #expect(subjects.contains(notice))
        subjects.reviewYear = 2027
        #expect(!subjects.contains(notice))
        subjects.reviewYear = nil
        #expect(!subjects.contains(notice))
    }

    @Test("Shown from 15 December for the year ending, in January for the year just ended")
    func window() {
        #expect(YearReviewWindow.year(on: date(2026, 12, 14), calendar: calendar) == nil)
        #expect(YearReviewWindow.year(on: date(2026, 12, 15), calendar: calendar) == 2026)
        #expect(YearReviewWindow.year(on: date(2026, 12, 31), calendar: calendar) == 2026)
        #expect(YearReviewWindow.year(on: date(2027, 1, 1), calendar: calendar) == 2026)
        #expect(YearReviewWindow.year(on: date(2027, 1, 31), calendar: calendar) == 2026)
        #expect(YearReviewWindow.year(on: date(2027, 2, 1), calendar: calendar) == nil)
        #expect(YearReviewWindow.year(on: date(2026, 11, 24), calendar: calendar) == nil)
    }
}
