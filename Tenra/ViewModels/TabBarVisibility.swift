//
//  TabBarVisibility.swift
//  Tenra
//
//  App-level control of the root tab bar's visibility.
//

import SwiftUI

/// Shared control of the root `TabView`'s tab bar visibility, owned by
/// `MainTabView` and injected via `@Environment`.
///
/// Why this exists: `TransactionAddModal` is pushed into the home
/// `NavigationStack` and pins a calculator keypad to the bottom via
/// `.safeAreaInset(edge: .bottom)`. That bottom inset competes with the tab bar
/// for the bottom safe area. Hiding the bar with the modal's own
/// `.toolbar(.hidden, for: .tabBar)` works, but on pop the inset collapse and the
/// bar restore race each other — an interrupting tap/scroll on the underlying
/// home ScrollView leaves the bottom safe area (and the tab bar) stuck collapsed.
///
/// Hoisting visibility to this stable, TabView-owned object makes restoration a
/// plain `isHidden = false` state flip on a view that never tears down, so it is
/// no longer tied to the modal's transient safe-area teardown.
@MainActor
@Observable
final class TabBarVisibility {
    var isHidden = false
}
