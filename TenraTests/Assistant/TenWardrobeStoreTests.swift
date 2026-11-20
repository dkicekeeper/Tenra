//
//  TenWardrobeStoreTests.swift
//  TenraTests
//
//  Ten's wardrobe state (plan-ten-gamification.md §7.1, §10): the record streak and its day off,
//  what counts as the person's record, what the old streak of app opens leaves open, the merge
//  of a restored backup, and the store hook that keeps imports out of the streak.
//

import Testing
import Foundation
@testable import Tenra

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private func record(_ streak: inout TenRecordStreak, _ days: [Int]) {
    for day in days { streak.record(at: noon(2026, 10, day), calendar: utc) }
}

@MainActor
@Suite("Ten's record streak")
struct TenRecordStreakTests {

    @Test("The next day adds one, the same day keeps the run, two days missed start again")
    func basics() {
        var streak = TenRecordStreak()
        record(&streak, [10, 11, 11, 12])
        #expect(streak.count == 3)
        record(&streak, [15])
        #expect(streak.count == 1)
        #expect(streak.best == 3)
    }

    @Test("One missed day is a day off: the run goes on, the missed day adds nothing")
    func dayOff() {
        var streak = TenRecordStreak()
        record(&streak, [10, 11, 13])
        #expect(streak.count == 3)
        #expect(streak.dayOff == "2026-10-12")
    }

    @Test("A second day off within a week breaks the run")
    func secondDayOffBreaks() {
        var streak = TenRecordStreak()
        record(&streak, [10, 11, 13, 14, 16])
        #expect(streak.count == 1)
        #expect(streak.dayOff == "")
        #expect(streak.best == 4)
    }

    @Test("A day off a week after the last one is fine")
    func dayOffAWeekLater() {
        var streak = TenRecordStreak()
        record(&streak, [10, 11, 13, 14, 15, 16, 17, 18, 20])
        #expect(streak.count == 9)
        #expect(streak.dayOff == "2026-10-19")
    }

    @Test("The run stands while today's record can still continue it")
    func current() {
        var streak = TenRecordStreak()
        record(&streak, [10, 11, 12])
        #expect(streak.current(at: noon(2026, 10, 13), calendar: utc) == 3)
        #expect(streak.current(at: noon(2026, 10, 14), calendar: utc) == 3)   // yesterday can be a day off
        #expect(streak.current(at: noon(2026, 10, 15), calendar: utc) == 0)
        #expect(TenRecordStreak().current(at: noon(2026, 10, 15), calendar: utc) == 0)
    }
}

