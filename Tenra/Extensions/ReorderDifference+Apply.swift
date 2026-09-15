//
//  ReorderDifference+Apply.swift
//  Tenra
//
//  iOS 27 reports a drag-to-reorder as a `ReorderDifference` (which items moved, and
//  where they landed) instead of the `IndexSet` + offset that `onMove` used. Applying
//  it is the caller's job, so the one implementation lives here.
//
//  Shape follows Apple's `swiftui-whats-new-27` guidance: one in-place pass, a `Set`
//  for O(1) membership.
//

import SwiftUI

@available(iOS 27, *)
extension ReorderDifference where CollectionID == ReorderableSingleCollectionIdentifier {

    /// Applies the move to `collection`, which must be the same ordered list the
    /// reorder container was built from.
    ///
    /// Scoped to single-collection containers: a sectioned container routes by
    /// `destination.collectionID` instead and needs its own handling.
    func apply<C>(to collection: inout C)
    where C: RangeReplaceableCollection,
          C.Element: Identifiable,
          C.Element.ID == ItemID {
        let moving = Set(sources)
        guard !moving.isEmpty else { return }

        // Drop the moved elements and capture them in their original order.
        var moved: [C.Element] = []
        moved.reserveCapacity(moving.count)
        collection.removeAll { element in
            guard moving.contains(element.id) else { return false }
            moved.append(element)
            return true
        }

        switch destination.position {
        case .before(let id):
            let index = collection.firstIndex { $0.id == id } ?? collection.endIndex
            collection.insert(contentsOf: moved, at: index)
        case .end:
            collection.append(contentsOf: moved)
        }
    }
}
