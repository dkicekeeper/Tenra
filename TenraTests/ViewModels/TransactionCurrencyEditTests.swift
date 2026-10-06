//
//  TransactionCurrencyEditTests.swift
//  TenraTests
//
//  The owner's report: "if I edit the currency, the equivalent is sometimes not
//  applied". TransactionEditCoordinator rebuilt the transaction with only
//  `convertedAmount`, re-priced at today's rate:
//  - `targetCurrency` / `targetAmount` were dropped on every save: the equivalent
//    under the amount vanished, and a cross-currency transfer credited its target
//    account with the source amount (10 USD arrived as 10 ₸);
//  - a missing rate saved the raw foreign amount, silently;
//  - editing only the description re-priced a foreign-currency transaction.
//  The add screen shares the rule and is pinned here too.
//
//  @MainActor + .sharedProcessState: the tests seed the process-global
//  CurrencyRateStore.shared (cleared in init) and swap CurrencyConverter.providerChain.
//

import Testing
import Foundation
@testable import Tenra

/// Every provider fails: a rate missing from the cache stays missing, and nothing
/// reaches the network.
private struct OfflineRateProvider: CurrencyRateProvider {
    let name: String = "offline"

    func fetchRates(on date: Date?) async throws -> ExchangeRates {
        throw CurrencyProviderError.providerDisabled
    }
}

@MainActor
@Suite(.serialized, .sharedProcessState)
struct TransactionCurrencyEditTests {

    init() {
        CurrencyRateStore.shared.clearAll()
    }

    // MARK: - Fixtures

