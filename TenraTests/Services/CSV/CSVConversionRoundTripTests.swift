//
//  CSVConversionRoundTripTests.swift
//  TenraTests
//
//  Export → import through the real CSV pipeline (CSVExporter, CSVParsingService,
//  CSVImportCoordinator) into a fresh store, for transactions in another currency than
//  their account:
//  - export dropped a transfer's source leg and labelled the converted column with the
//    transaction's currency;
//  - import never converted a row in another currency than its account, so the balance
//    moved by the raw foreign amount (10 USD off a tenge account as 10 ₸).
//  Old 11-column files must import as before.
//
//  @MainActor + .sharedProcessState: the tests seed the process-global
//  CurrencyRateStore.shared (cleared in init) and swap CurrencyConverter.providerChain;
//  the import also invalidates CategoryStyleCache.shared.
//

import Testing
import Foundation
@testable import Tenra

/// Every provider fails: nothing reaches the network.
private struct CSVOfflineRateProvider: CurrencyRateProvider {
    let name: String = "offline"

    func fetchRates(on date: Date?) async throws -> ExchangeRates {
        throw CurrencyProviderError.providerDisabled
    }
}

@MainActor
@Suite(.serialized, .sharedProcessState)
struct CSVConversionRoundTripTests {

    init() {
        CurrencyRateStore.shared.clearAll()
    }

    // MARK: - Fixtures

    /// A tenge ("kzt", "Tenge") and a dollar ("usd", "Dollars") account, both created
    /// before the rows, base currency KZT.
    private func makeGraph() async -> TransactionFlowTestGraph {
        let graph = await TransactionFlowTestGraph.make()
        let created = DateFormatters.dateFormatter.date(from: "2026-01-01")!
        graph.store.accounts = [
            Account(id: "kzt", name: "Tenge", currency: "KZT", createdDate: created, initialBalance: 0),
            Account(id: "usd", name: "Dollars", currency: "USD", createdDate: created, initialBalance: 0)
        ]
        graph.store.rebuildAccountById()
        await graph.balance.registerAccounts(graph.store.accounts)
        return graph
    }

