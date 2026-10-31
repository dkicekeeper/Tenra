//
//  TransactionMerchant.swift
//  Tenra
//
//  The merchant an expense or income counts towards, for the "Merchant" row of the transaction
//  forms (TransactionEditView, TransactionAddModal) and the storefront button of the edit form
//  (the owner's request, 2026-10-31: a payment entered by hand had a merchant only through its
//  description). Two sources, in this order:
//
//  - a link made by hand (`MerchantGroupStore.link`, the form's row or the merchant screen's
//    "Link payments"): it counts there whatever its description says;
//  - its description, when it names a merchant worth a screen: remembered by the Wallet
//    automation, with a logo or a name the person gave it, or a point of a brand. A note
//    ("lunch with Ann") or a transfer to a person is none.
//
//  The description stays the person's text: picking a merchant never rewrites it.
//

import Foundation

@MainActor
enum TransactionMerchant {

    /// The merchant `transaction` counts towards, as the bank wrote it (or as typed); nil for none.
    static func merchant(of transaction: Transaction) -> String? {
        if let linked = MerchantGroupStore.shared.linkedMerchant(forTransactionId: transaction.id) {
            return linked
        }
        return describedMerchant(transaction.description)
    }

    /// The merchant a description names, when it is one worth a screen; nil otherwise.
    static func describedMerchant(_ description: String) -> String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let logos = MerchantLogoStore.shared
        let isMerchant = MerchantCategoryMemory.shared.merchant(forDescription: trimmed) != nil
            || logos.iconSource(forDescription: trimmed) != nil
            || logos.customName(forDescription: trimmed) != nil
            || MerchantGroupStore.shared.group(forMerchant: trimmed) != nil
        return isMerchant ? trimmed : nil
    }

    /// The name a merchant is shown under: the person's, else the bank's text cleaned.
    static func title(of merchant: String) -> String {
        MerchantLogoStore.shared.customName(forDescription: merchant) ?? MerchantName.displayName(merchant)
    }

    /// Whether two texts name the same merchant (the merchant memory's key).
    static func isSame(_ a: String, _ b: String) -> Bool {
        let key = CategorySuggestionService.normalizedMerchant(a)
        return !key.isEmpty && key == CategorySuggestionService.normalizedMerchant(b)
    }

    /// The form's choice for `description`: nil when it is the merchant the description already
    /// names (the row shows it without a link), else the merchant to link.
    static func link(for merchant: String, description: String) -> String? {
        let named = describedMerchant(description).map { isSame($0, merchant) } ?? false
        return named ? nil : merchant
    }

    /// Saves a link the form changed for saved operations: links them to `merchant`, or removes
    /// their links for nil.
    static func setLink(_ merchant: String?, for transactionIds: [String]) {
        let store = MerchantGroupStore.shared
        if let merchant {
            store.link(transactionIds: transactionIds, toMerchant: merchant)
        } else {
            for id in transactionIds where store.linkedMerchant(forTransactionId: id) != nil {
                store.unlink(transactionId: id)
            }
        }
    }
}
