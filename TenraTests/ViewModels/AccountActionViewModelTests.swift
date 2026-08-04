//
//  AccountActionViewModelTests.swift
//  TenraTests
//
//  Unit tests for AccountActionViewModel default-action selection.
//

import Testing
import Foundation
@testable import Tenra

@Suite("AccountActionViewModel.defaultAction")
@MainActor
struct AccountActionViewModelTests {

    private func regularAccount(id: String = "a1") -> Account {
        Account(id: id, name: "Bank", currency: "KZT", iconSource: nil, initialBalance: 100_000)
    }

    private func depositAccount(id: String = "d1") -> Account {
        Account(
            id: id, name: "Savings", currency: "KZT", iconSource: nil,
            depositInfo: DepositInfo(
                bankName: "T",
                initialPrincipal: 100_000,
                capitalizationEnabled: false,
                interestRateAnnual: 0,
                interestRateHistory: [RateChange(effectiveFrom: "2020-01-01", annualRate: 0)],
                interestPostingDay: 1,
                lastInterestCalculationDate: "2020-01-01",
                lastInterestPostingMonth: "2020-01-01",
                interestAccruedForCurrentPeriod: 0,
                startDate: "2020-01-01"
            ),
            initialBalance: 100_000
        )
    }

    @Test("regular account defaults to .transfer when defaultAction is nil")
    func regularAccount_defaultsToTransfer() {
        let coord = AppCoordinator()
        let vm = AccountActionViewModel(
            account: regularAccount(),
            accountsViewModel: coord.accountsViewModel,
            transactionsViewModel: coord.transactionsViewModel,
            categoriesViewModel: coord.categoriesViewModel,
            defaultAction: nil
        )
        #expect(vm.selectedAction == .transfer)
    }

    @Test("deposit defaults to .transfer when defaultAction is nil")
    func depositAccount_defaultsToTransfer() {
        let coord = AppCoordinator()
        let vm = AccountActionViewModel(
            account: depositAccount(),
            accountsViewModel: coord.accountsViewModel,
            transactionsViewModel: coord.transactionsViewModel,
            categoriesViewModel: coord.categoriesViewModel,
            defaultAction: nil
        )
        #expect(vm.selectedAction == .transfer)
    }

    @Test("explicit defaultAction overrides per-account default")
    func explicitDefaultActionOverrides() {
        let coord = AppCoordinator()
        let vm = AccountActionViewModel(
            account: depositAccount(),
            accountsViewModel: coord.accountsViewModel,
            transactionsViewModel: coord.transactionsViewModel,
            categoriesViewModel: coord.categoriesViewModel,
            defaultAction: .transfer
        )
        #expect(vm.selectedAction == .transfer)
    }

    // MARK: - Subcategory tags (top-up)

    @Test("switching action drops the picked subcategories")
    func switchingActionClearsSubcategories() {
        let coord = AppCoordinator()
        let vm = AccountActionViewModel(
            account: regularAccount(),
            accountsViewModel: coord.accountsViewModel,
            transactionsViewModel: coord.transactionsViewModel,
            categoriesViewModel: coord.categoriesViewModel,
            defaultAction: .income
        )
        vm.selectedSubcategoryIds = ["sub-1", "sub-2"]

        vm.selectedAction = .transfer
        #expect(vm.selectedSubcategoryIds.isEmpty)
    }

    @Test("changing the income category drops the picked subcategories")
    func changingCategoryClearsSubcategories() {
        let coord = AppCoordinator()
        let vm = AccountActionViewModel(
            account: regularAccount(),
            accountsViewModel: coord.accountsViewModel,
            transactionsViewModel: coord.transactionsViewModel,
            categoriesViewModel: coord.categoriesViewModel,
            defaultAction: .income
        )
        vm.selectedSubcategoryIds = ["sub-1"]

        vm.handleCategorySelectionChange()
        #expect(vm.selectedSubcategoryIds.isEmpty)
    }

    @Test("subcategory picker stays hidden for transfers")
    func transferHasNoSubcategoryPicker() {
        let coord = AppCoordinator()
        let vm = AccountActionViewModel(
            account: regularAccount(),
            accountsViewModel: coord.accountsViewModel,
            transactionsViewModel: coord.transactionsViewModel,
            categoriesViewModel: coord.categoriesViewModel,
            defaultAction: .transfer
        )
        vm.selectedCategory = "Salary"
        #expect(vm.selectedCategoryId == nil)
    }
}