    /// 1 USD = 500 ₸ in the cache: the transactions below were recorded at 450-460 ₸,
    /// so anything re-priced on the way shows.
    private func seedRates() {
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 500, "EUR": 550],
            date: Date(),
            providerName: "test"
        ))
    }

    /// Every column mapped by its header; an absent header reads as unmapped.
    private var mapping: CSVColumnMapping {
        var mapping = CSVColumnMapping()
        mapping.dateColumn = "date"
        mapping.typeColumn = "type"
        mapping.amountColumn = "amount"
        mapping.currencyColumn = "currency"
        mapping.accountColumn = "account"
        mapping.categoryColumn = "category"
        mapping.subcategoriesColumn = "subcategories"
        mapping.noteColumn = "note"
        mapping.targetAccountColumn = "targetAccount"
        mapping.targetCurrencyColumn = "targetCurrency"
        mapping.targetAmountColumn = "targetAmount"
        mapping.convertedAmountColumn = "convertedAmount"
        return mapping
    }

    @discardableResult
    private func importCSV(_ csv: String, into graph: TransactionFlowTestGraph) async throws -> ImportStatistics {
        let file = try await CSVParsingService().parseContent(csv)
        let coordinator = CSVImportCoordinator.create(for: file, transactionStore: graph.store)
        return await coordinator.importTransactions(
            csvFile: file,
            columnMapping: mapping,
            entityMapping: EntityMapping(),
            transactionsViewModel: graph.transactions,
            categoriesViewModel: graph.categories,
            accountsViewModel: graph.accounts,
            progress: ImportProgress()
        )
    }

    /// Runs `body` with no network rate source, then restores the real one.
    private func offline<T>(_ body: () async throws -> T) async rethrows -> T {
        let original = CurrencyConverter.providerChain
        CurrencyConverter.providerChain = CurrencyRateProviderChain(providers: [CSVOfflineRateProvider()])
        defer { CurrencyConverter.providerChain = original }
        return try await body()
    }

    private func byDescription(_ graph: TransactionFlowTestGraph) -> [String: Transaction] {
        Dictionary(uniqueKeysWithValues: graph.store.transactions.map { ($0.description, $0) })
    }

    private func close(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.01
    }

    // MARK: - Round trip

    @Test("export → import keeps every recorded conversion, and the balances with them")
    func roundTripKeepsConversions() async throws {
        seedRates()
        let source = await makeGraph()
        let originals = [
            // Saved by voice: only convertedAmount.
            Transaction(id: "voice", date: "2026-09-01", description: "Voice coffee", amount: 10,
                        currency: "USD", convertedAmount: 4_500, type: .expense, category: "Food",
                        accountId: "kzt"),
            // Saved by the add screen: convertedAmount and the equivalent.
            Transaction(id: "rule", date: "2026-09-02", description: "Book", amount: 20,
                        currency: "USD", convertedAmount: 9_000, type: .expense, category: "Food",
                        accountId: "kzt", targetCurrency: "KZT", targetAmount: 9_000),
            // A transfer typed in dollars from the tenge account.
            Transaction(id: "xfer", date: "2026-09-03", description: "To dollars", amount: 10,
                        currency: "USD", convertedAmount: 4_600, type: .internalTransfer,
                        category: TransactionType.transferCategoryName, accountId: "kzt",
                        targetAccountId: "usd", targetCurrency: "USD", targetAmount: 10),
            // In its account's currency, with the base-currency equivalent.
            Transaction(id: "base", date: "2026-09-04", description: "Snack", amount: 5,
                        currency: "USD", type: .expense, category: "Food", accountId: "usd",
                        targetCurrency: "KZT", targetAmount: 2_300)
        ]
        let csv = CSVExporter.exportTransactions(originals, accounts: source.store.accounts)

        let graph = await makeGraph()
        let stats = try await importCSV(csv, into: graph)

        #expect(stats.importedCount == originals.count)
        #expect(stats.errors.isEmpty)
        let imported = byDescription(graph)
        let voice = try #require(imported["Voice coffee"])
        #expect(voice.convertedAmount == 4_500, "not re-priced at today's 500")
        let book = try #require(imported["Book"])
        #expect(book.convertedAmount == 9_000)
        let transfer = try #require(imported["To dollars"])
        #expect(transfer.convertedAmount == 4_600, "a transfer's source leg survives (was dropped)")
        #expect(transfer.targetCurrency == "USD")
        #expect(transfer.targetAmount == 10)
        let snack = try #require(imported["Snack"])
        #expect(snack.convertedAmount == nil)
        #expect(snack.targetCurrency == "KZT")
        #expect(snack.targetAmount == 2_300)

        // Tenge: −(4 500 + 9 000 + 4 600). Dollars: +10 − 5.
        #expect(close(graph.balance.balances["kzt"], -18_100))
        #expect(close(graph.balance.balances["usd"], 5))
    }

    @Test("an 11-column file from before reads as before and converts what it left unconverted")
    func oldFileReadsAsBefore() async throws {
        seedRates()
        let graph = await makeGraph()
        let csv = """
        date,type,amount,currency,account,category,subcategories,note,targetAccount,targetCurrency,targetAmount
        2026-09-01,expense,10.00,USD,Tenge,Food,,Old label,,USD,4500.00
        2026-09-02,expense,10.00,USD,Tenge,Food,,No value,,,
        2026-09-03,internal,10.00,USD,Tenge,,,Old transfer,Dollars,USD,10.00
        """

        let stats = try await importCSV(csv, into: graph)

        #expect(stats.importedCount == 3)
        let imported = byDescription(graph)
        // The old exporter labelled the tenge value with the transaction's currency.
        let oldLabel = try #require(imported["Old label"])
        #expect(oldLabel.convertedAmount == 4_500)
        #expect(oldLabel.targetAmount == nil, "read exactly as before")
        // Moved the tenge balance by the raw 10 before; now at the cached rate.
        let noValue = try #require(imported["No value"])
        #expect(noValue.convertedAmount == 5_000)
        let transfer = try #require(imported["Old transfer"])
        #expect(transfer.convertedAmount == 5_000, "the source leg the old file never had")
        #expect(transfer.targetAmount == 10)

        #expect(close(graph.balance.balances["kzt"], -14_500))
        #expect(close(graph.balance.balances["usd"], 10))
    }

    @Test("without a rate the row is skipped with an error, and the rows before it are saved")
    func missingRateSkipsTheRow() async throws {
        // No cached rate and no network. The skipped row is the last one: the final batch
        // was flushed only on the last row, so it dropped the rows before it too.
        let graph = await makeGraph()
        let csv = """
        date,type,amount,currency,account,category,subcategories,note,targetAccount,targetCurrency,targetAmount,convertedAmount
        2026-09-01,expense,1000.00,KZT,Tenge,Food,,Lunch,,,,
        2026-09-02,expense,10.00,USD,Tenge,Food,,Dollars spent,,,,
        """

        let stats = try await offline { try await importCSV(csv, into: graph) }

        #expect(stats.importedCount == 1)
        #expect(stats.errors.contains { $0.code == .conversionFailed })
        #expect(graph.store.transactions.map(\.description) == ["Lunch"])
        #expect(close(graph.balance.balances["kzt"], -1_000), "never moved by the raw 10")
    }
}
