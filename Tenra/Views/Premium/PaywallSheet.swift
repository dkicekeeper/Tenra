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
//  RevenueCatUI is shown only once PremiumManager has confirmed the App Store has something to
//  sell. When the offerings can't load (RevenueCat error 23 when the App Store has no products,
//  or no network), RevenueCatUI shows its raw alert and its OK dismisses the sheet: to the user
//  the paywall "opens, then closes". The sheet shows a localized "temporarily unavailable"
//  state with a retry instead.
//

import SwiftUI
import RevenueCatUI

struct PaywallSheet: ViewModifier {
    @Binding var isPresented: Bool
    /// Optional callback fired after a purchase or a restore unlocked Pro (sheet auto-dismisses).
    var onUnlocked: (() -> Void)?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            PaywallSheetContent(isPresented: $isPresented, onUnlocked: onUnlocked)
        }
    }
}

/// The sheet's content: RevenueCat's paywall when there is something to sell, else a
/// localized unavailable state with a retry.
private struct PaywallSheetContent: View {
    @Binding var isPresented: Bool
    let onUnlocked: (() -> Void)?

    /// The singleton rather than `@Environment`: the sheet is presented from many screens
    /// (and their previews) that need not carry PremiumManager.
    private let premium = PremiumManager.shared

    @State private var phase: Phase
    @State private var showingNothingToRestore = false

    private enum Phase: Equatable {
        case checking
        case ready
        case unavailable(OfferingsAvailability)
    }

    init(isPresented: Binding<Bool>, onUnlocked: (() -> Void)?) {
        _isPresented = isPresented
        self.onUnlocked = onUnlocked
        // A check that already found products (the launch health check runs one) opens the
        // paywall at once; anything else is verified before RevenueCatUI is shown.
        let known = PremiumManager.shared.offeringsAvailability
        _phase = State(initialValue: known?.canSell == true ? .ready : .checking)
    }

    var body: some View {
        switch phase {
        case .ready:
            paywall
        case .checking:
            NavigationStack {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar { closeButton }
            }
            .task { await check() }
        case .unavailable(let availability):
            NavigationStack {
                EmptyStateView(
                    icon: availability == .offline ? "wifi.slash" : "",
                    title: String(localized: "paywall.unavailable.title"),
                    description: availability == .offline
                        ? String(localized: "paywall.unavailable.offline")
                        : String(localized: "paywall.unavailable.message"),
                    actionTitle: String(localized: "button.retry"),
                    action: { phase = .checking },
                    style: .error
                )
                .toolbar { closeButton }
            }
        }
    }

    private var paywall: some View {
        // Renders the current "default" offering's paywall as designed in the
        // RevenueCat dashboard. `PremiumManager.customerInfoStream` also picks
        // up the entitlement change independently, so `isPro` flips even if a
        // call site forgets to react to `onUnlocked`.
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { customerInfo in
                premium.applyPaywallResult(customerInfo)
                // Rarest, highest-emotion success moment in the app — acknowledge the
                // unlock with a success haptic (ordinary tx saves already fire one)
                // before dismissing.
                HapticManager.success()
                isPresented = false
                onUnlocked?()
            }
            .onRestoreCompleted { customerInfo in
                // A restore "completes" even when it found nothing: close only when Pro is
                // actually active, else say so and keep the offer on screen.
                guard premium.applyPaywallResult(customerInfo) else {
                    showingNothingToRestore = true
                    return
                }
                HapticManager.success()
                isPresented = false
                onUnlocked?()
            }
            .alert(
                String(localized: "paywall.restore.none.title"),
                isPresented: $showingNothingToRestore
            ) {
                Button(String(localized: "button.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "paywall.restore.none.message"))
            }
            // App Review guideline 3.1.2(c): the Terms of Use (EULA) + Privacy
            // Policy links required in the purchase flow are configured in the
            // RevenueCat paywall footer (dashboard), so no in-app footer here —
            // a second row of links would duplicate them.
    }

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(String(localized: "button.close"))
        }
    }

    private func check() async {
        let availability = await premium.checkOfferings()
        phase = availability.canSell ? .ready : .unavailable(availability)
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
