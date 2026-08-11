//
//  ImportTransactionPreviewViewTests.swift
//  TenraTests
//
//  Pins ImportTransactionPreviewView.availableAccounts(for:regularAccounts:),
//  the pure account-matching rule factored out of the view body so it is
//  unit-testable without standing up a View or an AccountsViewModel.
//
//  Fix 4 (CRITICAL): a statement transaction whose currency matched no
//  account could still be selected in the UI, saved with a nil accountId,
//  and become invisible to every balance calculation (accountId drives
//  balance derivation throughout this codebase). The UI now gates
//  selectability on this function returning a non-empty result.
//
//  Fix 5 (IMPORTANT): the preview screen must be called with
//  `regularAccounts`, never `accounts` (which also holds deposit/loan
//  accounts) — assigning a plain transaction to one of those would move its
//  derived balance directly, bypassing DepositInterestService and
//  LoanPaymentService's leg accounting. This function itself is agnostic to
//  that distinction (it just filters by currency); the call-site contract is
//  documented on the function itself and verified informally by reading
//  ImportTransactionPreviewView.swift's `accountsViewModel.regularAccounts`
//  call sites (four, all switched from `.accounts`).
//

import Testing
import Foundation
@testable import Tenra

// Account's synthesized Equatable conformance is MainActor-isolated under
// this project's SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor default (see
// CLAUDE.md's testing notes), so any suite comparing Account values must be
// @MainActor to avoid a warning today and a hard error under Swift 6 mode.
@MainActor
struct ImportTransactionPreviewViewTests {

    private func transaction(currency: String, id: String = "tx-1") -> Transaction {
        Transaction(
            id: id,
            date: "2026-08-11",
            description: "Test",
            amount: 100,
            currency: currency,
            type: .expense,
            category: "Food"
        )
    }

    private func account(currency: String, id: String = UUID().uuidString) -> Account {
        Account(id: id, name: "Account \(id)", currency: currency)
    }

    @Test("an account matching the transaction's currency is returned")
    func matchingCurrencyAccountReturned() {
        let kztAccount = account(currency: "KZT")
        let usdAccount = account(currency: "USD")
        let result = ImportTransactionPreviewView.availableAccounts(
            for: transaction(currency: "USD"),
            regularAccounts: [kztAccount, usdAccount]
        )
        #expect(result == [usdAccount])
    }

    @Test("no account in the transaction's currency yields an empty result")
    func noMatchingCurrencyYieldsEmpty() {
        // This is the exact trigger for Fix 4: a foreign-currency statement
        // (or any user without an account in that currency) must resolve to
        // an empty list, which the view now uses to disable the row instead
        // of silently allowing a nil-accountId save.
        let kztAccount = account(currency: "KZT")
        let result = ImportTransactionPreviewView.availableAccounts(
            for: transaction(currency: "EUR"),
            regularAccounts: [kztAccount]
        )
        #expect(result.isEmpty)
    }

    @Test("multiple accounts in the same currency are all returned")
    func multipleMatchingAccountsAllReturned() {
        let first = account(currency: "KZT", id: "acc-1")
        let second = account(currency: "KZT", id: "acc-2")
        let other = account(currency: "USD", id: "acc-3")
        let result = ImportTransactionPreviewView.availableAccounts(
            for: transaction(currency: "KZT"),
            regularAccounts: [first, second, other]
        )
        #expect(Set(result.map(\.id)) == Set([first.id, second.id]))
    }

    @Test("an empty regularAccounts list yields an empty result regardless of currency")
    func emptyRegularAccountsYieldsEmpty() {
        let result = ImportTransactionPreviewView.availableAccounts(
            for: transaction(currency: "KZT"),
            regularAccounts: []
        )
        #expect(result.isEmpty)
    }
}
