//
//  ReorderDifference+Apply.swift
//  Tenra
//
//  iOS 27 reports a drag-to-reorder as a `ReorderDifference` (which items moved, and
//  where they landed) instead of the `IndexSet` + offset that `onMove` used.
//
//  This file is only the adapter. `ReorderDifference` has no public initializer, so any
//  logic written against it is untestable; the ordering itself lives in `ReorderApplier`,
//  which is pinned by `ReorderApplierTests`.
//

import SwiftUI

@available(iOS 27, *)
extension ReorderDifference where CollectionID == ReorderableSingleCollectionIdentifier {

    /// Applies the move to `collection`, which must be the same ordered list the reorder
    /// container was built from.
    ///
    /// Scoped to single-collection containers: a sectioned container routes by
    /// `destination.collectionID` instead and needs its own handling.
    func apply<Element: Identifiable>(to collection: inout [Element])
    where Element.ID == ItemID {
        let target: ReorderApplier.Destination<Element.ID>
        switch destination.position {
        case .before(let id): target = .before(id)
        case .end: target = .end
        }

        collection = ReorderApplier.reordered(collection, moving: sources, to: target)
    }
}
