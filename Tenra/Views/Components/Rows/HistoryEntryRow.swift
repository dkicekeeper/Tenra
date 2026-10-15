//
//  HistoryEntryRow.swift
//  Tenra
//
//  One entry of money in a goal's or a debt's history (a contribution, a repayment):
//  an adapter over DesignKit's AmountRow in the info style, so it pads itself vertically and
//  takes the card's inset. The note is the title with the date under it; without a note the
//  date is the title. The amount is FormattedAmountText, hidden with the other amounts.
//

import SwiftUI

struct HistoryEntryRow: View {
    let date: Date
    let note: String?
    let amount: Double
    let currency: String
    /// The SF Symbol on the row's tinted disc ("plus" for a contribution, "arrow.uturn.down"
    /// for a repayment).
    let symbol: String

    var body: some View {
        let day = DateFormatters.displayDateOmittingCurrentYear(date)
        let note = note.flatMap { $0.isEmpty ? nil : $0 }
        AmountRow(
            note ?? day,
            subtitle: note == nil ? nil : day,
            subtitleLineLimit: 1,
            leading: .tinted(.sfSymbol(symbol), AppColors.income),
            value: .amount(amount),
            currency: currency
        )
    }
}

#Preview("History entries") {
    VStack(spacing: 0) {
        HistoryEntryRow(date: Date(), note: "Bonus", amount: 50_000, currency: "KZT", symbol: "plus")
        Divider().padding(.leading, AppIconSize.Tile.sm + AppSpacing.md)
        HistoryEntryRow(date: Date().addingTimeInterval(-86_400 * 30), note: nil, amount: 20_000, currency: "KZT", symbol: "arrow.uturn.down")
    }
    .padding(AppSpacing.lg)
    .cardStyle()
    .screenPadding()
}
