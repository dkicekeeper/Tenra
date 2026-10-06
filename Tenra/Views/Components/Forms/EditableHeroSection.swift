//
//  EditableHeroSection.swift
//  Tenra
//
//  Phase 16: Hero-style Edit Views
//  Updated: Phase 16 - AnimatedHeroInput
//
//  Adapter over DesignKit's EditableHero (1.10.0): icon (opens the icon picker), name,
//  optional amount and currency. HeroConfig presets and the hex tint stay Tenra's.
//

import SwiftUI

// MARK: - HeroConfig

/// Configuration for EditableHeroSection appearance and behavior
struct HeroConfig {
    var showBalance: Bool = false
    var showCurrency: Bool = false
    var allowLogos: Bool = true

    static let accountHero = HeroConfig(showBalance: true, showCurrency: true)
    static let subscriptionHero = HeroConfig(showBalance: true, showCurrency: true)
    static let categoryHero = HeroConfig(allowLogos: false)
}

// MARK: - EditableHeroSection

/// Editable hero section for edit views: an adapter over DesignKit's `EditableHero` (1.10.0),
/// which presents DesignKit's IconPicker and CurrencyList. Keeps Tenra's `HeroConfig`
/// presets and the category colour as a stored hex.
struct EditableHeroSection: View {
    @Binding var iconSource: IconSource?
    @Binding var title: String
    @Binding var balance: String
    @Binding var currency: String

    let titlePlaceholder: String
    let config: HeroConfig
    /// When set, the icon renders tinted with this colour on glass (e.g. for categories).
    /// When nil, the icon keeps its own colours (e.g. accounts, subscriptions).
    let iconTintColor: String?
    /// Focus the title on first appear (e.g. onboarding account step).
    let autoFocusTitle: Bool

    init(
        iconSource: Binding<IconSource?>,
        title: Binding<String>,
        balance: Binding<String> = .constant(""),
        currency: Binding<String> = .constant("USD"),
        iconTintColor: String? = nil,
        titlePlaceholder: String,
        config: HeroConfig = HeroConfig(),
        autoFocusTitle: Bool = false
    ) {
        self._iconSource = iconSource
        self._title = title
        self._balance = balance
        self._currency = currency
        self.iconTintColor = iconTintColor
        self.titlePlaceholder = titlePlaceholder
        self.config = config
        self.autoFocusTitle = autoFocusTitle
    }

    var body: some View {
        EditableHero(
            icon: $iconSource,
            title: $title,
            titlePlaceholder: titlePlaceholder,
            amount: $balance,
            currency: $currency,
            iconTint: iconTintColor.map { Color(hex: $0) },
            options: EditableHero.Options(
                showsAmount: config.showBalance,
                showsCurrency: config.showCurrency,
                allowsLogos: config.allowLogos
            ),
            autoFocusTitle: autoFocusTitle
        )
    }
}

// MARK: - Previews

#Preview("Account Hero") {
    @Previewable @State var icon: IconSource? = .brandService("kaspi.kz")
    @Previewable @State var title = "Kaspi Gold"
    @Previewable @State var balance = "125000.50"
    @Previewable @State var currency = "KZT"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            titlePlaceholder: String(localized: "account.namePlaceholder"),
            config: .accountHero
        )
    }
    .padding()
}

#Preview("Category Hero") {
    @Previewable @State var icon: IconSource? = .sfSymbol("fork.knife")
    @Previewable @State var title = "Food & Drinks"
    @Previewable @State var color = "#ec4899"

    return ScrollView {
        VStack(spacing: 0) {
            EditableHeroSection(
                iconSource: $icon,
                title: $title,
                iconTintColor: color,
                titlePlaceholder: String(localized: "category.namePlaceholder"),
                config: .categoryHero
            )
            ColorPickerRow(selectedColorHex: $color)
                .padding(.horizontal, AppSpacing.lg)
        }
    }
    .padding()
}

#Preview("Subscription Hero") {
    @Previewable @State var icon: IconSource? = .brandService("netflix")
    @Previewable @State var title = "Netflix Premium"
    @Previewable @State var balance = "15.99"
    @Previewable @State var currency = "USD"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            titlePlaceholder: String(localized: "subscription.namePlaceholder"),
            config: .subscriptionHero
        )
    }
    .padding()
}

#Preview("Empty State") {
    @Previewable @State var icon: IconSource? = nil
    @Previewable @State var title = ""
    @Previewable @State var balance = ""
    @Previewable @State var currency = "USD"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            titlePlaceholder: String(localized: "account.namePlaceholder"),
            config: .accountHero
        )
    }
    .padding()
}

#Preview("Interactive Demo") {
    struct InteractiveDemoView: View {
        @State private var icon: IconSource? = .sfSymbol("star.fill")
        @State private var title = "My Category"
        @State private var balance = "1000"
        @State private var currency = "USD"
        @State private var color = "#3b82f6"
        @State private var selectedConfig: HeroConfig = .categoryHero

        var body: some View {
            VStack(spacing: AppSpacing.xxl) {
                EditableHeroSection(
                    iconSource: $icon,
                    title: $title,
                    balance: $balance,
                    currency: $currency,
                    iconTintColor: selectedConfig.allowLogos ? nil : color,
                    titlePlaceholder: String(localized: "common.name"),
                    config: selectedConfig
                )

                Divider()

                VStack(spacing: AppSpacing.md) {
                    Text(String(localized: "settings.title"))
                        .font(AppTypography.h4)

                    Button("Account Hero") {
                        selectedConfig = .accountHero
                        icon = .brandService("kaspi.kz")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Category Hero") {
                        selectedConfig = .categoryHero
                        icon = .sfSymbol("fork.knife")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Subscription Hero") {
                        selectedConfig = .subscriptionHero
                        icon = .brandService("netflix")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    return InteractiveDemoView()
}
