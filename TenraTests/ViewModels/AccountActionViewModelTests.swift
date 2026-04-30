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
            defaultAction: .transfer
        )
        #expect(vm.selectedAction == .transfer)
    }
}
