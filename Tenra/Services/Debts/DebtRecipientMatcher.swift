//
//  DebtRecipientMatcher.swift
//  Tenra
//
//  The personal debt a payment repays (docs/plan-auto-capture.md §6): a bank receipt names the
//  person the money went to, and when the person owes that someone (an open "I owe" debt),
//  the receipt screen offers to record the payment as its repayment.
//
//  Names are compared word by word on letters only (CategorySuggestionService.normalizedMerchant):
//  the first word must be the same, and when both names carry a second one, its first letter
//  too: "Иван И." repays "Иван Иванов", never "Иван Петров". Exactly one such debt or none:
//  a guess between two people is no offer.
//

import Foundation

nonisolated enum DebtRecipientMatcher {

    static func debt(repaidTo recipient: String, in debts: [PersonalDebt]) -> PersonalDebt? {
        let recipientWords = words(recipient)
        guard let first = recipientWords.first,
              first.count >= CategorySuggestionService.minimumMerchantLength else { return nil }
        let matches = debts.filter { debt in
            guard debt.direction == .iOwe, !debt.isSettled else { return false }
            let personWords = words(debt.person)
            guard personWords.first == first else { return false }
            guard recipientWords.count > 1, personWords.count > 1 else { return true }
            return recipientWords[1].first == personWords[1].first
        }
        return matches.count == 1 ? matches.first : nil
    }

    private static func words(_ name: String) -> [String] {
        CategorySuggestionService.normalizedMerchant(name)
            .split(separator: " ")
            .map(String.init)
    }
}
