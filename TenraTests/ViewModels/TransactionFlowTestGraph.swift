//
//  TransactionFlowTestGraph.swift
//  TenraTests
//
//  The view-model graph the add/edit transaction screens need, wired the way
//  AppCoordinator wires it, on an isolated UserDefaultsRepository. Keeps the
//  store alive (AccountsViewModel / TransactionsViewModel hold it weakly).
//

import Foundation
@testable import Tenra

@MainActor
struct TransactionFlowTestGraph {
    let store: TransactionStore
    let balance: BalanceCoordinator
    let transactions: TransactionsViewModel
    let accounts: AccountsViewModel
    let categories: CategoriesViewModel

    static func make() async -> TransactionFlowTestGraph {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.flow.\(UUID().uuidString)")!
        )
        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: RecurringStore(repository: repo))

        let transactions = TransactionsViewModel(repository: repo)
        transactions.transactionStore = store
        transactions.balanceCoordinator = balance
        let accounts = AccountsViewModel(repository: repo)
        accounts.transactionStore = store
        accounts.balanceCoordinator = balance
        let categories = CategoriesViewModel(repository: repo)
        categories.transactionStore = store

        store.addCategory(CustomCategory(name: "Food", iconSource: .sfSymbol("cart"), colorHex: "#22c55e", type: .expense))
        store.addCategory(CustomCategory(name: "Groceries", iconSource: .sfSymbol("basket"), colorHex: "#16a34a", type: .expense))
        store.accounts = [Account(id: "a1", name: "Main", currency: "KZT", createdDate: Date(), initialBalance: 0)]
        store.rebuildAccountById()
        await balance.registerAccounts(store.accounts)

        return TransactionFlowTestGraph(store: store, balance: balance, transactions: transactions,
                                        accounts: accounts, categories: categories)
    }

    /// Rating-prompt transaction counter (process-global UserDefaults).
    static var ratingTxCount: Int { UserDefaults.standard.integer(forKey: "rating.txCount") }
}
