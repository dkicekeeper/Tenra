//
//  WalletStatementCheckTests.swift
//  TenraTests
//
//  Pins which Apple Pay payments a statement is said not to show: the review
//  screen lists them as possibly declined.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct WalletStatementCheckTests {

    private func payment(_ id: String, _ date: String, _ amount: Double, account: String = "a1", currency: String = "KZT") -> Transaction {
        Transaction(id: id, date: date, description: "GREENMART 12", amount: amount, currency: currency, type: .expense, category: "Продукты", accountId: account)
    }

    private func row(_ id: String, _ date: String, _ amount: Double, type: TransactionType = .expense) -> Transaction {
        Transaction(id: id, date: date, description: "Покупка GREENMART", amount: amount, currency: "KZT", type: type, category: "")
    }

    private let statement: [Transaction] = []

    private func missing(_ captured: [Transaction], _ rows: [Transaction]) -> [String] {
        WalletStatementCheck.missing(captured: captured, rows: rows, accountId: "a1", accountCurrency: "KZT").map(\.id)
    }

    @Test("A payment the statement shows, on its day or the next, is not missing")
    func shownPayments() {
        let rows = [row("r1", "2026-10-01", 3_500), row("r2", "2026-10-06", 1_200), row("r3", "2026-10-20", 100)]
        #expect(missing([payment("p1", "2026-10-01", 3_500), payment("p2", "2026-10-05", 1_200)], rows).isEmpty)
    }

    @Test("A payment with no row of its amount is missing")
    func declinedPayment() {
        let rows = [row("r1", "2026-10-01", 3_500), row("r2", "2026-10-20", 100)]
        #expect(missing([payment("p1", "2026-10-03", 9_990)], rows) == ["p1"])
    }

    @Test("Each row shows one payment: two equal payments and one row leave one missing")
    func rowsTakenOnce() {
        let rows = [row("r1", "2026-10-02", 1_500), row("r2", "2026-10-20", 100)]
        #expect(missing([payment("p1", "2026-10-02", 1_500), payment("p2", "2026-10-02", 1_500)], rows) == ["p2"])
    }

    @Test("An income row of the same amount does not show a payment")
    func incomeDoesNotCount() {
        let rows = [row("r1", "2026-10-02", 1_500, type: .income), row("r2", "2026-10-20", 100)]
        #expect(missing([payment("p1", "2026-10-02", 1_500)], rows) == ["p1"])
    }

    @Test("Payments outside the statement, near its end, on another account or in another currency are not checked")
    func notChecked() {
        let rows = [row("r1", "2026-10-05", 100), row("r2", "2026-10-20", 100)]
        let captured = [
            payment("before", "2026-10-01", 9_000),
            payment("settling", "2026-10-19", 9_000),
            payment("other-account", "2026-10-10", 9_000, account: "a2"),
            payment("usd", "2026-10-10", 20, currency: "USD")
        ]
        #expect(missing(captured, rows).isEmpty)
    }

    @Test("An empty statement says nothing")
    func emptyStatement() {
        #expect(missing([payment("p1", "2026-10-03", 9_990)], statement).isEmpty)
    }
}
