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

    @Test func ownAccountMovesAreRecognized() {
        #expect(StatementOperationKind.classify("Перевод на свой счет") == .ownAccountTransfer)
        #expect(StatementOperationKind.classify("Поступление со своего счета") == .ownAccountTransfer)
        #expect(StatementOperationKind.classify("Transfer to own account") == .ownAccountTransfer)
        // "Поступление" alone is an ordinary top-up, not an own-account move.
        #expect(StatementOperationKind.classify("Поступление") == .topUp)
    }

    @Test func ownAccountMoveNamedOnlyInTheDetails() {
        // Freedom: the operation says "Пополнение", the details say it came from a deposit.
        #expect(StatementOperationKind.classify(
            operation: "Пополнение", details: "Перевод вклада по Договору от 19.09.2026") == .ownAccountTransfer)
        #expect(StatementOperationKind.classify(
            operation: "Другое", details: "Прием вклада по договору в сумме 950000 KZT") == .ownAccountTransfer)
        #expect(StatementOperationKind.classify(
            operation: "Пополнение", details: "С карты другого банка") == .topUp)
        // A merchant name never turns a purchase into a transfer.
        #expect(StatementOperationKind.classify(operation: "Покупка", details: "Депозит Маркет") == .purchase)
    }

    @Test func cashAndOwnAccountMovesStartUnchecked() {
        #expect(StatementOperationKind.cashWithdrawal.startsUnchecked)
        #expect(StatementOperationKind.ownAccountTransfer.startsUnchecked)
        #expect(!StatementOperationKind.transfer.startsUnchecked)
        #expect(!StatementOperationKind.topUp.startsUnchecked)
        #expect(!StatementOperationKind.purchase.startsUnchecked)
    }

    @Test func onlyMovementsAreLabeled() {
        #expect(StatementOperationKind.transfer.isMoneyMovement)
        #expect(StatementOperationKind.ownAccountTransfer.isMoneyMovement)
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

    @Test func paymentOrderDetailsShrinkToTheCounterparty() throws {
        let table = DocumentSnapshot.Table(rows: [
            ["Дата", "Сумма", "Операция", "Детали"],
            ["19.09.2026", "-30,000.00 ₸", "Перевод",
             "Плательщик: Тестов Тест Получатель: АО Банк Назначение: ФИО: Асан Б.. Мобильный: 77000000000. Референс: FBK1-abc. БИК: TESTKZKA."],
            ["18.09.2026", "+50,000.00 ₸", "Пополнение",
             "Перевод вклада по Договору №KZ00000A0000000000 от 18.09.2026. Вкладчик: Тестов Т."]
        ])
        let snapshot = DocumentSnapshot(
            pages: [.init(index: 0, tables: [table], lines: [], barcodes: [])],
            hadTextLayer: true
        )
        let roles = try #require(ColumnRoleResolver.resolve(table: table))
        let result = StatementInterpreter.interpret(snapshot: snapshot, roles: roles, defaultCurrency: "KZT")

        #expect(result.transactions.map(\.descriptionText) == [
            "Перевод · Асан Б.",
            "Пополнение · Перевод вклада по Договору от 18.09.2026. Вкладчик: Тестов Т."
        ])
    }
}
