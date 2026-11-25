//
//  View+Usage.swift
//  Tenra
//
//  A screen's part in the app's usage counts (UsageEvents, docs/plan-sales.md §4): a feature's
//  use once a day, a screen's first visit once per install.
//

import SwiftUI

extension View {
    /// Counts the feature once a day when the screen appears.
    func usageFeature(_ feature: UsageFeature) -> some View {
        onAppear { UsageEvents.shared.count(.feature(feature)) }
    }

    /// Notes the screen's first visit.
    func usageFirstScreen(_ screen: UsageScreen) -> some View {
        onAppear { UsageEvents.shared.reach(.firstScreen(screen)) }
    }
}
