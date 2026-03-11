//
//  EditableHeroSection.swift
//  AIFinanceManager
//
//  Phase 16: Hero-style Edit Views
//  Updated: Phase 16 - AnimatedHeroInput
//
//  Universal hero section component for edit views with:
//  - Large tappable IconView with spring animation
//  - AnimatedTitleInput: per-character spring+fade animation
//  - AnimatedAmountInput: per-digit spring+wobble animation
//  - Inline currency picker as Menu button
//  - Optional ColorPickerRow carousel
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

/// Editable hero section for edit views with animated icon, title, and optional balance/color.
struct EditableHeroSection: View {
    // MARK: - Bindings

    @Binding var iconSource: IconSource?
    @Binding var title: String
    @Binding var balance: String
    @Binding var currency: String

    // MARK: - Configuration

    let titlePlaceholder: String
    let config: HeroConfig
    let currencies: [String]
    /// When set, the icon renders as a tinted circle (e.g. for categories).
    /// When nil, the icon renders as a glass hero (e.g. for accounts, subscriptions).
    let iconTintColor: String?

    // MARK: - State

    @State private var showingIconPicker = false
    @State private var iconScale: CGFloat = 0

    // MARK: - Initializer

    init(
        iconSource: Binding<IconSource?>,
        title: Binding<String>,
        balance: Binding<String> = .constant(""),
        currency: Binding<String> = .constant("USD"),
        iconTintColor: String? = nil,
        titlePlaceholder: String,
        config: HeroConfig = HeroConfig(),
        currencies: [String] = ["USD", "EUR", "KZT", "RUB", "GBP"]
    ) {
        self._iconSource = iconSource
        self._title = title
        self._balance = balance
        self._currency = currency
        self.iconTintColor = iconTintColor
        self.titlePlaceholder = titlePlaceholder
        self.config = config
        self.currencies = currencies
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Hero Icon
            heroIconView
                .scaleEffect(iconScale)
                .onAppear {
                    withAnimation(AppAnimation.heroSpring) {
                        iconScale = 1.0
                    }
                }

            // Animated Title
            AnimatedTitleInput(
                text: $title,
                placeholder: titlePlaceholder
            )
            .padding(.horizontal, AppSpacing.lg)

            // Balance (if enabled)
            if config.showBalance {
                balanceView
            }
        }
        .padding(.vertical, AppSpacing.xl)
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedSource: $iconSource, allowLogos: config.allowLogos)
        }
    }

    // MARK: - Hero Icon View

    private var heroIconView: some View {
        Button {
            HapticManager.light()
            showingIconPicker = true
        } label: {
            if let tintHex = iconTintColor {
                // Tinted circle icon (e.g. categories)
                IconView(
                    source: iconSource ?? .sfSymbol("star.fill"),
                    style: .circle(
                        size: AppIconSize.largeButton,
                        tint: .monochrome(Color(hex: tintHex)),
                        backgroundColor: AppColors.surface
                    )
                )
            } else {
                // Glass hero icon (e.g. accounts, subscriptions)
                if #available(iOS 18.0, *) {
                    IconView(
                        source: iconSource,
                        style: .glassHero()
                    )
                } else {
                    IconView(
                        source: iconSource,
                        size: AppIconSize.largeButton
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "common.changeIcon"))
    }

    // MARK: - Balance View

    private var balanceView: some View {
        VStack(spacing: AppSpacing.sm) {
            AnimatedAmountInput(amount: $balance)
                .padding(.horizontal, AppSpacing.lg)

            if config.showCurrency {
                CurrencySelectorView(
                    selectedCurrency: $currency,
                    availableCurrencies: currencies
                )
            }
        }
    }
}

// MARK: - Previews

#Preview("Account Hero") {
    @Previewable @State var icon: IconSource? = .bankLogo(.kaspi)
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
                        icon = .bankLogo(.kaspi)
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
