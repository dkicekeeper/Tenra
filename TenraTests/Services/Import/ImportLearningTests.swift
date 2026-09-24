//
//  ImportLearningTests.swift
//  TenraTests
//
//  What the statement import learns from the user's own data (subcategories per
//  merchant, transfers to their other accounts), the matcher that finds the other
//  side of a transfer between two banks, the statement's bank, and the plan the
//  review screen saves. All pure; names and amounts are made up.
//

import Testing
import Foundation
@testable import Tenra

struct ImportLearningTests {

    private func tx(
        _ id: String, _ date: String, _ description: String, _ amount: Double,
        _ type: TransactionType, account: String?, target: String? = nil,
        category: String = "", series: String? = nil
    ) -> Transaction {
        Transaction(
            id: id, date: date, description: description, amount: amount, currency: "KZT",
            type: type, category: type == .internalTransfer ? TransactionType.transferCategoryName : category,
            accountId: account, targetAccountId: target,
            targetCurrency: target == nil ? nil : "KZT", targetAmount: target == nil ? nil : amount,
            recurringSeriesId: series
        )
    }

    // MARK: - Subcategory history

    @Test func subcategoryIsLearnedPerMerchantAndCategory() {
        let uses = [
            CategorySuggestionService.SubcategoryUse(description: "Перевод · Асан Б.", type: .expense,
                                                     category: "Семья", subcategoryIds: ["loved"], date: "2026-09-01"),
            CategorySuggestionService.SubcategoryUse(description: "ПЕРЕВОД - Асан Б.", type: .expense,
                                                     category: "Семья", subcategoryIds: ["loved"], date: "2026-09-10")
        ]
        let index = CategorySuggestionService.buildSubcategoryIndex(from: uses)

        #expect(CategorySuggestionService.historySubcategory(
            for: "Перевод · Асан Б.", type: .expense, category: "Семья", in: index) == "loved")
        // Another category for the same merchant learned nothing.
        #expect(CategorySuggestionService.historySubcategory(
            for: "Перевод · Асан Б.", type: .expense, category: "Подарки", in: index) == nil)
        #expect(CategorySuggestionService.historySubcategory(
            for: "Перевод · Асан Б.", type: .income, category: "Семья", in: index) == nil)
    }

    @Test func mostUsedSubcategoryWinsThenTheLatest() {
        let uses = [
            CategorySuggestionService.SubcategoryUse(description: "MAGNUM", type: .expense, category: "Food",
                                                     subcategoryIds: ["home"], date: "2026-09-01"),
            CategorySuggestionService.SubcategoryUse(description: "MAGNUM", type: .expense, category: "Food",
                                                     subcategoryIds: ["home"], date: "2026-09-02"),
            CategorySuggestionService.SubcategoryUse(description: "MAGNUM", type: .expense, category: "Food",
                                                     subcategoryIds: ["party"], date: "2026-09-20")
        ]
        let index = CategorySuggestionService.buildSubcategoryIndex(from: uses)
        #expect(CategorySuggestionService.historySubcategory(
            for: "MAGNUM", type: .expense, category: "Food", in: index) == "home")
    }

    // MARK: - Transfer history

    @Test func savedTransferTeachesBothStatements() {
        let history = [
            tx("t1", "2026-09-04", "Перевод · Тест К., Freedom Bank", 1_000, .internalTransfer,
               account: "kaspi", target: "freedom")
        ]
        let index = ImportTransferHistory.build(from: history)

        // Kaspi statement, money out, same description: a transfer to Freedom.
        #expect(ImportTransferHistory.counterpart(
            accountId: "kaspi", direction: .outgoing, description: "Перевод · Тест К., Freedom Bank", in: index) == "freedom")
        // The same description arriving on Freedom came from Kaspi.
        #expect(ImportTransferHistory.counterpart(
            accountId: "freedom", direction: .incoming, description: "Перевод · Тест К., Freedom Bank", in: index) == "kaspi")
        // Another account or direction learned nothing.
        #expect(ImportTransferHistory.counterpart(
            accountId: "kaspi", direction: .incoming, description: "Перевод · Тест К., Freedom Bank", in: index) == nil)
    }

    @Test func plainSpendingOutvotesAStrayTransfer() {
        let history = [
            tx("t1", "2026-09-01", "Перевод с карты на карту", 5_000, .internalTransfer, account: "freedom", target: "kaspi"),
            tx("e1", "2026-09-02", "Перевод с карты на карту", 7_000, .expense, account: "freedom"),
            tx("e2", "2026-09-03", "Перевод с карты на карту", 9_000, .expense, account: "freedom")
        ]
        let index = ImportTransferHistory.build(from: history)
        #expect(ImportTransferHistory.counterpart(
            accountId: "freedom", direction: .outgoing, description: "Перевод с карты на карту", in: index) == nil)
    }

    // MARK: - Transfer matcher

    private let own: Set<String> = ["kaspi", "freedom"]

    @Test func incomeRowMatchesTheExpenseOnTheOtherAccount() {
        let existing = [tx("f1", "2026-09-19", "Перевод с карты на карту", 50_000, .expense, account: "freedom")]
        let row = tx("r1", "2026-09-19", "Пополнение · С карты другого банка", 50_000, .income, account: nil)

        let matches = ImportTransferMatcher.detect(
            imported: [row], importedAccounts: ["r1": "kaspi"], eligibleRowIds: ["r1"],
            ownAccountIds: own, existing: existing)
        #expect(matches["r1"] == .counterpart(existingId: "f1", accountId: "freedom"))
    }

    @Test func matchNeedsTheWindowTheDirectionAndAnotherAccount() {
        let existing = [
            tx("far", "2026-09-10", "x", 50_000, .expense, account: "freedom"),
            tx("same", "2026-09-19", "x", 50_000, .expense, account: "kaspi"),
            tx("sameDirection", "2026-09-19", "x", 50_000, .income, account: "freedom"),
            tx("recurring", "2026-09-19", "x", 50_000, .expense, account: "freedom", series: "s1"),
            tx("foreign", "2026-09-19", "x", 50_000, .expense, account: "someoneElse")
        ]
        let row = tx("r1", "2026-09-19", "Пополнение", 50_000, .income, account: nil)
        let matches = ImportTransferMatcher.detect(
            imported: [row], importedAccounts: ["r1": "kaspi"], eligibleRowIds: ["r1"],
            ownAccountIds: own, existing: existing)
        #expect(matches.isEmpty)
    }

    @Test func depositMoveIsNotTheOtherSideOfATransferToAPerson() {
        // Deposit → Freedom card → Kaspi → a person, all 150 000 on one day. The
        // Kaspi transfer to the person must not pair with the deposit top-up; the
        // Kaspi top-up pairs with the Freedom card transfer.
        let existing = [
            tx("dep", "2026-09-03", "Пополнение · Перевод вклада по Договору от 03.09.2026", 150_000, .income, account: "freedom"),
            tx("card", "2026-09-03", "Перевод с карты на карту", 150_000, .expense, account: "freedom")
        ]
        let rows = [
            tx("toPerson", "2026-09-03", "Перевод · Асан Б.", 150_000, .expense, account: nil),
            tx("topUp", "2026-09-03", "Пополнение · С карты другого банка", 150_000, .income, account: nil)
        ]
        let matches = ImportTransferMatcher.detect(
            imported: rows, importedAccounts: ["toPerson": "kaspi", "topUp": "kaspi"],
            eligibleRowIds: ["toPerson", "topUp"], ownAccountIds: own, existing: existing)
        #expect(matches["toPerson"] == nil)
        #expect(matches["topUp"] == .counterpart(existingId: "card", accountId: "freedom"))
    }

    @Test func purchaseRowsAreNeverMatched() {
        let existing = [tx("f1", "2026-09-19", "x", 5_000, .income, account: "freedom")]
        let row = tx("r1", "2026-09-19", "MAGNUM", 5_000, .expense, account: nil)
        let matches = ImportTransferMatcher.detect(
            imported: [row], importedAccounts: ["r1": "kaspi"], eligibleRowIds: [],
            ownAccountIds: own, existing: existing)
        #expect(matches.isEmpty)
    }

    @Test func savedTransferMarksBothStatementsAsAlreadyRecorded() {
        let existing = [tx("t1", "2026-09-19", "Перевод", 50_000, .internalTransfer, account: "freedom", target: "kaspi")]
        let kaspiRow = tx("k1", "2026-09-20", "Пополнение", 50_000, .income, account: nil)
        let freedomRow = tx("f1", "2026-09-19", "Перевод", 50_000, .expense, account: nil)

        let onKaspi = ImportTransferMatcher.detect(
            imported: [kaspiRow], importedAccounts: ["k1": "kaspi"], eligibleRowIds: ["k1"],
            ownAccountIds: own, existing: existing)
        #expect(onKaspi["k1"] == .alreadyTransfer(existingId: "t1"))

        let onFreedom = ImportTransferMatcher.detect(
            imported: [freedomRow], importedAccounts: ["f1": "freedom"], eligibleRowIds: ["f1"],
            ownAccountIds: own, existing: existing)
        #expect(onFreedom["f1"] == .alreadyTransfer(existingId: "t1"))
    }

    @Test func eachSavedTransactionPairsWithOneRow() {
        let existing = [tx("f1", "2026-09-19", "x", 50_000, .expense, account: "freedom")]
        let rows = [
            tx("r1", "2026-09-19", "Пополнение", 50_000, .income, account: nil),
            tx("r2", "2026-09-20", "Пополнение", 50_000, .income, account: nil)
        ]
        let matches = ImportTransferMatcher.detect(
            imported: rows, importedAccounts: ["r1": "kaspi", "r2": "kaspi"], eligibleRowIds: ["r1", "r2"],
            ownAccountIds: own, existing: existing)
        #expect(matches.count == 1)
        #expect(matches["r1"] == .counterpart(existingId: "f1", accountId: "freedom"))
    }

    // MARK: - Statement bank

    @Test func bankComesFromTheDomainOnThePages() {
        let kaspi = ["АО «Kaspi Bank», БИК CASPKZKA, www.kaspi.kz", "24.09.26 - 995,00 ₸ Покупка MAGNUM",
                     "АО «Kaspi Bank», БИК CASPKZKA, www.kaspi.kz"]
        #expect(StatementBankDetector.bankDomain(in: kaspi) == "kaspi.kz")

        // A Freedom statement full of "KASPI MAGAZIN" purchases is still Freedom's.
        let freedom = ["www.bankffin.kz", "01.09.2026 -500.00 ₸ KZT Покупка TOO \"KASPI MAGAZIN\" ALMATY KZ",
                       "https://bankffin.kz/ru/check-receipt"]
        #expect(StatementBankDetector.bankDomain(in: freedom) == "ffin.kz")

        #expect(StatementBankDetector.bankDomain(in: ["no bank here"]) == nil)
    }

    @Test func statementAccountByLogoThenByName() {
        let accounts: [(id: String, name: String, logoDomain: String?)] = [
            (id: "a1", name: "Основная", logoDomain: "kaspi.kz"),
            (id: "a2", name: "Фридом карта", logoDomain: nil),
            (id: "a3", name: "Наличные", logoDomain: nil)
        ]
        #expect(StatementBankDetector.accountId(forBankDomain: "kaspi.kz", among: accounts) == "a1")
        #expect(StatementBankDetector.accountId(forBankDomain: "ffin.kz", among: accounts) == "a2")
        #expect(StatementBankDetector.accountId(forBankDomain: "halykbank.kz", among: accounts) == nil)

        // Two Kaspi accounts and no logo: the user picks.
        let twoKaspi: [(id: String, name: String, logoDomain: String?)] = [
            (id: "b1", name: "Kaspi Gold", logoDomain: nil),
            (id: "b2", name: "Kaspi Deposit", logoDomain: nil)
        ]
        #expect(StatementBankDetector.accountId(forBankDomain: "kaspi.kz", among: twoKaspi) == nil)
    }

    // MARK: - Commit plan

    @Test func plainRowKeepsCategoryAndSubcategories() {
        let row = tx("r1", "2026-09-19", "Перевод · Асан Б.", 30_000, .expense, account: nil)
        let operations = ImportCommitPlanner.operations(for: [
            ImportRowDecision(row: row, accountId: "freedom", category: "Семья", subcategoryIds: ["loved"],
                              transferAccountId: nil, mergeWith: nil)
        ])
        guard case .add(let saved, let subcategories)? = operations.first else {
            Issue.record("expected an add"); return
        }
        #expect(saved.accountId == "freedom")
        #expect(saved.category == "Семья")
        #expect(saved.type == .expense)
        #expect(subcategories == ["loved"])
    }

    @Test func markedRowsBecomeTransfersInTheRightDirection() {
        let out = tx("r1", "2026-09-04", "Перевод · Тест К., Freedom Bank", 1_000, .expense, account: nil)
        let incoming = tx("r2", "2026-09-04", "Пополнение · Тест К.", 1_000, .income, account: nil)
        let operations = ImportCommitPlanner.operations(for: [
            ImportRowDecision(row: out, accountId: "kaspi", category: "", subcategoryIds: ["ignored"],
                              transferAccountId: "freedom", mergeWith: nil),
            ImportRowDecision(row: incoming, accountId: "freedom", category: "", subcategoryIds: [],
                              transferAccountId: "kaspi", mergeWith: nil)
        ])
        guard case .add(let first, let firstSubcategories) = operations[0],
              case .add(let second, _) = operations[1] else {
            Issue.record("expected two adds"); return
        }
        #expect(first.type == .internalTransfer)
        #expect(first.accountId == "kaspi" && first.targetAccountId == "freedom")
        #expect(first.category == TransactionType.transferCategoryName)
        #expect(firstSubcategories.isEmpty, "transfers carry no subcategories")
        #expect(second.accountId == "kaspi" && second.targetAccountId == "freedom")
        #expect(second.id == "r2")
    }

    @Test func secondSideConvertsTheSavedTransaction() {
        let saved = tx("f1", "2026-09-19", "Перевод с карты на карту", 50_000, .expense,
                       account: "freedom", category: "Food")
        let row = tx("r1", "2026-09-19", "Пополнение · С карты другого банка", 50_000, .income, account: nil)
        let operations = ImportCommitPlanner.operations(for: [
            ImportRowDecision(row: row, accountId: "kaspi", category: "", subcategoryIds: [],
                              transferAccountId: "freedom", mergeWith: saved)
        ])
        guard case .convert(let old, let new, let statementAccount)? = operations.first else {
            Issue.record("expected a convert"); return
        }
        #expect(old == saved)
        #expect(new.id == "f1")
        #expect(new.type == .internalTransfer)
        #expect(new.accountId == "freedom" && new.targetAccountId == "kaspi")
        #expect(new.date == "2026-09-19")
        #expect(statementAccount == "kaspi")
    }

    @Test func outgoingSecondSideMovesTheSourceToTheStatementAccount() {
        let saved = tx("k1", "2026-09-04", "Пополнение · Тест К.", 1_000, .income, account: "freedom")
        let row = tx("r1", "2026-09-04", "Перевод · Тест К., Freedom Bank", 1_000, .expense, account: nil)
        let operations = ImportCommitPlanner.operations(for: [
            ImportRowDecision(row: row, accountId: "kaspi", category: "", subcategoryIds: [],
                              transferAccountId: "freedom", mergeWith: saved)
        ])
        guard case .convert(_, let new, _)? = operations.first else {
            Issue.record("expected a convert"); return
        }
        #expect(new.accountId == "kaspi" && new.targetAccountId == "freedom")
    }

    @Test func transferToAnotherAccountThanTheMatchAddsANewTransfer() {
        let saved = tx("f1", "2026-09-19", "x", 50_000, .expense, account: "freedom")
        let row = tx("r1", "2026-09-19", "Пополнение", 50_000, .income, account: nil)
        let operations = ImportCommitPlanner.operations(for: [
            ImportRowDecision(row: row, accountId: "kaspi", category: "", subcategoryIds: [],
                              transferAccountId: "cash", mergeWith: saved)
        ])
        guard case .add(let added, _)? = operations.first else {
            Issue.record("expected an add"); return
        }
        #expect(added.accountId == "cash" && added.targetAccountId == "kaspi")
    }
}
