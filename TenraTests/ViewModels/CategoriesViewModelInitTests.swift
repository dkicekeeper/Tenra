//
//  CategoriesViewModelInitTests.swift
//  TenraTests
//
//  `CategoriesViewModel.init` used to read the three subcategory tables from the
//  repository: three blocking CoreData fetches inside `AppCoordinator.init`, before the
//  first frame, whose result `setupTransactionStoreObserver()` replaced with the
//  still-empty store a few lines later. The tables now come only from the store.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoriesViewModelInitTests {

    private static func makeRepository() -> UserDefaultsRepository {
        UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.categoriesInit.\(UUID().uuidString)")!
        )
    }

    @Test("init reads no subcategory table; the store's tables arrive through sync")
    func subcategoryTablesComeFromTheStore() {
        let repository = Self.makeRepository()
        let coffee = Subcategory(name: "Coffee")
        repository.saveSubcategories([coffee])
        repository.saveCategorySubcategoryLinks([CategorySubcategoryLink(categoryId: "food", subcategoryId: coffee.id)])
        repository.saveTransactionSubcategoryLinks([TransactionSubcategoryLink(transactionId: "t1", subcategoryId: coffee.id)])

        let viewModel = CategoriesViewModel(repository: repository)
        #expect(viewModel.subcategories.isEmpty)
        #expect(viewModel.categorySubcategoryLinks.isEmpty)
        #expect(viewModel.transactionSubcategoryLinks.isEmpty)

        // What the app wires up: the store owns the tables (filled by its full load).
        let store = TransactionStore(
            repository: repository,
            balanceCoordinator: BalanceCoordinator(repository: repository),
            recurringStore: RecurringStore(repository: repository)
        )
        store.subcategories = [coffee]
        store.categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        store.transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()
        viewModel.transactionStore = store
        viewModel.syncCategoriesFromStore()

        #expect(viewModel.subcategories == [coffee])
        #expect(viewModel.categorySubcategoryLinks.map(\.subcategoryId) == [coffee.id])
        #expect(viewModel.transactionSubcategoryLinks.map(\.transactionId) == ["t1"])
    }

    @Test("reloadFromStorage still reads the repository (data reset)")
    func reloadFromStorageReadsTheRepository() {
        let repository = Self.makeRepository()
        let coffee = Subcategory(name: "Coffee")
        repository.saveSubcategories([coffee])

        let viewModel = CategoriesViewModel(repository: repository)
        viewModel.reloadFromStorage()
        #expect(viewModel.subcategories == [coffee])
    }
}
