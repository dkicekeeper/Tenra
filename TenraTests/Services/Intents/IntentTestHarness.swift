//
//  IntentTestHarness.swift
//  TenraTests
//
//  Collaborators the intent services need, assembled the way the existing
//  suites do it (see TransactionStoreNewIndexesTests.swift:23-34).
//  UserDefaultsRepository is the preview/test repository, so no CoreData
//  container is required for the commit path.
//
//  Holds a STRONG reference to the store: AccountsViewModel.transactionStore is
//  weak, and accounts empty out the moment the store deallocates.
//

import Foundation
@testable import Tenra

@MainActor
final class IntentTestHarness {

    let store: TransactionStore
    let categories: CategoriesViewModel

    private(set) var learningCalls: [(category: String?, accountId: String?)] = []
    private(set) var ratingCallCount = 0

    var hooks: CommitHooks {
        CommitHooks(
            recordLearning: { [weak self] category, accountId in
                self?.learningCalls.append((category, accountId))
            },
            recordRating: { [weak self] in
                self?.ratingCallCount += 1
            }
        )
    }

    init() {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "intent.tests.\(UUID().uuidString)")!
        )
        let recurring = RecurringStore(repository: repo)
        let balance = BalanceCoordinator(repository: repo)

        self.store = TransactionStore(
            repository: repo,
            balanceCoordinator: balance,
            recurringStore: recurring
        )
        self.categories = CategoriesViewModel(repository: repo)

        let food = CustomCategory(
            name: "Food",
            iconSource: .sfSymbol("fork.knife"),
            colorHex: "#f97316",
            type: .expense
        )

        // TransactionStore.validate reads store.accounts (via the accountById
        // index) and store.categories, so both must be seeded directly.
        // rebuildAccountById() is what every production account CRUD path calls
        // after mutating the array.
        store.accounts = [
            Account(id: "a1", name: "Wallet", currency: "KZT", balance: 0)
        ]
        store.rebuildAccountById()
        store.categories = [food]

        categories.addCategory(food)
    }
}
