//
//  AutoCaptureSetupCard.swift
//  Tenra
//
//  "Let Tenra log it for you" on Home: an adapter over DesignKit's NoticeCard that points to
//  the Wallet automation's setup guide until an automation records its first payment
//  (WalletCaptureStore.hasEverCaptured), or until the person hides it. Paid traffic lands on an
//  empty Home: this is the shortest way from there to entries that appear on their own.
//

import SwiftUI

struct AutoCaptureSetupCard: View {
    let onSetUp: () -> Void
    let onHide: () -> Void

    var body: some View {
        NoticeCard(
            title: String(localized: "home.autoCapture.title"),
            message: String(localized: "home.autoCapture.message"),
            actionTitle: String(localized: "home.autoCapture.action"),
            actionSystemImage: "wave.3.right",
            action: onSetUp,
            hideLabel: String(localized: "assistant.notice.hide"),
            onHide: onHide
        ) {
            Icon(
                source: .sfSymbol("wave.3.right"),
                style: .circle(
                    size: NoticeCardMetrics.leadingSize,
                    tint: .monochrome(AppColors.accent),
                    backgroundColor: AppColors.accent.opacity(0.15)
                )
            )
        }
    }
}

#Preview {
    AutoCaptureSetupCard(onSetUp: {}, onHide: {})
        .screenPadding()
}
