//
//  StaticSubscriptionIconsView.swift
//  AIFinanceManager
//
//  Static display of subscription icons as an overlapping facepile stack.
//

import SwiftUI

struct StaticSubscriptionIconsView: View {
    let subscriptions: [RecurringSeries]
    var maxVisible: Int = 5

    private let iconSize: CGFloat = 48
    private let overlap: CGFloat = 12
    private let borderWidth: CGFloat = 2

    private var visible: [RecurringSeries] {
        Array(subscriptions.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, subscriptions.count - maxVisible)
    }

    var body: some View {
        HStack(spacing: -(overlap)) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, subscription in
                SubscriptionFacepileIcon(
                    subscription: subscription,
                    size: iconSize,
                    borderWidth: borderWidth,
                    zIndex: Double(maxVisible - index),
                    animationDelay: Double(index) * 0.06
                )
                .zIndex(Double(maxVisible - index))
            }

            if overflowCount > 0 {
                OverflowBadge(
                    count: overflowCount,
                    size: iconSize,
                    borderWidth: borderWidth,
                    zIndex: 0,
                    animationDelay: Double(visible.count) * 0.06
                )
                .zIndex(0)
            }
        }
    }
}

// MARK: - Facepile Icon

private struct SubscriptionFacepileIcon: View {
    let subscription: RecurringSeries
    let size: CGFloat
    let borderWidth: CGFloat
    let zIndex: Double
    let animationDelay: Double

    @State private var appeared = false

    private var iconStyle: IconStyle {
        switch subscription.iconSource {
        case .sfSymbol:
            return .circle(size: size, tint: .accentMonochrome, backgroundColor: AppColors.surface)
        case .brandService, .none:
            return .circle(size: size, tint: .original)
        }
    }

    var body: some View {
        IconView(source: subscription.iconSource, style: iconStyle)
            .overlay(Circle().stroke(.background, lineWidth: borderWidth))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(
                AppAnimation.isReduceMotionEnabled
                    ? .linear(duration: 0)
                    : .spring(response: 0.4, dampingFraction: 0.7).delay(animationDelay),
                value: appeared
            )
            .task { appeared = true }
    }
}

// MARK: - Overflow Badge

private struct OverflowBadge: View {
    let count: Int
    let size: CGFloat
    let borderWidth: CGFloat
    let zIndex: Double
    let animationDelay: Double

    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.quaternary)
            Text("+\(count)")
                .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.background, lineWidth: borderWidth))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
        .animation(
            AppAnimation.isReduceMotionEnabled
                ? .linear(duration: 0)
                : .spring(response: 0.4, dampingFraction: 0.7).delay(animationDelay),
            value: appeared
        )
        .task { appeared = true }
    }
}

// MARK: - Previews

#Preview("5 icons, no overflow") {
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
                        startDate: today, kind: .subscription, iconSource: .sfSymbol("dumbbell.fill"), status: .active),
    ]

    VStack(spacing: AppSpacing.md) {
        Text("5 subscriptions").font(AppTypography.caption).foregroundStyle(.secondary)
        StaticSubscriptionIconsView(subscriptions: mockSubscriptions)
    }
    .padding()
}

#Preview("8 icons with overflow") {
    let today = DateFormatters.dateFormatter.string(from: Date())
    let mockSubscriptions = (1...8).map { i in
        RecurringSeries(id: "s\(i)", amount: Decimal(9.99), currency: "USD", category: "Cat",
                        description: "Sub \(i)", accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription,
                        iconSource: .sfSymbol(["star.fill","heart.fill","flame.fill","bolt.fill","leaf.fill","music.note","camera.fill","globe"][i - 1]),
                        status: .active)
    }

    VStack(spacing: AppSpacing.md) {
        Text("8 subscriptions").font(AppTypography.caption).foregroundStyle(.secondary)
        StaticSubscriptionIconsView(subscriptions: mockSubscriptions)
    }
    .padding()
}

#Preview("Empty") {
    StaticSubscriptionIconsView(subscriptions: [])
        .padding()
}
