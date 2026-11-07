//
//  SubscriptionChargeMatcherTests.swift
//  TenraTests
//
//  The planned charge of a subscription that a real one stands for (an Apple Pay payment, a
//  bank's notification), and the occurrence once the real charge is merged into it.
//  docs/domains/recurring.md §Real charges.
//

import Testing
import Foundation
@testable import Tenra

@Suite("SubscriptionChargeMatcher")
struct SubscriptionChargeMatcherTests {

    private func occurrence(
        _ id: String,
        _ description: String,
        amount: Double = 4_990,
        currency: String = "KZT",
        convertedAmount: Double? = nil,
        date: String,
        seriesId: String? = "series-1",
        accountId: String = "a1"
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmount,
            type: .expense,
            category: "Подписки",
            accountId: accountId,
            recurringSeriesId: seriesId,
            recurringOccurrenceId: seriesId == nil ? nil : "occ-\(id)"
        )
    }

    private func day(_ key: String) -> Int {
        ImportDuplicateDetector.dayNumber(key) ?? 0
    }

    private func charge(
        _ amount: Double = 4_990,
        _ currency: String = "KZT",
        on date: String = "2026-10-19",
        merchant: String
    ) -> SubscriptionChargeMatcher.Charge {
        SubscriptionChargeMatcher.Charge(amount: amount, currency: currency, day: day(date), merchant: merchant)
    }

    private func match(
        _ charge: SubscriptionChargeMatcher.Charge,
        _ occurrences: [Transaction],
        remembered: String? = nil,
        dismissed: Set<String> = [],
        suggests: Bool = true,
        accountCurrency: String? = "KZT",
        rate: Double? = nil
    ) -> SubscriptionChargeMatcher.Match? {
        SubscriptionChargeMatcher.match(
            charge,
            occurrences: occurrences,
            rememberedSeriesId: remembered,
            dismissedSeriesIds: dismissed,
            suggests: suggests,
            accountCurrency: { _ in accountCurrency },
            convert: { amount, _, _ in rate.map { amount * $0 } }
        )
    }

    // MARK: - A shared brand word (as before)

    @Test("A payment is the subscription charge whose description shares a brand word")
    func matchesSubscriptionCharge() {
        let result = match(charge(merchant: "NETFLIX.COM"), [occurrence("tx-1", "Netflix", date: "2026-10-18")])
        #expect(result?.occurrence.id == "tx-1")
        #expect(result?.isConfident == true)
    }

    @Test("A service billed under its parent's name matches: iCloud+ and APPLE.COM/BILL")
    func matchesBillingParent() {
        let apple = match(
            charge(450, merchant: "APPLE.COM/BILL"),
            [occurrence("tx-icloud", "iCloud+", amount: 450, date: "2026-10-19")]
        )
        #expect(apple?.occurrence.id == "tx-icloud")
        #expect(apple?.isConfident == true)

        let google = match(
            charge(2_990, merchant: "GOOGLE *SERVICES"),
            [occurrence("tx-youtube", "YouTube Premium", amount: 2_990, date: "2026-10-18")]
        )
        #expect(google?.occurrence.id == "tx-youtube")
    }

    @Test("The billing company does not match the other way round: an iCloud charge is not Apple Music")
    func billingParentOneWay() {
        let result = match(
            charge(450, merchant: "ICLOUD STORAGE"),
            [occurrence("tx-music", "Apple Music", amount: 450, date: "2026-10-19")],
            suggests: false
        )
        #expect(result == nil)
    }

    @Test("Generic words like com or bill alone do not match")
    func genericWordsDoNotMatch() {
        #expect(WalletPaymentResolver.brandWords("APPLE.COM/BILL") == ["apple"])
        let result = match(
            charge(merchant: "SHOP.COM BILL"),
            [occurrence("tx-1", "Music com bill", date: "2026-10-19")],
            suggests: false
        )
        #expect(result == nil)
    }

    @Test("Outside three days, five percent, a known currency or a series, nothing matches")
    func outsideTheWindow() {
        let candidates = [
            occurrence("far", "Netflix", date: "2026-10-23"),
            occurrence("dearer", "Netflix", amount: 5_300, date: "2026-10-19"),
            occurrence("usd", "Netflix", currency: "USD", date: "2026-10-19"),
            occurrence("one-off", "Netflix", date: "2026-10-19", seriesId: nil)
        ]
        #expect(match(charge(merchant: "NETFLIX.COM"), candidates, accountCurrency: "USD") == nil)
    }

    @Test("The closest charge wins")
    func closestChargeWins() {
        let result = match(
            charge(merchant: "NETFLIX.COM"),
            [
                occurrence("tx-early", "Netflix", date: "2026-10-16"),
                occurrence("tx-close", "Netflix", amount: 5_100, date: "2026-10-20")
            ]
        )
        #expect(result?.occurrence.id == "tx-close")
    }

    @Test("Two subscriptions of one brand and price: the one on the payment's account")
    func paymentAccountFirst() {
        let candidates = [
            occurrence("music", "Apple Music", amount: 450, date: "2026-10-19", seriesId: "music", accountId: "kaspi"),
            occurrence("icloud", "iCloud+", amount: 450, date: "2026-10-20", seriesId: "icloud", accountId: "freedom")
        ]
        let onFreedom = SubscriptionChargeMatcher.match(
            charge(450, merchant: "APPLE.COM/BILL"), occurrences: candidates,
            rememberedSeriesId: nil, dismissedSeriesIds: [], suggests: true, accountId: "freedom",
            accountCurrency: { _ in "KZT" }, convert: { _, _, _ in nil }
        )
        #expect(onFreedom?.occurrence.id == "icloud")
        // An unknown account: the closest date.
        #expect(match(charge(450, merchant: "APPLE.COM/BILL"), candidates)?.occurrence.id == "music")
    }

    // MARK: - Another currency

    @Test("A dollar subscription charged in tenge matches the account-currency amount it was planned at")
    func tengeChargeOfADollarSubscription() {
        let planned = occurrence("tx-1", "ChatGPT Plus", amount: 20, currency: "USD", convertedAmount: 10_400, date: "2026-10-19")
        let result = match(charge(10_650, "KZT", merchant: "OPENAI *CHATGPT SUBSCR"), [planned])
        #expect(result?.occurrence.id == "tx-1")
        #expect(result?.isConfident == true)
    }

    @Test("Without a planned conversion the charge is converted at the cached rate, within ten percent")
    func convertedAtTheCachedRate() {
        let planned = occurrence("tx-1", "Spotify", amount: 5.99, currency: "USD", date: "2026-10-19")
        let near = match(charge(3_100, "KZT", merchant: "SPOTIFY P1234"), [planned], accountCurrency: "USD", rate: 1.0 / 520)
        #expect(near?.occurrence.id == "tx-1")
        let far = match(charge(3_600, "KZT", merchant: "SPOTIFY P1234"), [planned], accountCurrency: "USD", rate: 1.0 / 520)
        #expect(far == nil)
    }

    // MARK: - Remembered merchant

    @Test("A merchant linked to a subscription matches it without a shared word, within thirty percent")
    func rememberedMerchant() {
        let planned = occurrence("tx-1", "Яндекс Плюс", amount: 2_990, date: "2026-10-18", seriesId: "plus")
        let result = match(charge(3_490, merchant: "YANDEX*PLUS"), [planned], remembered: "plus")
        #expect(result?.occurrence.id == "tx-1")
        #expect(result?.isConfident == true)
    }

    @Test("A remembered merchant takes its own subscription over another one with a shared word")
    func rememberedWinsOverBrandWord() {
        let result = match(
            charge(2_990, merchant: "YANDEX GO"),
            [
                occurrence("go", "Yandex Go Pass", amount: 2_990, date: "2026-10-19", seriesId: "go-pass"),
                occurrence("plus", "Плюс", amount: 2_990, date: "2026-10-19", seriesId: "plus")
            ],
            remembered: "plus"
        )
        #expect(result?.occurrence.id == "plus")
    }

    // MARK: - Suggestion

    @Test("Same amount and date with no shared word is a suggestion, not a match")
    func suggestion() {
        let result = match(charge(merchant: "KAZAKHTELECOM AO"), [occurrence("tx-1", "Интернет", date: "2026-10-19")])
        #expect(result?.occurrence.id == "tx-1")
        #expect(result?.isConfident == false)
    }

    @Test("No suggestion for a dismissed subscription, a transfer or a merchant remembered elsewhere")
    func noSuggestion() {
        let planned = occurrence("tx-1", "Интернет", date: "2026-10-19", seriesId: "internet")
        #expect(match(charge(merchant: "KAZAKHTELECOM AO"), [planned], dismissed: ["internet"]) == nil)
        #expect(match(charge(merchant: "Иван П."), [planned], suggests: false) == nil)
        #expect(match(charge(merchant: "KAZAKHTELECOM AO"), [planned], remembered: "other") == nil)
        #expect(match(charge(merchant: ""), [planned]) == nil)
    }

    // MARK: - Merge

    @Test("The merged occurrence keeps its id, series, category and name and takes the charge's money, date and account")
    func merged() {
        let planned = Transaction(
            id: "occ", date: "2026-10-20", description: "Netflix", amount: 10, currency: "USD",
            convertedAmount: 5_200, type: .expense, category: "Подписки", accountId: "card",
            accountName: "Card", targetCurrency: "KZT", targetAmount: 5_200,
            recurringSeriesId: "netflix", recurringOccurrenceId: "o-1", createdAt: 100
        )
        let result = SubscriptionChargeMatcher.merged(
            planned, amount: 10, currency: "USD", convertedAmount: 5_310, targetCurrency: "KZT", targetAmount: 5_310,
            accountId: "gold", date: "2026-10-19"
        )
        #expect(result.id == "occ")
        #expect(result.recurringSeriesId == "netflix")
        #expect(result.recurringOccurrenceId == "o-1")
        #expect(result.category == "Подписки")
        #expect(result.description == "Netflix")
        #expect(result.amount == 10)
        #expect(result.convertedAmount == 5_310)
        #expect(result.targetAmount == 5_310, "the balance reads targetAmount first: never the planned one")
        #expect(result.accountId == "gold")
        #expect(result.accountName == nil)
        #expect(result.date == "2026-10-19")
        #expect(result.createdAt == 100)
    }

    // MARK: - Picked by hand

    @Test("A charge picked by hand takes the nearest planned charge within half the period, not one already taken")
    func plannedOccurrenceForAHandPick() {
        let picked = Transaction(
            id: "bank", date: "2026-10-26", description: "YANDEX*PLUS", amount: 2_990, currency: "KZT",
            type: .expense, category: "Other", accountId: "a1"
        )
        let siblings = [
            occurrence("sep", "Плюс", date: "2026-09-18"),
            occurrence("oct", "Плюс", date: "2026-10-18"),
            occurrence("taken", "Плюс", date: "2026-10-25"),
            occurrence("real", "Плюс", date: "2026-10-26", seriesId: "series-1"),
        ].map { $0.id == "real" ? Transaction(
            id: "real", date: $0.date, description: $0.description, amount: $0.amount, currency: $0.currency,
            type: .expense, category: $0.category, accountId: "a1", recurringSeriesId: "series-1"
        ) : $0 }
        let result = SubscriptionChargeMatcher.plannedOccurrence(
            for: picked, among: siblings, frequency: .monthly, isTaken: { $0 == "taken" }
        )
        #expect(result?.id == "oct")
        #expect(SubscriptionChargeMatcher.plannedOccurrence(
            for: picked, among: siblings, frequency: .weekly, isTaken: { $0 == "taken" }
        ) == nil)
    }
}