@MainActor
@Suite("Ten's wardrobe store")
struct TenWardrobeStoreTests {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
    }

    private func expense(createdAt: Date, seriesId: String? = nil, type: TransactionType = .expense) -> Transaction {
        Transaction(id: UUID().uuidString, date: "2026-10-10", description: "coffee", amount: 1500, currency: "KZT",
                    type: type, category: "Food", recurringSeriesId: seriesId,
                    createdAt: createdAt.timeIntervalSince1970)
    }

    @Test("What the streak of app opens opened stays open; its run does not carry over")
    func keepsWhatAppOpensOpened() {
        let defaults = defaults()
        defaults.set(31, forKey: "streak.best")
        defaults.set(2, forKey: "streak.count")
        defaults.set("2026-10-01", forKey: "streak.lastDay")
        let store = TenWardrobeStore(defaults: defaults)
        #expect(store.unlocked.isSuperset(of: ["sunglasses", "sleepMask"]))
        #expect(store.streak == TenRecordStreak())
        #expect(defaults.object(forKey: "streak.best") == nil)
        // Read again: nothing to migrate twice, the open accessories are stored.
        #expect(TenWardrobeStore(defaults: defaults).unlocked == store.unlocked)
    }

    @Test("A week of the old streak opens only the sunglasses")
    func oldWeek() {
        let defaults = defaults()
        defaults.set(7, forKey: "streak.best")
        let store = TenWardrobeStore(defaults: defaults)
        #expect(store.unlocked.contains("sunglasses"))
        #expect(!store.unlocked.contains("sleepMask"))
    }

    @Test("Only the person's own records from today move the streak")
    func whatCounts() {
        let store = TenWardrobeStore(defaults: defaults())
        let now = noon(2026, 10, 10)
        store.noteRecords([expense(createdAt: now, seriesId: "s1")], now: now, calendar: utc)
        store.noteRecords([expense(createdAt: now, type: .depositInterestAccrual)], now: now, calendar: utc)
        store.noteRecords([expense(createdAt: noon(2026, 10, 9))], now: now, calendar: utc)
        #expect(store.streak.count == 0)
        store.noteRecords([expense(createdAt: now)], now: now, calendar: utc)
        #expect(store.streak.count == 1)
    }

    @Test("Seven days of records open the sunglasses without a visit to the wardrobe")
    func weekOpensSunglasses() {
        let store = TenWardrobeStore(defaults: defaults())
        for day in 1...7 {
            let now = noon(2026, 10, day)
            store.noteRecords([expense(createdAt: now)], now: now, calendar: utc)
        }
        #expect(store.streak.best == 7)
        #expect(store.unlocked.contains("sunglasses"))
        #expect(!store.unlocked.contains("sleepMask"))
    }

    @Test("A locked accessory is never worn; an open one is kept")
    func choose() {
        let defaults = defaults()
        let store = TenWardrobeStore(defaults: defaults)
        store.choose(.crown)
        #expect(store.choice == "")
        store.choose(.beanie)
        #expect(TenWardrobeStore(defaults: defaults).choice == "beanie")
        #expect(TenWardrobeStore(defaults: defaults).accessory(at: noon(2026, 10, 15)) == .beanie)
    }

    @Test("A celebrated day puts the crown on for that day only")
    func crown() {
        let store = TenWardrobeStore(defaults: defaults())
        store.celebrate(at: .now)
        #expect(store.accessory() == .crown || AssistantWardrobe.holiday(at: .now) != nil)
        #expect(store.accessory(at: .now.addingTimeInterval(3 * 86_400)) != .crown)
    }

    @Test("A restored backup loses nothing earned on either side")
    func merge() throws {
        let backup = TenWardrobeStore(defaults: defaults())
        for day in 1...7 {
            let now = noon(2026, 10, day)
            backup.noteRecords([expense(createdAt: now)], now: now, calendar: utc)
        }
        backup.choose(.sunglasses)
        let data = try #require(backup.backupData())

        let phone = TenWardrobeStore(defaults: defaults())
        let now = noon(2026, 10, 20)
        phone.noteRecords([expense(createdAt: now)], now: now, calendar: utc)
        phone.merge(backup: data)

        #expect(phone.unlocked.contains("sunglasses"))
        #expect(phone.choice == "sunglasses")
        #expect(phone.streak.best == 7)
        #expect(phone.streak.lastDay == "2026-10-20")   // the later run goes on
        #expect(phone.streak.count == 1)
    }
}

@MainActor
@Suite(.sharedProcessState)
struct TenRecordWiringTests {

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
        return TransactionStore(repository: repo, balanceCoordinator: BalanceCoordinator(repository: repo),
                                recurringStore: RecurringStore(repository: repo))
    }

    private static func expense(id: String) -> Transaction {
        Transaction(id: id, date: "2026-11-05", description: "coffee", amount: 1500, currency: "KZT",
                    type: .expense, category: "")
    }

    @Test("A record and a voice batch reach the streak's hook")
    func ownRecords() async throws {
        let store = Self.makeStore()
        var own: [[String]] = []
        store.onOwnRecords = { own.append($0.map(\.id)) }
        _ = try await store.add(Self.expense(id: "t1"))
        try await store.addBatch([Self.expense(id: "a"), Self.expense(id: "b")])
        #expect(own == [["t1"], ["a", "b"]])
    }

    @Test("A statement's rows reach the reminder but never the streak")
    func statementIsNotARecord() async throws {
        let store = Self.makeStore()
        var own: [[String]] = []
        var all: [[String]] = []
        store.onOwnRecords = { own.append($0.map(\.id)) }
        store.onRecorded = { all.append($0.map(\.id)) }
        await ImportCommitter.commit([.add(Self.expense(id: "s1"), subcategoryIds: [])], store: store,
                                     categories: nil, balance: nil)
        #expect(all == [["s1"]])
        #expect(own.isEmpty)
        #expect(!store.isCommittingImport)
    }

    @Test("Rows a CSV import adds never reach the streak")
    func csvIsNotARecord() async throws {
        let store = Self.makeStore()
        var own: [[String]] = []
        store.onOwnRecords = { own.append($0.map(\.id)) }
        store.isImporting = true
        try await store.addBatch([Self.expense(id: "c1")])
        store.isImporting = false
        #expect(own.isEmpty)
    }
}
