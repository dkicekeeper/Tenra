//
//  WalletPaymentResolverTests.swift
//  TenraTests
//
//  Pins the decisions LogWalletPaymentIntent makes without asking: the currency
//  code it trusts, the account a card payment goes to, the category, and which
//  of them is a guess for the To review list.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct WalletPaymentResolverTests {

    // MARK: - Fixtures

    private func account(_ id: String, loan: Bool = false, deposit: Bool = false) -> Account {
        Account(
            id: id,
            name: id,
            currency: "KZT",
            depositInfo: deposit ? depositInfo() : nil,
            loanInfo: loan ? loanInfo() : nil,
            balance: 0
        )
    }

    private func depositInfo() -> DepositInfo {
        DepositInfo(
            bankName: "T",
            initialPrincipal: 1_000_000,
            capitalizationEnabled: false,
            interestRateAnnual: 0,
            interestRateHistory: [RateChange(effectiveFrom: "2026-01-01", annualRate: 0)],
            interestPostingDay: 1,
            lastInterestCalculationDate: "2026-01-01",
            lastInterestPostingMonth: "2026-01-01",
            interestAccruedForCurrentPeriod: 0,
            startDate: "2026-01-01"
        )
    }

    private func loanInfo() -> LoanInfo {
        LoanInfo(
            bankName: "B",
            loanType: .annuity,
            originalPrincipal: 1_000_000,
            remainingPrincipal: 800_000,
            interestRateAnnual: 12,
            termMonths: 12,
            startDate: "2026-01-01",
            paymentDay: 1
        )
    }

    private let groceries = CustomCategory(id: "cat-groceries", name: "Продукты", colorHex: "#00AA00", type: .expense)
    private let salary = CustomCategory(id: "cat-salary", name: "Зарплата", colorHex: "#0000AA", type: .income)
    private var other: CustomCategory {
        CustomCategory(id: "cat-other", name: String(localized: "category.other"), colorHex: "#888888", type: .expense)
    }

    private func chosen(_ id: String) -> WalletPaymentResolver.AccountChoice {
        WalletPaymentResolver.AccountChoice(accountId: id, isGuess: false)
    }

    private func guessed(_ id: String) -> WalletPaymentResolver.AccountChoice {
        WalletPaymentResolver.AccountChoice(accountId: id, isGuess: true)
    }

    // MARK: - Currency code

    @Test("A three-letter code is trimmed and uppercased")
    func currencyCodeNormalized() {
        #expect(WalletPaymentResolver.currencyCode(" usd ") == "USD")
        #expect(WalletPaymentResolver.currencyCode("KZT") == "KZT")
    }

    @Test("Anything but three Latin letters reads as not passed")
    func currencyCodeRejected() {
        #expect(WalletPaymentResolver.currencyCode(nil) == nil)
        #expect(WalletPaymentResolver.currencyCode("") == nil)
        #expect(WalletPaymentResolver.currencyCode("US") == nil)
        #expect(WalletPaymentResolver.currencyCode("12A") == nil)
        #expect(WalletPaymentResolver.currencyCode("₸") == nil)
        #expect(WalletPaymentResolver.currencyCode("ДОЛ") == nil)
    }

    // MARK: - Account

    @Test("The account fixed in the automation wins over the card's")
    func fixedAccountWins() {
        let choice = WalletPaymentResolver.account(
            fixedId: "a2",
            cardAccountId: "a1",
            accounts: [account("a1"), account("a2")],
            suggested: { "a1" }
        )
        #expect(choice == chosen("a2"))
    }

    @Test("The card's remembered account is not a guess")
    func cardAccount() {
        let choice = WalletPaymentResolver.account(
            fixedId: nil,
            cardAccountId: "a2",
            accounts: [account("a1"), account("a2")],
            suggested: { "a1" }
        )
        #expect(choice == chosen("a2"))
    }

    @Test("A fixed or remembered account that cannot take a card payment is skipped")
    func ineligibleRememberedAccountsSkipped() {
        let choice = WalletPaymentResolver.account(
            fixedId: "loan",
            cardAccountId: "deleted",
            accounts: [account("loan", loan: true), account("a1"), account("a2")],
            suggested: { "a2" }
        )
        #expect(choice == guessed("a2"))
    }

    @Test("The only account a card can pay from is not a guess")
    func singleEligibleAccount() {
        let choice = WalletPaymentResolver.account(
            fixedId: nil,
            cardAccountId: nil,
            accounts: [account("deposit", deposit: true), account("a1"), account("loan", loan: true)],
            suggested: { nil }
        )
        #expect(choice == chosen("a1"))
    }

    @Test("With several accounts the ranking suggestion is a guess")
    func suggestedAccountIsGuess() {
        let choice = WalletPaymentResolver.account(
            fixedId: nil,
            cardAccountId: nil,
            accounts: [account("a1"), account("a2")],
            suggested: { "a2" }
        )
        #expect(choice == guessed("a2"))
    }

    @Test("A suggestion that cannot take a card payment falls back to the first account")
    func ineligibleSuggestionFallsBack() {
        let choice = WalletPaymentResolver.account(
            fixedId: nil,
            cardAccountId: nil,
            accounts: [account("deposit", deposit: true), account("a1"), account("a2")],
            suggested: { "deposit" }
        )
        #expect(choice == guessed("a1"))
    }

    @Test("No account a card can pay from")
    func noEligibleAccount() {
        let choice = WalletPaymentResolver.account(
            fixedId: nil,
            cardAccountId: nil,
            accounts: [account("loan", loan: true), account("deposit", deposit: true)],
            suggested: { nil }
        )
        #expect(choice == nil)
    }

    // MARK: - Category

    @Test("The merchant's remembered category and subcategories are not a guess")
    func rememberedCategory() {
        let choice = WalletPaymentResolver.category(
            remembered: groceries,
            rememberedSubcategoryIds: ["sub-1"],
            suggestion: "Кафе",
            categories: [groceries, other]
        )
        #expect(choice == WalletPaymentResolver.CategoryChoice(name: "Продукты", subcategoryIds: ["sub-1"], isGuess: false))
    }

    @Test("A suggestion is a guess, without subcategories")
    func suggestedCategory() {
        let choice = WalletPaymentResolver.category(
            remembered: nil,
            rememberedSubcategoryIds: nil,
            suggestion: "Продукты",
            categories: [groceries, other]
        )
        #expect(choice == WalletPaymentResolver.CategoryChoice(name: "Продукты", subcategoryIds: nil, isGuess: true))
    }

    @Test("A suggestion that is not one of the expense categories falls back to Other")
    func unknownSuggestionFallsBack() {
        let choice = WalletPaymentResolver.category(
            remembered: nil,
            rememberedSubcategoryIds: nil,
            suggestion: "Зарплата",
            categories: [groceries, salary, other]
        )
        #expect(choice == WalletPaymentResolver.CategoryChoice(name: other.name, subcategoryIds: nil, isGuess: true))
    }

    @Test("Without Other the payment stays uncategorized")
    func uncategorizedWithoutOther() {
        let choice = WalletPaymentResolver.category(
            remembered: nil,
            rememberedSubcategoryIds: nil,
            suggestion: nil,
            categories: [groceries]
        )
        #expect(choice == WalletPaymentResolver.CategoryChoice(name: "", subcategoryIds: nil, isGuess: true))
    }
    // MARK: - Subscription charges

    private func occurrence(
        _ id: String,
        _ description: String,
        amount: Double = 4_990,
        currency: String = "KZT",
        date: String,
        seriesId: String? = "series-1"
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            type: .expense,
            category: "Подписки",
            accountId: "a1",
            recurringSeriesId: seriesId
        )
    }

    private func day(_ key: String) -> Int {
        ImportDuplicateDetector.dayNumber(key) ?? 0
    }

    @Test("A payment repeats the subscription charge whose description shares a brand word")
    func matchesSubscriptionCharge() {
        let match = WalletPaymentResolver.subscriptionOccurrence(
            amount: 4_990,
            currency: "KZT",
            day: day("2026-10-19"),
            merchant: "NETFLIX.COM",
            occurrences: [occurrence("tx-1", "Netflix", date: "2026-10-18")]
        )
        #expect(match?.id == "tx-1")
    }

    @Test("A service billed under its parent's name matches: iCloud+ and APPLE.COM/BILL")
    func matchesBillingParent() {
        let apple = WalletPaymentResolver.subscriptionOccurrence(
            amount: 450,
            currency: "KZT",
            day: day("2026-10-19"),
            merchant: "APPLE.COM/BILL",
            occurrences: [occurrence("tx-icloud", "iCloud+", amount: 450, date: "2026-10-19")]
        )
        #expect(apple?.id == "tx-icloud")

        let google = WalletPaymentResolver.subscriptionOccurrence(
            amount: 2_990,
            currency: "KZT",
            day: day("2026-10-19"),
            merchant: "GOOGLE *SERVICES",
            occurrences: [occurrence("tx-youtube", "YouTube Premium", amount: 2_990, date: "2026-10-18")]
        )
        #expect(google?.id == "tx-youtube")
    }

    @Test("The billing company does not match the other way round: an Apple charge is not any subscription")
    func billingParentOneWay() {
        let match = WalletPaymentResolver.subscriptionOccurrence(
            amount: 450,
            currency: "KZT",
            day: day("2026-10-19"),
            merchant: "ICLOUD STORAGE",
            occurrences: [occurrence("tx-music", "Apple Music", amount: 450, date: "2026-10-19")]
        )
        #expect(match == nil)
    }

    @Test("Same amount and date but another merchant is a new payment")
    func otherMerchantIsNotTheSubscription() {
        let match = WalletPaymentResolver.subscriptionOccurrence(
            amount: 4_990,
            currency: "KZT",
            day: day("2026-10-19"),
            merchant: "COFFEE BOOM 12",
            occurrences: [occurrence("tx-1", "Netflix", date: "2026-10-19")]
        )
        #expect(match == nil)
    }

    @Test("Generic words like com or bill alone do not match")
    func genericWordsDoNotMatch() {
        #expect(WalletPaymentResolver.brandWords("APPLE.COM/BILL") == ["apple"])
        let match = WalletPaymentResolver.subscriptionOccurrence(
            amount: 4_990,
            currency: "KZT",
            day: day("2026-10-19"),
            merchant: "SHOP.COM BILL",
            occurrences: [occurrence("tx-1", "Music com bill", date: "2026-10-19")]
        )
        #expect(match == nil)
    }

    @Test("Outside three days, five percent, the currency or a series, nothing matches")
    func outsideTheWindow() {
        let payment = (amount: 4_990.0, currency: "KZT", day: day("2026-10-19"), merchant: "NETFLIX.COM")
        let candidates = [
            occurrence("far", "Netflix", date: "2026-10-23"),
            occurrence("dearer", "Netflix", amount: 5_300, date: "2026-10-19"),
            occurrence("usd", "Netflix", currency: "USD", date: "2026-10-19"),
            occurrence("one-off", "Netflix", date: "2026-10-19", seriesId: nil)
        ]
        let match = WalletPaymentResolver.subscriptionOccurrence(
            amount: payment.amount,
            currency: payment.currency,
            day: payment.day,
            merchant: payment.merchant,
            occurrences: candidates
        )
        #expect(match == nil)
    }

    @Test("The closest charge wins")
    func closestChargeWins() {
        let match = WalletPaymentResolver.subscriptionOccurrence(
            amount: 4_990,
            currency: "KZT",
            day: day("2026-10-19"),
            merchant: "NETFLIX.COM",
            occurrences: [
                occurrence("tx-early", "Netflix", date: "2026-10-16"),
                occurrence("tx-close", "Netflix", amount: 5_100, date: "2026-10-20")
            ]
        )
        #expect(match?.id == "tx-close")
    }
}
