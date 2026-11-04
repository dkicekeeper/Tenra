//
//  TransactionMerchantTests.swift
//  TenraTests
//
//  Pins the transaction form's merchant (TransactionMerchantRow): which merchant a payment
//  counts towards, when the form's choice becomes a link, and that the link is saved and
//  removed on `MerchantGroupStore.shared` (process-global, hence `.sharedProcessState`).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct TransactionMerchantTests {

    private func tx(_ id: String, _ description: String) -> Transaction {
        Transaction(id: id, date: "2026-10-30", description: description, amount: 2_500, currency: "KZT",
                    type: .expense, category: "Транспорт", accountId: "a1")
    }

    @Test("Texts name the same merchant by the memory's key")
    func sameMerchant() {
        #expect(TransactionMerchant.isSame("YANDEX.GO", "Yandex Go"))
        #expect(!TransactionMerchant.isSame("YANDEX.GO", "Uber"))
        #expect(!TransactionMerchant.isSame("", ""))
    }

    @Test("A note is not a merchant: the form links the payment to the one picked")
    func noteIsNotAMerchant() {
        let note = "поездка в аэропорт zq\(UUID().uuidString.prefix(4))"
        #expect(TransactionMerchant.describedMerchant(note) == nil)
        #expect(TransactionMerchant.describedMerchant("   ") == nil)
        #expect(TransactionMerchant.link(for: "YANDEX.GO", description: note) == "YANDEX.GO")
        #expect(TransactionMerchant.link(for: "YANDEX.GO", description: "") == "YANDEX.GO")
    }

    @Test("A link is saved and removed, and the payment counts towards its merchant")
    func linkAndUnlink() {
        let id = "merchant-test-\(UUID().uuidString)"
        let payment = tx(id, "")
        defer { MerchantGroupStore.shared.unlink(transactionId: id) }

        #expect(TransactionMerchant.merchant(of: payment) == nil)

        TransactionMerchant.setLink("YANDEX.GO", for: [id])
        #expect(MerchantGroupStore.shared.linkedMerchant(forTransactionId: id) == "YANDEX.GO")
        #expect(TransactionMerchant.merchant(of: payment) == "YANDEX.GO")

        TransactionMerchant.setLink(nil, for: [id])
        #expect(MerchantGroupStore.shared.linkedMerchant(forTransactionId: id) == nil)
        #expect(TransactionMerchant.merchant(of: payment) == nil)
    }
}
