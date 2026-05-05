//
//  ChartSelectionBanner.swift
//  Tenra
//
//  Reusable selection banner shown above a chart when the user taps a data
//  point. Two content modes:
//
//  - `.dual(income:expenses:)`   — green dot + income, red dot + expenses
//  - `.single(value:color:)`     — one tinted amount (no dot)
//
//  The title is always rendered with its first character capitalised
//  (Russian `MMMM` formatters return lowercase month names which look wrong
//  in a banner header).
//

import SwiftUI

struct ChartSelectionBanner: View {

    enum Content {
        case dual(income: Double, expenses: Double)
        case single(value: Double, color: Color)
    }

    let title: String
    let currency: String
    let content: Content

    private var capitalizedTitle: String {
        guard let first = title.first else { return title }
        return first.uppercased() + title.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(capitalizedTitle)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)

            amounts
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var amounts: some View {
        switch content {
        case .dual(let income, let expenses):
            HStack(spacing: AppSpacing.md) {
                amountRow(amount: income, color: AppColors.success)
                amountRow(amount: expenses, color: AppColors.destructive)
            }
        case .single(let value, let color):
            amountRow(amount: value, color: color, withDot: false)
        }
    }

    @ViewBuilder
    private func amountRow(amount: Double, color: Color, withDot: Bool = true) -> some View {
        HStack(spacing: AppSpacing.xs) {
            if withDot {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            if currency.isEmpty {
                Text(ChartAxisHelpers.formatCompact(amount))
                    .font(AppTypography.body)
                    .foregroundStyle(color)
            } else {
                FormattedAmountText(
                    amount: amount,
                    currency: currency,
                    fontSize: AppTypography.body,
                    fontWeight: .regular,
                    color: color
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
        }
    }
}

#Preview("Dual") {
    ChartSelectionBanner(
        title: "январь 2025",
        currency: "KZT",
        content: .dual(income: 480_000, expenses: 275_000)
    )
    .padding()
}

#Preview("Single") {
    ChartSelectionBanner(
        title: "январь 2025",
        currency: "KZT",
        content: .single(value: 205_000, color: AppColors.success)
    )
    .padding()
}
