//
//  HeroSection.swift
//  Tenra
//
//  Standard hero for all entity-detail screens:
//  icon + title + primary amount + optional subtitle + optional progress + optional base-currency conversion.
//
//  NOTE: The older simpler icon+title hero is now named `SimpleHeroSection`
//  (see Views/Components/Headers/SimpleHeroSection.swift). It is still used by
//  TransactionAddModal, TransactionEditView, and InsightDeepDiveView.
//

import SwiftUI

struct HeroSection: View {
    let icon: IconSource?
    let title: String
    let primaryAmount: Double
    let primaryCurrency: String
    let subtitle: String?
    let progress: ProgressConfig?
    let showBaseConversion: Bool
    let baseCurrency: String

    init(
        icon: IconSource?,
        title: String,
        primaryAmount: Double,
        primaryCurrency: String,
        subtitle: String? = nil,
        progress: ProgressConfig? = nil,
        showBaseConversion: Bool = false,
        baseCurrency: String = ""
    ) {
        self.icon = icon
        self.title = title
        self.primaryAmount = primaryAmount
        self.primaryCurrency = primaryCurrency
        self.subtitle = subtitle
        self.progress = progress
        self.showBaseConversion = showBaseConversion
        self.baseCurrency = baseCurrency
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            IconView(source: icon, style: .glassHero())

            VStack(alignment: .center, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.h1)
                    .multilineTextAlignment(.center)

                FormattedAmountText(
                    amount: primaryAmount,
                    currency: primaryCurrency,
                    fontSize: AppTypography.h4,
                    color: .secondary
                )

                if showBaseConversion, !baseCurrency.isEmpty, primaryCurrency != baseCurrency {
                    ConvertedAmountView(
                        amount: primaryAmount,
                        fromCurrency: primaryCurrency,
                        toCurrency: baseCurrency,
                        fontSize: AppTypography.caption,
                        color: .secondary.opacity(0.7)
                    )
                }

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, AppSpacing.xs)
                }
            }

            if let progress {
                progressBar(progress)
                    .padding(.top, AppSpacing.sm)
                    .padding(.horizontal, AppSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func progressBar(_ cfg: ProgressConfig) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if let label = cfg.label {
                HStack {
                    Text(label)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((cfg.fraction * 100).rounded()))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(cfg.color.opacity(0.15))
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(cfg.color)
                        .frame(width: geo.size.width * cfg.fraction)
                        .animation(AppAnimation.progressBarSpring, value: cfg.fraction)
                }
            }
            .frame(height: 6)
        }
    }
}

#Preview("No progress") {
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
