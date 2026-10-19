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
    /// of the user's categories), else "Other". Only the first is not a guess.
    static func category(
        remembered: CustomCategory?,
        rememberedSubcategoryIds: [String]?,
        suggestion: String?,
        categories: [CustomCategory]
    ) -> CategoryChoice {
        if let remembered {
            return CategoryChoice(name: remembered.name, subcategoryIds: rememberedSubcategoryIds, isGuess: false)
        }
        if let suggestion, categories.contains(where: { $0.type == .expense && $0.name == suggestion }) {
            return CategoryChoice(name: suggestion, subcategoryIds: nil, isGuess: true)
        }
        let fallback = TransactionDraftService.resolveCategory(named: nil, type: .expense, in: categories)
        return CategoryChoice(name: fallback.name, subcategoryIds: nil, isGuess: true)
    }
}