    /// The flow graph with a dollar ("usd") and a euro ("eur") account next to the tenge
    /// one ("a1"), base currency KZT, and 1 USD = 500 ₸, 1 EUR = 550 ₸ in the rate cache.
    private func makeGraph(seedRates: Bool = true) async -> TransactionFlowTestGraph {
        let graph = await TransactionFlowTestGraph.make()
        graph.store.accounts.append(Account(id: "usd", name: "Dollars", currency: "USD", createdDate: Date(), initialBalance: 0))
        graph.store.accounts.append(Account(id: "eur", name: "Euros", currency: "EUR", createdDate: Date(), initialBalance: 0))
        graph.store.rebuildAccountById()
        await graph.balance.registerAccounts(graph.store.accounts)
        graph.transactions.appSettings.baseCurrency = "KZT"
        if seedRates {
            CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
                pivot: "KZT",
                rates: ["USD": 500, "EUR": 550],
                date: Date(),
                providerName: "test"
            ))
        }
        return graph
    }

    /// Runs `body` with no network rate source, then restores the real one.
    private func offline(_ body: () async throws -> Void) async rethrows {
        let original = CurrencyConverter.providerChain
        CurrencyConverter.providerChain = CurrencyRateProviderChain(providers: [OfflineRateProvider()])
        defer { CurrencyConverter.providerChain = original }
        try await body()
    }

    private static var yesterday: String {
        DateFormatters.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    }

    private func editor(_ graph: TransactionFlowTestGraph, _ transaction: Transaction) -> TransactionEditCoordinator {
        TransactionEditCoordinator(
            transaction: transaction,
            transactionsViewModel: graph.transactions,
            categoriesViewModel: graph.categories,
            accountsViewModel: graph.accounts,
            transactionStore: graph.store
        )
    }

    /// `save` finishes on a spawned Task; wait until it reports success or an error.
    private func saveAndWait(_ editor: TransactionEditCoordinator) async -> Bool {
        var succeeded = false
        editor.save { succeeded = true }
        for _ in 0..<2000 where !succeeded && editor.errorMessage == nil && editor.bulkCategoryProposal == nil {
            await Task.yield()
        }
        return succeeded
    }

    // MARK: - Edit screen

    @Test("changing the currency keeps the equivalent and moves the balance by it")
    func currencyEditKeepsEquivalent() async throws {
        let graph = await makeGraph()
        let original = try await graph.store.add(Transaction(
            id: "t1", date: Self.yesterday, description: "Lunch", amount: 5_000, currency: "KZT",
            type: .expense, category: "Food", accountId: "a1"
        ))

        let edit = editor(graph, original)
        edit.formData.selectedCurrency = "USD"
        edit.formData.amountText = "20"
        let succeeded = await saveAndWait(edit)

        #expect(succeeded, "error: \(edit.errorMessage ?? "none")")
        let saved = try #require(graph.store.transactionById["t1"])
        #expect(saved.currency == "USD")
        #expect(saved.convertedAmount == 10_000)
        // The equivalent shown under the amount: dropped by every edit before.
        #expect(saved.targetCurrency == "KZT")
        #expect(saved.targetAmount == 10_000)
        #expect(graph.balance.balances["a1"] == -10_000)
    }

    @Test("editing only the description keeps the recorded conversion")
    func descriptionEditKeepsConversion() async throws {
        let graph = await makeGraph()
        // Recorded at 480 ₸/$; today's cached rate is 500.
        let original = try await graph.store.add(Transaction(
            id: "t1", date: Self.yesterday, description: "Hotel", amount: 10, currency: "USD",
            convertedAmount: 4_800, type: .expense, category: "Food", accountId: "a1",
            targetCurrency: "KZT", targetAmount: 4_800
        ))
        #expect(graph.balance.balances["a1"] == -4_800)

        let edit = editor(graph, original)
        edit.formData.descriptionText = "Hotel, two nights"
        let succeeded = await saveAndWait(edit)

        #expect(succeeded, "error: \(edit.errorMessage ?? "none")")
        let saved = try #require(graph.store.transactionById["t1"])
        #expect(saved.convertedAmount == 4_800)
        #expect(saved.targetCurrency == "KZT")
        #expect(saved.targetAmount == 4_800)
        #expect(graph.balance.balances["a1"] == -4_800)
    }

    @Test("an amount edit keeps the rate the transaction was recorded with")
    func amountEditKeepsRecordedRate() async throws {
        let graph = await makeGraph()
        let original = try await graph.store.add(Transaction(
            id: "t1", date: Self.yesterday, description: "Hotel", amount: 10, currency: "USD",
            convertedAmount: 4_800, type: .expense, category: "Food", accountId: "a1",
            targetCurrency: "KZT", targetAmount: 4_800
        ))

        let edit = editor(graph, original)
        edit.formData.amountText = "20"
        let succeeded = await saveAndWait(edit)

        #expect(succeeded, "error: \(edit.errorMessage ?? "none")")
        let saved = try #require(graph.store.transactionById["t1"])
        #expect(saved.convertedAmount == 9_600)
        #expect(saved.targetAmount == 9_600)
        #expect(graph.balance.balances["a1"] == -9_600)
    }

    @Test("editing a cross-currency transfer keeps what the target account received")
    func transferEditKeepsTargetAmount() async throws {
        let graph = await makeGraph()
        let original = try await graph.store.add(Transaction(
            id: "tr1", date: Self.yesterday, description: "To tenge", amount: 10, currency: "USD",
            type: .internalTransfer, category: TransactionType.transferCategoryName,
            accountId: "usd", targetAccountId: "a1", targetCurrency: "KZT", targetAmount: 4_800
        ))
        #expect(graph.balance.balances["usd"] == -10)
        #expect(graph.balance.balances["a1"] == 4_800)

        let edit = editor(graph, original)
        edit.formData.descriptionText = "To the tenge card"
        let succeeded = await saveAndWait(edit)

        #expect(succeeded, "error: \(edit.errorMessage ?? "none")")
        let saved = try #require(graph.store.transactionById["tr1"])
        #expect(saved.convertedAmount == nil)
        #expect(saved.targetCurrency == "KZT")
        #expect(saved.targetAmount == 4_800)
        #expect(graph.balance.balances["usd"] == -10)
        // Was credited 10 ₸ once targetAmount was dropped.
        #expect(graph.balance.balances["a1"] == 4_800)
    }

    @Test("no rate for the new currency: the edit is refused and nothing changes")
    func missingRateRefusesEdit() async throws {
        try await offline {
            let graph = await makeGraph(seedRates: false)
            let original = try await graph.store.add(Transaction(
                id: "t1", date: Self.yesterday, description: "Lunch", amount: 5_000, currency: "KZT",
                type: .expense, category: "Food", accountId: "a1"
            ))

            let edit = editor(graph, original)
            // A code no rate provider knows: unconvertible even if real rates land meanwhile.
            edit.formData.selectedCurrency = "ZZZ"
            edit.formData.amountText = "20"
            let succeeded = await saveAndWait(edit)

            #expect(!succeeded)
            #expect(edit.errorMessage == String(localized: "currency.error.conversionFailed"))
            let saved = try #require(graph.store.transactionById["t1"])
            #expect(saved.currency == "KZT")
            #expect(saved.amount == 5_000)
            #expect(graph.balance.balances["a1"] == -5_000)
        }
    }

    // MARK: - Add screen

    @Test("adding dollars to a euro card stores euros in convertedAmount, not tenge")
    func addStoresAccountCurrencyValue() async throws {
        let graph = await makeGraph()
        let add = TransactionAddCoordinator(
            category: "Food",
            type: .expense,
            currency: "USD",
            transactionsViewModel: graph.transactions,
            categoriesViewModel: graph.categories,
            accountsViewModel: graph.accounts,
            transactionStore: graph.store
        )
        add.formData.amountText = "11"
        add.formData.accountId = "eur"

        let result = await add.save()

        #expect(result.isValid)
        let saved = try #require(graph.store.transactions.first)
        #expect(saved.currency == "USD")
        // 11 × 500 / 550. Was 5 500, the base-currency value.
        #expect(saved.convertedAmount == 10)
        #expect(saved.targetCurrency == "EUR")
        #expect(saved.targetAmount == 10)
        #expect(graph.balance.balances["eur"] == -10)
    }

    @Test("adding with no rate for the currency is refused, not saved raw")
    func addWithoutRateIsRefused() async throws {
        try await offline {
            let graph = await makeGraph(seedRates: false)
            let add = TransactionAddCoordinator(
                category: "Food",
                type: .expense,
                currency: "ZZZ",
                transactionsViewModel: graph.transactions,
                categoriesViewModel: graph.categories,
                accountsViewModel: graph.accounts,
                transactionStore: graph.store
            )
            add.formData.amountText = "10"
            add.formData.accountId = "a1"

            let result = await add.save()

            #expect(!result.isValid)
            #expect(graph.store.transactions.isEmpty)
            #expect(graph.balance.balances["a1"] == 0)
        }
    }
}
