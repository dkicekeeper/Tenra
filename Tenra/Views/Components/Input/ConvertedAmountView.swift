//
//  ConvertedAmountView.swift
//  Tenra
//
//  Displays a converted amount in a target currency, loading asynchronously.
//

import SwiftUI

/// Shows a currency-converted amount using CurrencyConverter.
/// Renders nothing while loading or if conversion fails.
struct ConvertedAmountView: View {
    let amount: Double
    let fromCurrency: String
    let toCurrency: String
    let fontSize: Font
    let color: Color

    @State private var convertedAmount: Double?

    var body: some View {
        Group {
            if let converted = convertedAmount, converted > 0 {
                FormattedAmountText(
                    amount: converted,
                    currency: toCurrency,
                    fontSize: fontSize,
                    color: color
                )
            }
        }
        .task(id: "\(amount)-\(fromCurrency)-\(toCurrency)") {
            convertedAmount = await CurrencyConverter.convert(
                amount: amount,
                from: fromCurrency,
                to: toCurrency
            )
        }
    }
}
