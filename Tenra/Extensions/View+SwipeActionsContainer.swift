//
//  View+SwipeActionsContainer.swift
//  Tenra
//
//  iOS 27 lets `.swipeActions` work on rows outside a `List`, provided the
//  enclosing scroll container opts in via `swipeActionsContainer()`. The
//  deployment target is iOS 26, so the availability check lives here once
//  instead of at every call site.
//

import SwiftUI

extension View {
    /// Enables row-level `.swipeActions` inside a non-`List` scroll container (iOS 27+).
    ///
    /// On iOS 26 this is a no-op and rows keep relying on the mirrored
    /// `.contextMenu` (see [TransactionCard](../Views/Components/Cards/TransactionCard.swift)),
    /// which stays in place on both versions as the long-press affordance.
    @ViewBuilder
    func swipeActionsContainerIfAvailable() -> some View {
        if #available(iOS 27.0, *) {
            swipeActionsContainer()
        } else {
            self
        }
    }
}
