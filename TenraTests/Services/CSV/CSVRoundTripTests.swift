//
//  CSVRoundTripTests.swift
//  TenraTests
//
//  CSV export → import round-trip tests that pin the column contract.
//
//  Column contract (11 columns):
//  index: 0=date, 1=type, 2=amount, 3=currency, 4=account, 5=category,
//         6=subcategories, 7=note, 8=targetAccount, 9=targetCurrency, 10=targetAmount
//
//  Per-type rules:
//  - expense: [4]=accountName, [5]=category; [8..10] empty unless convertedAmount exists
//  - income (SWAP): [4]=category (not account!), [5]="", [8]=accountName
//    import: effectiveAccountValue reads [8] (rawTargetAccountValue)
//            effectiveCategoryValue reads [4] (rawAccountValue)
//  - internalTransfer: [4]=sourceAccountName, [5]="", [8]=targetAccountName,
//                      [9]=targetCurrency, [10]=targetAmount (actual amounts, NOT convertedAmount)
//  - other types (depositTopUp, etc.): same pattern as expense
//
//  Income swap is the most critical case — it is the ONLY reason effectiveAccountValue
//  and effectiveCategoryValue exist on CSVRow.
//

import Testing
import Foundation
@testable import Tenra

@MainActor @Suite struct CSVRoundTripTests {

    // MARK: - Fixtures

    private let kaspiId  = "acc-kaspi"
    private let wiseId   = "acc-wise"

    private var kaspi: Account {
        Account(id: kaspiId, name: "Каспи", currency: "KZT")
    }
    private var wise: Account {
        Account(id: wiseId, name: "Wise", currency: "USD")
    }
    private var accounts: [Account] { [kaspi, wise] }

    // sub1, sub2 used for the subcategory join/split test
    private let sub1Id = "sub-1"
    private let sub2Id = "sub-2"
    private var sub1: Subcategory { Subcategory(id: sub1Id, name: "Groceries") }
    private var sub2: Subcategory { Subcategory(id: sub2Id, name: "Fresh Produce") }

    private let expenseTxId    = "tx-expense"
    private let expenseSubTxId = "tx-expense-sub"
    private let incomeTxId     = "tx-income"
    private let transferTxId   = "tx-transfer"
    private let escapeTxId     = "tx-escape"

    /// All fixture transactions (order matters for row-index assertions).
    private var transactions: [Transaction] {
        [
            // 0: plain expense — Каспи KZT
            Transaction(
                id: expenseTxId,
                date: "2026-01-15",
                description: "Coffee",
                amount: 1234.56,
                currency: "KZT",
                type: .expense,
                category: "Food",
                accountId: kaspiId
            ),
            // 1: expense with 2 subcategories — linked via TransactionSubcategoryLink
            Transaction(
                id: expenseSubTxId,
                date: "2026-02-10",
                description: "Market run",
                amount: 5000.00,
                currency: "KZT",
                type: .expense,
                category: "Food",
                accountId: kaspiId
            ),
            // 2: income (swap case) — category="Salary", account=kaspi
            Transaction(
                id: incomeTxId,
                date: "2026-03-01",
                description: "Monthly pay",
                amount: 350000.00,
                currency: "KZT",
                type: .income,
                category: "Salary",
                accountId: kaspiId
            ),
            // 3: internal transfer KZT→USD with distinct targetAmount/targetCurrency
            Transaction(
                id: transferTxId,
                date: "2026-04-05",
                description: "Exchange",
                amount: 200000.00,
                currency: "KZT",
                type: .internalTransfer,
                category: "Transfer",
                accountId: kaspiId,
                targetAccountId: wiseId,
                targetCurrency: "USD",
                targetAmount: 450.25
            ),
            // 4: expense with comma + double-quote in note (escaping test)
            Transaction(
                id: escapeTxId,
                date: "2026-05-20",
                description: "Note with, comma and \"quote\"",
                amount: 99.99,
                currency: "KZT",
                type: .expense,
                category: "Other",
                accountId: kaspiId
            ),
        ]
    }

    /// Subcategory links for the 2-subcategory expense transaction.
    private var subcategoryLinks: [TransactionSubcategoryLink] {
        [
            TransactionSubcategoryLink(transactionId: expenseSubTxId, subcategoryId: sub1Id),
            TransactionSubcategoryLink(transactionId: expenseSubTxId, subcategoryId: sub2Id),
        ]
    }
    private var subcategories: [Subcategory] { [sub1, sub2] }

    // MARK: - Helpers

    /// Exports all fixtures and parses back, returning the CSVFile.
    private func roundTrip() async throws -> CSVFile {
        let csv = CSVExporter.exportTransactions(
            transactions,
            accounts: accounts,
            subcategoryLinks: subcategoryLinks,
            subcategories: subcategories
        )
        return try await CSVParsingService().parseContent(csv)
    }

    // MARK: - Test 1: Row count and header

