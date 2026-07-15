//
//  HeroSection.swift
//  Tenra
//
//  Unified read-only hero section for entity-detail screens AND simpler
//  icon+title contexts (TransactionAddModal, TransactionEditView, InsightDeepDiveView).
//  - Amount / subtitle / progress / currency-conversion are all optional.
//  - Icon animates in with a spring scale-up on appear.
//  - For edit flows with bindings + IconPicker use `EditableHeroSection` instead.
//

import SwiftUI

struct HeroSection<Accessory: View>: View {
    let icon: IconSource?
    let iconTint: IconTint?
    /// When `false` the icon block (and its progress ring) is omitted entirely — no
    /// placeholder container. Use when the icon is shown elsewhere (e.g. an orb centre).
    /// This differs from `icon: nil`, which intentionally renders a placeholder.
    let showsIcon: Bool
    let title: String
    let primaryAmount: Double?
    let primaryCurrency: String
    /// Colour for the primary amount; defaults to `AppColors.textSecondary`.
    let primaryAmountColor: Color?
    /// Non-currency metric fallback (percent, count, composed strings) rendered
    /// in the amount slot's style when there is no `primaryAmount`/currency pair.
    let primaryText: String?
    let subtitle: String?
    let progress: ProgressConfig?
    let showBaseConversion: Bool
    let baseCurrency: String
    /// Optional centered accessory under the amount (e.g. a trend badge).
    @ViewBuilder private let accessory: () -> Accessory

    @State private var iconScale: CGFloat = AppAnimation.heroHiddenScale
    @State private var iconOpacity: Double = 0

    init(
        icon: IconSource?,
        title: String,
        iconTint: IconTint? = nil,
        showsIcon: Bool = true,
        primaryAmount: Double? = nil,
        primaryCurrency: String = "",
        primaryAmountColor: Color? = nil,
        primaryText: String? = nil,
        subtitle: String? = nil,
        progress: ProgressConfig? = nil,
        showBaseConversion: Bool = false,
        baseCurrency: String = "",
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.showsIcon = showsIcon
        self.title = title
        self.primaryAmount = primaryAmount
        self.primaryCurrency = primaryCurrency
        self.primaryAmountColor = primaryAmountColor
        self.primaryText = primaryText
        self.subtitle = subtitle
        self.progress = progress
        self.showBaseConversion = showBaseConversion
        self.baseCurrency = baseCurrency
        self.accessory = accessory
    }

    /// Diameter of the progress ring that wraps the hero icon.
    /// Icon is `AppIconSize.ultra` (80pt); ring sits 6pt outside.
    /// (Computed, not `static let` — the type is generic, which bars stored statics.)
    private static var ringSize: CGFloat { AppIconSize.ultra + 12 }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            if showsIcon {
                ZStack {
                    if let progress {
                        ProgressRing(
                            progress: progress.fraction,
                            size: Self.ringSize,
                            lineWidth: 4,
                            isOverBudget: progress.fraction > 1.0,
                            overrideColor: progress.color
                        )
                    }
                    IconView(source: icon, style: .glassHero(tint: iconTint ?? .original))
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .onAppear {
                    withAnimation(AppAnimation.heroEntranceAnimation) {
                        iconScale = 1.0
                        iconOpacity = 1.0
                    }
                }
            }

            VStack(alignment: .center, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.h1)
                    .multilineTextAlignment(.center)

                if let primaryAmount, !primaryCurrency.isEmpty {
                    FormattedAmountText(
                        amount: primaryAmount,
                        currency: primaryCurrency,
                        fontSize: AppTypography.h3,
                        color: primaryAmountColor ?? AppColors.textSecondary
                    )

                    if showBaseConversion, !baseCurrency.isEmpty, primaryCurrency != baseCurrency {
                        ConvertedAmountView(
                            amount: primaryAmount,
                            fromCurrency: primaryCurrency,
                            toCurrency: baseCurrency,
                            fontSize: AppTypography.h3,
                            color: AppColors.textSecondary.opacity(0.7)
                        )
                    }
                } else if let primaryText {
                    // Non-currency metric (percent, count, composed string) —
                    // same visual slot/style as the amount.
                    Text(primaryText)
                        .font(AppTypography.h3)
                        .foregroundStyle(primaryAmountColor ?? AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                accessory()
                    .padding(.top, AppSpacing.xs)

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.top, AppSpacing.xs)
                }

                if let progress, let label = progress.label {
                    HStack(spacing: AppSpacing.xs) {
                        Text(label)
                        Text("·")
                        Text("\(Int((progress.fraction * 100).rounded()))%")
                    }
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, AppSpacing.xs)
                }
            }
        }
    }
}

// MARK: - Convenience init (no accessory)

extension HeroSection where Accessory == EmptyView {
    /// Accessory-free init — keeps the dozens of existing call sites source-compatible.
    init(
        icon: IconSource?,
        title: String,
        iconTint: IconTint? = nil,
        showsIcon: Bool = true,
        primaryAmount: Double? = nil,
        primaryCurrency: String = "",
        primaryAmountColor: Color? = nil,
        primaryText: String? = nil,
        subtitle: String? = nil,
        progress: ProgressConfig? = nil,
        showBaseConversion: Bool = false,
        baseCurrency: String = ""
    ) {
        self.init(
            icon: icon,
            title: title,
            iconTint: iconTint,
            showsIcon: showsIcon,
            primaryAmount: primaryAmount,
            primaryCurrency: primaryCurrency,
            primaryAmountColor: primaryAmountColor,
            primaryText: primaryText,
            subtitle: subtitle,
            progress: progress,
            showBaseConversion: showBaseConversion,
            baseCurrency: baseCurrency,
            accessory: { EmptyView() }
        )
    }
}

#Preview("Icon + Title only") {
    HeroSection(
        icon: .sfSymbol("fork.knife"),
        title: "Food & Drinks"
    )
    .padding()
}

#Preview("With amount") {
    HeroSection(
        icon: .sfSymbol("creditcard.fill"),
        title: "Kaspi Gold",
        primaryAmount: 1_245_300,
        primaryCurrency: "KZT",
        showBaseConversion: true,
        baseCurrency: "USD"
    )
    .padding()
}

#Preview("With budget progress") {
    HeroSection(
        icon: .sfSymbol("fork.knife"),
        title: "Food",
        primaryAmount: 185_000,
        primaryCurrency: "KZT",
        subtitle: "This month",
        progress: ProgressConfig(current: 185_000, total: 250_000, label: "Budget", color: .orange)
    )
    .padding()
}

#Preview("Brand logo, no amount") {
    HeroSection(
        icon: .brandService("kaspi.kz"),
        title: "Kaspi Gold"
    )
    .padding()
}

#Preview("Nil icon") {
    HeroSection(
        icon: nil,
        title: "Unknown Category"
    )
    .padding()
}
