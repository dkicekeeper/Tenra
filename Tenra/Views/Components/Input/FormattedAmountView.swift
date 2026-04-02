//
//  FormattedAmountView.swift
//  AIFinanceManager
//
//  Created on 2026-01-30
//  Formatted amount display with separate opacity for decimal part
//  REFACTORED 2026-02-11: Now delegates to FormattedAmountText for unified logic
//

import SwiftUI

/// Обертка для обратной совместимости - делегирует в FormattedAmountText
struct FormattedAmountView: View {
    let amount: Double
    let currency: String
    let prefix: String
    let color: Color

    var body: some View {
        FormattedAmountText(
            amount: amount,
            currency: currency,
            prefix: prefix,
            fontSize: AppTypography.body,
            fontWeight: .semibold,
            color: color
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        FormattedAmountView(amount: 1000.00, currency: "KZT", prefix: "+", color: .green)
        FormattedAmountView(amount: 1234.56, currency: "USD", prefix: "-", color: .primary)
        FormattedAmountView(amount: 500.50, currency: "EUR", prefix: "", color: .blue)
    }
    .padding()
}
