//
//  SettingsProSection.swift
//  Tenra
//
//  "Tenra Pro" block at the top of Settings: purchase CTA for free users,
//  subscription status (plan + renewal date) for subscribers, and the
//  Founding-User state for grandfathered users. Self-contained — reads
//  PremiumManager from the environment and owns its paywall presentation,
//  so SettingsView just drops `SettingsProSection()` into its List.
//

import SwiftUI

struct SettingsProSection: View {

    @Environment(PremiumManager.self) private var premium

    @State private var showingPaywall = false
    @State private var isRestoring = false
    @State private var restoreOutcome: RestoreOutcome?

    private enum RestoreOutcome {
        case restored
        case nothingToRestore
        case failed
    }

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: "Tenra Pro")) {
            if premium.isSubscriber {
                subscriberStatusRow
                if premium.proStatus?.plan != .lifetime {
                    manageSubscriptionRow
                }
            } else if premium.isFounder {
                founderRow
            } else {
                purchaseCTARow
                restorePurchasesRow
            }
        }
        .paywallSheet(isPresented: $showingPaywall)
    }

    // MARK: - Free: purchase CTA + restore

    private var purchaseCTARow: some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol("crown.fill", color: AppColors.accent, size: AppIconSize.md)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(String(localized: "settings.pro.cta.title"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text(String(localized: "settings.pro.cta.subtitle"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        } trailing: {
            Image(systemName: "chevron.right")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
        .actionRow {
            HapticManager.light()
            showingPaywall = true
        }
    }

    private var restorePurchasesRow: some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol("arrow.clockwise", color: AppColors.accent, size: AppIconSize.md)
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
    }

    // MARK: - Subscriber: status + manage

    private var subscriberStatusRow: some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol("crown.fill", color: AppColors.accent, size: AppIconSize.md)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: "Tenra Pro")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                if let subtitle = subscriptionSubtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        } trailing: {
            HStack(spacing: AppSpacing.xs) {
                Text(String(localized: "settings.pro.status.active"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.success)
                Image(systemName: "checkmark.seal.fill")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.success)
            }
        }
    }

    private var manageSubscriptionRow: some View {
        Link(destination: manageSubscriptionURL) {
            UniversalRow(
                config: .settings,
                leadingIcon: .sfSymbol("gearshape", color: AppColors.accent, size: AppIconSize.md)
            ) {
                Text(String(localized: "settings.pro.manage"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            } trailing: {
                Image(systemName: "arrow.up.right")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Founder

    private var founderRow: some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol("crown.fill", color: AppColors.accent, size: AppIconSize.md)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: "Tenra Pro")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text(String(localized: "settings.pro.founder.subtitle"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        } trailing: {
            HStack(spacing: AppSpacing.xs) {
                Text(String(localized: "settings.pro.founder"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.success)
                Image(systemName: "checkmark.seal.fill")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.success)
            }
        }
    }

    // MARK: - Helpers

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
                // A successful restore that unlocked Pro flips `isSubscriber`,
                // which re-renders this section into the status state — the
                // outcome label only matters when nothing was found.
                restoreOutcome = premium.isPro ? .restored : .nothingToRestore
                if premium.isPro { HapticManager.success() }
            } catch {
                restoreOutcome = .failed
            }
            isRestoring = false
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        SettingsProSection()
    }
    .environment(PremiumManager.shared)
}