    @Test("row count and header column order match the 11-column contract")
    func rowCountAndHeader() async throws {
        let file = try await roundTrip()
        #expect(file.rows.count == transactions.count,
                "parsed row count should equal fixture count")
        let expectedHeaders = [
            "date", "type", "amount", "currency",
            "account", "category", "subcategories", "note",
            "targetAccount", "targetCurrency", "targetAmount"
        ]
        #expect(file.headers == expectedHeaders,
                "header row must match the documented 11-column order exactly")
    }

    // MARK: - Test 2: Expense fidelity

    @Test("plain expense fidelity: date, type, amount, currency, account, category, note survive")
    func expenseFidelity() async throws {
        let file = try await roundTrip()
        // Row 0 is the plain expense (expenseTxId)
        let row = file.rows[0]
        #expect(row[0] == "2026-01-15",  "date")
        #expect(row[1] == "expense",     "type")
        #expect(row[2] == "1234.56",     "amount uses %.2f format")
        #expect(row[3] == "KZT",         "currency")
        #expect(row[4] == "Каспи",       "account column = account name for expense")
        #expect(row[5] == "Food",        "category column = category for expense")
        #expect(row[7] == "Coffee",      "note survives")
    }

    // MARK: - Test 3: Income swap round-trips

    @Test("income swap: effectiveAccountValue returns account name; effectiveCategoryValue returns category")
    func incomeSwapRoundTrips() async throws {
        let csv = CSVExporter.exportTransactions(
            transactions,
            accounts: accounts,
            subcategoryLinks: subcategoryLinks,
            subcategories: subcategories
        )
        let file = try await CSVParsingService().parseContent(csv)

        // Row 2 is the income transaction (incomeTxId)
        let rawRow = file.rows[2]

        // Verify raw column layout first — this pins the contract at string level.
        // account column (4) must carry the CATEGORY name (the swap)
        #expect(rawRow[4] == "Salary",
                "income export: account column (4) must carry the CATEGORY name due to swap")
        // targetAccount column (8) must carry the ACCOUNT name
        #expect(rawRow[8] == "Каспи",
                "income export: targetAccount column (8) must carry the ACCOUNT name due to swap")

        // Now verify the import accessors correctly undo the swap via a manually constructed CSVRow.
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let parsedDate = try #require(dateFormatter.date(from: rawRow[0]))

        let csvRow = CSVRow(
            rowIndex: 2,
            date: parsedDate,
            type: .income,
            amount: Double(rawRow[2]) ?? 0,
            currency: rawRow[3],
            rawAccountValue: rawRow[4],       // "Salary" (swapped into account column)
            rawTargetAccountValue: rawRow[8].isEmpty ? nil : rawRow[8],  // "Каспи"
            targetCurrency: rawRow[9].isEmpty ? nil : rawRow[9],
            targetAmount: Double(rawRow[10]),
            rawCategoryValue: rawRow[5],      // "" (blank for income)
            subcategoryNames: [],
            note: rawRow[7].isEmpty ? nil : rawRow[7]
        )

        // effectiveAccountValue for income reads rawTargetAccountValue → "Каспи"
        #expect(csvRow.effectiveAccountValue == "Каспи",
                "effectiveAccountValue must return the actual account name for income")
        // effectiveCategoryValue for income reads rawAccountValue → "Salary"
        #expect(csvRow.effectiveCategoryValue == "Salary",
                "effectiveCategoryValue must return the category name for income")
    }

    // MARK: - Test 4: Transfer target columns

    @Test("transfer: targetAccount, targetCurrency, targetAmount columns carry actual target data")
    func transferTargetColumns() async throws {
        let file = try await roundTrip()
        // Row 3 is the transfer (transferTxId)
        let row = file.rows[3]
        #expect(row[1] == "internal",  "type column for internalTransfer")
        #expect(row[4] == "Каспи",    "source account name in account column")
        #expect(row[8] == "Wise",     "target account name in targetAccount column")
        #expect(row[9] == "USD",      "targetCurrency column")
        #expect(row[10] == "450.25",  "targetAmount column uses %.2f format")
    }

    // MARK: - Test 5: Subcategories join/split

    @Test("subcategories: 2-subcategory expense exports comma-joined field, parses back to same 2 names")
    func subcategoriesJoinSplit() async throws {
        let file = try await roundTrip()
        // Row 1 is the 2-subcategory expense (expenseSubTxId)
        let row = file.rows[1]
        // The subcategories column (6) should contain the comma-joined names.
        // CSVExporter wraps "Groceries,Fresh Produce" in quotes so the comma
        // is treated as a literal — the parser returns the whole string as one field.
        let rawSubcategoriesField = row[6]
        let parsed = rawSubcategoriesField
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let expected = Set(["Groceries", "Fresh Produce"])
        let actual = Set(parsed)
        #expect(actual == expected,
                "parsed subcategory names must match the 2 fixture subcategories (order-insensitive)")
    }

    // MARK: - Test 6: Escaping survives

    @Test("comma-and-quote note round-trips byte-identical through CSV escaping")
    func escapingSurvives() async throws {
        let file = try await roundTrip()
        // Row 4 is the escape test transaction (escapeTxId)
        let row = file.rows[4]
        let expected = "Note with, comma and \"quote\""
        #expect(row[7] == expected,
                "note containing a comma and double-quote must survive CSV escaping/unescaping")
    }

    // MARK: - Test 7: Empty input

    @Test("exporting empty transaction list yields header-only / zero data rows without throwing")
    func emptyInput() async throws {
        let csv = CSVExporter.exportTransactions([], accounts: [])
        // parseContent should succeed (not throw) for header-only content
        let file = try await CSVParsingService().parseContent(csv)
        #expect(file.rows.count == 0,
                "no data rows expected for empty export")
        #expect(file.headers.count == 11,
                "header row must still have all 11 columns even for empty export")
    }
}
