//
//  TenraProView.swift
//  Tenra
//
//  Settings → Tenra Pro: a hero on DesignKit's drifting AuroraBackground with what the person
//  has (Active with the plan and its renewal date, Free forever for a Founding User, or the
//  pitch for a free user), what Pro includes, and the actions of each state: buy (the paywall),
//  restore, redeem an offer code (StoreKit's sheet; PremiumManager syncs it with RevenueCat),
//  manage the subscription. Reads PremiumManager only, never RevenueCat.
//

import StoreKit
import SwiftUI

struct TenraProView: View {

    @Environment(PremiumManager.self) private var premium

    @State private var showingPaywall = false
    @State private var showingCodeRedemption = false
    @State private var isRestoring = false
    @State private var restoreOutcome: RestoreOutcome?
    /// Bumped each time the buy button appears: DesignKit's shine sweeps across it once.
    @State private var ctaShine = 0
    /// The title shows in the navigation bar once the hero has scrolled under it.
    @State private var isNavTitleVisible = false

    private enum RestoreOutcome {
        case restored
        case nothingToRestore
        case failed
    }

    /// Gated features (CLAUDE.md, Monetization): what a free user gets by buying Pro.
    private static let features: [(icon: String, key: String)] = [
        ("creditcard", "pro.feature.accounts"),
        ("waveform", "pro.feature.voice"),
        ("doc.text.viewfinder", "pro.feature.import"),
        ("building.columns", "pro.feature.deposits"),
        ("banknote", "pro.feature.loans"),
        ("person.2", "pro.feature.debts")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                hero
                    .screenPadding()
                    .padding(.top, AppSpacing.lg)
                    .scrollHero()

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
                    .screenPadding()
                }

                featuresSection
                    .screenPadding()

                if hasActions {
                    actionsSection
                        .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .background(alignment: .top) { aurora }
        // On the screen, not on the button or the row that opened them: buying or redeeming
        // turns this screen into the Active state, which removes both.
        .paywallSheet(isPresented: $showingPaywall)
        .offerCodeRedemption(isPresented: $showingCodeRedemption) { result in
            guard case .success = result else { return }
            Task { await premium.syncAfterOfferCodeRedemption() }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > TenraProMetrics.navTitleThreshold
        } action: { _, shouldShow in
            isNavTitleVisible = shouldShow
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: "Tenra Pro")
                    .font(AppTypography.bodyEmphasis)
                    .opacity(isNavTitleVisible ? 1 : 0)
                    .animation(AppAnimation.smooth, value: isNavTitleVisible)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HeroSection(
            icon: .sfSymbol("crown.fill"),
            title: "Tenra Pro",
            iconTint: .monochrome(AppColors.accent),
            subtitle: heroSubtitle
        ) {
            if let badge = statusBadge {
                Badge(badge, systemImage: "checkmark.seal.fill", color: AppColors.success)
                    // A holographic foil on the Pro badge: its colours follow the finger (DesignKit).
                    .holographic()
            }
        }
    }

