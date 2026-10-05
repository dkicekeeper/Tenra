//
//  SubscriptionCard.swift
//  Tenra
//
//  Subscription card. Adapter over DesignKit's `RecurringPaymentCard`: maps the
//  recurring series and its next-charge copy.
//

import SwiftUI

struct SubscriptionCard: View, Equatable {
    let subscription: RecurringSeries
    let nextChargeDate: Date?
    var baseCurrency: String = ""

    /// Equatable compares only rendering-affecting fields. Same pattern as `CategoryRow`.
    /// Apply at call sites via `.equatable()` to let SwiftUI skip body re-evals when
    /// the underlying subscription / next-charge-date / base currency didn't change.
    static func == (lhs: SubscriptionCard, rhs: SubscriptionCard) -> Bool {
        lhs.subscription == rhs.subscription
            && lhs.nextChargeDate == rhs.nextChargeDate
            && lhs.baseCurrency == rhs.baseCurrency
    }

    var body: some View {
        RecurringPaymentCard(
            iconSource: subscription.iconSource,
            title: subscription.description,
            amount: NSDecimalNumber(decimal: subscription.amount).doubleValue,
            currency: subscription.currency,
            baseCurrency: baseCurrency,
            caption: nextChargeDate.map {
                String(format: String(localized: "subscriptions.nextChargeOn"), formatDate($0))
            },
            status: subscription.entityStatus
        )
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatters.displayDateOmittingCurrentYear(date)
    }
}

#Preview {
    SubscriptionCard(
        subscription: RecurringSeries(
            id: "1",
            amount: Decimal(9.99),
            currency: "USD",
            category: "Entertainment",
            description: "Netflix",
            accountId: "1",
            frequency: .monthly,
            startDate: DateFormatters.dateFormatter.string(from: Date()),
            kind: .subscription,
            iconSource: .brandService("Netflix"),
            status: .active
        ),
        nextChargeDate: Date().addingTimeInterval(7 * 24 * 60 * 60) // 7 days from now
    )
    .padding()
}
