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
                    isPresented = false
                    onUnlocked?()
                }
                .onRestoreCompleted { _ in
                    isPresented = false
                }
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
