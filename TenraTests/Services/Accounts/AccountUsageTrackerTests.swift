//
//  AccountUsageTrackerTests.swift
//  TenraTests
//
//  Covers the smart-default-account heuristic:
//  1. 90-day activity window excludes dormant accounts.
//  2. MAX recency (not sum) prevents historical volume from dominating.
//  3. Per-category filtering biases toward accounts used for that category.
//  4. Fallback ladder: per-category → global → most-recent → first.
//

import XCTest
@testable import Tenra

final class AccountUsageTrackerTests: XCTestCase {

    // MARK: - Fixtures

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func dateString(daysAgo: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return Self.dateFormatter.string(from: d)
    }

    private func makeAccount(id: String, name: String = "Test", currency: String = "KZT") -> Account {
        Account(id: id, name: name, currency: currency)
    }

    private func makeTx(
        id: String = UUID().uuidString,
        accountId: String,
        category: String = "Other",
        daysAgo: Int,
        type: TransactionType = .expense
    ) -> Transaction {
        Transaction(
            id: id,
            date: dateString(daysAgo: daysAgo),
            description: "",
            amount: 100,
            currency: "KZT",
            type: type,
            category: category,
            accountId: accountId
        )
    }

    // MARK: - Activity window

    func testDormantAccountIsSkipped() {
        // Old account has tons of transactions but all are 200+ days old.
        // Fresh account has just one, yesterday. Fresh should win.
        let oldAccount = makeAccount(id: "old")
        let freshAccount = makeAccount(id: "fresh")

        var txs: [Transaction] = (0..<500).map { i in
            makeTx(id: "old-\(i)", accountId: "old", daysAgo: 200 + i)
        }
        txs.append(makeTx(accountId: "fresh", daysAgo: 1))

        let tracker = AccountUsageTracker(transactions: txs, accounts: [oldAccount, freshAccount])
        XCTAssertEqual(tracker.getSmartDefaultAccount()?.id, "fresh")
    }

    func testMaxRecencyBeatsHistoricalVolume() {
        // Old account: 100 transactions, all 60–89 days old (in the window
        //   but past every recency bucket → max recency = 10).
        // Fresh account: 1 transaction today (max recency = 100).
        // Even with 100× the volume, the old account loses on freshness.
        let oldAccount = makeAccount(id: "old")
        let freshAccount = makeAccount(id: "fresh")

        var txs: [Transaction] = (0..<100).map { i in
            makeTx(id: "old-\(i)", accountId: "old", daysAgo: 60 + (i % 30))
        }
        txs.append(makeTx(accountId: "fresh", daysAgo: 0))

        let tracker = AccountUsageTracker(transactions: txs, accounts: [oldAccount, freshAccount])
        // Old:   volume 100 * 0.4 = 40, freshness 10 * 0.6 = 6   → 46
        // Fresh: volume   1 * 0.4 = 0.4, freshness 100 * 0.6 = 60 → 60.4
        XCTAssertEqual(tracker.getSmartDefaultAccount()?.id, "fresh")
    }

    func testFewRecentTxsVsManyRecentTxsButOlder() {
        // Account A: 5 transactions today.
        // Account B: 50 transactions all 20 days old.
        // A should win on freshness despite lower volume.
        let a = makeAccount(id: "a")
        let b = makeAccount(id: "b")

        var txs: [Transaction] = (0..<5).map { i in makeTx(id: "a-\(i)", accountId: "a", daysAgo: 0) }
        txs += (0..<50).map { i in makeTx(id: "b-\(i)", accountId: "b", daysAgo: 20) }

        let tracker = AccountUsageTracker(transactions: txs, accounts: [a, b])
        // A: vol 5*0.4=2, fresh 100*0.6=60 → 62
        // B: vol 50*0.4=20, fresh 40*0.6=24 → 44
        XCTAssertEqual(tracker.getSmartDefaultAccount()?.id, "a")
    }

    // MARK: - Per-category

    func testPerCategoryBiasPicksCorrectAccount() {
        // Card account is dominant overall, but Wallet has all the transport txs.
        let card = makeAccount(id: "card")
        let wallet = makeAccount(id: "wallet")

        var txs: [Transaction] = []
        // 30 grocery transactions on card (today)
        txs += (0..<30).map { i in
            makeTx(id: "card-\(i)", accountId: "card", category: "Food", daysAgo: i % 10)
        }
        // 5 transport transactions on wallet (recent)
        txs += (0..<5).map { i in
            makeTx(id: "wallet-\(i)", accountId: "wallet", category: "Transport", daysAgo: i)
        }

        let tracker = AccountUsageTracker(transactions: txs, accounts: [card, wallet])
        XCTAssertEqual(tracker.getSmartDefaultAccount()?.id, "card", "Global default is the busy card")
        XCTAssertEqual(tracker.getSmartDefaultAccount(forCategory: "Transport")?.id, "wallet",
                       "Per-category lookup must prefer the account actually used for that category")
    }

    func testPerCategoryFallsBackWhenCategoryUnknown() {
        let card = makeAccount(id: "card")
        let txs = (0..<5).map { i in
            makeTx(id: "card-\(i)", accountId: "card", category: "Food", daysAgo: i)
        }

        let tracker = AccountUsageTracker(transactions: txs, accounts: [card])
        // No "Transport" usage in fixture — should fall back to global default.
        XCTAssertEqual(tracker.getSmartDefaultAccount(forCategory: "Transport")?.id, "card")
    }

    func testPerCategoryIsCaseInsensitive() {
        let card = makeAccount(id: "card")
        let txs = (0..<3).map { i in
            makeTx(id: "card-\(i)", accountId: "card", category: "Транспорт", daysAgo: i)
        }
        let tracker = AccountUsageTracker(transactions: txs, accounts: [card])
        XCTAssertEqual(tracker.getSmartDefaultAccount(forCategory: "транспорт")?.id, "card")
        XCTAssertEqual(tracker.getSmartDefaultAccount(forCategory: "ТРАНСПОРТ")?.id, "card")
    }

    // MARK: - Fallbacks

    func testEmptyAccountsReturnsNil() {
        let tracker = AccountUsageTracker(transactions: [], accounts: [])
        XCTAssertNil(tracker.getSmartDefaultAccount())
    }

    func testNoTransactionsReturnsFirstAccount() {
        let a = makeAccount(id: "a")
        let b = makeAccount(id: "b")
        let tracker = AccountUsageTracker(transactions: [], accounts: [a, b])
        XCTAssertEqual(tracker.getSmartDefaultAccount()?.id, "a")
    }

    func testAllDormantFallsBackToMostRecent() {
        // Every transaction is older than 90 days — no account "in window".
        // Should fall through to most-recent overall, then first.
        let a = makeAccount(id: "a")
        let b = makeAccount(id: "b")
        let txs = [
            makeTx(accountId: "a", daysAgo: 200),
            makeTx(accountId: "b", daysAgo: 150),
        ]
        let tracker = AccountUsageTracker(transactions: txs, accounts: [a, b])
        // getMostRecentAccount picks the account with the lexically newest
        // date string — daysAgo 150 (more recent) maps to account "b".
        XCTAssertEqual(tracker.getSmartDefaultAccount()?.id, "b")
    }
}