    /// The top of the screen: the accent's aurora, drifting, fading into the page below the
    /// hero. Fixed behind the scroll view, so it reaches under the navigation bar.
    private var aurora: some View {
        AuroraBackground(intensity: TenraProMetrics.auroraIntensity)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: TenraProMetrics.auroraSolidEnd),
                        .init(color: .clear, location: TenraProMetrics.auroraFadeEnd)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
    }

    /// "Active" for a subscriber, "Free forever" for a Founding User, none for a free user.
    private var statusBadge: String? {
        if premium.isSubscriber { return String(localized: "settings.pro.status.active") }
        if premium.isFounder { return String(localized: "settings.pro.founder") }
        return nil
    }

    private var heroSubtitle: String? {
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

    // MARK: - Features

    private var featuresSection: some View {
        FormSection(header: String(localized: "pro.page.features")) {
            ForEach(Array(Self.features.enumerated()), id: \.offset) { _, feature in
                UniversalRow(
                    leadingIcon: .sfSymbol(feature.icon, color: AppColors.accent, size: AppIconSize.lg)
                ) {
                    Text(String(localized: String.LocalizationValue(feature.key)))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                } trailing: {
                    // Included: the person has Pro.
                    if premium.isPro {
                        Icon("checkmark", size: AppIconSize.sm)
                            .foregroundStyle(AppColors.success)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Free: restore and redeem a code. Subscriber: manage, unless the purchase is lifetime.
    /// A Founding User has nothing to manage.
    private var hasActions: Bool {
        if premium.isSubscriber { return premium.proStatus?.plan != .lifetime }
        return !premium.isFounder
    }

    private var actionsSection: some View {
        FormSection {
            if premium.isSubscriber {
                Link(destination: manageSubscriptionURL) {
                    UniversalRow(
                        leadingIcon: .sfSymbol("gearshape", color: AppColors.accent, size: AppIconSize.lg)
                    ) {
                        Text(String(localized: "settings.pro.manage"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                    } trailing: {
                        Icon("arrow.up.right", size: AppIconSize.sm)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                // A link's label keeps the row's divider inset to itself: its icon and space.
                .rowDividerInset(AppIconSize.lg + AppSpacing.md)
            } else {
                restorePurchasesRow
                redeemCodeRow
            }
        }
    }

    private var restorePurchasesRow: some View {
        UniversalRow(
            leadingIcon: .sfSymbol("arrow.clockwise", color: AppColors.accent, size: AppIconSize.lg)
        ) {
            Text(String(localized: "settings.pro.restore"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
        } trailing: {
            if isRestoring {
                ProgressView()
            } else if let restoreOutcome {
                Text(label(for: restoreOutcome))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(restoreOutcome == .failed ? AppColors.destructive : AppColors.textSecondary)
            }
        }
        .actionRow { restorePurchases() }
        .buttonStyle(.plain)
        // The button around the row keeps its divider inset to itself: the icon and its space.
        .rowDividerInset(AppIconSize.lg + AppSpacing.md)
    }

    /// Opens the App Store's offer-code sheet (codes made in App Store Connect →
    /// the subscription → Offer Codes). A redeemed code unlocks Pro like a purchase.
    private var redeemCodeRow: some View {
        UniversalRow(
            String(localized: "settings.pro.redeemCode"),
            icon: "giftcard",
            accessory: .action {
                HapticManager.light()
                showingCodeRedemption = true
            }
        )
    }

    // MARK: - Helpers

    /// RevenueCat's per-customer management URL when known; Apple's generic
    /// subscriptions page otherwise (opens the App Store subscription list).
    private var manageSubscriptionURL: URL {
        premium.proStatus?.managementURL
            ?? URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    private func label(for outcome: RestoreOutcome) -> String {
        switch outcome {
        case .restored:         String(localized: "settings.pro.restore.restored")
        case .nothingToRestore: String(localized: "settings.pro.restore.none")
        case .failed:           String(localized: "settings.pro.restore.failed")
        }
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        HapticManager.light()
        isRestoring = true
        restoreOutcome = nil
        Task {
            do {
                try await premium.restorePurchases()
                // A restore that unlocked Pro flips `isSubscriber`, which re-renders this
                // screen into the Active state: the label only matters when nothing was found.
                restoreOutcome = premium.isPro ? .restored : .nothingToRestore
                if premium.isPro { HapticManager.success() }
            } catch {
                restoreOutcome = .failed
            }
            isRestoring = false
        }
    }
}

private enum TenraProMetrics {
    /// How strongly the aurora shows over the page: soft enough for the hero's text on it.
    static let auroraIntensity: Double = 0.55
    /// The aurora is whole down to this share of the screen's height…
    static let auroraSolidEnd: CGFloat = 0.3
    /// …and fades out by this one, under the first cards.
    static let auroraFadeEnd: CGFloat = 0.6
    /// The hero's title has scrolled under the navigation bar.
    static let navTitleThreshold: CGFloat = 120
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TenraProView()
    }
    .environment(PremiumManager.shared)
}
