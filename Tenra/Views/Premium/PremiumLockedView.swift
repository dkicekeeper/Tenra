//
//  PremiumLockedView.swift
//  Tenra
//
//  Reusable "this is a Pro feature" placeholder for whole-tab gates (Voice, Import).
//  When the user becomes Pro, the host view re-renders (isPro is observable) and
//  swaps this out for the real feature — no manual refresh needed.
//

import SwiftUI

struct PremiumLockedView: View {
    let icon: String
    let title: String
    let message: String

    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: AppIconSize.mega, weight: .light))
                .foregroundStyle(AppColors.accent)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h3)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxxl)
            }

            Button {
                HapticManager.light()
                showPaywall = true
            } label: {
                Label(String(localized: "premium.unlock"), systemImage: "crown.fill")
            }
            .primaryButton()
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
        }
        .paywallSheet(isPresented: $showPaywall)
    }
}
