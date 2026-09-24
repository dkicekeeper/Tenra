//
//  StatementOperationTests.swift
//  TenraTests
//
//  The statement's transaction-type column ("Операция": Покупка / Перевод /
//  Пополнение / Снятие) used to be dropped. Pins its detection, classification,
//  and the operation label on money-movement rows.
//

import Testing
import Foundation
@testable import Tenra

struct StatementOperationTests {

    // MARK: - Classification

    @Test func classifiesKaspiOperations() {
        #expect(StatementOperationKind.classify("Покупка") == .purchase)
        #expect(StatementOperationKind.classify("Перевод") == .transfer)
        #expect(StatementOperationKind.classify("Пополнение") == .topUp)
        #expect(StatementOperationKind.classify("Снятие") == .cashWithdrawal)
        #expect(StatementOperationKind.classify("Разное") == .other)
        #expect(StatementOperationKind.classify(nil) == .other)
    }

    @Test func classifiesOtherLanguages() {
        #expect(StatementOperationKind.classify("Überweisung") == .transfer)
        #expect(StatementOperationKind.classify("Cash withdrawal ATM") == .cashWithdrawal)
        #expect(StatementOperationKind.classify("Top-up") == .topUp)
        #expect(StatementOperationKind.classify("Purchase") == .purchase)
    }

    @Test func onlyMovementsAreLabeled() {
        #expect(StatementOperationKind.transfer.isMoneyMovement)
        #expect(StatementOperationKind.cashWithdrawal.isMoneyMovement)
        #expect(!StatementOperationKind.purchase.isMoneyMovement)
        #expect(!StatementOperationKind.other.isMoneyMovement)
    }

    // MARK: - Column detection

    private let kaspi = DocumentSnapshot.Table(rows: [
        ["Дата", "Сумма", "Операция", "Детали"],
        ["08.01.2026", "- 2 500,00 ₸", "Покупка", "YANDEX.GO"],
        ["09.01.2026", "- 20 000,00 ₸", "Перевод", "Асан Б."],
        ["10.01.2026", "- 30 000,00 ₸", "Снятие", "ATM Halyk"]
    ])

    @Test func separateOperationColumnIsDetected() {
        let roles = ColumnRoleResolver.resolve(table: kaspi)
        #expect(roles?.description == 3)
        #expect(roles?.operation == 2)
    }

    @Test func operationUsedAsDescriptionIsNotAlsoTheOperation() {
        let table = DocumentSnapshot.Table(rows: [
            ["Date", "Operation", "Amount"],
            ["08.01.2026", "Coffee shop", "12.50"],
            ["09.01.2026", "Grocery store", "40.00"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.description == 1)
        #expect(roles?.operation == nil)
    }

    // MARK: - Interpretation

    @Test func movementRowsCarryTheOperationLabel() throws {
        let snapshot = DocumentSnapshot(
            pages: [.init(index: 0, tables: [kaspi], lines: [], barcodes: [])],
            hadTextLayer: true
        )
        let roles = try #require(ColumnRoleResolver.resolve(table: kaspi))
        let result = StatementInterpreter.interpret(snapshot: snapshot, roles: roles, defaultCurrency: "KZT")

        #expect(result.transactions.count == 3)
        #expect(result.transactions[0].descriptionText == "YANDEX.GO")
        #expect(result.transactions[0].operation == "Покупка")
        #expect(result.transactions[1].descriptionText == "Перевод · Асан Б.")
        #expect(result.transactions[2].descriptionText == "Снятие · ATM Halyk")
        #expect(StatementOperationKind.classify(result.transactions[2].operation) == .cashWithdrawal)
    }
}
