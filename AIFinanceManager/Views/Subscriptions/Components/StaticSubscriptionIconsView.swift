//
//  StaticSubscriptionIconsView.swift
//  AIFinanceManager
//
//  Static display of subscription icons
//

import SwiftUI

struct StaticSubscriptionIconsView: View {
    let subscriptions: [RecurringSeries]
    let maxIcons: Int = 20
    private let iconSize: CGFloat = 32
    private let columns = 3
    private let spacing: CGFloat = 8

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(iconSize), spacing: spacing), count: columns),
            alignment: .center,
            spacing: spacing
        ) {
            ForEach(subscriptions.prefix(maxIcons)) { subscription in
                SubscriptionIconView(subscription: subscription, size: iconSize)
            }
        }
        .padding(spacing)
    }
}

// MARK: - Subscription Icon View

private struct SubscriptionIconView: View {
    let subscription: RecurringSeries
    let size: CGFloat

    var body: some View {
        IconView(
            source: subscription.iconSource,
            size: size
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(AppColors.backgroundPrimary, lineWidth: 2)
        )
    }
}

#Preview("With Icons") {
    let today = DateFormatters.dateFormatter.string(from: Date())
    let mockSubscriptions = [
        RecurringSeries(id: "s1", amount: Decimal(9.99),  currency: "USD", category: "Entertainment",
                        description: "Netflix",     accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .brandService("Netflix"), status: .active),
        RecurringSeries(id: "s2", amount: Decimal(4990),  currency: "KZT", category: "Music",
                        description: "Spotify",     accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .brandService("Spotify"), status: .active),
        RecurringSeries(id: "s3", amount: Decimal(2990),  currency: "KZT", category: "Cloud",
                        description: "iCloud",      accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .sfSymbol("cloud.fill"), status: .active),
        RecurringSeries(id: "s4", amount: Decimal(5.99),  currency: "USD", category: "Gaming",
                        description: "Xbox Pass",   accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .sfSymbol("gamecontroller.fill"), status: .active),
        RecurringSeries(id: "s5", amount: Decimal(15000), currency: "KZT", category: "Health",
                        description: "Фитнес зал",  accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .sfSymbol("dumbbell.fill"), status: .active)
    ]

    VStack(spacing: AppSpacing.md) {
        Text("5 subscriptions").font(AppTypography.caption).foregroundStyle(.secondary)
        StaticSubscriptionIconsView(subscriptions: mockSubscriptions)
    }
    .padding()
}

#Preview("Empty") {
    StaticSubscriptionIconsView(subscriptions: [])
        .padding()
}
