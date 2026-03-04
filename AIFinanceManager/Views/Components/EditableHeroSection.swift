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
    var showColorPicker: Bool = false
    var showCurrency: Bool = false

    static let accountHero = HeroConfig(showBalance: true, showCurrency: true)
    static let categoryHero = HeroConfig(showColorPicker: true)
    static let subscriptionHero = HeroConfig(showBalance: true, showCurrency: true)
}

// MARK: - EditableHeroSection

/// Editable hero section for edit views with animated icon, title, and optional balance/color.
struct EditableHeroSection: View {
    // MARK: - Bindings

    @Binding var iconSource: IconSource?
    @Binding var title: String
    @Binding var balance: String
    @Binding var currency: String
    @Binding var selectedColor: String

    // MARK: - Configuration

    let titlePlaceholder: String
    let config: HeroConfig
    let colorPalette: [String]
    let currencies: [String]

    // MARK: - State

    @State private var showingIconPicker = false
    @State private var iconScale: CGFloat = 0.8

    // MARK: - Initializer

    init(
        iconSource: Binding<IconSource?>,
        title: Binding<String>,
        balance: Binding<String> = .constant(""),
        currency: Binding<String> = .constant("USD"),
        selectedColor: Binding<String> = .constant("#3b82f6"),
        titlePlaceholder: String,
        config: HeroConfig = HeroConfig(),
        colorPalette: [String] = [
            "#3b82f6", "#8b5cf6", "#ec4899", "#f97316", "#eab308",
            "#22c55e", "#14b8a6", "#06b6d4", "#6366f1", "#d946ef",
            "#f43f5e", "#a855f7", "#10b981", "#f59e0b"
        ],
        currencies: [String] = ["USD", "EUR", "KZT", "RUB", "GBP"]
    ) {
        self._iconSource = iconSource
        self._title = title
        self._balance = balance
        self._currency = currency
        self._selectedColor = selectedColor
        self.titlePlaceholder = titlePlaceholder
        self.config = config
        self.colorPalette = colorPalette
        self.currencies = currencies
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Hero Icon
            heroIconView
                .scaleEffect(iconScale)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
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

            // Color Picker (if enabled)
            if config.showColorPicker {
                ColorPickerRow(
                    selectedColorHex: $selectedColor,
                    title: "",
                    palette: colorPalette
                )
            }
        }
        .padding(.vertical, AppSpacing.xl)
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedSource: $iconSource, allowLogos: !config.showColorPicker)
        }
    }

    // MARK: - Hero Icon View

    private var heroIconView: some View {
        Button {
            HapticManager.light()
            showingIconPicker = true
        } label: {
            if config.showColorPicker {
                // Category icon with selected color
                IconView(
                    source: iconSource ?? .sfSymbol("star.fill"),
                    style: .circle(
                        size: AppIconSize.largeButton,
                        tint: .monochrome(Color(hex: selectedColor)),
                        backgroundColor: AppColors.surface
                    )
                )
            } else {
                // Account/Subscription icon with glass effect
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
    @Previewable @State var color = "#3b82f6"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            selectedColor: $color,
            titlePlaceholder: String(localized: "account.namePlaceholder"),
            config: .accountHero
        )
    }
    .padding()
}

#Preview("Category Hero") {
    @Previewable @State var icon: IconSource? = .sfSymbol("fork.knife")
    @Previewable @State var title = "Food & Drinks"
    @Previewable @State var balance = ""
    @Previewable @State var currency = "USD"
    @Previewable @State var color = "#ec4899"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            selectedColor: $color,
            titlePlaceholder: String(localized: "category.namePlaceholder"),
            config: .categoryHero
        )
    }
    .padding()
}

#Preview("Subscription Hero") {
    @Previewable @State var icon: IconSource? = .brandService("netflix")
    @Previewable @State var title = "Netflix Premium"
    @Previewable @State var balance = "15.99"
    @Previewable @State var currency = "USD"
    @Previewable @State var color = "#3b82f6"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            selectedColor: $color,
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
    @Previewable @State var color = "#3b82f6"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            selectedColor: $color,
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
                    selectedColor: $color,
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
