//
//  WalletPaymentResolver.swift
//  Tenra
//
//  The decisions LogWalletPaymentIntent makes without asking: which account and
//  which category an Apple Pay payment goes to, and which of them is a guess for
//  the To review list (WalletCaptureStore). Pure: the stores, the history fetch
//  and the account ranking are passed in, so every rule is testable.
//
//  The owner's decision of 2026-10-19 (docs/plan-auto-capture.md §3): a payment is
//  saved at once, never stopped by a question. What Tenra could not know is a
//  guess the user confirms or fixes later.
//

import Foundation

@MainActor
enum WalletPaymentResolver {

    /// The currency code as the automation passed it: "usd " → "USD". Anything but
    /// three letters reads as "not passed", and the account's currency applies.
    nonisolated static func currencyCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return nil
        }
        return code
    }

    struct AccountChoice: Equatable {
        let accountId: String
        let isGuess: Bool
    }

    /// The account a payment goes to, strongest signal first: fixed in the
    /// automation, remembered for the card, the only account a card can pay from,
    /// then the history ranking for the category, then the first account. The last
    /// two are guesses. Loans and deposits never take a card payment.
    /// nil when there is no account to pay from.
    static func account(
        fixedId: String?,
        cardAccountId: String?,
        accounts: [Account],
        suggested: () -> String?
    ) -> AccountChoice? {
        let eligible = accounts.filter { !$0.isLoan && !$0.isDeposit }
        guard let first = eligible.first else { return nil }

        for id in [fixedId, cardAccountId].compactMap({ $0 }) where eligible.contains(where: { $0.id == id }) {
            return AccountChoice(accountId: id, isGuess: false)
        }
        if eligible.count == 1 {
            return AccountChoice(accountId: first.id, isGuess: false)
        }
        if let id = suggested(), eligible.contains(where: { $0.id == id }) {
            return AccountChoice(accountId: id, isGuess: true)
        }
        return AccountChoice(accountId: first.id, isGuess: true)
    }

    // MARK: - Subscription charges

    /// Merchant words that name no one: domains, legal forms, billing labels.
    private nonisolated static let genericMerchantWords: Set<String> = [
        "com", "net", "org", "www", "app", "apps", "bill", "billing", "pay", "payment",
        "inc", "ltd", "llc", "llp", "gmbh", "too", "тоо", "ип", "the", "kz", "ru"
    ]

    /// Services billed under their parent's name: an iCloud+ subscription is charged as
    /// "APPLE.COM/BILL", YouTube Premium as "GOOGLE *YouTube".
    private nonisolated static let billingParent: [String: String] = [
        "icloud": "apple", "itunes": "apple",
        "youtube": "google"
    ]

    /// The words of a merchant or description that can identify a brand.
    nonisolated static func brandWords(_ text: String) -> Set<String> {
        Set(
            CategorySuggestionService.normalizedMerchant(text)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= CategorySuggestionService.minimumMerchantLength && !genericMerchantWords.contains($0) }
        )
    }

    /// A subscription's brand words plus the company that bills it ("iCloud+" → icloud, apple).
    nonisolated static func billedWords(_ description: String) -> Set<String> {
        let words = brandWords(description)
        return words.union(words.compactMap { billingParent[$0] })
    }

    /// The subscription charge a payment repeats: an occurrence of a recurring series in
    /// the same currency, within the statement import's window and tolerance
    /// (`ImportDuplicateDetector.subscriptionDayWindow`, `subscriptionAmountTolerance`), whose
    /// description shares a brand word with the merchant ("Netflix" and "NETFLIX.COM", or
    /// the billing company: "iCloud+" and "APPLE.COM/BILL"),
    /// closest date first. The word is required: a missed match leaves a duplicate the user
    /// can delete, a false one would drop a real payment (a coffee priced like a
    /// subscription).
    nonisolated static func subscriptionOccurrence(
        amount: Double,
        currency: String,
        day: Int,
        merchant: String,
        occurrences: [Transaction]
    ) -> Transaction? {
        let merchantWords = brandWords(merchant)
        guard !merchantWords.isEmpty else { return nil }
        return occurrences
            .compactMap { occurrence -> (Transaction, Int)? in
                guard occurrence.recurringSeriesId?.isEmpty == false,
                      occurrence.type == .expense,
                      occurrence.currency == currency,
                      abs(occurrence.amount - amount) <= ImportDuplicateDetector.subscriptionAmountTolerance * amount,
                      let occurrenceDay = ImportDuplicateDetector.dayNumber(occurrence.date),
                      abs(occurrenceDay - day) <= ImportDuplicateDetector.subscriptionDayWindow,
                      !billedWords(occurrence.description).isDisjoint(with: merchantWords)
                else { return nil }
                return (occurrence, abs(occurrenceDay - day))
            }
            .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }?
            .0
    }

    // MARK: - Category

    struct CategoryChoice: Equatable {
        /// "" means uncategorized, which the store accepts.
        let name: String
        /// The remembered subcategory decision (see MerchantCategoryMemory.Entry);
        /// nil when there is none.
        let subcategoryIds: [String]?
        let isGuess: Bool
    }

    /// The category a payment goes to: the one the user chose for this merchant
    /// before, else a suggestion (history, brands, keywords; already resolved to one
    /// of the user's categories), else "Other". Only the first is not a guess. `type`
    /// is income for money in from a bank's notification.
    static func category(
        remembered: CustomCategory?,
        rememberedSubcategoryIds: [String]?,
        suggestion: String?,
        categories: [CustomCategory],
        type: TransactionType = .expense
    ) -> CategoryChoice {
        if let remembered {
            return CategoryChoice(name: remembered.name, subcategoryIds: rememberedSubcategoryIds, isGuess: false)
        }
        if let suggestion, categories.contains(where: { $0.type == type && $0.name == suggestion }) {
            return CategoryChoice(name: suggestion, subcategoryIds: nil, isGuess: true)
        }
        let fallback = TransactionDraftService.resolveCategory(named: nil, type: type, in: categories)
        return CategoryChoice(name: fallback.name, subcategoryIds: nil, isGuess: true)
    }
}
