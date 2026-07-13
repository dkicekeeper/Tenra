//
//  PaywallSheet.swift
//  Tenra
//
//  The ONLY file that imports RevenueCatUI. Wraps RevenueCat's prebuilt
//  PaywallView (configured remotely from the RevenueCat dashboard) in a sheet,
//  so feature gates only need a `Bool` binding and never touch the SDK.
//
//  Usage at a gated call site:
//
//      @Environment(PremiumManager.self) private var premium
//      @State private var showPaywall = false
//      ...
//      Button {
//          if premium.isPro { doGatedThing() } else { showPaywall = true }
//      } label: { ... }
//      .paywallSheet(isPresented: $showPaywall)
//

import SwiftUI
import RevenueCatUI

struct PaywallSheet: ViewModifier {
    @Binding var isPresented: Bool
    /// Optional callback fired after a successful purchase (sheet auto-dismisses).
    var onUnlocked: (() -> Void)?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            // Renders the current "default" offering's paywall as designed in the
            // RevenueCat dashboard. `PremiumManager.customerInfoStream` also picks
            // up the entitlement change independently, so `isPro` flips even if a
            // call site forgets to react to `onUnlocked`.
            PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { _ in
                    // Rarest, highest-emotion success moment in the app — acknowledge the
                    // unlock with a success haptic (ordinary tx saves already fire one)
                    // before dismissing.
                    HapticManager.success()
                    isPresented = false
                    onUnlocked?()
                }
                .onRestoreCompleted { _ in
                    HapticManager.success()
                    isPresented = false
                }
                // App Review guideline 3.1.2(c): the Terms of Use (EULA) + Privacy
                // Policy links required in the purchase flow are configured in the
                // RevenueCat paywall footer (dashboard), so no in-app footer here —
                // a second row of links would duplicate them.
        }
    }
}

extension View {
    /// Presents the RevenueCat paywall when `isPresented` becomes true.
    func paywallSheet(
        isPresented: Binding<Bool>,
        onUnlocked: (() -> Void)? = nil
    ) -> some View {
        modifier(PaywallSheet(isPresented: isPresented, onUnlocked: onUnlocked))
    }
}
