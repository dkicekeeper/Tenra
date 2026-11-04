//
//  TransactionMerchantRow.swift
//  Tenra
//
//  "Merchant" in the transaction forms (TransactionEditView, TransactionAddModal) for an expense
//  or income: the merchant the payment counts towards, which opens MerchantPickerView. A payment
//  entered by hand gets one without a description (the owner's request, 2026-10-31); the
//  description stays the person's own text. The row shows the link the form holds, else the
//  merchant the description names (`TransactionMerchant`); the form saves the link.
//

import SwiftUI

struct TransactionMerchantRow: View {
    /// The merchant the form links the payment to; nil: none (the description's, if any).
    @Binding var linkedMerchant: String?
    /// The form's description as typed.
    let description: String

    var body: some View {
        let shown = linkedMerchant ?? TransactionMerchant.describedMerchant(description)
        FormSection {
            UniversalRow(
                String(localized: "transaction.merchant"),
                icon: "storefront",
                value: shown.map(TransactionMerchant.title(of:)) ?? String(localized: "transaction.merchant.none"),
                accessory: .navigation {
                    MerchantPickerView(current: shown, canClear: linkedMerchant != nil) { picked in
                        linkedMerchant = picked.flatMap { TransactionMerchant.link(for: $0, description: description) }
                    }
                }
            )
            .accessibilityIdentifier("transactionForm.merchant")
        }
        .screenPadding()
    }
}
