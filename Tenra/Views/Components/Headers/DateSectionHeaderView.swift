//
//  DateSectionHeaderView.swift
//  AIFinanceManager
//
//  Specialized section header for date-grouped transaction lists
//  Shows date label + optional total amount for the day
//

import SwiftUI

/// Date section header with optional amount display
/// Used in HistoryView and transaction lists grouped by date
struct DateSectionHeaderView: View {
    let dateKey: String
    let amount: Double?
    let currency: String?

    init(
        dateKey: String,
        amount: Double? = nil,
        currency: String? = nil
    ) {
        self.dateKey = dateKey
        self.amount = amount
        self.currency = currency
    }

    var body: some View {
        HStack {
            SectionHeaderView(dateKey)

            Spacer()

            if let amount = amount, amount > 0, let currency = currency {
                FormattedAmountText(
                    amount: amount,
                    currency: currency,
                    prefix: "-",
                    fontSize: AppTypography.bodySmall,
                    fontWeight: .semibold,
                    color: .gray
                )
            }
        }
        .textCase(nil)
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}

// MARK: - Previews

#Preview("With Amount") {
    DateSectionHeaderView(
        dateKey: "Today",
        amount: 1250.50,
        currency: "USD"
    )
    .padding()
}

#Preview("Without Amount") {
    DateSectionHeaderView(
        dateKey: "Yesterday",
        amount: nil,
        currency: nil
    )
    .padding()
}

#Preview("In List Context") {
    List {
        Section {
            Text("Transaction 1")
            Text("Transaction 2")
            Text("Transaction 3")
        } header: {
            DateSectionHeaderView(
                dateKey: "Today",
                amount: 1250.50,
                currency: "KZT"
            )
        }

        Section {
            Text("Transaction 4")
            Text("Transaction 5")
        } header: {
            DateSectionHeaderView(
                dateKey: "Yesterday",
                amount: 850.00,
                currency: "KZT"
            )
        }

        Section {
            Text("Transaction 6")
        } header: {
            DateSectionHeaderView(
                dateKey: "2 days ago",
                amount: 0,
                currency: "KZT"
            )
        }
    }
}
