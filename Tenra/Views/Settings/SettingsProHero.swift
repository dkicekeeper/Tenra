//
//  SettingsProHero.swift
//  Tenra
//
//  The top of Settings: Tenra Pro on DesignKit's drifting AuroraBackground, which scrolls with
//  the page and reaches under the navigation bar. A free user sees the pitch and one button,
//  "Get Tenra Pro", which opens the paywall (RevenueCat's, PaywallSheet); what Pro includes is
//  the paywall's to tell. A subscriber sees the plan and its renewal date with "Manage
//  Subscription", a Founding User the "Free forever" badge. Restore and redeem a code are rows
//  of Settings' About section (SettingsView). Reads PremiumManager only, never RevenueCat.
//

import SwiftUI

struct SettingsProHero: View {

    @Environment(PremiumManager.self) private var premium
    @Environment(\.openURL) private var openURL

    @State private var showingPaywall = false
    /// Bumped each time the buy button appears: DesignKit's shine sweeps across it once.
    @State private var ctaShine = 0

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            HeroSection(
                icon: .sfSymbol("crown.fill"),
                title: "Tenra Pro",
                iconTint: .monochrome(AppColors.accent),
                subtitle: subtitle
            ) {
                if let badge = statusBadge {
                    Badge(badge, systemImage: "checkmark.seal.fill", color: AppColors.success)
                        // A holographic foil on the Pro badge: its colours follow the finger (DesignKit).
                        .holographic()
                }
            }
            button
        }
        .screenPadding()
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xxl)
        .background(alignment: .top) { aurora }
        // On the hero, not on the button: buying turns it into the Active state, which removes it.
        .paywallSheet(isPresented: $showingPaywall)
    }

    // MARK: - Button

    @ViewBuilder
    private var button: some View {
        if !premium.isPro {
            DSButton(
                String(localized: "settings.pro.cta.title"),
                systemImage: "crown.fill",
                fullWidth: true
            ) {
                HapticManager.light()
                showingPaywall = true
            }
            .shine(trigger: ctaShine, in: Capsule())
            .onAppear { ctaShine += 1 }
            .accessibilityIdentifier("settings.pro.subscribe")
        } else if premium.isSubscriber, premium.proStatus?.plan != .lifetime {
            DSButton(
                String(localized: "settings.pro.manage"),
                systemImage: "gearshape",
                appearance: .secondary,
                fullWidth: true
            ) {
                HapticManager.light()
                openURL(manageSubscriptionURL)
            }
        }
    }

    /// RevenueCat's per-customer management URL when known; Apple's subscriptions page otherwise.
    private var manageSubscriptionURL: URL {
        premium.proStatus?.managementURL
            ?? URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    // MARK: - Aurora

    /// The accent's aurora, fading into the page by the hero's bottom: behind the hero only, so
    /// the glass sections below never redraw for its drift. It reaches up under the navigation
    /// bar and over a pull-down.
    private var aurora: some View {
        AuroraBackground(intensity: SettingsProHeroMetrics.auroraIntensity)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: SettingsProHeroMetrics.auroraSolidEnd),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .padding(.top, -SettingsProHeroMetrics.auroraOverscroll)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Status

    /// "Active" for a subscriber, "Free forever" for a Founding User, none for a free user.
    private var statusBadge: String? {
        if premium.isSubscriber { return String(localized: "settings.pro.status.active") }
        if premium.isFounder { return String(localized: "settings.pro.founder") }
        return nil
    }

    private var subtitle: String? {
        if premium.isSubscriber { return subscriptionSubtitle }
        if premium.isFounder { return String(localized: "settings.pro.founder.subtitle") }
        return String(localized: "pro.page.subtitle")
    }

    /// "Annual · Renews 12 Aug 2026" / "Monthly · Expires …" / "Lifetime access".
    private var subscriptionSubtitle: String? {
        guard let status = premium.proStatus else { return nil }
        if status.plan == .lifetime {
            return String(localized: "settings.pro.plan.lifetime")
        }
        let planName: String
        switch status.plan {
        case .monthly:  planName = String(localized: "settings.pro.plan.monthly")
        case .annual:   planName = String(localized: "settings.pro.plan.annual")
        case .lifetime, .unknown: planName = "Pro"
        }
        guard let date = status.expirationDate else { return planName }
        let dateString = date.formatted(date: .abbreviated, time: .omitted)
        let key = status.willRenew ? "settings.pro.status.renews" : "settings.pro.status.expires"
        return String(
            format: String(localized: String.LocalizationValue(key)),
            planName, dateString
        )
    }
}

private enum SettingsProHeroMetrics {
    /// How strongly the aurora shows: soft enough for the hero's text on it.
    static let auroraIntensity: Double = 0.55
    /// The aurora is whole down to this share of its height, then fades out by the hero's bottom.
    static let auroraSolidEnd: CGFloat = 0.45
    /// How far the aurora reaches above the hero: under the navigation bar and a pull-down.
    static let auroraOverscroll: CGFloat = 320
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScrollView {
            SettingsProHero()
        }
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
    .environment(PremiumManager.shared)
}
