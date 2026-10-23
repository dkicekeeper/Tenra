//
//  SettingsPurchaseSection.swift
//  Tenra
//
//  For a free user, above About: restore purchases (also on the paywall, which is not always
//  there to open: SettingsProHero) and redeem an offer code (StoreKit's sheet, codes made in
//  App Store Connect → the subscription → Offer Codes; PremiumManager syncs it with RevenueCat).
//  Hidden once Pro is on. Reads PremiumManager only, never RevenueCat.
//

import StoreKit
import SwiftUI

struct SettingsPurchaseSection: View {

    @Environment(PremiumManager.self) private var premium

    @State private var showingCodeRedemption = false
    @State private var isRestoring = false
    @State private var restoreOutcome: RestoreOutcome?

    private enum RestoreOutcome {
        case nothingToRestore
        case failed
    }

    var body: some View {
        if !premium.isPro {
            FormSection {
                restorePurchasesRow
                redeemCodeRow
            }
            .offerCodeRedemption(isPresented: $showingCodeRedemption) { result in
                guard case .success = result else { return }
                Task { await premium.syncAfterOfferCodeRedemption() }
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

    private func label(for outcome: RestoreOutcome) -> String {
        switch outcome {
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
                // A restore that unlocked Pro hides this section and turns the hero Active.
                if premium.isPro {
                    HapticManager.success()
                } else {
                    restoreOutcome = .nothingToRestore
                }
            } catch {
                restoreOutcome = .failed
            }
            isRestoring = false
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        SettingsPurchaseSection()
            .screenPadding()
    }
    .environment(PremiumManager.shared)
}
